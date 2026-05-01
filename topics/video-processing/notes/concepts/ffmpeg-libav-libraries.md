---
title: "FFmpeg libav* libraries"
type: concept
topic: video-processing
tags: [ffmpeg, libav, libavcodec, libavformat, library, c-api]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# [[ffmpeg-entity|FFmpeg]] libav* libraries

When developers say "[[ffmpeg-entity|FFmpeg]]" they usually mean the `ffmpeg` binary. But the `ffmpeg` binary is a thin orchestrator over a much more important asset: the **`libav*` library family**. These C libraries are what every other open-source video tool actually links against. Understanding their split clarifies why so many codepaths in Actuate ([[pyav-entity|PyAV]], [[opencv-entity|OpenCV]], [[gstreamer-entity|GStreamer]]'s `gst-libav`, MoviePy, decord, [[imageio-entity|imageio]]) are really the same library underneath, just with different glue.

> **Confusing-name aside**: there is also a project called **Libav** (no asterisk), a 2011 fork of [[ffmpeg-entity|FFmpeg]] that died in 2018. The current `libav*` libraries belong to [[ffmpeg-entity|FFmpeg]], not the abandoned fork. Inside [[ffmpeg-entity|FFmpeg]]'s source tree the libraries are still called `libav*` for legacy reasons.

## The library split

| Library | What it does |
|---------|--------------|
| **libavcodec** | Codec implementations: [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]], [[av1-vp9-future|VP9]], [[av1-vp9-future|AV1]], AAC, Opus, [[mjpeg-and-still-image-formats|MJPEG]], JPEG2000, ProRes, DV, and ~hundreds more. Decoder + encoder pairs. |
| **libavformat** | Container muxers/demuxers: MP4, MKV, [[mpeg-ts-over-udp|MPEG-TS]], WebM, FLV, [[rtsp-deep-dive|RTSP]], [[rtmp-and-srt|RTMP]], [[hls-and-dash|HLS]], [[hls-and-dash|DASH]]. Also the protocol layer (`http`, `rtsp`, `tcp`, `udp`, `pipe`). |
| **libavfilter** | Filtergraph engine — scale, crop, overlay, hstack, format conversion, audio mixing, and so on. The C-API equivalent of `-vf` / `-filter_complex`. See [[ffmpeg-filtergraphs]]. |
| **libavutil** | Common utilities: pixel format definitions, AVFrame/AVPacket structs, math helpers, hardware-frame contexts, error codes. Almost everything else depends on this. |
| **libswscale** | Pixel format and color space conversion + resampling. The thing that turns a `YUV420P` into `BGR24` (which is exactly what [[pyav-entity|PyAV]] does at `av_url_puller.py:1351`). |
| **libswresample** | Audio sample-format conversion (the audio analogue of swscale). |
| **libavdevice** | Capture/playback device APIs: V4L2, AVFoundation, DirectShow, dshow, ALSA, PulseAudio. Used to make `ffmpeg -f v4l2 -i /dev/video0` work. Rarely used in server contexts. |

(There were two more historical libraries — **libpostproc** (legacy MPEG postprocessing) and **libavresample** (a Libav-fork audio resampler) — that are deprecated or removed in modern [[ffmpeg-entity|FFmpeg]].)

## Why "[[ffmpeg-entity|FFmpeg]]" the project ≠ `ffmpeg` the binary

The `ffmpeg` binary is roughly **3000 lines of C glue** (in `fftools/ffmpeg.c`) wrapping the libraries. Almost all the heavy lifting — packet parsing, codec dispatch, color conversion, filter graph evaluation, hwaccel context management — happens inside the libraries. The binary's job is:

1. Parse CLI options into AVDictionary structures.
2. Open inputs via `avformat_open_input()`.
3. Read packets via `av_read_frame()`.
4. Dispatch to decoders via `avcodec_send_packet()` / `avcodec_receive_frame()`.
5. Push frames through a filtergraph via `av_buffersrc_add_frame()` / `av_buffersink_get_frame()`.
6. Encode and mux the results.

