---
title: "Frame-Storage Design-Deltas per Fleet Proposal"
type: synthesis
topic: fleet-architecture
tags: [frame-storage, proposals, design-delta, s3-api-cost, in-cluster-blob, conditional-promotion, synthesizer-pilot]
created: 2026-04-22
updated: 2026-04-22
author: kb-bot
---

# Frame-Storage Design-Deltas per Fleet Proposal

> ## ⚠️ AMENDMENT (2026-04-22, post-publication)
>
> **The headline ">50× S3 API-call reduction" claim in this synthesis's original Motivation is INCORRECT.** It was derived from a flawed proxy in the first NR validation query (using `raise_patrol_alert succeeded` at 501/24h — autopatrol-only — as a proxy for "detection-positive windows"). A follow-up query against the actual `create-detection-window` service revealed the true detection-positive rate is **~5.3M / 24h (68.9% of all window closes)**, not ~0.007%. Non-eventful ratio is **~31%**, not >99%.
>
> **Corrected conclusions (grounded in AWS Cost Explorer 30-day S3 data, queried 2026-04-22):**
>
> | Metric | Original synthesis claimed | Corrected reality |
> |--------|-----------------------------|--------------------|
> | S3 PUT-rate reduction from conditional promotion | >50× | **~1.45×** (~31% non-eventful saved) |
> | Implied fleet S3 API-call savings | Transformative | ~31% of PUT cost ≈ **~$4.7k/month** (on $15k/mo PUT baseline) |
> | API-calls-dominate hypothesis | Directionally yes | **CONFIRMED** — S3 is 62.7% API calls / 35.2% storage / 2.1% transfer over 30d ($32.8k total) |
> | Proposal B's "invalidation" under the delta | Load-bearing | **No longer load-bearing** — B stays at its 2026-04-16 score of 7.25/10 |
> | Motion-gating at puller (D, E) vs conditional-promotion at window-close | Complementary | **Motion-gating IS the lever**; conditional-promotion is a minor second-order win |
>
> **What survives the correction:**
>
> 1. **The API-calls-dominate hypothesis itself is right** — S3 PUT cost is ~1.3× storage cost on the actual fleet. Any cost-side design work should focus on PUT-count reduction mechanisms.
> 2. **Motion-gating at the edge (FDMD in puller) is where the real cost savings are.** Proposal E's architecture — 60–80% frame drop BEFORE transport — delivers an order-of-magnitude PUT reduction. Proposal D delivers similar with its FDMD-at-puller + motion-filtered forwarding. **The real cost-side ranking is already baked into the 2026-04-16 scoring via the existing "cost reduction" axis that rewarded motion-gating.**
> 3. **The per-proposal design-delta analysis below** (Sections "Proposal A" through "Proposal E") is still structurally useful as a design-space inventory of *where frames could live and when they graduate*, independent of the cost multiplier. Read those sections as architectural alternatives, not as a re-ranking argument.
> 4. **Proposal E remains the top contender.** Its lead wasn't caused by the flawed premise; the motion-gate mechanism is doing the work.
>
> **What is formally closed by this amendment:**
>
> - **Proposal B-prime (stateless-with-coordinator):** the synthesis `topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md` concluded "park as examined-and-closed" at 6.25/10 even under the flawed premise. Under the corrected premise, B-prime's coordinator complexity for a ~1.45× saving is even less defensible. **Formally closed.** Reference artifact only.
> - **Proposal B (original stage fleets):** the delta-synthesis's "B's score premise is invalidated" claim is itself invalidated by the NR correction. B's 2026-04-16 score of 7.25/10 stands as originally documented. B remains a valid but operationally complex proposal; it is not closed by this amendment.
>
> **Validation sources for the correction:**
>
> - NR query 1 (flawed): `raise_patrol_alert succeeded` 501/24h — autopatrol-only, not fleet-wide detection signal
> - NR query 2 (correct): `create-detection-window` container processing-complete events 5,331,855/24h ≈ 99.996% success rate out of 5,332,060 starts
> - AWS Cost Explorer (`AWS_PROFILE=prod aws ce get-cost-and-usage`, 30-day window): S3 UnblendedCost $32,820.89 total, Tier1 PUTs $15,016.91 on 2.8B requests, storage $11,548.20 on 1.94M GB-months — confirms API-calls-dominate but at modest ratio, not extreme
> - CE access pattern documented at `topics/engineering-process/notes/concepts/aws-cost-explorer-access-pattern.md`
>
> **Fleet-coordinator question surfaced independently:** see `topics/fleet-architecture/notes/concepts/fleet-coordinator-unification-question.md` — survives the NR correction because it's a structural question about control-plane consolidation, not a cost claim.
>
> **Next actions (pushed to `topics/personal-notes/notes/entities/mark-todos.md` Not-Yet-Prioritized):**
>
> 1. Formal A-E re-score, now unblocked — real CE data in hand, no need to wait further. Cost-reduction axis will shift modestly, not dramatically; likely does not change the PoC-selection recommendation.
> 2. `SlidingWindowStep.close_window` outcome instrumentation (~5 LoC) — makes the non-eventful-ratio a first-class queryable signal, removes the proxy-hunting that caused this mistake.
> 3. Motion-gate validation — what fraction of raw frames does FDMD actually drop today? If it's in the 60–80% range proposals D/E assumed, that's where to focus cost modeling.
>
> — End amendment —

