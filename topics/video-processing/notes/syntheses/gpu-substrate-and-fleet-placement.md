---
title: "GPU Substrate & Fleet Placement: hwaccel as a K8s scheduling constraint"
type: synthesis
topic: video-processing
tags: [bridge, fleet-architecture, hwaccel, gpu, nvidia, eks, karpenter, placement, preliminary, g4dn, g5, g6, nvdec]
jira: null
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/eks-prod-node-pool-gpu-availability.md
  - topics/video-processing/notes/syntheses/decode-locality-per-proposal.md
incoming_updated: 2026-05-01
---

# GPU Substrate & Fleet Placement: hwaccel as a K8s scheduling constraint

Hardware acceleration (decode on [[hardware-accelerated-codecs|NVDEC]] instead of CPU) is the foundation of Actuate's frame-ingest scaling — but **today it's invisible to fleet scheduling**. The connector pod auto-detects hwaccel at startup via `nvidia-smi` / `ffmpeg -hwaccels` / `lspci`, and dispatches accordingly. In a [[fleet-architecture/_summary|fleet-redesigned world]], hwaccel becomes a **node-pool placement constraint** enforced via K8s labels, taints, and resource requests. This note bridges the gap.

## Today's substrate (known gaps)

The codebase is prepared for hwaccel via `HW_DECODERS` table in `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:24-77`, which enumerates **codec → hardware-decoder-name** mappings. The auto-detection logic at lines 527-607 shells out at puller startup to confirm what's available.

**What we don't know:**
- **Do production EKS node groups today expose [[hardware-accelerated-codecs|NVDEC]]?** The connector Dockerfile system-deps ([[ffmpeg-entity|FFmpeg]] build flags, NVIDIA Container Toolkit, libnvidia-decode install) haven't been verified end-to-end. See [[connector-docker-system-deps]] follow-up.
- **Does Karpenter currently spin G-class instances for connector pods, or only CPU instances?** This is a critical blocker for proposals C and E that assume per-pod GPU availability.
- **Which proposal puts GPU decode where?** Proposals A & B may decode on the puller (GPU). Proposal C needs GPU on *every* worker pod. Proposal D and E need a sub-proposal on decode locality. The K8s scheduling story diverges sharply per proposal.

## EC2 GPU instance families (decode-relevant)

Only the [[hardware-accelerated-codecs|NVDEC]] side; no [[hardware-accelerated-codecs|NVENC]] in current scope.

| Family | GPU | Codec support | [[hardware-accelerated-codecs|NVDEC]] engines | Perf/$ | Best for |
|--------|-----|---|---|---|---|
| **G4dn** | NVIDIA T4 (Turing) | [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]], [[av1-vp9-future|VP9]] (no [[av1-vp9-future|AV1]]) | 1 | Lowest cost; older fleet baseline | Cost-sensitive; H.264-only sites |
| **G5** | NVIDIA A10G (Ampere) | [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]], [[av1-vp9-future|AV1]] | 1 | Mid | Inference-heavy sites; [[av1-vp9-future|AV1]] support |
| **G6** | NVIDIA L4 (Ada) | [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]], [[av1-vp9-future|AV1]] | 2 | **Best today** | Mixed decode + inference; high camera density |
| **G6e** | NVIDIA L40S (Ada, large) | [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]], [[av1-vp9-future|AV1]] | 3 | Highest perf | High-throughput decode + inference dense |
| **Inf2 / Trn2** | Inferentia / Trainium | **No [[hardware-accelerated-codecs|NVDEC]]** (AWS chips) | — | — | **Not viable for decode** |
| **Graviton G5g** | T4 on ARM | T4 [[hardware-accelerated-codecs|NVDEC]] (ARM path thinner) | 1 | — | ARM ecosystem not broadly tested; document constraint |

**Throughput reality**: L4 [[hardware-accelerated-codecs|NVDEC]] handles ~1080p @ 1080 fps [[h264-deep-dive|H.264]] (multiple concurrent streams, hardware-shared). Pod density per GPU matters — very high per-pod camera counts may queue on decode engine capacity. This is a PoC discovery point: do we hit [[hardware-accelerated-codecs|NVDEC]] saturation first or CPU/inference first?

## Cost and density trade-off

- **G5.xlarge** (~$1.00/hr) vs **c7g.xlarge** (~$0.07/hr) = 14× cost delta for the node.
- Puller fleet on GPU nodes only makes sense if (a) multiple puller pods share one GPU efficiently, or (b) puller density is high enough to dilute the node cost across many camera streams.
- **Proposal A/B** (puller fleet on GPU, downstream on CPU) spreads the GPU cost over puller pods only — needs density math.
- **Proposal C** (every worker has GPU) is the highest-cost scenario and requires strong economics evidence (fewer total pods / higher utilization).
- **Proposal E** (smart pullers only on GPU) is middle-ground but requires sidecar decode injection (complexity).

## Per-proposal K8s placement implications

### Proposal A (Minimal Split) or B (Stage Fleets)

If puller fleet decodes, place it on GPU node-pool:

```yaml
# Puller Deployment / StatefulSet
spec:
  template:
    spec:
      nodeSelector:
        karpenter.sh/capacity-type: on-demand  # GPU node stability
      tolerations:
      - key: nvidia.com/gpu
        operator: Equal
        value: "true"
        effect: NoSchedule
      containers:
      - name: puller
        resources:
          requests:
            nvidia.com/gpu: "1"   # Karpenter resource constraint
      affinity:
        # TSC: spread across GPU nodes to dilute per-node pod density
        podTopologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              fleet: puller
```

Downstream inference/detection fleets go on CPU node-pool (no GPU request, no toleration).