Anything you can do with the `ffmpeg` binary, you can do by linking the libraries directly. That's exactly what every binding listed in the next section does.

## Who uses the libraries (not the binary)

| Consumer | How it uses libav* |
|----------|-------------------|
| **[[pyav-entity]]** | Cython bindings to the C API. Surfaces `av.Container`, `av.Stream`, `av.Packet`, `av.Frame` directly. Most "Pythonic" of the bindings. |
| **[[opencv-entity]]** (`cv2.VideoCapture`) | Bundles its own statically-linked [[ffmpeg-entity|FFmpeg]] in `opencv-python` PyPI wheels. Reads via libavformat, decodes via libavcodec, converts via libswscale to BGR. |
| **[[gstreamer-entity|GStreamer]] `gst-libav`** | `decodebin` and `videoconvert` elements wrap libav*. Most [[gstreamer-entity|GStreamer]] pipelines that decode [[h264-deep-dive|H.264]] are routed through `avdec_h264` (libavcodec) or `nvh264dec` ([[hardware-accelerated-codecs|NVDEC]], separate path). See [[gstreamer-vs-ffmpeg]]. |
| **MoviePy** | High-level editing API; uses `imageio-ffmpeg` underneath, which subprocess-calls `ffmpeg` (so technically not direct linking). |
| **decord** | Custom C++ reader on top of libavformat/libavcodec, focused on random-access frame indexing for ML training. |
| **VLC** | Optional libav* backend (alongside its native demuxers). |
| **Handbrake** | Statically links libav* for decoding; uses x264/x265 directly for encoding. |
| **ffmpeg-python** | Builds shell command strings and `subprocess.run`s them. Doesn't link libav* itself but generates `ffmpeg` invocations. |
| **[[nvidia-deepstream|NVIDIA DeepStream]]** | Has its own `Gst-nvvideo4linux2` decoder path on [[hardware-accelerated-codecs|NVDEC]], but the `nvurisrcbin` element falls back to libav* for unsupported [[codecs-overview|codecs]]. |
| **Every video editor on Earth** (Premiere, Final Cut, DaVinci, Kdenlive, Blender) | At least demux through libavformat. Most also decode through libavcodec for "weird" formats. |

The corollary: **bug-for-bug compatibility across all of these is the norm** when libav* upstream has a bug. If a stream decodes wrong in ffmpeg-CLI, it almost certainly decodes wrong in [[pyav-entity|PyAV]] and [[opencv-entity|OpenCV]] too.

## The C-API mental model

A simplified read-loop in pseudo-C looks like this:

```c
AVFormatContext *fmt;
avformat_open_input(&fmt, "input.mp4", NULL, NULL);
avformat_find_stream_info(fmt, NULL);

int video_idx = av_find_best_stream(fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
AVCodecContext *cc = ...;  // alloc + open with the right codec
AVPacket *pkt = av_packet_alloc();
AVFrame  *frm = av_frame_alloc();

while (av_read_frame(fmt, pkt) >= 0) {
    if (pkt->stream_index != video_idx) continue;
    avcodec_send_packet(cc, pkt);
    while (avcodec_receive_frame(cc, frm) == 0) {
        // frm->data[] is a YUV420P plane set, frm->width / frm->height are set
        // sws_scale() to convert to RGB if needed
    }
    av_packet_unref(pkt);
}
```

[[pyav-entity|PyAV]]'s `for frame in container.decode(video=0)` is almost exactly this loop in Cython, with reference counting handled in `__dealloc__`. [[opencv-entity|OpenCV]]'s `VideoCapture::read()` is the same loop plus a `swscale` call to BGR. Once you see this skeleton, every binding looks like the same code wearing different costumes.

## ABI / version pinning