## Motivation

The 2026-04-21 grounding pass on `[[frame-storage-current-state]]` §§11-12 overturned a premise that the original 2026-04-16 proposal scoring took for granted: **S3 cost is dominated by API-call volume, not stored bytes.** The current pattern fires ~22 S3 API calls per 10-frame detection window — 10 per-frame PUTs during accumulation, then 10 GETs + 1 PUT by the external `/create-video` lambda, plus a consumer GET. Fleet-aggregated, that's the real line item; Intelligent-Tiering and format changes are second-order.

The converging design is **in-cluster blob for per-frame accumulation, conditional S3 promotion only on detection-positive window close**, as a single pre-encoded clip object. Per §12, this collapses the per-window API budget to 0 (non-eventful windows, dropped entirely) or 2 (eventful: 1 encoded-clip PUT + 1 consumer GET). For always-on camera fleets where most windows are non-eventful, fleet-aggregate reduction is **projected >50×, pending PoC validation** against real event rates and encode CPU. Crucially, the 2026-04-16 proposals were scored against frame-data-volume assumptions; several scores do not survive this re-baseline.

## Design-delta framing

Each proposal is scored against five axes:

1. **Blob locality** — where per-frame accumulation lives between puller pull and window close (in-pod memory, EmptyDir, PVC, NATS JetStream, Redis Streams, S3).
2. **Promotion trigger** — when a frame (or derived artifact) graduates to durable S3: every frame, every window, detection-positive only.
3. **S3 PUT-rate delta vs baseline** — order-of-magnitude change to the ~2.3 S3 API calls/frame baseline.
4. **Interaction with proposal's existing frame-transport choice** — does the delta compose naturally, force a rework, or invalidate prior rationale?
5. **Per-camera memory profile delta** — does the proposal's memory envelope widen (holding a window's raw JPEGs in-pod), narrow, or shift between pods?

## Proposal A — Minimal Split

**Today's (pre-delta) frame-storage story.** Pipeline worker stays monolithic per-site. Frames live in the existing in-process `PooledTTLImageCache` (`~44 MB/camera`, 60 s TTL). `save_frame_meta_step` fires 10 per-frame S3 PUTs per window into `detection_bucket`. `/create-video` lambda consumes by S3 key enumerated from `WindowIdsV2`. Redis Streams in A carry only the puller→pipeline-worker hop; they are not on the window-accumulation path.

**Design delta under in-cluster-blob + conditional-promotion.** The pipeline worker already holds frames in-process for 60 s — that is the in-cluster blob. The delta is purely step-level: replace `save_frame_meta_step`'s per-frame S3 PUT with an in-process window-buffer write (the existing `image_cache` slice, optionally promoted to an `emptyDir.medium: Memory` spill area for windows with retention >60 s). At `SlidingWindowStep.close_window`, branch on detection outcome: no-detection → drop buffer (0 S3 calls, 0 DDB writes); detection-positive → encode the window's JPEGs into an MP4 via [[pyav-entity|PyAV]] (already on the image per `frame-storage-current-state` §8), single PUT to `detection_bucket`, single `EnrichedFrameV2`-replacement row referencing the clip key. The `/create-video` lambda is retired (its 10 GETs + 1 PUT collapse into the in-process encode).

