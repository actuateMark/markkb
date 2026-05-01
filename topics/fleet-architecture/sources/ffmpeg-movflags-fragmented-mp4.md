---
title: "Source: FFmpeg Formats Documentation — MP4/MOV movflags for Fragmented Output"
type: source
topic: fleet-architecture
tags: [source, ffmpeg, mp4, fragmented-mp4, movflags, in-process-encoding, container-format]
url: https://ffmpeg.org/ffmpeg-formats.html
ingested: 2026-04-21
author: kb-bot
---

# FFmpeg Formats Documentation — MP4/MOV movflags for Fragmented Output

Canonical FFmpeg reference for the `movflags` options controlling fragmented/streaming MP4 output. Relevant to in-process detection-window clip encoding without a seekable output destination (pipe or in-memory buffer).

## Key Flags

### `frag_keyframe`
Starts a new fragment at each video keyframe (I-frame). For detection-window clips with a single keyframe at GOP start, produces one fragment per clip — ideal.

### `frag_every_frame`
One fragment per frame. Maximises seek granularity at significant per-fragment overhead. Not recommended for detection-window clips.

### `empty_moov`
Writes an initial empty `moov` atom at stream start, with per-fragment metadata in `moof` atoms. Allows the muxer to begin writing without knowing the final stream length — **compatible with pipes and memory buffers**. Required for non-seekable output with fragmented MP4.

### `default_base_moof`
Sets `default-base-is-moof` flag in `tfhd` atoms, removing the need for explicit `base_data_offset` fields. Reduces per-fragment overhead and improves parser compatibility.

### `faststart`
Moves `moov` atom to file start via a second pass — enables progressive-download playback. **Requires seekable output. Incompatible with pipes and memory buffers.** Do NOT use for in-process encoding to a pipe or `BytesIO`.

## Recommended Flag Combination for In-Process Clips

For encoding to a non-seekable buffer (pipe, `subprocess.PIPE`, `BytesIO` via `ffmpeg -f mp4 pipe:1`):

```
-movflags frag_keyframe+empty_moov+default_base_moof
```

(1) writes an initial moov so decoders can initialise before any frames arrive; (2) fragments at keyframe boundaries (one fragment for a short clip with single I-frame at position 0); (3) uses modern moof-relative addressing.

## Production Gotchas

- **`faststart` is a common mistake** for streaming/piped workflows — silently fails or errors on non-seekable output. Most likely failure mode when naively adapting a file-write FFmpeg command for in-process encoding.
- **Moov atom placement**: without `empty_moov`, muxer may need to seek back to position 0. Raises `[mp4 @ ...] muxer does not support non seekable output` on pipe output.
- **Short-GOP considerations**: for a 10-frame detection window at 10 fps, forcing a keyframe at frame 0 (`-force_key_frames 0`) ensures `frag_keyframe` produces exactly one fragment.
- **PyAV compatibility**: PyAV (`av` library, already in the connector's Docker image per [[frame-storage-current-state]] §8) exposes container-level options including movflags. Can drive fragmented MP4 output without shelling out to ffmpeg subprocess, keeping encode fully in-process.

## Relevance to Fleet Proposals

- **A — Minimal Split**: Directly applicable — in-process encoding in the existing pipeline pod. PyAV already present.
- **B — Stage Fleets**: Dedicated encode stage runs these flags on window-close events; flag selection is implementation detail.
- **C — Camera-Worker**: Each worker encodes at window close; same flag set applies.
- **D — Event-Driven**: Encode consumer subscribing to NATS window-close events uses these flags before S3 PUT.
- **E — Hybrid Sidecar**: Detection core encodes before promoting; these flags are the concrete implementation choice.

## Relevance to Frame-Storage Design Directions

- **In-process encoding (§11)**: Directly and concretely relevant. This is THE implementation reference for in-process clip encoding. The flag combination is the specific solution to "how do we encode to a buffer without seekable output."
- **In-cluster blob + conditional promotion (§12)**: Relevant at the promotion step. When a detection-positive window triggers S3 promotion, in-cluster JPEG frames are encoded to fragmented MP4 using these flags before the single S3 PUT.
- **API-call cost structure**: Indirect. Using these flags correctly ensures the clip is emitted as a single object (one S3 PUT), preserving the 22→2 API-call reduction.

## Source
https://ffmpeg.org/ffmpeg-formats.html