libav* is **version-pinned per [[ffmpeg-entity|FFmpeg]] major release**. [[pyav-entity|PyAV]] wheels declare a specific [[ffmpeg-entity|FFmpeg]] version they expect; building against a different system [[ffmpeg-entity|FFmpeg]] can break. PyPI wheels for [[pyav-entity|PyAV]] ship a vendored [[ffmpeg-entity|FFmpeg]] in the wheel itself to avoid this — that's why `pip install av` doesn't require a system `ffmpeg-dev` package.

The [[opencv-entity|OpenCV]] wheels do the same. Two consequences:

1. **Two FFmpegs may be on disk** in any given Python image: the system `/usr/bin/ffmpeg` (used for hwaccel probes) and the libavcodec/libavformat shared objects bundled inside `cv2/`. They can be different versions; usually fine, occasionally surprising for codec support edge cases.
2. **Hardware accel availability differs** between the bundled and system [[ffmpeg-entity|FFmpeg]]. The bundled [[opencv-entity|OpenCV]] [[ffmpeg-entity|FFmpeg]] may not include [[hardware-accelerated-codecs|NVENC]]/[[hardware-accelerated-codecs|NVDEC]]; the system one almost certainly does (we install `jellyfin-ffmpeg` or BtbN nightly explicitly for this).

## Module dependencies

Roughly: `libavutil` is the base. Everything else depends on it. `libavformat` depends on `libavcodec` (parses bitstreams to identify packets). `libavfilter` depends on `libavutil`, `libswscale`, and `libswresample`. `libavdevice` depends on `libavformat`. The `ffmpeg` binary links all of them.

Static vs dynamic linking is a build-time decision; [[pyav-entity|PyAV]] wheels are static, distro packages are dynamic.

## Actuate touchpoints

The libav* libraries are the **load-bearing layer** of every Actuate decode path:

- **`av_url_puller.py:320-1438`** — [[pyav-entity|PyAV]] path uses libavformat ([[rtsp-deep-dive|RTSP]]/HTTP open), libavcodec (decode), libswscale (`frame.to_ndarray(format="bgr24")` at line 1351 invokes `sws_scale` to convert YUV→BGR for [[opencv-entity|OpenCV]]/numpy compatibility).
- **`av_url_puller.py:83-131`** — `create_hw_decoder_context()` instantiates an `av.CodecContext` directly with a hardware-decoder name like `h264_cuvid` (libavcodec hwaccel-enabled decoder).
- **`url_puller.py:17-395`** — `cv2.VideoCapture` uses [[opencv-entity|OpenCV]]'s bundled libav*. Same library family, different orchestration. [[rtsp-deep-dive|RTSP]] transport tuning via `OPENCV_FFMPEG_CAPTURE_OPTIONS=rtsp_transport;tcp` (lines 314, 318) is in effect setting an `AVOptions` dict that gets passed to libavformat's [[rtsp-deep-dive|RTSP]] demuxer.
- **`sqs_puller.py:53`** — `cv2.VideoCapture(local_clip_file)` for SMTP-per-camera path. Same libavformat MP4 demuxer, libavcodec [[h264-deep-dive|H.264]] decoder pipeline.
- **[[gstreamer-entity|GStreamer]]-using integrations** (where present in `vms-connector` per [[vms-connector/_summary]]) reach libav* via the `avdec_*` family of [[gstreamer-entity|GStreamer]] elements supplied by the `gst-libav` plugin.

The practical implication: **a libav* upstream regression affects every Actuate decode path simultaneously.** Pinning [[ffmpeg-entity|FFmpeg]] / [[pyav-entity|PyAV]] / [[opencv-entity|OpenCV]] versions in `actuate-libraries`'s lockfiles is therefore a load-bearing decision. See [[actuate-frame-ingest-decode-paths]] for the per-integration matrix and [[actuate-libraries/_summary]] for version-management policy.

Cross-refs: [[ffmpeg-entity]] | [[ffmpeg-command-anatomy]] | [[ffmpeg-python-bindings]] | [[ffmpeg-hardware-acceleration]] | [[ffmpeg-filtergraphs]] | [[pyav-entity]] | [[opencv-entity]] | [[gstreamer-entity]]