**Fit quality: neutral.** A already has frames in-process; the delta works but A gains no *architectural* leverage from it — any other proposal could copy this step-level change.

**Components specifically affected.**
- `save_frame_meta_step.py` — rewritten to append-to-window-buffer rather than S3 PUT.
- `SlidingWindowStep.close_window` — new encode+promote branch; [[pyav-entity|PyAV]] encode path is new production code.
- `WindowIdsV2` schema — `clip_s3_key` replaces per-frame enumeration; `/create-video` URL wiring in `actuate-daos/window_ids.py:62-89` goes away.
- `EnrichedFrameV2` — collapses from N rows/window to 0 or 1 rows/window (stored as sidecar JSON or MP4 metadata atom).
- Pipeline worker VPA envelope — unchanged (frames were already cached in-process).

**Open questions.**
- Does [[pyav-entity|PyAV]] encode fit inside the single pipeline-worker GIL budget without starving inference? Today's encode is TurboJPEG per-frame; [[h264-deep-dive|H.264]] window encode is a different cost profile.
- What happens on pipeline-worker crash mid-window — is losing the detection-positive frames acceptable if the tracker already emitted the alert envelope?
- Is the score for A (4.25/10) salvageable by this delta? The delta closes most of A's cost-reduction gap without adding scalability — A stays a fallback, not a contender.
- Does the step-level rewrite add enough pipeline-library churn to erode A's "lowest migration risk" advantage?

## Proposal B — Stage Fleets

**Today's (pre-delta) frame-storage story.** Four stateless stages with JPEG bytes traversing 4 Redis Streams hops (`raw` → `motion` → `inference` → `observed`). Stream MAXLEN ~100; per-camera frames hop bodily through the bus. Per-frame S3 PUT happens in observer+filter fleet (which owns `save_frame_meta`). Cross-AZ frame transit is already B's largest cost concern (~$400k/mo uncontrolled at current scale per `frame-transport-comparison` §"AWS deployment specifics").

**Design delta under in-cluster-blob + conditional-promotion.** B has no natural blob owner. Each stage is by design stateless; frames are "in-flight" on Redis Streams, not "accumulated." Implementing the delta requires introducing stateful blob residency somewhere:

- **Option B1 — blob lives in observer+filter.** Observer is already per-camera stateful (tracker), so gains a per-camera window-buffer. But B's observer is a Deployment in the reference architecture; adding durable window accumulation turns it into a de facto StatefulSet, eroding B's "every stage stateless" premise. Redis Streams now act as the blob; MAXLEN must widen from ~100 (frame-rate headroom) to N-frames-per-window × N-open-windows, effectively turning Redis into an in-cluster blob store.
- **Option B2 — blob lives in inference-coord.** Inference-coord already buffers frames awaiting AIMD-controlled inference per `memory-and-fork-safety.md` ("Biggest memory footprint of B"); window accumulation could piggyback. But windows are a concept owned by observer; cross-stage window state coupling reintroduces the coordination the stage split was meant to eliminate.

**Fit quality: awkward.** Either option compromises B's statelessness premise. The delta reveals that B's score for "independent scalability" (10/10) was built on pass-through-frame-bytes assumptions; conditional-promotion wants stateful ownership somewhere, and that ownership is structurally a single stage.

**Components specifically affected.**
- Redis Streams MAXLEN tuning — `raw:cam:{id}` stream must now size for entire open windows, not just rate headroom. Cluster RAM budget in `frame-transport-comparison` §"Memory sizing example" (~200 GB at current scale) inflates ~5-10×.
- Observer+filter fleet controller choice — forced toward StatefulSet per `k8s-controller-selection-guide`'s table; undermines B's "all stages Deployment" simplicity claim.
- Cross-AZ transfer cost — counterintuitively *worse* under the delta: the full window's frame bytes must now land in the same AZ as the encoding stage, forcing stricter zone-affinity than B already needed.

