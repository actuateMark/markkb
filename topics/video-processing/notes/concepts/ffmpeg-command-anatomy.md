---
title: "FFmpeg command anatomy"
type: concept
topic: video-processing
tags: [ffmpeg, cli, transcode, recipes]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/ffmpeg-filtergraphs.md
  - topics/video-processing/notes/concepts/ffmpeg-hardware-acceleration.md
  - topics/video-processing/notes/concepts/ffmpeg-libav-libraries.md
  - topics/video-processing/notes/entities/ffmpeg-entity.md
  - topics/video-processing/notes/syntheses/actuate-clip-generation-flow.md
incoming_updated: 2026-05-01
---

# [[ffmpeg-entity|FFmpeg]] command anatomy

[[ffmpeg-entity|FFmpeg]] has a famously fiddly CLI but the underlying grammar is consistent. Once you internalize the shape, recipes start to write themselves and the man page becomes navigable. This note is a practical reference: the grammar, the most useful flags, and the gotchas that bite even experienced users.

## The grammar

```
ffmpeg [global_opts]                            \
       [in_opts_for_input_0] -i INPUT_0          \
       [in_opts_for_input_1] -i INPUT_1          \
       ...                                       \
       [filtergraph_opts]                        \
       [out_opts_for_output_0] OUTPUT_0          \
       [out_opts_for_output_1] OUTPUT_1
```

The critical mental model: **options apply to the next file (input or output) on the command line.** `-ss 30 -i video.mp4` and `-i video.mp4 -ss 30` both compile fine but mean different things. Order matters.

A schematic example with three inputs and one output:

```bash
ffmpeg -hide_banner -loglevel warning \
  -hwaccel cuda -i rtsp://cam/stream \
  -i logo.png \
  -i caption.srt \
  -filter_complex "[0:v]scale=1280:720[v];[v][1:v]overlay=10:10[out]" \
  -map "[out]" -map 0:a? -map 2:s \
  -c:v h264_nvenc -preset p4 -b:v 4M \
  -c:a aac -b:a 128k \
  -c:s mov_text \
  -f mp4 output.mp4
```

That looks dense but it's just: global opts, three inputs each with their own input opts, a filtergraph, then output opts and the output file.

## Stream selectors

`-map` chooses which streams from which inputs go to which output. The selector grammar is `<input_index>:<stream_specifier>`:

- `-map 0:v:0` — first video stream of input 0
- `-map 0:a` — all audio streams of input 0
- `-map 0:s?` — subtitle streams of input 0, ignored if absent (the `?` is critical to avoid hard fails)
- `-map -0:d` — exclude data streams from input 0 (the `-` negates)
- `-map "[label]"` — output of a labeled filtergraph pad

If you don't pass `-map`, [[ffmpeg-entity|FFmpeg]] picks "the best" stream per type, which is usually wrong for anything beyond a single file → single file transcode. **Always be explicit with `-map` for multi-input or multi-output jobs.**

## Codec selection

`-c:v`, `-c:a`, `-c:s` set video/audio/subtitle [[codecs-overview|codecs]] respectively. Special values:

- `-c copy` — stream copy (no decode/encode), lossless and instant
- `-c:v copy -c:a aac` — copy video, transcode audio
- `-c:v libx264` — software [[h264-deep-dive|H.264]]
- `-c:v h264_nvenc` — NVIDIA [[hardware-accelerated-codecs|NVENC]]
- `-c:v h264_vaapi` — Linux [[hardware-accelerated-codecs|VAAPI]]
- `-c:v h264_qsv` — Intel [[hardware-accelerated-codecs|QuickSync]]
- `-c:v h264_videotoolbox` — Apple [[hardware-accelerated-codecs|VideoToolbox]]
- `-c:v hevc_nvenc` / `hevc_vaapi` / etc. for [[h265-hevc-deep-dive|H.265]]

See [[hardware-accelerated-codecs]] for the encoder selection cheat sheet.

## `-vf` vs `-filter_complex`

- `-vf` is sugar for a single-input single-output filterchain attached to the implicit "first video output." Use for simple chains: `-vf scale=1280:720,fps=10,format=bgr24`.
- `-filter_complex` is required for any filtergraph that takes multiple inputs, has multiple outputs, splits streams, or names pads. Use for overlays, hstack/vstack, multi-output, or anything with `[label]` syntax.

See [[ffmpeg-filtergraphs]] for filtergraph deep dive.

## `-f` format coercion

`-f` overrides the container format detection. Useful when:
- The output filename has no extension (`-f mp4 -` to write MP4 to stdout)
- You need a specific muxer (`-f mpegts`, `-f flv`, `-f rtsp`)
- The input is a raw stream where format can't be sniffed (`-f rawvideo -pix_fmt yuv420p -s 1920x1080 -i raw.yuv`)
- You want to write to a network sink (`-f rtsp rtsp://server/stream`)

## `-ss` placement (the classic gotcha)

`-ss <time>` seeks. **Where you put it changes its semantics.**

- **Before `-i`** (input-side): fast seek by demuxer to nearest keyframe. Fast (no decoding) but only keyframe-accurate.
- **After `-i`** (output-side): decode from start, discard frames until target. Slow but frame-accurate.
- **Both** (`-ss 30 -i video.mp4 -ss 0.5 ...`): fast seek to keyframe before 30s, then decode-discard the remaining 0.5s. Best of both worlds, the standard recipe for fast frame-accurate seeks.

Default behavior changed across [[ffmpeg-entity|FFmpeg]] versions; the "input-side `-ss` is keyframe-accurate" rule has been stable since 4.x.

## Stream copy `-c copy`

