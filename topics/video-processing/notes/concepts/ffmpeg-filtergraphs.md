---
title: "FFmpeg filtergraphs"
type: concept
topic: video-processing
tags: [ffmpeg, libavfilter, filtergraph, scale, overlay, hwaccel]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# [[ffmpeg-entity|FFmpeg]] filtergraphs

Filtergraphs are how [[ffmpeg-entity|FFmpeg]] expresses any non-trivial transformation on streams: scaling, cropping, frame-rate conversion, format conversion, overlays, audio mixing, multi-stream stacking. The syntax is dense and the error messages are punishing, but the underlying model is elegant — once you internalize it, you can express almost any transformation as a filtergraph and the rest of [[ffmpeg-entity|FFmpeg]] falls into place. This note is the practical reference: syntax, common patterns, hardware-filter quirks, and when to drop down to libavfilter directly.

## The model

A filtergraph is a directed acyclic graph of **filters**, each with **input pads** and **output pads** carrying typed streams (video or audio). Filters connect via labeled or implicit pads. The whole graph runs as a pull-based pipeline: when an output pad is asked for a frame, libavfilter walks back through the graph, pulling frames from inputs and applying transformations.

Three syntactic forms:

1. **Single chain (`-vf`)** — one input, one output, comma-separated filters.
   ```
   -vf scale=1280:720,fps=10,format=bgr24
   ```
2. **Multi-chain (`-filter_complex`)** — multiple chains joined by named pads.
   ```
   -filter_complex "[0:v]scale=1280:720[v];[v][1:v]overlay=10:10[out]"
   ```
3. **Programmatic (`av.filter.Graph` in [[pyav-entity|PyAV]] / `AVFilterGraph` in C)** — same model, called via API.

## Syntax cheat sheet

```
[input_pad]filter_name=key1=val1:key2=val2[output_pad]
chain;chain;chain
```

- **Filters** separated by `,` form a chain (output of one is implicit input of next).
- **Chains** separated by `;` are independent.
- **Square brackets** name pads. Inputs from the command line look like `[0:v]` (input 0, video) or `[1:a]` (input 1, audio). Internal labels are arbitrary names.
- **Filter args** are colon-separated `key=value` pairs.
- **Multiple outputs** via `split` filter: `[0:v]split=2[a][b]`.

## Common filters

| Filter | Purpose | Example |
|--------|---------|---------|
| `scale` | Resize | `scale=1280:720`, `scale=-1:720` (preserve aspect) |
| `crop` | Crop | `crop=1280:720:100:50` (W:H:X:Y) |
| `pad` | Letterbox | `pad=1920:1080:(ow-iw)/2:(oh-ih)/2` |
| `fps` | Force framerate | `fps=10` |
| `format` | Pixel format coercion | `format=yuv420p`, `format=bgr24` |
| `setpts` | Change PTS (speed) | `setpts=0.5*PTS` (2x speed) |
| `select` | Drop frames | `select='not(mod(n,30))'` (every 30th) |
| `overlay` | Composite | `overlay=10:10` (X:Y of overlay layer) |
| `drawtext` | Burn-in text | `drawtext=text='hello':x=10:y=10:fontsize=24` |
| `hstack` / `vstack` | Side-by-side / stacked | `hstack=inputs=2` |
| `split` | Branch | `split=2[a][b]` |
| `null` | Identity / placeholder | rarely needed |
| `trim` / `atrim` | Time-window | `trim=start=10:end=20,setpts=PTS-STARTPTS` |

## Worked examples

### Scale and re-frame an [[rtsp-deep-dive|RTSP]] feed for inference

```
-vf "scale=640:480,fps=10,format=bgr24"
```

What's happening: scale to 640×480, force 10 fps (drops or duplicates frames as needed), coerce to BGR24 so [[opencv-entity|OpenCV]]/numpy sees the right pixel layout. Almost exactly what we want for AI pipeline ingestion if not running through [[pyav-entity|PyAV]] directly.

### Picture-in-picture