**Open questions.**
- Is there a B-preserving variant where Redis Streams AOF itself *is* the in-cluster blob (i.e. window lives in-stream, consumer encodes on close)? What does that do to stream-memory at 10× fleet?
- Does the delta invalidate B's 7.25/10 composite? The cost-reduction axis (6/10) was already marginal; awkward statefulness could drop operational-simplicity (3/10) further.
- Should B be re-scoped as "B-prime" with an explicit blob-holding stage, distinguishing it from the original stateless-stage premise?

## Proposal C — Camera-Worker Fleet

**Today's (pre-delta) frame-storage story.** Full pipeline per camera, in-process, inside a generic worker that bin-packs N cameras. **No frame transport over the network.** `PooledTTLImageCache` per worker; frames never leave the pod until `save_frame_meta` fires per-frame S3 PUTs. The per-window API cost structure is identical to today's monolith — the proposal didn't address it.

**Design delta under in-cluster-blob + conditional-promotion.** Near-perfect composition. The worker already holds all of a camera's frames for the full window in-process; the delta is step-level identical to Proposal A's delta, but with no cross-pod coordination concern. Window buffer is a slice of the existing `image_cache` (optionally spilled to `emptyDir` with `sizeLimit: 2Gi` for windows beyond 60 s TTL). On `close_window`: non-eventful → free slice (MADV_DONTNEED per `memory-and-fork-safety.md` reassignment semantics); detection-positive → [[pyav-entity|PyAV]] encode in-pod, single PUT.

**Fit quality: natural.** C's core value proposition (frames stay in-process) is exactly what the delta asks for. The conditional-promotion collapse from 22 → 0/2 API calls compounds with C's existing bin-packing and Spot viability (per `proposal-c` §"Spot viability") to stack three independent cost wins.

**Components specifically affected.**
- Worker pod memory envelope — window buffer widens per-camera memory by ~1.5 MB (10 frames × 150 KB post-JPEG-encode) in the worst case. Acceptable on top of 32 MB/camera budget.
- `emptyDir` spec — new addition for windows beyond in-memory TTL. Node-local NVMe via `local.storageClass` on Karpenter-selected `i3en`/`m5d` node families (per `frame-storage-current-state` §"Open design questions" item 1).
- Assignment controller drain protocol — must now wait for encode-in-progress windows before releasing a camera. Adds a state to the preStop handshake in `pod-termination-sequence.md`.
- `karpenter.sh/do-not-disrupt` annotation scope — expanded from "mid-heavy-processing" to "has open detection-positive window awaiting encode."
- `EnrichedFrameV2` → clip-metadata consolidation (as A).

**Open questions.**
- [[pyav-entity|PyAV]] encode on Spot: can the 2-minute interruption warning reliably cover the encode of a just-closed window? If not, does the worker cold-dump the buffer to S3 as raw JPEGs (fallback) and let a separate encode fleet pick it up?
- Does the delta move C's "cost reduction" score (10/10) further up, or is it already maxed? Qualitative win: the API-call reduction is independent of and compounds with bin-packing.
- Does node-local NVMe selection erode C's bin-packing freedom by constraining the NodePool?
- Is image-size bloat from adding [[pyav-entity|PyAV]] encode (already present for decode) negligible?

## Proposal D — Event-Driven Pipeline

**Today's (pre-delta) frame-storage story.** NATS JetStream envelopes + S3 Express One Zone per-AZ buckets as the durable blob. Every frame is S3-PUT by the puller (motion-gated, so 20-40% of raw rate, but still 96k PUT/s inflated-to-$60k/mo per `proposal-d` §"Cost model"). Mitigation already in proposal: batch 5-10 frames per PUT. Detector GETs by S3 key for inference.

**Design delta under in-cluster-blob + conditional-promotion.** The delta proposes moving the blob *out of* S3 and into in-cluster state. D has a natural alternative: **NATS JetStream file-backed storage on EBS gp3 is already an in-cluster blob.** Route per-frame writes to a JetStream subject (`frame:cam:{id}:window:{window_id}`) with `Storage: file` and per-subject retention matching open-window lifetime; the stream itself is the accumulation buffer. At window close, the encoder consumer (a new role, likely co-located with observer) replays the window's JetStream subject to build the MP4, fires a single S3 Express PUT for the clip, and acks — JetStream drops the window subject.