`-c copy` reads packets from the input and writes them to the output muxer without decoding. Use cases:

- Remux MP4 ↔ MKV: `ffmpeg -i in.mkv -c copy out.mp4`
- Trim without re-encoding (must align to keyframes): `ffmpeg -ss 30 -i in.mp4 -t 10 -c copy out.mp4`
- Strip an audio track: `ffmpeg -i in.mp4 -map 0 -map -0:a:1 -c copy out.mp4`
- Remux [[rtsp-deep-dive|RTSP]] to MP4 in real-time: `ffmpeg -i rtsp://cam/stream -c copy -f mp4 -movflags +frag_keyframe+empty_moov out.mp4`

Caveats: timestamps, [[gop-keyframe-fundamentals|GOP]] boundaries, and fragment alignment must be sane in the source. `ffprobe` the output to verify.

## ffprobe recipes

`ffprobe` ships alongside `ffmpeg`. Always use JSON output for parsing:

```bash
# What's in this file?
ffprobe -hide_banner -show_streams -show_format -of json input.mp4

# Just video stream info
ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,width,height,r_frame_rate,pix_fmt \
  -of default=noprint_wrappers=1 input.mp4

# Duration in seconds
ffprobe -v error -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 input.mp4

# List all keyframe timestamps (great for seek planning)
ffprobe -v error -select_streams v:0 \
  -show_entries packet=pts_time,flags \
  -of csv=print_section=0 input.mp4 | grep K

# Sniff RTSP stream metadata without recording
ffprobe -rtsp_transport tcp -i rtsp://user:pass@cam/stream
```

## The 20 flags worth memorizing

| Flag | Purpose |
|------|---------|
| `-hide_banner` | Stop printing version banner on every run |
| `-loglevel <warning\|error\|verbose\|debug>` | Control verbosity |
| `-y` / `-n` | Overwrite output / never overwrite |
| `-i <input>` | Input |
| `-map <selector>` | Choose streams |
| `-c <codec>` / `-c:v` / `-c:a` | Codec selection |
| `-c copy` | Stream copy |
| `-b:v` / `-b:a` | Bitrate target |
| `-crf <n>` | Constant Rate Factor (x264/x265 quality target) |
| `-preset <name>` | Encoder speed/quality trade |
| `-vf <filterchain>` | Single-input video filter |
| `-filter_complex <graph>` | Multi-input filtergraph |
| `-ss <time>` | Seek (placement matters!) |
| `-t <duration>` / `-to <time>` | Duration / end-time |
| `-r <fps>` | Output framerate |
| `-s <WxH>` | Output size (use `scale=` filter for hwaccel) |
| `-pix_fmt <fmt>` | Pixel format coercion |
| `-f <format>` | Container/muxer override |
| `-rtsp_transport <tcp\|udp>` | [[rtsp-deep-dive|RTSP]] transport (set to tcp for public internet) |
| `-hwaccel <name>` | Hardware accel selection (see [[ffmpeg-hardware-acceleration]]) |

## Common recipes

**Generate a 5s thumbnail clip every minute of a long video:**
```bash
ffmpeg -i long.mp4 -vf "select='not(mod(t,60))',setpts=N/(30*TB)" \
  -an -t 60 -r 30 thumbnails.mp4
```

**[[rtsp-deep-dive|RTSP]] → segmented MP4 chunks every 60s:**
```bash
ffmpeg -rtsp_transport tcp -i rtsp://cam/stream \
  -c copy -f segment -segment_time 60 -reset_timestamps 1 \
  out_%03d.mp4
```

**Extract one keyframe every 10s as JPEGs (Actuate-relevant pattern):**
```bash
ffmpeg -i input.mp4 -vf "fps=1/10" -q:v 2 frame_%04d.jpg
```

**Stitch MP4s losslessly (concat demuxer):**
```bash
printf "file '%s'\n" *.mp4 > list.txt
ffmpeg -f concat -safe 0 -i list.txt -c copy out.mp4
```

## Actuate touchpoints

Actuate's `actuate-pullers` does **not shell out to `ffmpeg`** for media work — the CLI grammar above is mostly relevant for ad-hoc operator work (downloading a clip from a customer site, repackaging an [[rtsp-deep-dive|RTSP]] segment for analysis, generating test fixtures).

Where the CLI does come up in code:

- **`av_url_puller.py:546, 567, 587, 597`** — `subprocess.run(["ffmpeg", "-hide_banner", "-hwaccels"])` for hardware-accel detection. The `-hide_banner` flag in particular keeps the output parseable.
- **Local debugging / repro** — when reproducing a customer-site decode failure, the operator-level workflow is to grab the [[rtsp-deep-dive|RTSP]] URL, run `ffprobe -rtsp_transport tcp -i <url>` to confirm codec + resolution, then attempt a decode with `ffmpeg -rtsp_transport tcp -i <url> -t 10 -c copy out.mp4` to confirm the stream is even pullable. This is upstream of the [[pyav-entity|PyAV]]-level path that production uses.
- **Test fixture generation** — most of `actuate-pullers/tests/fixtures/` is checked-in MP4/MKV files generated with `ffmpeg`. Recipes are not always documented; learn the grammar so you can regenerate them.

For programmatic use in Python, prefer [[pyav-entity]] (direct libav* bindings) over shelling out — see [[ffmpeg-python-bindings]] for the decision matrix.

Cross-refs: [[ffmpeg-entity]] | [[ffmpeg-filtergraphs]] | [[ffmpeg-hardware-acceleration]] | [[hardware-accelerated-codecs]] | [[h264-deep-dive]] | [[h265-hevc-deep-dive]] | [[rtsp-deep-dive]]
