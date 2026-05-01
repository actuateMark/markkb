---
title: Containers Overview
type: concept
topic: video-processing
tags: [container, mp4, fmp4, mkv, webm, mpeg-ts, muxing]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/av1-vp9-future.md
  - topics/video-processing/notes/concepts/codecs-overview.md
  - topics/video-processing/notes/concepts/hardware-accelerated-codecs.md
  - topics/video-processing/notes/concepts/mjpeg-and-still-image-formats.md
  - topics/video-processing/notes/concepts/mpeg-ts-over-udp.md
  - topics/video-processing/notes/syntheses/frame-transport-payload-formats.md
incoming_updated: 2026-05-01
---

# Containers Overview

A **container** is a file/stream format that wraps one or more elementary streams (video, audio, subtitles, metadata) along with the **timing** information that lets a decoder play them back. The container is orthogonal to the codec — see [[codecs-overview]]. The container says "here is a video track at 30fps starting at PTS=0, here are the byte ranges of each frame, here is a moof box for the next fragment". The codec inside the track says "this is what a [[h264-deep-dive|H.264]] frame looks like".

This split confuses people regularly, mostly because file extensions hint at containers (`.mp4`, `.mkv`, `.mov`, `.webm`, `.ts`), the codec is a separate axis (`.mp4` can hold [[h264-deep-dive|H.264]], [[h265-hevc-deep-dive|H.265]], [[av1-vp9-future|AV1]], ProRes, MPEG-2, ...), and codec/container compatibility isn't symmetric (you can put [[av1-vp9-future|AV1]] in MP4 _or_ WebM, but you can't put ProRes in WebM).

## What containers actually carry

Beyond the elementary stream bytes, a container provides:

1. **Timing** — Presentation Timestamps (PTS), Decode Timestamps (DTS), and a timebase / timescale. Without this, the decoder doesn't know when to display each frame.
2. **Sample tables** — index of byte ranges and durations for each frame ("sample" in MP4 nomenclature).
3. **Codec config / parameter sets** — SPS/PPS/VPS for [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]] (see [[h264-deep-dive]], [[h265-hevc-deep-dive]]) carried "out of band" in container headers (`avcC`/`hvcC` boxes), separate from the inline NAL units.
4. **Random-access points** — keyframe index, so seeking can land on a decodable frame.
5. **Track metadata** — language tag, rotation matrix (the displaymatrix that bites Avigilon decode), creation time, codec name.
6. **Multiplex layout** — for live/streaming containers (fMP4, [[mpeg-ts-over-udp|MPEG-TS]]), the chunking strategy that lets the format be consumed before it's complete.

A "raw" elementary stream — Annex-B [[h264-deep-dive|H.264]] with start codes, for instance — has none of this. It can be played, but only by guessing the framerate. [[rtsp-deep-dive|RTSP]] transports raw NAL units in RTP and reconstructs timing from RTP timestamps; [[hls-and-dash|HLS]] wraps the same NAL units in [[mpeg-ts-over-udp|MPEG-TS]] or fMP4 to get PTS/DTS back.

## The common containers, briefly

**MP4 / ISO-BMFF (`.mp4`, `.mov`)** — the dominant on-disk container, originally derived from Apple's QuickTime MOV format and standardized as ISO/IEC 14496-12 (the "ISO Base Media File Format"). Box-structured — the file is a tree of typed boxes (`ftyp`, `moov`, `mdat`, `trak`, `mdia`, `stbl`, ...). The `moov` box holds the index; in classic MP4 it lives at the end of the file (so the encoder can finalize it after writing all samples). For streaming this is bad — players can't start until the moov arrives.

**fMP4 (fragmented MP4)** — the streaming-friendly variant. The big one-shot `moov` is replaced by a small init segment plus a stream of `moof`+`mdat` fragments, each self-contained. This is the underlying format of [[hls-and-dash|MPEG-DASH]] and modern [[hls-and-dash|HLS]] (see [[hls-and-dash]]), and the wire format for several VMS HTTP-streaming flows including Avigilon. CMAF is essentially a profiled fMP4.

**MKV / Matroska (`.mkv`, `.webm`)** — Matroska is the open-spec rival to MP4. EBML-binary structure (a typed-tree similar to ISO-BMFF but with a different schema). More flexible about [[codecs-overview|codecs]] and metadata, less universal in support. **WebM** is a profiled MKV restricted to [[av1-vp9-future|VP8]]/[[av1-vp9-future|VP9]]/[[av1-vp9-future|AV1]] + Vorbis/Opus. [[aws-kvs-entity|AWS Kinesis Video Streams]] uses MKV as its on-the-wire container.

**[[mpeg-ts-over-udp|MPEG-TS]] (`.ts`, `.m2ts`)** — packet-oriented (188-byte packets) container designed for broadcast over lossy links. Self-synchronizing — a decoder can join mid-stream by waiting for the next PAT/PMT and keyframe. This is why [[hls-and-dash|HLS]] originally chose [[mpeg-ts-over-udp|MPEG-TS]] segments. Significantly higher overhead than fMP4 for the same content (~5–10%), which is why CMAF exists.

