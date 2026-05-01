---
title: "Actuate Build-vs-Buy Tradeoffs (where AWS managed services could replace homegrown code)"
type: synthesis
topic: video-processing
tags: [actuate, build-vs-buy, aws, mediaconvert, kvs, ivs, mediapackage, hwaccel, webrtc]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# Actuate Build-vs-Buy Tradeoffs

Where AWS managed video services could replace homegrown code in our connector / pipeline / alert path. This is the strategic synthesis at the intersection of [[aws-video-services-decision-matrix]] and [[fleet-architecture/_summary]]. **Not every gap is worth filling with a managed service** -- some of our homegrown code is the right size for the problem, and the cost of an SLA boundary, lock-in, or per-stream pricing is real. The goal here is to put the candidates side-by-side, evaluate them honestly, and end with a prioritized list of next investigations.

## Six candidates, evaluated

### A. MP4 clip muxing -- currently downstream FIFO + custom code → [[aws-mediaconvert-entity|MediaConvert]]?

**State today.** No MP4 muxer in the connector libraries (see [[actuate-clip-generation-flow]] for full detail). `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/immix/immix_alert_sender.py:88-100` hands off frame counts + S3 folder to `event_queue_immix_alarm.fifo`; a downstream consumer (Lambda / SQS worker outside this codebase) actually muxes the MP4. The downstream consumer is **not** managed -- it's our own service, somewhere outside `actuate-libraries`/`vms-connector`/`actuate-alarm-senders`.

**Could [[aws-mediaconvert-entity|MediaConvert]] replace it?** No, not for alert-time clips. [[aws-mediaconvert-entity|MediaConvert]] is built for re-encode-at-rest workflows. Job latency (30s-2min), per-output-minute pricing with a ~6s minimum, and queue scheduling overhead make it the wrong tool for "this alert needs to be on a dispatcher's screen in seconds." See [[aws-mediaconvert-entity]], [[aws-video-services-decision-matrix]].

**Could [[aws-mediaconvert-entity|MediaConvert]] replace it for archive/cold-storage re-encoding?** Maybe. If we ever decide to take the JPEG sequences in S3 and produce an MP4 for long-term retention (instead of keeping the JPEG sequence forever), [[aws-mediaconvert-entity|MediaConvert]] is a reasonable fit. But we should first ask whether we even need the archived MP4s at all -- the JPEGs already work for any UI playback; the MP4 is bandwidth optimization, not capability.

**The right move.** Bring muxing in-process via [[pyav-entity|PyAV]] write-mode (Option A in [[actuate-clip-generation-flow]]) **only if** the FIFO consumer becomes a maintenance pain. Today, the seam is doing what it should. Don't fix what isn't broken.

**Investigation deliverable.** A small spike: who owns the downstream FIFO consumer? Is it tracked in any fleet-status dashboard? If the consumer is one Lambda owned by one engineer, that's a bus factor of one and the build-vs-buy framing should include "fold the Lambda into the connector pipeline."

### B. Live preview to dispatcher -- not built today → IVS Real-Time / KVS [[webrtc-deep-dive|WebRTC]]?

**State today.** Not built. The connector decodes frames for inference and forwards JPEG snapshots to alert senders. There is no live-preview path from camera → monitoring-centre dispatcher's UI today. See [[actuate-video-pipeline-walkthrough]] for the closest we have.

**The user need.** Dispatchers occasionally want to see "is this still happening?" after an alert fires. Today they see a JPEG (the alert frame) plus, on Immix MP4 mode, a 5-15s clip assembled downstream. They cannot see *now*.

**[[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]].** [[aws-kvs-entity|Kinesis Video Streams]] supports [[webrtc-deep-dive|WebRTC]] signalling channels for ultra-low-latency live preview. Architecture: camera (or our connector pod, acting as producer) publishes to a [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] signalling channel; dispatcher's browser subscribes via the [[webrtc-deep-dive|WebRTC]] SDK. End-to-end latency: 1-3 seconds typical. See [[aws-kvs-entity]], [[webrtc-deep-dive]], [[protocol-latency-comparison]].

**IVS Real-Time.** AWS Elemental IVS Real-Time is the WebRTC-based broadcast variant of IVS. Different positioning -- IVS Real-Time is more "broadcaster-to-many-viewers" than [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]]'s "peer-to-peer with TURN fallback." See [[aws-ivs-entity]], reading-list entry on [[aws-ivs-entity|AWS IVS]] Real-Time.

**Tradeoff matrix.**

