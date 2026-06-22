---
title: "KVS WebRTC as Fleet Frame-Plane (sub-second cross-fleet delivery evaluation)"
type: synthesis
topic: video-processing
tags: [bridge, fleet-architecture, kvs, webrtc, frame-transport, live-preview, preliminary]
jira: ""
confluence: ""
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/video-processing/_summary.md
incoming_updated: 2026-05-01
---

# KVS [[webrtc-deep-dive|WebRTC]] as Fleet Frame-Plane

**Lede:** Fleet-architecture's frame-transport comparison evaluates Redis Streams / NATS JetStream / SNS+SQS / S3-refs for inter-pod messaging. Could AWS [[aws-kvs-entity|Kinesis Video Streams]] [[webrtc-deep-dive|WebRTC]] signaling channels bridge that gap? This note evaluates the fit for sub-second cross-fleet frame delivery.

## What KVS [[webrtc-deep-dive|WebRTC]] actually is

[[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] is **not** the [[kvs-components|KVS]] Producer path we use today for camera ingest. It's a separate API surface: managed [[webrtc-deep-dive|WebRTC]] **signaling channels** that handle the connection negotiation between a master (publisher) and viewers. AWS hosts:

- The signaling endpoint (SDP offer/answer exchange over WSS).
- STUN servers (public-IP discovery).
- TURN relay service (NAT traversal when direct ICE fails).

Once signaling completes, media flows **peer-to-peer** (if both sides can negotiate direct path) or **via TURN relay** (if NAT prevents direct). Latency floor is **sub-second** — realistic ~400ms–1s glass-to-glass on typical AWS+customer-NAT paths. See [[webrtc-deep-dive]] for the protocol stack.

**Key constraint:** [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] is **1:N broadcast model** — one master, many viewers. Not a full SFU (Selective Forwarding Unit). If you need many-to-many or viewer-to-viewer, you're out of scope.

## Three candidate use cases

### 1. Inter-fleet frame transport (puller → inference pipeline)

**Model:** pullers fetch [[rtsp-deep-dive|RTSP]] from cameras, push frame bytes to a pipeline fleet; pipeline fleet decodes and infers. High-volume, every-frame, unidirectional.

**Could [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] work?** Technically yes — you could set up a puller pod as master, inference pods as viewers, and stream [[h264-deep-dive|H.264]] or raw frames over [[webrtc-deep-dive|WebRTC]].

**Why it's weak:** This workload doesn't need [[webrtc-deep-dive|WebRTC]]'s properties.

- **Cost:** [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] charges per-signaling-channel-minute plus per-GB TURN relay. For 100 cameras × 10 inference consumers, that's 100 channels open continuously — each consuming channel-minutes. Compare against Redis Streams (one [[kvs-components|KVS]] pod, amortized CPU/memory), NATS JetStream (same), or SNS+SQS (per-message, but extremely cheap at volume). [[webrtc-deep-dive|WebRTC]]'s TURN relay is an extra step only if NAT forces it; for pod-to-pod in EKS, direct UDP (via Calico/Cilium) or simple TCP (Redis/NATS) is cheaper.
- **Latency variance:** [[webrtc-deep-dive|WebRTC]]'s sub-second floor is good, but the protocol's jitter buffer adds adaptive buffering (30–150ms depending on network noise). For a frame-at-a-time "newest frame only" ingest, you don't need that buffer; you'd want the lowest-latency raw-bytes transport. NATS JetStream or Redis Streams with subject-keying lets you subscribe to "latest camera X", not "all frames X ordered".
- **Producer-side stack:** [[webrtc-deep-dive|WebRTC]] needs an encoder ([[h264-deep-dive|H.264]] / [[av1-vp9-future|VP9]]). In the puller pod, you either encode [[rtsp-deep-dive|RTSP]]→[[h264-deep-dive|H.264]] (extra CPU, already done for inference anyway), or push raw frames ([[webrtc-deep-dive|WebRTC]] doesn't have an ergonomic raw-frame codec path). The cognitive and operational load is higher than "write bytes to Redis list".

**Verdict: ❌ Probably not.** Redis Streams, NATS JetStream, or even SNS+SQS are the right shapes for high-volume every-frame inter-pod transport.

### 2. Live preview to dispatcher (pod-to-browser)

**Model:** puller pod (or inference consumer) has a live [[h264-deep-dive|H.264]] stream; dispatcher's browser needs to see it sub-second. Typically one operator viewing one camera.

**Could [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] work?** Yes, exactly. This is what [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] was built for.

**Why it's strong:**

- **Latency:** 400ms–1s is acceptable for a human watching an event unfold in real time. Not as fast as RTSP-direct-to-VMS (often unavailable), much better than [[hls-and-dash|HLS]]/[[hls-and-dash|DASH]] (2–5s realistic).
- **Browser-native:** JavaScript `RTCPeerConnection` API works in all modern browsers. AWS SDK handles the signaling. No custom WebSocket server or TURN infrastructure to operate.
- **Costs are reasonable:** If only "active alert" cameras stream (not all cameras simultaneously), the channel-minute cost is predictable. TURN relay kicks in only for ~10–15% of client pairs.
- **Producer path is natural:** [[h264-deep-dive|H.264]] encoder already exists in the pipeline; WebRTC-encode a copy to a [[kvs-components|KVS]] signaling channel as a secondary output.

**Verdict: ✅ Plausible and worth a spike.** This is a live-preview-to-dispatcher use case Actuate doesn't have today (operators see alert clips, not live video). [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] would be the simplest AWS-native path.

### 3. [[watchman-repo|Watchman]] live-view / real-time monitoring

**Model:** A VLM (vision language model) agent watches a live frame stream and reasons about it in real time. Today, [[watchman-repo|Watchman]] processes alert clips after the fact; for live triage, you want the agent to see frames now.

**Could [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] work?** Yes, same mechanics as #2.

**Why it's plausible:**

- The [[watchman-repo|Watchman]] consumer can join as a viewer, pull frames from the signaling channel's media stream, and ingest them into its VLM pipeline.
- Latency requirement is similar (sub-second for responsiveness) but less strict (an agent doesn't perceive "jerky" video the way a human does).
- Cost shape is identical to #2: one channel per camera, one viewer (the [[watchman-repo|Watchman]] agent). ([[watchman/_summary]] notes the current architecture; a live-view addition would be a small extension.)

**Verdict: ✅ Plausible,** but tied to #2. If we solve live-preview for dispatchers, [[watchman-repo|Watchman]] live-view is a secondary win.

## Comparison to alternatives

### Self-hosted [[webrtc-deep-dive|WebRTC]] (Pion / aiortc / LiveKit)

- **Full control:** Implement exactly the topology and security you need. No vendor lock-in to [[kvs-components|KVS]] API changes.
- **More operational toil:** You host the SFU (or P2P signaling server), manage TURN infrastructure, patch [[webrtc-deep-dive|WebRTC]] library updates, handle ICE failures.
- **Cost at low scale:** Self-hosted Pion on EKS with modest TURN relay is ~equivalent to [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] once you account for engineering time. At high scale (many cameras, many concurrent viewers), self-hosted potentially beats AWS-managed because you amortize SFU cost across streams.

**For Actuate's shape (internal tools, low concurrent viewers per feed):** [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] is simpler. If we ever ship a public live-preview product with variable viewer scale, re-evaluate.

### LiveKit (open core + cloud option)

- **Intermediate:** More features than bare Pion (recording, analytics, composition), less operational toil than self-hosted.
- **Cost:** per-minute participant pricing similar to IVS Real-Time — potentially expensive if every camera is a publisher and multiple viewers [[watch-entity|watch]].

**Verdict:** Reasonable as a fallback if [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] proves too limiting. Not the first choice for Actuate.

### Redis Streams / NATS JetStream for inter-pod, IVS Real-Time for browser

Some teams split the problem: use a message bus (Redis / NATS) for pod-to-pod frame transport (case #1), and a separate service (IVS Real-Time or [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]]) only for the outbound-to-browser legs (cases #2, #3). This is feasible but adds complexity — you're managing two transport [[layers]].

## Cost shape

| Scenario | Component | [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] | Self-hosted Pion | Redis Streams | NATS JetStream |
|----------|-----------|-----------|------------------|---------------|---|
| **100 cameras, dispatcher live-preview** | Signaling channels (100) + TURN relay (est. 10% of viewers, ~100 GB/month) | ~$15/mo channels + ~$5/mo TURN | ~$50/mo EKS node + TURN ops | N/A | N/A |
| **Inter-pod frame shuttle, all 100 cameras** | 100 channels + heavy TURN (pod-to-pod NAT edge case, rare) | ~$15/mo channels + minimal TURN | N/A | ~$30/mo pod + 1000 GB shared costs (amortized) | ~$30/mo pod + shared costs |
| **[[watchman-repo|Watchman]] live-view (10 concurrent cameras)** | 10 channels + TURN (10% relay) | ~$2/mo channels + <$1 TURN | ~$50/mo EKS node | N/A | N/A |

Rough estimates. Real costs depend heavily on frame resolution, bitrate, and TURN relay %. [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]]'s per-channel model works best when channels are sparse and episodic (not always-on). **For always-on pod-to-pod, Redis/NATS wins on cost.** For episodic browser preview, [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] wins on ops simplicity.

## Lock-in assessment

**[[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]]:** Medium lock-in.

- The signaling protocol is standard [[webrtc-deep-dive|WebRTC]]; the master/viewer model and IAM auth are KVS-specific.
- Migration to self-hosted Pion or LiveKit is **straightforward** — replace [[kvs-components|KVS]] signaling endpoint with your own SFU endpoint, keep the encoder/decoder stack ([[h264-deep-dive|H.264]], [[webrtc-deep-dive|WebRTC]] media).
- Migration to IVS Real-Time is also plausible (same [[webrtc-deep-dive|WebRTC]] stack, different signaling).

Not as sticky as, say, picking a proprietary VMS vendor. If [[kvs-components|KVS]] becomes a cost problem or AWS deprecates the service, the switching cost is weeks, not months.

## Verdict for fleet-architecture

Squint at [[fleet-architecture/_summary]] and [[2026-04-16_proposal-*]] notes:

- **Inter-pod high-volume (case #1):** ❌ **Not the right tool.** Stick with Redis Streams / NATS JetStream / SNS+SQS. They're cheaper, simpler, and more Actuate-shaped for every-frame transport.

- **Outbound live-preview to dispatcher (case #2):** ✅ **Worth a small spike.** A 1-week evaluation on the dispatcher live-preview use case would yield real cost and latency numbers, unblock the UX, and resolve the "do we self-host [[webrtc-deep-dive|WebRTC]] or use AWS?" question.

- **[[watchman-repo|Watchman]] live-view (case #3):** ✅ **Plausible secondary outcome.** Shares the [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] plumbing with #2. If we build #2, #3 is ~1 week of integration.

## Next steps (if pursued)

1. **Spike outline:** Set up a test puller pod that encodes [[h264-deep-dive|H.264]] and publishes to a [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] signaling channel. Have a dummy consumer (browser or test client) join as viewer. Measure glass-to-glass latency, TURN relay activation rate, and cost for 24h continuous run.
2. **Cost template:** Sketch out "100 cameras, 10 concurrent alerts, 2 dispatchers per alert" cost for [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] vs self-hosted Pion. Use the spike data to validate assumptions.
3. **Decision:** If [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] + live-preview ROI is positive (dispatcher UX + reasonable cost), commit to building it. If not, revisit self-hosted Pion or schedule for later.

---

> **Status: preliminary draft (2026-04-27).** [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] is a strong candidate for outbound live-preview and [[watchman-repo|Watchman]] feeds; weak fit for inter-pod high-volume frame transport. A 1-week spike on the dispatcher live-preview use case would yield definitive cost and latency numbers and unblock the broader fleet-architecture decision.

## Related notes

- [[fleet-architecture/_summary]] — the redesign effort that raised the question.
- [[aws-kvs-entity]] — [[kvs-components|KVS]] Producer (today's usage) and [[webrtc-deep-dive|WebRTC]] overview.
- [[aws-ivs-entity]] — IVS Real-Time as an alternative for interactive use cases.
- [[aws-video-services-decision-matrix]] — decision grid across all AWS video services.
- [[webrtc-deep-dive]] — protocol stack, ICE, DTLS-SRTP, SFU vs P2P.
- [[protocol-latency-comparison]] — glass-to-glass latency table ([[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]] vs [[rtsp-deep-dive|RTSP]] vs [[hls-and-dash|HLS]], etc.).
- [[watchman/_summary]] — [[watchman-repo|Watchman]] architecture; live-view would be an extension.