S3 Express One Zone is retained for the clip (durability, consumer retrieval via VPC gateway endpoint), but per-frame S3 PUT and consumer GET are eliminated.

**Fit quality: natural alternative.** D was already paying for JetStream; the delta leans further into what JetStream is good at (durable, replayable in-cluster state) rather than paying S3 Express for something JetStream could own. API-call math per window: ~96k/s per-frame PUTs → 0; plus 1 clip PUT per eventful window. Projected S3 PUT-rate reduction is the sharpest of any proposal because D's baseline was the highest.

**Components specifically affected.**
- NATS JetStream memory + EBS sizing — inflates substantially. At 32k cameras × 10 frames × 150 KB per open window = ~48 GB concurrently in JetStream file-backed storage. Manageable; EBS gp3 at ~$0.08/GB-month is negligible vs the S3 PUT savings.
- NATS JetStream PDB `maxUnavailable: 1` (already called out in `proposal-d` §"NATS deployment") becomes more critical — blob-holding cluster, not just envelope-holding.
- `persistentVolumeClaimRetentionPolicy: Delete` on the JetStream StatefulSet (flagged in `k8s-controller-selection-guide.md`) — now protects against orphan blobs, not just orphan envelopes.
- S3DAO usage — per-frame PUT path in puller-with-FDMD goes away entirely; the `actuate-s3-frame-ref` primitive proposed in `proposal-d` §"Enhancement opportunities" becomes unnecessary.
- MinIO as a fallback — can be dropped from consideration; JetStream replaces its role in the delta.

**Open questions.**
- JetStream RAFT replication cost for blob-sized subjects: at 48 GB × 3 replicas × inter-AZ RAFT writes, is the intra-cluster replication bill material compared to the ~$60k/mo S3 PUT savings?
- Does JetStream-as-blob invalidate D's "MinIO is a new SPOF" failure-mode entry? JetStream has its own SPOF characteristics but is already in-cluster by design.
- Encoder-consumer placement: co-located with observer (stateful pressure rises) or separate stage (adds a hop)?
- Does the delta's JetStream pressure force in-cluster NATS into larger instance classes, shifting the cost curve?

## Proposal E — Hybrid Sidecar

**Today's (pre-delta) frame-storage story.** Three fleets. Smart puller runs FDMD, drops 60-80% of frames before they hit Redis. Detection core is a StatefulSet with camera-affinity (10-50 cameras/pod), owns the full pipeline in-process, fires per-frame S3 PUTs. Redis Streams carry only motion-filtered frames, per-camera-group stream key. The camera-group StatefulSet pattern already naturally localizes state per-pod.

