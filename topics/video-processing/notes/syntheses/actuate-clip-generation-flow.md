---
title: "Actuate Clip Generation Flow (or: where MP4s actually come from)"
type: synthesis
topic: video-processing
tags: [actuate, clip, mp4, mux, immix, alert, s3]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
related: [[immix-mp4-mux-downstream]]
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/ffmpeg-filtergraphs.md
  - topics/video-processing/notes/concepts/hls-and-dash.md
  - topics/video-processing/notes/concepts/immix-mp4-mux-downstream.md
  - topics/video-processing/notes/concepts/mjpeg-and-still-image-formats.md
  - topics/video-processing/notes/entities/aws-mediaconvert-entity.md
  - topics/video-processing/notes/entities/aws-mediapackage-entity.md
  - topics/video-processing/notes/syntheses/actuate-build-vs-buy-tradeoffs.md
  - topics/video-processing/notes/syntheses/actuate-frame-ingest-decode-paths.md
incoming_updated: 2026-06-25
---

# Actuate Clip Generation Flow

How alert clips become MP4 files on S3 (or why they sometimes don't). The TL;DR: **the connector libraries do not mux MP4s today.** Frames are uploaded as individual JPEGs; clip assembly happens in a downstream consumer for Immix MP4 mode, or arrives pre-muxed from upstream for AILink/Frontel/SQS-clip. This synthesis maps the current state, identifies the gap, and evaluates four candidate places where in-process MP4 muxing could live if we owned that path.

## What actually happens today

### The Immix MP4 path (most common)

When `use_mp4=True` on an Immix integration:

1. **Detection windowing fires**, post-processors run.
2. **Each frame in the alert window is uploaded as a JPEG to S3** by `actuate-libraries/actuate-frames/src/actuate_frames/save_frame_meta.py:12-79`. Key shape: `<custcam_id><label>/<window_timestamp>/<frame_id>`. Async via `executor.submit`. The DDB EnrichedFrame row at line 54-73 stores `s3_bucket`, `s3_key`, `frame_id`, `model_labels` so consumers can find the frames.
3. **The Immix sender computes the expected frame count** and hands off to a FIFO queue: `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/immix/immix_alert_sender.py:88-100` calculates `attachment_frames = alert_data.attachment_frame_count * alert_data.product_fps` and pushes an event onto `event_queue_immix_alarm.fifo` with `event_type`, `s3_folder` (the prefix the JPEGs landed under), and the frame count.
4. **A downstream FIFO consumer** (a Lambda / SQS worker that lives **outside** `actuate-libraries`, `vms-connector`, and `actuate-alarm-senders`) reads that FIFO message, downloads the JPEG sequence from `s3_folder`, muxes them into an MP4, and pushes the MP4 to Immix VCH.

Step 4 is the seam. We do not own the muxer in this codebase. The scout pass confirmed this: **no `[[pyav-entity|av]].open(..., mode="w")`, no `[[opencv-entity|cv2]].VideoWriter`, no `[[imageio-entity|imageio]].get_writer`, no `subprocess.run([[ffmpeg-entity|ffmpeg"]], ...])` for muxing exists in `actuate-pullers`, `actuate-pipeline`, or `actuate-alarm-senders`**. The only [[ffmpeg-entity|ffmpeg]] subprocess invocations in the pullers are hardware-accel detection (`av_url_puller.py:546, 562, 567, 587, 597`) and they're bounded with `timeout=5`.

**Resolved:** the consumer is the `queue_consumer` ECS service `prod-queue-immix-consumer` (cluster `prod-queue-consumers-sqs`) running `consumers/immix/immix_consumer.py`. It muxes via raw `subprocess.run([[ffmpeg-entity|ffmpeg"]], "-vcodec", "libxvid", ...])` (so the bytes are actually **AVI/Xvid despite the `.mp4` MIME filename**) and ships the result via **SMTP** to the Immix server, not S3 or HTTP. Full breakdown in [[immix-mp4-mux-downstream]].

### The AILink / Frontel / SQS-clip path

These integrations receive **pre-muxed MP4 clips from upstream**. The clip is written to S3 by some external process (the customer's NVR, a partner integration server, a cloud bridge) and the connector is told "here's the S3 URL of the clip."

The bridge code: `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/shared_alert/clips_alert_bridge.py:34-128`. The function `clips_to_alert_data` maps `ClipsAlertData` (containing `clip_alert_s3_bucket` and `clip_alert_s3_key`) → `AlertData` with the same fields propagated through. The connector neither demuxes nor remuxes. It just forwards the S3 reference.

This is the "least amount of work" path -- and from a video-processing standpoint it's also the cleanest, because the source-of-truth video file already exists.

### The Immix non-MP4 / annotated-image path

`actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/immix/autopatrol_sender.py:102-133` -- `_build_annotated_image_url` annotates the first detection frame, uploads to `annotated/<window_id>/<frame_id>.jpg`, and returns a presigned URL. No video involved at all; it's a single still image. Used for non-MP4 Immix flows.

## The gap, named explicitly

If we ever needed to mux an MP4 inside the connector or its libraries -- say, to remove the FIFO consumer dependency, or to support a new monitoring centre that wants MP4 directly in the alert payload, or to assemble a "preview clip" for the UI -- **we don't have that capability today**. There is no in-process video muxer.

This isn't a bug. It's a choice. JPEG-frames-on-S3-plus-DDB-row is a remarkably flexible substrate: any consumer can stitch the frames into whatever format it wants (MP4, MKV, animated GIF, image sequence) without the connector having to predict its needs. But it does mean every new "I want a clip in format X" requirement adds a downstream service rather than a pipeline step.

## Where would in-process muxing live? Four candidates

If we decided to bring muxing in-house, here are the realistic options. Honest tradeoffs, no library marketing.

### Option A -- [[pyav-entity|PyAV]] `[[pyav-entity|av]].open(..., mode="w")`

The grown-up choice. Same library we already use for decoding (`actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:320-1438`), so no new dependency. Use:

```python
out = av.open(buffer, mode="w", format="mp4")
stream = out.add_stream("h264", rate=fps)
stream.options = {"preset": "ultrafast", "tune": "zerolatency"}
for frame_bgr in frames:
    frame = av.VideoFrame.from_ndarray(frame_bgr, format="bgr24")
    for packet in stream.encode(frame):
        out.mux(packet)
for packet in stream.encode():
    out.mux(packet)
out.close()
```

**Pros:** stays in process, full control over codec/quality, can re-use the existing [[pyav-entity|PyAV]] expertise we built into `av_url_puller.py`, can target [[h264-deep-dive|H.264]] with [[hardware-accelerated-codecs|NVENC]] if hardware is there. Same [[ffmpeg-entity|FFmpeg]] substrate; see [[ffmpeg-entity]], [[pyav-entity]].

**Cons:** real CPU cost on the connector pod. With a typical alert window of 5-15s at 5-10fps, encoding that to [[h264-deep-dive|H.264]] at decent quality is non-trivial -- maybe 100-300ms of CPU per clip depending on resolution and preset. That's cumulative across the fleet. [[hardware-accelerated-codecs|NVENC]] would help; see [[hardware-accelerated-codecs]] and [[ffmpeg-hardware-acceleration]]. [[hardware-accelerated-codecs|NVENC]] is also a per-GPU concurrent-session limit (consumer drivers are deliberately capped, datacenter drivers aren't) -- needs to be checked against our EC2 G5/G6 substrate.

### Option B -- `[[opencv-entity|cv2]].VideoWriter`

The lazy choice. We already use [[opencv-entity|OpenCV]] everywhere (`url_puller.py`, `attachment_alert_sender.py`, `cv2encode_step.py`). One-liner:

```python
writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h))
for frame in frames: writer.write(frame)
writer.release()
```

**Pros:** zero new mental model. Works immediately.

**Cons:** [[opencv-entity|OpenCV]]'s mp4 muxing is **notorious** -- the `mp4v` fourcc is MPEG-4 Part 2, not [[h264-deep-dive|H.264]], and most mobile players + most monitoring centres hate it. Getting [[h264-deep-dive|H.264]] out of `[[opencv-entity|cv2]].VideoWriter` requires [[opencv-entity|OpenCV]] built with [[ffmpeg-entity|FFmpeg]] + a special fourcc (`avc1`), and it's flaky. Not recommended for any monitoring-centre handoff. See [[opencv-entity]], [[cv2-videocapture-internals]] (the `VideoWriter` complement is similarly quirky).

### Option C -- `subprocess.run([[ffmpeg-entity|ffmpeg"]], ...])`

The pragmatic choice. Pipe JPEGs into [[ffmpeg-entity|ffmpeg]] over stdin and let it mux:

```python
proc = subprocess.run(
    ["ffmpeg", "-y", "-f", "image2pipe", "-framerate", str(fps),
     "-i", "-", "-c:v", "libx264", "-preset", "veryfast",
     "-pix_fmt", "yuv420p", out_path],
    input=b"".join(jpeg_bytes_list), timeout=30, check=True,
)
```

**Pros:** [[ffmpeg-entity|ffmpeg]] is bulletproof at this. Tunable, predictable, well-documented. See [[ffmpeg-command-anatomy]], [[ffmpeg-entity]].

**Cons:** subprocess overhead per clip (fork + execve). If we issue this at high cadence (say, 10/sec across the fleet) the fork rate is non-trivial on a busy pod. Process management adds new failure modes -- we already have one untimed `subprocess.run` in `actuate-libraries/actuate-pullers/src/actuate_pullers/shared/base_puller.py:333-339` (the `fish2pano` panorama unwarp) that's a hang risk; we don't want to add more without timeouts and bounded queues.

### Option D -- [[aws-mediaconvert-entity|AWS Elemental MediaConvert]]

The "buy" option. POST a job, [[aws-mediaconvert-entity|MediaConvert]] pulls the frame sequence from S3 and produces an MP4. See [[aws-mediaconvert-entity]], [[aws-video-services-decision-matrix]].

**Pros:** zero compute on our connector. Operationally sound; AWS handles scale, formats, codec licensing.

**Cons:** **not built for short clips**. [[aws-mediaconvert-entity|MediaConvert]] pricing is by output minute and there's a job-level minimum (~6 seconds rounded); a 5s alert clip is billed as 6s. At per-output-minute pricing (varies by codec and tier; [[h264-deep-dive|H.264]] SD is around $0.0075/min on standard, ~$0.015/min on professional), the math at 1000 alerts/day comes to single-digit dollars/day -- not nothing, but not catastrophic either. The bigger issue is **latency**: [[aws-mediaconvert-entity|MediaConvert]] jobs take 30s-2min to schedule and run, which is fine for "save this for the customer to view tomorrow" but **terrible for a monitoring-centre alert that needs to be on a dispatcher's screen in seconds**. [[aws-mediaconvert-entity|MediaConvert]] is the right tool for re-encode-at-rest workflows, not real-time clip assembly. See [[aws-mediaconvert-entity]] for service positioning, [[aws-video-services-decision-matrix]] for the comparison grid.

A **[[aws-mediapackage-entity|MediaPackage]] / [[aws-ivs-entity|IVS]]** path for live preview is a different question; addressed in [[actuate-build-vs-buy-tradeoffs]].

## Recommendation (today, without further investigation)

If we ever need in-process MP4 assembly: **[[pyav-entity|PyAV]] write-mode (Option A)** is the right home. Same library we already use, deepest expressiveness, can grow to [[hardware-accelerated-codecs|NVENC]], and the team is already paying the [[pyav-entity|PyAV]] learning curve in `av_url_puller.py`. The fallback on hardware-accel-absent pods is software x264 at `preset=ultrafast`, which is fine for ~5-15s clips at 720p/5fps.

The two paths to *avoid* unless deliberately chosen:

- `[[opencv-entity|cv2]].VideoWriter` -- the format flakiness will burn us downstream.
- Adding an unbounded `subprocess.run([[ffmpeg-entity|ffmpeg"]], ...])` without a timeout. We have one already (`fish2pano`) and that's enough.

[[aws-mediaconvert-entity|MediaConvert]] is not the right tool for *alert* clip assembly because of latency. It might be the right tool for *archival* re-encoding (cold-storage clip transcoding for cost) -- discussed separately in [[actuate-build-vs-buy-tradeoffs]].

## Side note: the format is already implicit

If we ever do bring muxing in-house, we should pick our format inputs carefully. The frames we'd be muxing today are JPEGs at quality 95, 4:2:0 (`turbojpegencode_step.py:1-31`). That's lossy, so muxing JPEGs into an [[mjpeg-and-still-image-formats|MJPEG]]-in-MP4 container is **lossless** (no re-encoding) but produces large files; muxing JPEGs into [[h264-deep-dive|H.264]] is **transcoding** and costs CPU but produces smaller files monitoring centres prefer. See [[mjpeg-and-still-image-formats]] for why [[mjpeg-and-still-image-formats|MJPEG]]-in-MP4 is the cheap-but-fat choice and [[h264-deep-dive]] for the encode tradeoffs.

## Cross-references

- For who does the muxing today (downstream FIFO consumer) -- the `queue_consumer` ECS service; full detail in [[immix-mp4-mux-downstream]]. Integration overview in [[integrations/immix/_summary]].
- For where managed services *could* fit better than in-process work -- [[actuate-build-vs-buy-tradeoffs]].
- For per-frame ingest detail (the frames that feed a clip) -- [[actuate-frame-ingest-decode-paths]].
- For end-to-end pipeline context -- [[actuate-video-pipeline-walkthrough]].
- For codec-level encode tradeoffs -- [[h264-deep-dive]], [[h265-hevc-deep-dive]], [[hardware-accelerated-codecs]].
- For container choice -- [[mjpeg-and-still-image-formats]] ([[mjpeg-and-still-image-formats|MJPEG]]-in-MP4 lossless option), [[gop-keyframe-fundamentals]].
- For library positioning -- [[ffmpeg-entity]], [[pyav-entity]], [[opencv-entity]], [[aws-mediaconvert-entity]], [[aws-video-services-decision-matrix]], [[knowledgebase/topics/billing/reading-list]].