| Option | Latency | Per-stream cost | Lock-in | Maintenance burden |
|---|---|---|---|---|
| **[[kvs-components|KVS]] WebRTC** | 1-3s | per-minute streaming + per-MB out | medium | low (managed) |
| **IVS Real-Time** | 1-3s | per-participant-minute | medium | low (managed) |
| **Self-hosted SFU (Janus / LiveKit / Pion)** | 1-3s | EC2 + bandwidth only | low | high (we own the SFU) |
| **Re-stream [[rtsp-deep-dive|RTSP]] via TURN** | 3-8s | bandwidth only | low | medium |
| **[[hls-and-dash|HLS]]** | 6-30s | S3 + CloudFront | none | low | -- but **too slow for the dispatcher use case** ([[hls-and-dash]]) |

**The right move.** This is the **most strategically interesting** item on the list. Live preview is a feature customers actively ask for. KVS WebRTC is the lowest-friction managed path; the producer SDK is C++/Java/[[gstreamer-entity|GStreamer]] (the Python `boto3` client is *not* a producer client -- see reading-list note). That means **bringing KVS WebRTC live-preview in would be a net-new component, not a swap-out of existing code.**

**Investigation deliverable.** A spike with a single test camera: route its [[rtsp-deep-dive|RTSP]] through the existing [[pyav-entity|PyAV]] decoder, then re-publish to a KVS WebRTC signalling channel via the [[gstreamer-entity|GStreamer]] KVS Producer plugin. Measure end-to-end latency to a Chrome dispatcher. If <2s, consider productionizing.

### C. Cross-fleet frame transport -- motivated by [[fleet-architecture/_summary]] -- KVS WebRTC viable?

**State today.** Frame transport between fleet pods is via S3 + DDB (the EnrichedFrame model in `actuate-libraries/actuate-frames/src/actuate_frames/save_frame_meta.py:12-79`). For real-time pod-to-pod video transport (e.g. one pod decoding, another pod inference-batching, a third pod assembling alerts) we don't have a dedicated wire format -- just S3.

**Why KVS WebRTC?** WebRTC is data-channel-and-media-channel together; it could carry both frame batches and detection metadata over a single peer connection. But the use case is unclear: are we trying to move *raw frames* between pods (tens of MB/s per camera per pod), *encoded packets* (kilobits/s per camera), or *decoded numpy arrays + detection metadata* (current model)?

If the answer is "encoded packets" -- which is roughly what KVS WebRTC carries -- then we'd be re-encoding on the source pod (CPU cost) and re-decoding on the destination pod (CPU cost). That's worse than what we have today unless the source already has the encoded bytes (which the puller, in fact, does -- but throws them away after decoding).

**The right move.** Probably not WebRTC. **Probably gRPC + protobuf** for frame batches with detection metadata, if anything. Decoded frames + metadata, framed protobuf, push over HTTP/2. That's the "cross-fleet transport" pattern that matches our actual data shape. See [[fleet-architecture/_summary]] for context; this is more a fleet-architecture problem than a video-processing one.

**Investigation deliverable.** Defer to fleet-architecture topic. Tag the synthesis there with a back-reference once written.

### D. Long-term clip archive serving -- [[aws-mediapackage-entity|MediaPackage]] v2?

**State today.** No long-term archive. Detection JPEGs land in the detection bucket (`save_frame_meta.py:43`) and stay there. No automatic transcode-to-MP4-for-archive. No tiered storage policy in code. Whatever S3 lifecycle rules exist live in Terraform, not in the application.

**Could [[aws-mediapackage-entity|MediaPackage]] v2 help?** [[aws-mediapackage-entity|MediaPackage]] v2 is the modern AWS service for packaging on-demand and live video into [[hls-and-dash|HLS]]/[[hls-and-dash|DASH]]/CMAF for delivery via CloudFront. It's the right answer for "we have an MP4 and want to stream it to many viewers efficiently." It is **not** the right answer for "we have a million JPEG sequences and want them stored cheaply." That's an S3 Glacier / Intelligent-Tiering question.

**The real question:** do we need clips at all in long-term archive, or are JPEG sequences fine? Sibling to "do we need MP4 muxing in-process at all?" Same answer: depends on whether anyone consumes the long-term archive. If the answer is "compliance" -- maybe. If the answer is "customer historical playback in the Actuate UI" -- the JPEG sequence already works.

**The right move.** Skip [[aws-mediapackage-entity|MediaPackage]] v2 for our current shape. Revisit if we add a "playback long historical video" UI feature with serious viewer counts. See [[aws-mediapackage-entity]] for service positioning, [[aws-video-services-decision-matrix]] for the comparison.