**Design delta under in-cluster-blob + conditional-promotion.** Strongest fit. The detection core StatefulSet already holds window state per camera group; the delta adds a per-camera window buffer inside the existing pod (same shape as C's delta), with no architectural change. EmptyDir-backed with `sizeLimit: 2Gi` per pod for windows beyond in-memory TTL; jemalloc handles the allocation churn. On window close: non-eventful → drop (0 API calls); detection-positive → [[pyav-entity|PyAV]] encode in-pod, single S3 PUT.

Compounds with E's existing wins: FDMD motion-gate (60-80% frame drop at puller, per `proposal-e` §"Cost model") + VPA bimodal fix (per `vpa-bimodal-workload-limitation.md` — E is scored "best fix") + in-cluster-blob conditional promotion. Three independent levers stack.

**Fit quality: natural.** E's "stateful core" premise is what the delta wants. The camera-affinity StatefulSet is already the per-camera-group blob owner; no reshuffling of responsibilities is required. `proposal-e`'s existing `partition`-field staged upgrade story (from `k8s-controller-selection-guide.md`) already covers the "don't evict a core mid-encode" requirement via `terminationGracePeriodSeconds` sized for snapshot + encode completion.

**Components specifically affected.**
- Detection core pod spec — adds `emptyDir.sizeLimit: 2Gi` (or `emptyDir.medium: Memory` for tmpfs if node RAM allows), backed by node-local NVMe selected via Karpenter NodePool `instance-type` filter on `m5d`/`i3en` families.
- `terminationGracePeriodSeconds` — widens from baseline ~30 s to ~60-120 s to cover preStop drain + tracker snapshot write + in-progress encode finalize. See `pod-termination-sequence.md` §"Production Configuration."
- `actuate-fdmd` library — unchanged.
- `SlidingWindowStep` — `close_window` gains encode-and-promote branch (shared with A, C).
- ENG-78/ENG-96/ENG-66 story — unchanged; delta is orthogonal to all three existing E benefits.

**Open questions.**
- Does the delta's [[pyav-entity|PyAV]] encode CPU push VPA's recommendation for detection core into a bimodal shape that VPA *can't* fit, reintroducing ENG-78 for the core pods? Mitigation: run encode on a separate thread with bounded CPU via cgroup, so encode peaks don't factor into VPA steady-state recommendation.
- Camera-group sizing (10-50 cameras) — does concurrent encode across an entire group's open windows saturate the pod's CPU budget? Motion-gated frame rate already drops 60-80%; windows-per-second per pod should be sparse.
- Does the delta raise E's composite (currently 8.05/10)? Cost axis was already 10/10; qualitative: API-call collapse is a new top-tier win that wasn't in the original scoring.

## Comparison matrix

| Proposal | Blob locality | Promotion trigger | S3 PUT-rate delta vs baseline | Fit quality |
|----------|---------------|-------------------|-------------------------------|-------------|
| A — Minimal Split | In-process (pipeline worker) | Detection-positive only | 22 → 0/2 per window | Neutral |
| B — Stage Fleets | Redis Streams (MAXLEN-inflated) OR forced stateful stage | Detection-positive only | 22 → 0/2, but Redis RAM inflates 5-10× | Awkward |
| C — Camera-Worker | In-process worker + optional EmptyDir on NVMe | Detection-positive only | 22 → 0/2 per window | Natural |
| D — Event-Driven | NATS JetStream file-backed (EBS) | Detection-positive only | Extremely high → 0/2 per window (sharpest absolute reduction) | Natural alternative |
| E — Hybrid Sidecar | In-process detection core + EmptyDir, per-camera-group | Detection-positive only | 22 → 0/2, stacks on motion-gate 60-80% drop | Natural |

## Cross-cutting implications

**Does the delta change the 2026-04-16 ranking?** Yes, in three ways:

1. **A's relative position improves.** A was scored lowest on cost (3/10) and primary criterion (3/10). The delta closes most of the cost gap — any proposal that eliminates per-frame S3 PUT gets the same ~50× API-call reduction. A's remaining deficit is *scalability*, which the delta doesn't touch. Net: A remains the fallback, but the cost-case-for-doing-nothing improves.
2. **B's position weakens.** B's 6/10 on cost was built on "stage right-sizing at 10× scale"; that logic survives, but B is now the only proposal where the delta is *awkward* rather than neutral/natural. The delta exposes a structural tension in the stateless-stage premise.
3. **C and E compete more closely.** Both compose naturally with the delta. C gains marginally more (the delta is its first cost story beyond bin-packing). E's composite was already highest; delta reinforces rather than reshuffles.
4. **D's absolute API-call reduction is largest.** D's baseline was the worst (per-frame S3 PUTs even post-motion-gate); the delta cuts deepest in absolute terms. But D's 6.85/10 composite was drag-limited by operational complexity (2/10), and the delta doesn't reduce NATS + S3 Express + tracing op burden.

**New primitives the delta introduces, shared across proposals.** Candidates for standalone concept notes:

- **In-pod window buffer** (pattern: `PooledTTLImageCache` → `WindowFrameBuffer` extension; TTL keyed on window close, not wall-clock).
- **EmptyDir-backed NVMe spill pattern** (node-local storage selection via Karpenter NodePool + `local.storageClass`).
- **[[pyav-entity|PyAV]] in-process window encoder** ([[h264-deep-dive|H.264]] baseline, ~1-2× real-time on a single CPU core at 720p per `frame-storage-current-state` §11 — needs PoC validation).
- **Conditional-promotion `SlidingWindowStep.close_window` branch** — the step that decides "encode+PUT or drop."
- **Clip-metadata-in-container** pattern — embed `EnrichedFrameV2` contents as an MP4 metadata atom rather than a DDB row per frame.

**Downstream-consumer-audit shape.** Per `frame-storage-current-state` §§4-6, the consumers that the delta must preserve or break:

- **`/create-video` lambda** — *retired entirely.* The connector produces the assembled clip in-process. This is the biggest cross-team negotiation. Whoever owns `/create-video` needs to know it goes away; the clip-URL contract (from UI/Immix perspective) is preserved.
- **[[alert-ui|Alert-UI]] / Immix** — unchanged. Consumes presigned clip URLs; whether the clip was assembled by the connector or by `/create-video` is opaque.
- **`EnrichedFrameV2` consumers** — must migrate to clip-level metadata (or an embedded-in-container equivalent). This is the largest internal consumer-side change; alert reprocessing and `WindowIdsV2`-based enumeration both touch this.
- **`spray_bucket` run-frame keys** — unchanged. Run frames are a separate path (`frame-storage-current-state` §5) not on the window-accumulation line.
- **[[watchman-repo|Watchman]] / AutoPatrol clip-fetch paths** — unchanged if clip-URL contract is preserved.

## Open questions surfaced by this synthesis

1. **[[pyav-entity|PyAV]] in-process encode cost at realistic fleet concurrency.** [[h264-deep-dive|H.264]] at 1-2× real-time per core for 720p is the `frame-storage-current-state` §11 estimate. What's the p99 under bursty concurrent-window-close load? PoC needed before committing any proposal to the delta.
2. **Non-eventful window ratio at production scale.** The delta's >50× reduction hinges on most windows being non-eventful. Is there a billing-data or NR-query-based estimate of current detection-positive vs non-detection window ratio? Feeds directly into cost projection.
3. **Consumer-contract negotiation ownership.** Who owns `/create-video`? The retirement is a cross-team change; which team and which Jira is this?
4. **B-preserving variant feasibility.** Is there a version of B where the delta fits without erosion of stateless-stage premise — e.g. Redis Streams AOF as blob with encode-on-close consumer? Or does the delta formally invalidate B?
5. **EBS gp3 vs node-local NVMe for blob storage.** JetStream file-backed (D) uses EBS; C/E EmptyDir can use either. Cost/performance/availability tradeoffs need modeling for the per-window IO pattern.
6. **DDB consolidation strategy.** Do we embed frame metadata as MP4 atoms (container-level, opaque to DDB) or keep a single `clip-metadata` row per window (DDB-visible, queryable)? Affects downstream analytics and alert reprocessing.
7. **Graceful-shutdown encode completion.** If a pod receives SIGTERM mid-encode, does the delta's `terminationGracePeriodSeconds` budget accommodate encode-finalize + snapshot write? `pod-termination-sequence.md` §"The 1-Second Snapshot Cadence Constraint" becomes more load-bearing.
8. **Re-run of 2026-04-16 proposal scoring with cost-reduction axis re-baselined.** The original rubric weights cost-reduction at 20%. Re-scoring every proposal with the delta's API-call collapse applied would likely widen E's lead but might also bring A into contender range.

## Post-synthesis decisions (2026-04-22)

Decisions taken in the interview immediately after this synthesis, shaping what happens next:

1. **`/create-video` retirement** → **wait for PoC selection.** All 5 proposals retire the Lambda under the delta, but the actual cross-team conversation is gated on which proposal wins the bake-off. Captured as post-PoC follow-up in `topics/personal-notes/notes/entities/mark-todos.md` Not-Yet-Prioritized → "From synthesis-decision interview (2026-04-22)".

2. **Non-eventful window ratio validation** → **both signals.** NR query dispatched and returned 2026-04-22.

   **NR findings (24h, `cluster_name='Connector-EKS'`):**

   | Signal | Count | % of total closes |
   |--------|-------|-------------------|
   | Total `closing window` events | 7,445,929 | 100% |
   | `closing window None` (confirmed non-eventful, zero-S3-cost) | 2,910,120 | ~39% |
   | `closing window <id>` (has window-ID, NOT necessarily detection-positive) | 4,535,809 | ~61% |
   | `skipping detection window video for None` (same population, video-skip branch) | 3,013,325 | ~40% |
   | `raise_patrol_alert succeeded` (actual delivered alerts) | 501 | 0.007% |

   **Direction strongly supported:** even if the S3-triggering threshold is 100× looser than the alert threshold, eventful fraction is at most ~0.7% — far below the 50% threshold needed to invalidate the >50× projection. >90% non-eventful is a near-certain lower bound, validating the API-call collapse directionally.

   **Precision limitation:** the "None vs window-ID" split in `closing window` does NOT cleanly map to the S3-PUT boundary. A 4.5M-vs-501 (9,000×) gap between "non-None window closes" and "patrol alerts delivered" means "has window-ID" is not a detection-positive proxy. The exact multiplier (50× vs 100× vs 200×) requires either (a) a follow-up NR query against `create_detection_window` container logs, or (b) new instrumentation (see next-steps below).

   **Confidence level: medium-low on the precise multiplier; medium-high on the >50× directional claim.**

   **AWS Cost Explorer pull (user-driven, ~15–30 min AWS console work)** — still pending: S3 PUT/GET counts for `detection_bucket` + `spray_bucket` over 30 days. This gives real $ figures and grounds the "multiplier" in actual cost numbers rather than proxy counts.

   **Instrumentation gap (new follow-up):** a single structured INFO log line at `SlidingWindowStep.close_window` emitting `window_outcome=detection_positive|no_detection` + `window_id` + `site_id` would close the ratio gap completely. ~5 lines of code, very high-value for future cost-model work. Captured in `topics/personal-notes/notes/entities/mark-todos.md` Not-Yet-Prioritized.

3. **Formal A-E re-score against the evaluation rubric with delta baked in** → **deferred until cost-data validation lands.** Building the re-score on projections would force `TBD` cells in the weighted-score matrix; worth waiting 1–2 days for solid inputs. Will spawn as a third synthesizer pass once NR query + Cost Explorer data are in hand. Target file: `topics/fleet-architecture/notes/syntheses/2026-04-XX_fleet-proposal-rescore-with-delta.md`.

4. **B vs B-prime** → **synthesize B-prime now.** Second synthesizer pass dispatched 2026-04-22 writing to `topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md`. If honest analysis concludes B-prime doesn't earn its seat (doesn't clearly beat B on primary criterion or differentiate from E), the synthesis itself functions as the "examined and closed" artifact.