```
-filter_complex "[0:v]scale=1920:1080[bg];[1:v]scale=640:360[pip];[bg][pip]overlay=W-w-20:H-h-20[out]" -map "[out]"
```

Background scaled to 1080p, PiP scaled to 360p, PiP placed in bottom-right with 20px margin. The `W-w-20` syntax means "background width minus pip width minus 20".

### Side-by-side comparison of two streams

```
-filter_complex "[0:v]scale=960:540[l];[1:v]scale=960:540[r];[l][r]hstack[out]" -map "[out]"
```

### Burn-in timestamp

```
-vf "drawtext=text='%{pts\\:hms}':x=10:y=10:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5"
```

Useful for proving frames are flowing in real-time during a debug session.

### Take one frame every 5 seconds for a contact sheet

```
-vf "fps=1/5,tile=4x4"
```

`tile` packs frames into a grid — it has its own buffering semantics (waits until the tile is full).

## Hardware filtergraphs

Hardware filters keep frames in GPU memory between operations. Useful when you decode + scale + encode all on GPU.

### NVIDIA: `scale_npp` / `scale_cuda`

```
-hwaccel cuda -hwaccel_output_format cuda -i in.mp4 \
  -vf "scale_npp=1280:720" \
  -c:v h264_nvenc out.mp4
```

`scale_npp` runs on NVIDIA's NPP library; `scale_cuda` is a newer pure-CUDA kernel. Both keep frames in `AV_PIX_FMT_CUDA` so no GPU↔CPU round-trip happens.

### [[hardware-accelerated-codecs|VAAPI]]: `scale_vaapi`

```
-hwaccel vaapi -hwaccel_device /dev/dri/renderD128 -hwaccel_output_format vaapi \
  -i in.mp4 -vf "scale_vaapi=1280:720,format=nv12" \
  -c:v h264_vaapi out.mp4
```

### `hwupload` / `hwdownload`

Bridges between CPU and GPU memory. Use cases:

- CPU input → GPU filter: `[0:v]format=nv12,hwupload[gpu];[gpu]scale_npp=...`
- GPU filter → CPU output: `[gpu]hwdownload,format=bgr24`

This is exactly the pattern Actuate would need if it ever wanted GPU-side scale before CPU egress to numpy. Currently we skip the GPU scale entirely (let [[pyav-entity|PyAV]] `to_ndarray()` handle YUV→BGR on CPU) because the decode-side speedup dominates.

### Why hardware filtergraphs are tricky

- The pixel format must match between adjacent filters and between filter and codec. NV12 ↔ YUV420P ↔ NV12-on-GPU all confuse libavfilter.
- Hardware frames carry context (device handle, decoder reference). Mixing contexts (e.g. CUDA frames + [[hardware-accelerated-codecs|VAAPI]] filter) does not work.
- Errors are cryptic (`Impossible to convert between the formats supported by the filter 'X' and the filter 'Y'`).
- Insertion of `format=` filters is sometimes necessary even when "obviously" both sides agree on format.

## Why filtergraphs are powerful but illegible

The filtergraph mini-language is concise — too concise. Once you have three or more chains, the readability falls off a cliff. Strategies:

1. **Use named pads liberally**, even when not strictly needed — `[v0]`, `[v1]`, `[scaled]`, `[overlaid]` is far easier to read than `[v]`, `[v]`, `[v]`.
2. **Split into multiple chains** with `;` rather than chaining everything into one string.
3. **Comment in surrounding shell** — the filtergraph itself doesn't support comments, but the script that builds it does.
4. **Use `-filter_complex_script`** — point at a file that contains the filtergraph (with comments allowed).
5. **For anything beyond 2-3 chains**, drop down to libavfilter directly via [[pyav-entity|PyAV]].

## Dropping down to libavfilter ([[pyav-entity|PyAV]])

[[pyav-entity|PyAV]]'s `av.filter.Graph` builds filtergraphs programmatically — same engine, more legible:

```python
import av
import av.filter

graph = av.filter.Graph()

# Build the graph
in_buffer = graph.add_buffer(template=in_stream)
scale = graph.add('scale', '1280:720')
fps = graph.add('fps', 'fps=10')
fmt = graph.add('format', 'pix_fmts=bgr24')
out_sink = graph.add('buffersink')

# Wire it up
in_buffer.link_to(scale)
scale.link_to(fps)
fps.link_to(fmt)
fmt.link_to(out_sink)

graph.configure()

# Drive it
for frame in container.decode(video=0):
    in_buffer.push(frame)
    while True:
        try:
            out = out_sink.pull()
        except (av.BlockingIOError, av.EOFError):
            break
        # out is an av.VideoFrame in BGR24
```

When to use `av.filter.Graph`:

- Multi-stage transformations done in-process (avoid subprocess overhead).
- When you need to inspect intermediate frames or change the graph dynamically.
- When the same filtergraph is reused across many decode sessions (build once, reuse).

When to stick with `-vf` / `-filter_complex` strings:

- Quick CLI work / one-shots.
- When the graph is composed by a tool (Bash script, [[ffmpeg-entity|ffmpeg]]-python builder) rather than written by hand.

## Common gotchas

- **`scale` does YUV→YUV by default**; if you want RGB out, you must include `format=` after.
- **`fps` interpolates by duplicating/dropping**; for accurate time-based selection use `select='not(mod(n,30))'`.
- **`setpts=PTS-STARTPTS`** is the canonical "reset timestamps after `trim`" idiom.
- **Audio filters require `-filter_complex` even for single audio chains** if there's any video output too; pass `[0:a]anull[aout]` to keep audio alive.
- **`-vf` doesn't work on hardware streams** if they're flowing in GPU pixel formats — you need `-filter_complex` plus explicit `hwupload`/`hwdownload`.
- **Filtergraph errors are evaluated at graph-build time**, not at first-frame time; watch for the `Filtering and streamcopy cannot be used together` class of error before you blame the input.

## Actuate touchpoints

Actuate uses filtergraphs **sparingly** in the production decode path:

- **Primary pattern**: `frame.to_ndarray(format="bgr24")` on each [[pyav-entity|PyAV]] frame at `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:1351`. This is conceptually a tiny one-step filtergraph (`format=bgr24`) but [[pyav-entity|PyAV]] implements it as a direct swscale call in C, not through libavfilter. Functionally equivalent; better-performing.
- **No explicit `av.filter.Graph` use** in the puller code — the only transformation we apply per-frame is the format conversion above. Resizing happens **downstream** in the inference path (Python-level `cv2.resize` / `Pillow` ops), not in libavfilter.
- **Where filtergraphs would help but don't yet**: clip generation paths that re-encode for partner delivery would be cheaper if scale + format + encode happened in a single GPU-side hardware filtergraph. Currently the path reads YUV → numpy → BGR → [[opencv-entity|cv2]].resize → re-encode, which is wasteful. Tracked as a possible future optimization in [[actuate-clip-generation-flow]].
- **Operator-level use**: when manually generating test fixtures or repackaging customer-supplied clips, the team uses ad-hoc `-vf` invocations (`scale=640:480,fps=5,format=yuvj420p` is a common pattern for shrinking captures into the test fixtures directory).
- **[[gstreamer-entity|GStreamer]] alternative**: where a fleet pipeline does need multi-stage transforms (rare), [[gstreamer-entity|GStreamer]]'s element-graph model (see [[gstreamer-pipeline-model]] and [[gstreamer-vs-ffmpeg]]) is often more legible than libavfilter strings. The [[gstreamer-entity|GStreamer]] `videoconvert ! videoscale ! capsfilter` triplet is the ergonomic equivalent of `format=bgr24,scale=...`.

Cross-refs: [[ffmpeg-entity]] | [[ffmpeg-command-anatomy]] | [[ffmpeg-libav-libraries]] | [[ffmpeg-hardware-acceleration]] | [[ffmpeg-python-bindings]] | [[pyav-entity]] | [[gstreamer-pipeline-model]] | [[gstreamer-vs-ffmpeg]]