### E. KVS pipeline JPEG round-trip -- replace with cleaner GStreamer caps OR move to PyAV-on-MKV

**State today.** `actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_ingestor.py:148-156, 104-128` runs:

```
appsrc → matroskademux → decodebin → videoconvert → jpegenc → appsink
```

then `cv2.imdecode` the JPEG buffer back to numpy at line 119. **JPEG encode in [[gstreamer-entity|GStreamer]] + JPEG decode in Python = wasted CPU per frame.** Flagged in [[actuate-frame-ingest-decode-paths]].

**Two clean fixes:**

1. **[[gstreamer-entity|GStreamer]] caps fix.** Terminate the pipeline at `appsink` with `caps="video/x-raw,format=BGR"` and skip `jpegenc` entirely. The `appsink` buffer is then a raw BGR plane; `np.frombuffer + reshape` produces the numpy array directly. No JPEG round-trip. Lowest-effort fix, stays in [[gstreamer-entity|GStreamer]].
2. **Move KVS to PyAV-on-MKV.** KVS streams are MKV containing [[h264-deep-dive|H.264]] / [[h265-hevc-deep-dive|H.265]]. [[pyav-entity|PyAV]] can demux MKV byte streams via a custom `AvIOContext` reading from the boto3 `kinesis-video-media` GetMedia stream. This unifies the KVS path with the [[rtsp-deep-dive|RTSP]] path -- same decoder substrate, same hardware-accel logic, same fMP4-style edge-case handling. Higher effort, but eliminates the [[gstreamer-entity|GStreamer]] dependency for KVS entirely.

**The right move.** Option 1 first (low-risk, weeks not months). Option 2 as a follow-on if we want to deprecate GStreamer for KVS.

**Investigation deliverable.** A spike: change `kvs_ingestor.py` to terminate at raw BGR `appsink`. Measure CPU before/after on a representative KVS-heavy customer. Expected savings: 10-25% per-stream CPU on the KVS path. See [[gstreamer-entity]], [[gstreamer-pipeline-model]], [[pyav-entity]], [[aws-kvs-entity]].

### F. Hardware-accel substrate -- EC2 G5/G6/L4 + NVIDIA Container Toolkit -- do we use NVENC/NVDEC today?

**State today.** Hardware-acceleration **detection** is implemented in `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:527-607`. The detection runs on puller init: `nvidia-smi -L`, `ffmpeg -hide_banner -hwaccels`, `lspci`, each with `timeout=5`. Priority: macOS [[hardware-accelerated-codecs|VideoToolbox]] → NVIDIA CUDA → Intel VAAPI → AMD AMF.

The HW decoder table at `av_url_puller.py:24-77` enumerates the codec × hwaccel matrix. The per-hwaccel options dict at line 412-494 sets `hwaccel=<type>`, `hwaccel_device=/dev/dri/renderD128` for VAAPI, etc. So the code **can** drive [[hardware-accelerated-codecs|NVDEC]].

**But.** `hwaccel_output_format` is **deliberately not set** at line 454-456, 432-434. The comment says GPU-memory frames break `frame.to_ndarray()`. This means even when we hardware-decode, frames round-trip CPU memory. We get the *decode* speedup but not the zero-copy benefit; for many workloads the CPU copy is the dominant cost.

**Are we even running on GPU nodes?** Unknown from the connector code alone. Production EKS node groups are defined in `ds-terraform-eks-v2`. We need to verify whether our connector pods are scheduled on G5 / G6 / L4 instances or on CPU-only nodes. **If we're on CPU-only nodes, the entire HW-detect logic in `av_url_puller.py` is decorative.**

**Even if we are on GPU nodes:**
- Are [[hardware-accelerated-codecs|NVENC]]/[[hardware-accelerated-codecs|NVDEC]] kernel drivers loaded? `nvidia-smi -L` would say so, but the detection has a 5s timeout that could eat container startup.
- Is the NVIDIA Container Toolkit installed? Kubernetes pods need `nvidia.com/gpu: 1` in resource requests to actually get device access.
- Are we requesting GPU resources in the connector Helm chart / pod spec? **Scout pass did not locate the connector Helm chart.**

