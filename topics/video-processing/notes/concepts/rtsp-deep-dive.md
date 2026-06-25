---
title: RTSP Deep Dive
type: concept
topic: video-processing
tags: [rtsp, rtp, transport, streaming, ip-cameras]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - home/offboarding/2026-06-23_watchman-fleet-handoff-paolo-mike.md
  - home/orientation/system-architecture.md
  - home/the-topic-landscape.md
  - home/what-is-actuate.md
  - topics/actuate-libraries/notes/concepts/2026-05-19_stream-publisher-design.md
  - topics/actuate-libraries/notes/concepts/image-cache-strategies.md
  - topics/actuate-libraries/notes/entities/actuate-config.md
  - topics/actuate-libraries/notes/entities/actuate-integration-calls.md
  - topics/actuate-libraries/notes/entities/actuate-pullers.md
  - topics/actuate-libraries/notes/syntheses/2026-05-12_adr-actuate-instrumentation-v1.md
incoming_updated: 2026-06-25
---

# RTSP Deep Dive

**Real-Time Streaming Protocol** is the lingua franca of IP cameras and the primary protocol surface for Actuate's connector. RTSP is **not a media transport** -- it's a control protocol (think "remote VCR") that negotiates an RTP session which then carries the actual media. Understanding the split is the first step to understanding why RTSP behaves the way it does.

## Protocol mechanics

### RTSP/1.0 (RFC 2326)

RTSP looks like HTTP/1.1 (request-response, ASCII headers, `CSeq` instead of nothing) but is *not* HTTP. The canonical session-establishment dance is:

1. **`OPTIONS rtsp://cam/`** -- discover supported methods.
2. **`DESCRIBE rtsp://cam/stream1`** -- server returns an **SDP** (RFC 4566) blob describing media tracks, [[codecs-overview|codecs]], and (for some cameras) the SPS/PPS in `fmtp` parameters.
3. **`SETUP rtsp://cam/stream1/trackID=0`** -- one per track (video, audio). Client proposes a transport (`Transport: RTP/AVP/UDP;unicast;client_port=...` or interleaved TCP). Server responds with a `Session:` ID and the chosen transport.
4. **`PLAY`** -- start streaming. Now RTP packets begin flowing.
5. **`TEARDOWN`** -- end the session.

`GET_PARAMETER` is also used as a poor-man's keepalive when the camera doesn't honour TCP-level keepalives.

### RTP-over-UDP vs RTP-over-TCP-interleaved

Two transports matter in practice:

- **RTP/AVP/UDP** -- two UDP ports per track (RTP + RTCP, even/odd). Lowest latency. Loss is tolerated; RTCP receiver reports surface stats but there's no built-in retransmit. Punching through NAT requires either UPnP, an explicit DMZ, or symmetric RTP. **Hard to make work behind enterprise firewalls.**
- **RTP/AVP/TCP "interleaved"** -- RTP packets are tunnelled inside the same TCP socket as the RTSP control channel, framed by a 4-byte header: `$<channel><len_be16>` then `<len>` bytes of RTP. No extra ports, single connection, NAT-friendly. **This is what Actuate forces.** The cost: head-of-line blocking on packet loss, slightly higher latency floor, and TCP backoff when the path is congested.

### RTSP/2.0 (RFC 7826)

Effectively dead in the wild. Almost no cameras implement it; almost no clients try. Treat any "RTSP/2.0" claim as marketing.

### Latency profile

Glass-to-glass with RTSP-over-TCP from a mid-tier IP camera:

- Camera encoder: 50-200ms (depends on [[gop-keyframe-fundamentals|GOP]] / B-frame use)
- Network serialization (TCP, jitter buffer): 100-500ms
- Decoder buffer (libavformat `analyzeduration`/`probesize`, our setting: 300ms / 128KB): 300-500ms
- Application handling (puller queue, downscale, push to inference): 50-200ms

Expect **500ms-1.5s** end-to-end on a healthy LAN, **1-3s** over the public internet. RTSP-over-UDP can shave 100-300ms off by skipping TCP back-pressure but costs reliability.

### NAT issues

UDP RTP requires the *server* (the camera) to send packets to the *client*. When the client is behind NAT, the camera can't reach it without explicit port mapping. RTSP doesn't have ICE; it has only `Transport: client_port=...` which is a static promise. This is why every cloud-hosted RTSP puller (us included) forces TCP transport.

## Why TCP transport is forced in Actuate

Cameras live behind customer routers; our pullers run in EKS. UDP RTP would require either:

1. Customer-side firewall-punching for our IP block (operational nightmare), or
2. A relay on the customer side (defeats the point).

TCP-interleaved sidesteps the entire NAT problem at the cost of HOL blocking. Empirically, the latency hit is worth it for the connection-success rate.

## Where RTSP lives in Actuate

This is the **primary protocol surface** of the connector. There are three concurrent decode paths:

### [[pyav-entity|PyAV]] path (default for most VMSes)

[`actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:320-1438`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py)

Uses `av.open(url, options={...})` ([[pyav-entity]] / libav) with these options forced ([`:412-494`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py)):

- `rtsp_transport=tcp`
- `probesize=131072` (128KB)
- `analyzeduration=300000` (300ms in microseconds)
- `fflags=discardcorrupt`
- `stimeout` (socket I/O timeout, microseconds)

The probesize / analyzeduration tuning is the latency-vs-codec-detection knob -- shorter values risk libav not detecting all streams correctly on rare cameras; longer values directly add to startup latency.

### [[opencv-entity|OpenCV]] legacy path

[`actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py:17-395`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py)

`cv2.VideoCapture(url)` ([[opencv-entity]]) under the hood is *also* libavformat -- but the option surface is leaked through an env var: `OPENCV_FFMPEG_CAPTURE_OPTIONS=rtsp_transport;tcp` set at import time for `omniaweb` and `eagleeyenetworks` (lines 314, 318). This is a global process env var which means it affects *every* [[opencv-entity|cv2]] capture in the process; a known footgun. See [[cv2-videocapture-internals]].

### Motion-gated RTSP

[`actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller_motion.py:20-100+`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller_motion.py)

Same RTSP backend, but the puller idles unless an external motion detector signals activity. Used by `openeye` and `milestone_rtsp` to manage encoder load.

### [[gstreamer-entity|GStreamer]] path ([[h264-deep-dive|H.264]]-only, silently)

[`actuate-libraries/actuate-pullers/src/actuate_pullers/url/gst_url_puller.py:11-62`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/gst_url_puller.py) wraps the pipeline at [`gstreamer_input_pipeline.py:86-101`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/gstreamer/gstreamer_input_pipeline.py):

```
rtspsrc ! rtph264depay ! h264parse ! avdec_h264 ! videorate ! videoconvert ! jpegenc ! appsink
```

**This pipeline is hardcoded for [[h264-deep-dive|H.264]].** Any [[h265-hevc-deep-dive|H.265/HEVC]] RTSP stream piped here will fail at the depayloader stage with no graceful fallback to [[pyav-entity]]. This is a **silent gap** -- worth flagging in any "should we move this VMS to the [[gstreamer-entity|GST]] path?" discussion. See [[h265-hevc-deep-dive]] for context on encoder-side prevalence.

The pipeline also re-encodes to JPEG (via `jpegenc`) before `appsink` so that the Python side gets compressed frames it can decode with [[opencv-entity]]. That's a double-encode: [[h264-deep-dive|H.264]] -> raw -> JPEG -> raw. See [[gstreamer-vs-ffmpeg]] for whether to keep this.

## Actuate touchpoints

- **Primary RTSP decoder**: [`actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:320-1438`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py) ([[pyav-entity]] / libav, forces `rtsp_transport=tcp`; probesize 128KB / analyzeduration 300ms / `discardcorrupt`)
- **[[opencv-entity|OpenCV]] path**: [`actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py:17-395`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py) -- env-var-controlled, used by omniaweb, eagleeyenetworks
- **Motion-gated**: [`url_puller_motion.py:20-100+`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller_motion.py) -- openeye / milestone_rtsp
- **[[gstreamer-entity]] ([[h264-deep-dive|H.264]] only)**: [`gst_url_puller.py:11-62`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/url/gst_url_puller.py) -> [`gstreamer_input_pipeline.py:86-101`](file:///home/mork/work/actuate-libraries/actuate-pullers/src/actuate_pullers/gstreamer/gstreamer_input_pipeline.py); pipeline is `rtspsrc ! rtph264depay ! h264parse ! avdec_h264 ! videorate ! videoconvert ! jpegenc ! appsink`. **[[h265-hevc-deep-dive|H.265]] silently fails on this path.**
- See also [[actuate-frame-ingest-decode-paths]], [[integrations/rtsp/_summary]], [[vms-connector/_summary]].
- For latency comparison against other transports: [[protocol-latency-comparison]].
- For tooling alternatives (MediaMTX, Live555, GO2RTC) see [[knowledgebase/topics/billing/reading-list]].