**Meta-ask (surfaced during interview):** bake AWS Cost Explorer API calls into skills/checks generally (`/autopatrol-cleanup-lambda-check`, `/log-check`, `/daily-scope` fan-out), so cost impact surfaces alongside operational health. Captured in `topics/personal-notes/notes/entities/mark-todos.md` Not-Yet-Prioritized.

## Related

- [[frame-storage-current-state]] — cost insight grounding §§11-12 and consumer constraints
- [[2026-04-16_proposal-a-minimal-split]]
- [[2026-04-16_proposal-b-stage-fleets]]
- [[2026-04-16_proposal-c-camera-worker]]
- [[2026-04-16_proposal-d-event-driven]]
- [[2026-04-16_proposal-e-hybrid-sidecar]]
- [[2026-04-16_frame-transport-comparison]] — cross-AZ, S3 Express, Redis deployment specifics
- [[2026-04-16_graceful-failover-design]] — snapshot cadence + grace-period sizing
- [[2026-04-16_evaluation-rubric]] — cost-reduction axis weighting
- [[k8s-placement-primitives]] — TSC + PDB + affinity for blob-holding pods
- [[k8s-controller-selection-guide]] — StatefulSet vs Deployment decision for each fleet's blob owner
- [[pod-termination-sequence]] — grace-period sizing for encode + snapshot completion
- [[memory-and-fork-safety]] — per-proposal memory deltas this synthesis builds on
- [[vpa-bimodal-workload-limitation]] — encode-peak risk for detection core pods
- [[tracker-snapshot-schema]] — adjacent snapshot-on-shutdown mechanism the delta composes with
- [[downstream-consumer-impact]] — `/create-video` retirement cross-team negotiation