**The right move.** This is the **single highest-leverage investigation on this list**, because if our production fleet is on GPU nodes and we're not using [[hardware-accelerated-codecs|NVDEC]], we're paying for hardware we don't use. Conversely, if our fleet is on CPU nodes and we want to scale, moving to G5/G6/L4 with [[hardware-accelerated-codecs|NVDEC]] could 5-10x per-pod stream capacity for [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]] streams. See [[hardware-accelerated-codecs]], [[ffmpeg-hardware-acceleration]], [[nvidia-deepstream]] ([[nvidia-deepstream|DeepStream]] is the reference for "max streams per GPU"; we're not using it but the patterns matter).

**Investigation deliverable.** Three concrete checks:
1. SSH to a production connector pod, run `nvidia-smi`, check for an actual GPU.
2. Read the connector EKS node-group Terraform in `ds-terraform-eks-v2/stages/prod/*` to see what instance families are in use.
3. Profile a single high-bitrate [[h264-deep-dive|H.264]] [[rtsp-deep-dive|RTSP]] stream through the connector with `py-spy` on a representative pod. Confirm whether `_decode_packet` is showing CPU time (software decode) or whether NVDEC kernels are firing.

## Prioritized "next investigations" list

In rough order of strategic value × ease of investigation:

1. **F -- Hardware-accel audit on production fleet.** Highest leverage. Could change connector cost-per-stream by an order of magnitude. Investigation is hours not weeks (verify instance families, confirm [[hardware-accelerated-codecs|NVDEC]], profile one stream). Outcome: either a "we're already using it, move on" or a budget spike toward fleet hardware-accel migration.

2. **B -- Live preview spike with [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]].** Highest customer-visible value. One test camera, [[gstreamer-entity|GStreamer]] [[kvs-components|KVS]] Producer, Chrome dispatcher. Day-of-effort. If <2s end-to-end latency, productionize. Could become the differentiator vs Verkada / Eagle Eye.

3. **E -- [[kvs-components|KVS]] pipeline JPEG round-trip fix.** Tactical. Direct, measurable CPU savings on a real customer-segment-relevant path. One-engineer-week. Low risk if behind a feature flag.

4. **A -- MP4 muxing ownership audit.** Identify who owns the downstream Immix FIFO consumer, document it, and decide if it should be folded into a connector pipeline step ([[pyav-entity|PyAV]] write-mode) or kept as a separate service. Bus-factor reduction.

5. **D -- Long-term clip archive cost audit.** Read S3 lifecycle rules in Terraform, calculate current cost per customer for JPEG retention, decide if we'd save by transcoding to [[h264-deep-dive|H.264]] or by moving JPEGs to Glacier. Likely answer: Glacier tier is enough; no need for [[aws-mediapackage-entity|MediaPackage]].

6. **C -- Cross-fleet frame transport.** Defer to fleet-architecture topic; not a video-processing question.

## What this synthesis is *not* saying

- **We should not chase managed services for their own sake.** Every managed service we add is an SLA boundary, a per-MB-out invoice, and a vendor lock-in vector. Our homegrown JPEG-on-S3 + DDB substrate is doing exactly what it should for the alert-frame use case.
- **Build-vs-buy is not a binary.** Some candidates above ([[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] for live preview) are net-new capabilities, not replacements. Others ([[aws-mediaconvert-entity|MediaConvert]] for archive) are buy-side options for capabilities we don't currently have.
- **CPU savings are not the only metric.** Maintenance burden, on-call rotation impact, and engineering velocity matter. A managed service we don't have to debug at 2am is worth real money.

## Cross-references

- End-to-end pipeline context -- [[actuate-video-pipeline-walkthrough]]
- Per-VMS decode detail (where some candidates live) -- [[actuate-frame-ingest-decode-paths]]
- Why MP4 muxing isn't in this codebase -- [[actuate-clip-generation-flow]]
- AWS service positioning -- [[aws-kvs-entity]], [[aws-mediaconvert-entity]], [[aws-medialive-entity]], [[aws-mediapackage-entity]], [[aws-rekognition-video-entity]], [[aws-ivs-entity]], [[aws-video-services-decision-matrix]]
- Codec / accel detail -- [[h264-deep-dive]], [[h265-hevc-deep-dive]], [[hardware-accelerated-codecs]], [[ffmpeg-hardware-acceleration]], [[nvidia-deepstream]]
- Transport latency -- [[webrtc-deep-dive]], [[hls-and-dash]], [[protocol-latency-comparison]]
- Topic landing -- [[reading-list]]
- Cross-topic -- [[fleet-architecture/_summary]], [[vms-connector/_summary]], [[actuate-libraries/_summary]], [[ai-models/_summary]], [[infrastructure/_summary]], [[integrations/kvs/_summary]]