**AVI** — historical, mostly dead. Index-at-end and no good support for variable frame rate. Mentioned only because it still appears in legacy footage.

**Raw elementary stream** — `.[[h264-deep-dive|h264]]` / `.[[h265-hevc-deep-dive|h265]]` files of NAL units with start codes, or `.aac` of ADTS frames. No timing; players guess. Useful for piping between processes; not a real container.

## Muxing and demuxing

**Muxing** = combining elementary streams (and timing/metadata) into a container. **Demuxing** = the inverse. [[pyav-entity|PyAV]]'s `[[pyav-entity|av]].open(url)` returns a `Container` whose `streams` are demuxed elementary streams; you iterate `container.demux()` to get `Packet` objects (typically one frame's worth of compressed bytes plus PTS/DTS/keyframe flag), then `packet.decode()` to get raw `Frame` objects. [[gstreamer-entity|GStreamer]]'s pipeline equivalent is the `*demux` family of elements (`qtdemux`, `matroskademux`, `tsdemux`).

The demuxer knows nothing about pixels. It just chops the container apart and hands the codec packets to the decoder. This separation means we can swap decoders (software → hardware) without touching demux. We exploit this in [[hardware-accelerated-codecs|hardware decode setup]] — same demuxer, different `CodecContext`.

## Why containers carry timing, not just bytes

A frequent confusion: "isn't the framerate just `1/duration` of each frame?" Two reasons that's wrong:

1. **Variable frame rate** — most surveillance cameras drop frames during low-motion scenes, or speed up I-frames during scene changes. PTS isn't a monotone arithmetic progression.
2. **B-frames** — [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]] decode order ≠ display order. The decoder needs DTS (when to decode) and PTS (when to display). The container carries both.

A demuxer that fakes PTS by counting frames will produce subtly broken playback the moment the stream is non-CFR. We've hit this in practice when [[pyav-entity|PyAV]] had stale state in the mov demuxer — see the fMP4 recycle workaround below.

## Containers in Actuate, by ingestion path

- **[[pyav-entity|PyAV]] / `av_url_puller.py`** — the workhorse. Demuxes MP4, fMP4, MOV, [[mpeg-ts-over-udp|MPEG-TS]], raw [[h264-deep-dive|H.264]] over HTTP, and [[rtsp-deep-dive|RTSP]]-over-TCP/UDP. The `videocodec=h264&` URL hint at `url_puller.py:150-151, 1121-1122` is a workaround for cameras that don't advertise their codec in their stream metadata cleanly. The fMP4 recycle every ~300s with jitter (`av_url_puller.py:496-503, 1158-1185`) flushes the libav `mov` demuxer's `frag_index` leak that costs ~5–10 MB/hr on Avigilon HTTP fMP4 streams. The displaymatrix sidedata rotation handling at `:139-171` translates the container's track-level rotation matrix into a `[[opencv-entity|cv2]].rotate` call on the decoded frame.
- **[[gstreamer-entity|GStreamer]] / `kvs_ingestor.py`** — [[aws-kvs-entity|KVS]] payload is MKV. Pipeline element `matroskademux` chews chunks as they come off the [[aws-kvs-entity|KVS]] GetMedia stream (`actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_ingestor.py:148-167`). MKV is the right choice for [[aws-kvs-entity|KVS]] because it's stream-friendly (no central index requirement) and supports the "rolling buffer of arbitrary codec" model [[aws-kvs-entity|KVS]] targets.
- **AutoPatrol WebSocket / `autopatrol_websocket_stream_puller.py`** — raw ISO-BMFF boxes off a WebSocket. Manual box-header parser at `:111-135` reads the size+type pairs and looks for `moov`/`ftyp`/`moof`/`mdat` to assemble a synthetic fMP4 stream that [[pyav-entity|PyAV]] can then ingest. This is the most "in-the-weeds" container code we have.

We do **not** mux clips in-process anywhere in the libraries. Detection frames go to S3 as JPEGs (per-frame, not muxed video). Clip muxing for alert delivery happens downstream of the pipeline.

See [[reading-list]] for inspection tools (MediaInfo, ffprobe, GPAC/MP4Box) and the underlying ISO/IEC standards.

## Actuate touchpoints

- MP4 / fMP4 / MOV demuxing — `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:139-171, 496-503, 1158-1185`
- MKV demuxing via [[gstreamer-entity|GStreamer]] — `actuate-libraries/actuate-pullers/src/actuate_pullers/kvs/kvs_ingestor.py:148-167`
- Raw ISO-BMFF box parser — `actuate-libraries/actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py:111-135`
- Codec-hint URL rewrite — `actuate-libraries/actuate-pullers/src/actuate_pullers/url/url_puller.py:150-151, 1121-1122`
- Cross-topic: [[vms-connector/_summary]], [[autopatrol/_summary]], [[actuate-frame-ingest-decode-paths]]