**Karpenter NodePool setup** (sketch):

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: gpu-decoder
spec:
  template:
    spec:
      instanceFamily: [g5, g6]     # preferred; omit g4dn if AV1 stream coverage required
      zones: [us-west-2a, us-west-2b, us-west-2c]
  limits:
    resources:
      nvidia.com/gpu: "32"         # per-pool cap (e.g., 16 G6.xlarge nodes)
---
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: cpu-general
spec:
  template:
    spec:
      instanceFamily: [c7g, t4g]   # compute-optimized ARM/x86
      zones: [us-west-2a, us-west-2b, us-west-2c]
  limits:
    resources:
      cpu: "1024"
```

### Proposal C (Camera-Worker Fleet)

Every worker pod needs `nvidia.com/gpu: 1`, so the entire worker node-pool must be GPU. **Highest capex & opex cost but simplest placement logic.**

```yaml
nodeSelector:
  node.kubernetes.io/workload: camera-worker
resources:
  requests:
    nvidia.com/gpu: "1"
    memory: 4Gi              # per-camera memory estimate
    cpu: 1500m
```

Karpenter NodePool is **G5/G6 only**, no CPU fallback. Replicas scale on camera count; HPA drives per-pod GPU utilization.

### Proposal D (Event-Driven) or E (Hybrid Sidecar)

**D:** Decode happens wherever frames are pulled from S3-refs. If on puller fleet → GPU placement as A/B. If on decoder stage → separate small GPU node-pool.

**E:** Smart puller fleet is the GPU consumer (decode-heavy); detection core & alert stage stay CPU. Combine puller GPU strategy from A/B with per-core pod affinity to puller fleet via `requiredAffinity` (or `preferredAffinity` if scheduling flexibility is higher priority).

```yaml
# Detection core pod affinity to same-node puller pod
affinity:
  podAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            fleet: puller
            camera-group: "my-camera-group"  # sticky assignment
        topologyKey: kubernetes.io/hostname
```

## DeepStream (architectural cameo)

[[nvidia-deepstream|NVIDIA DeepStream]] is the canonical "many-streams decode→infer on GPU" pattern: [[gstreamer-entity|GStreamer]] plugin suite that keeps frames in GPU memory end-to-end (no GPU→CPU copy). It eliminates the `hwaccel_output_format` trap ([[ffmpeg-hardware-acceleration|detailed notes here]]) and is strictly lower latency + lower bandwidth than our per-stream [[pyav-entity|PyAV]] approach.

**Adoption trade-off:** [[nvidia-deepstream|DeepStream]] is high-risk, high-reward. It requires rewriting `actuate-pipeline` to consume GPU frame buffers. See [[nvidia-deepstream]] for the full comparison. For now: **document the decision to not adopt [[nvidia-deepstream|DeepStream]] as a post-PoC scope item** if a proposal's economics rely on staying below GPU memory saturation.

## Karpenter stability & GPU anti-patterns

**Known gotchas** specific to GPU node-pools:

1. **Consolidation can evict GPU pods** — annotate any pod holding live state with `karpenter.sh/do-not-disrupt: "true"`. For proposals C & E, this affects any camera-group-pinned worker.
2. **Driver version skew** — Karpenter's default AMI may lag NVIDIA driver versions. Verify `ds-terraform-eks-v2` pins a recent GPU-enabled EKS-optimized AMI.
3. **GPU oversubscription is invisible** — K8s doesn't natively over-commit GPUs. One `nvidia.com/gpu: 1` request per pod; Karpenter respects hard limits. **High pod-density strategies require custom Karpenter plugins or manual bin-packing**, not standard K8s.
4. **[[hardware-accelerated-codecs|NVDEC]] engine contention** — if two pods on the same G6 node both saturate their local [[hardware-accelerated-codecs|NVDEC]] engine, both stall. Pod density planning is essential (see throughput note above).

## Open blockers (before proposal scoring)

1. **Connector Dockerfile verification** — Does the production connector image have `libnvidia-decode`, [[ffmpeg-entity|FFmpeg]] with `--enable-cuda`, and NVIDIA Container Toolkit integration? Queued as [[connector-docker-system-deps]].
2. **Karpenter config audit** — What instance families does prod Karpenter *actually* provision? Are there existing G-class nodes in rotation, or is this a cold start?
3. **Per-proposal GPU placement decision** — Each of A–E needs a sub-decision: "decode on GPU vs CPU", "GPU on every pod vs centralized", "Karpenter auto-provision vs reserved capacity". These are binding on cost estimates and PoC design.
4. **Pod density assumptions** — If proposal C/E assumes "one big pod per GPU" vs "multiple small pods per GPU", [[hardware-accelerated-codecs|NVDEC]] saturation curves change significantly. PoC must measure this.

> **Status: preliminary draft (2026-04-27).** Hard data on today's prod node-pool composition + Karpenter config is a pre-req for proposal C scoring; flagged in [[fleet-architecture/_summary|fleet-architecture cross-cutting blockers]].

---

**Related:**
[[fleet-architecture/_summary]] | [[2026-04-16_proposal-a-minimal-split]] | [[2026-04-16_proposal-b-stage-fleets]] | [[2026-04-16_proposal-c-camera-worker]] | [[2026-04-16_proposal-d-event-driven]] | [[2026-04-16_proposal-e-hybrid-sidecar]] | [[k8s-placement-primitives]] | [[scaling-layer-taxonomy]] | [[hardware-accelerated-codecs]] | [[ffmpeg-hardware-acceleration]] | [[nvidia-deepstream]] | [[infrastructure/_summary]] | [[connector-docker-system-deps]]
