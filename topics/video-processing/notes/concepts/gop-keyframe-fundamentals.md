---
title: GOP and Keyframe Fundamentals
type: concept
topic: video-processing
tags: [gop, keyframe, idr, latency, decode]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-phase2-stream-probe.md
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/codecs-overview.md
  - topics/video-processing/notes/concepts/cv2-videocapture-internals.md
  - topics/video-processing/notes/concepts/ffmpeg-command-anatomy.md
  - topics/video-processing/notes/concepts/frame-extraction-strategies.md
  - topics/video-processing/notes/concepts/h264-deep-dive.md
  - topics/video-processing/notes/concepts/h265-hevc-deep-dive.md
  - topics/video-processing/notes/concepts/hardware-accelerated-codecs.md
incoming_updated: 2026-05-01
---

# GOP and Keyframe Fundamentals

A **Group of Pictures (GOP)** is the basic structural unit of an inter-frame-coded video stream: a sequence starting with a keyframe and continuing through subsequent dependent frames until the next keyframe. GOP structure controls **first-frame decode latency**, **error resilience**, **random-access granularity**, and **bitrate efficiency** — all of which are at odds with each other. Most surveillance-decode pain in Actuate traces back to choices the camera made about its GOP, often without exposing the choice to the operator.

## I, P, B and IDR

- **I-frame (intra-coded)** — coded purely from itself, no inter-frame references. The first frame of any GOP.
- **IDR I-frame (Instantaneous Decoder Refresh)** — an I-frame that *also* invalidates the decoder's reference buffer. After an IDR, no subsequent frame may reference any prior frame. IDRs are required entry points for clean stream join.
- **Non-IDR I-frame** — an I-frame that does *not* clear the reference buffer. Useful for compression (more reference variety) but doesn't allow random access. Less common in surveillance.
- **P-frame (predicted)** — references one or more prior frames via motion vectors + residual.
- **B-frame (bidirectional)** — references both prior and future frames. Adds latency (decode order ≠ display order).

Surveillance cameras typically use IDR-only intra-frames (no non-IDR I), almost always with B-frames disabled (B-frames cost first-frame latency and serve no purpose for short-GOP surveillance streams). So the practical pattern is `IDR P P P P P ... IDR P P P P P ... IDR ...` — call this a *closed GOP* because no frame outside a GOP can reference inside it.

## Open vs closed GOP

- **Closed GOP** — every GOP is fully self-contained. Random access at every IDR. Default for surveillance.
- **Open GOP** — first few frames of a new GOP may reference frames at the end of the prior GOP (typically B-frames doing this). Better compression at the cost of less clean random-access.

"Closed GOP" is the right default for our use case and is what we encounter in practice. Open GOP shows up in broadcast and streaming workflows but is rare in surveillance.

## Keyframe interval (GOP length)

The number of frames between consecutive IDRs. Common values:

- **Short (1s, ~30 frames at 30fps)** — best random-access and reconnect latency. Worst bitrate efficiency. Used by some VMS-targeted cameras.
- **Medium (2–4s, 60–120 frames)** — typical balance. Default on most IP cameras.
- **Long (10s+, 300+ frames)** — best bitrate efficiency for static scenes. Worst random-access. Common on bandwidth-constrained sites.
- **Adaptive** — camera inserts an IDR on motion / scene change in addition to a long minimum interval. Best of both worlds when the camera is competent, worst when the firmware is buggy.

The keyframe interval directly drives:

1. **First-frame decode latency on stream join.** If you join the stream right after an IDR, you decode immediately. If you join right before, you wait up to GOP-length seconds. **Mean wait = GOP/2** assuming uniform join time.
2. **Reconnect / corruption recovery cost.** Same arithmetic — after `fflags=discardcorrupt` triggers, you wait for the next IDR.
3. **Seek granularity in recorded video.** Playback can only resume at IDRs.
4. **Bitrate.** Long GOP = far better compression, especially for static scenes.

A 10-second GOP camera, observed in real Actuate deployments, gives a worst-case 10-second cold-start before any frame can be served to the AI pipeline. That's catastrophic for live-preview UX and even bad for first-detection-after-reconnect time.

## Why this drives the Actuate decode budget

The end-to-end "URL → first decoded numpy frame" budget on the connector pull path is approximately:

```
fetch SDP / first packet     ~100ms (RTSP) or 0ms (HTTP fMP4)
demuxer probe / analyze      ~300ms (probesize=128KB, analyzeduration=300ms)
wait for first IDR           0..GOP_LENGTH/2 seconds typical, GOP_LENGTH worst-case
decode IDR                   ~5-30ms software, ~1-5ms hardware
copy to numpy + colorspace   ~5-10ms
```

The GOP-wait term dominates everything else when GOP is long. This is the latency the puller hides via:

**Reduced probesize / analyzeduration** — `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:412-494` sets `probesize=128KB` and `analyzeduration=300ms` (vs. libav's much higher defaults). This trims demuxer probe time but **does not** affect the IDR-wait term. It's a constant shave, useful but not the big lever.

**Discard corrupt packets** — `fflags=discardcorrupt` in the same option dict. Pairs with the keyframe-wait guard.

**Keyframe-wait guard at `av_url_puller.py:1318-1335`** — explicitly drops packets until the first keyframe arrives. Counter-intuitively, this *increases* observed first-frame latency, but it converts "show a corrupt frame" failures (especially severe with [[h265-hevc-deep-dive|H.265]]) into "show no frame for slightly longer." The AI pipeline cannot consume corrupt frames usefully, so the right policy is wait.

## Adaptive frame-skip via AVDiscard

A subtler optimization in the puller: when GOP is short, the camera produces enough keyframes per second that we can survive on keyframes alone for some downstream tasks (snapshot endpoints, low-fps inference). The AVDiscard logic at `av_url_puller.py:617-753`:

1. Measures observed keyframe rate over a 10-second window.
2. If `keyframe_fps >= target_fps * 1.5` (i.e., "more keyframes coming in than we need to send out"), sets the libav `skip_frame=NONKEY` flag — the demuxer drops every non-keyframe packet without entering decode.
3. Re-evaluates every 5 minutes (the keyframe rate can shift as the camera adapts to scene content).
4. **Starvation detection** — if keyframes stop arriving (camera went into long-GOP mode after a scene-change IDR burst), falls back to `skip_frame=DEFAULT` so the decoder can produce frames from P-frames again.

This is **skipped** for two cases:

- **Hardware decoders** — the libav AVDiscard mechanism interacts poorly with hardware decode contexts; skipping is gated behind a software-decode check.
- **Intra-only [[codecs-overview|codecs]]** ([[mjpeg-and-still-image-formats|MJPEG]], etc.) — every frame is a keyframe, so the optimization is a no-op or worse.

The outcome on the right cameras: meaningful CPU savings on long-tail cameras whose target fps is 1–5 but whose source fps is 30 with a 1-2s GOP. We're decoding 1/15 of the bytes we'd otherwise decode.

## The fMP4 fragment-leak workaround

Tangentially related to GOP behavior: [[pyav-entity|PyAV]]'s `mov` demuxer leaks the `frag_index` table over time on long-running fMP4 streams. The leak is ~5–10 MB/hr per stream — innocuous for short jobs, fatal for the always-on connector. Mitigation at `av_url_puller.py:496-503, 1158-1185`: every 300 seconds (with jitter, to avoid thundering-herd recycle on multi-camera sites), the puller recycles the demuxer — closes and reopens the container. This forces a full re-probe and IDR-wait, but it's the only known path to flush the leak short of patching libav.

## Common gotchas

1. **First-frame latency is dominated by IDR-wait.** Tuning probesize matters but is a smaller lever. If you can influence the camera's GOP setting (rare in operator-provisioned hardware), prefer 1–2s GOP for live-preview use cases.
2. **Reconnect storms produce IDR-wait stacking.** If 100 cameras reconnect simultaneously after a network blip, all 100 wait for their next IDR; CPU is idle but no frames flow. Stagger reconnects.
3. **Adaptive cameras emit IDR bursts on motion.** A hot scene produces frequent IDRs (good for join latency, bad for bitrate). A quiet scene reverts to long GOP. The AVDiscard logic must handle the transition; the starvation fallback exists exactly for this.
4. **B-frame surprises.** Most surveillance cameras don't emit B-frames, but some "broadcaster-friendly" cameras do; this adds reorder latency and breaks naive "PTS in order" assumptions.
5. **`skip_frame=NONKEY` can mask underlying decode failures.** If non-keyframes are corrupt and we're discarding them, we wouldn't notice until keyframes also fail. Log the discard mode change.

## Actuate touchpoints

- Per-hwaccel option dict (low-latency [[rtsp-deep-dive|RTSP]] tuning: probesize=128KB, analyzeduration=300ms, fflags=discardcorrupt) — `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:412-494`
- Adaptive AVDiscard frame-skip with starvation fallback — `av_url_puller.py:617-753`
- Keyframe-wait guard (drop packets until first IDR) — `av_url_puller.py:1318-1335`
- fMP4 demuxer recycle every 300s + jitter ([[pyav-entity|PyAV]] mov frag_index leak workaround) — `av_url_puller.py:496-503, 1158-1185`
- Cross-topic: [[h264-deep-dive]], [[h265-hevc-deep-dive]], [[hardware-accelerated-codecs]], [[actuate-frame-ingest-decode-paths]], [[reading-list]].
