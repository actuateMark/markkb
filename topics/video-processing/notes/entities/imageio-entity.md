---
title: "imageio / imageio-ffmpeg"
type: entity
topic: video-processing
tags: [imageio, ffmpeg, python, frame-extraction, library, scripting]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/concepts/ffmpeg-libav-libraries.md
  - topics/video-processing/notes/concepts/ffmpeg-python-bindings.md
  - topics/video-processing/reading-list.md
incoming_updated: 2026-05-01
---

# imageio / imageio-[[ffmpeg-entity|ffmpeg]]

`imageio` is a Pythonic read/write library for images and videos, from the SciPy/scikit-image lineage. The companion package `imageio-ffmpeg` provides [[ffmpeg-entity|FFmpeg]] binaries and a reader/writer that shells out to [[ffmpeg-entity|ffmpeg]] as a subprocess, parsing its raw stdout pipe of pixel bytes. Together they form a **friendly, batteries-included alternative** to [[opencv-entity|OpenCV]] and [[pyav-entity|PyAV]] for ad-hoc scripting.

The model is deliberately simple:

```python
import imageio.v3 as iio

# Read all frames
for frame in iio.imiter("input.mp4"):
    process(frame)  # frame is RGB ndarray

# Write a video
iio.imwrite("out.mp4", frames, fps=30)
```

That's basically the entire surface area you need 95% of the time.

## How it works

`imageio` is a plugin registry. Each format (PNG, JPEG, GIF, MP4, etc.) has a backend. For video, the default backend is `imageio-ffmpeg`, which:

1. Locates an [[ffmpeg-entity|ffmpeg]] binary -- either system-installed, or **downloads a self-contained static binary** on first use (`pip install imageio-ffmpeg` triggers a binary fetch on first call -- this is the "lazy install" path).
2. Spawns `ffmpeg -i input.mp4 -f rawvideo -pix_fmt rgb24 -` as a subprocess.
3. Reads the raw RGB byte stream from [[ffmpeg-entity|ffmpeg]]'s stdout, reshapes into ndarrays.

This is genuinely nice for the user: you get [[ffmpeg-entity|FFmpeg]]'s full codec support without compiling anything, without root, and without conflicting with system [[ffmpeg-entity|FFmpeg]]. It's also genuinely limiting: the subprocess boundary means **no PTS access, no side-data, no hwaccel control, no codec-context tuning**. It's [[opencv-entity|OpenCV's]] limitations all over again, with worse performance on the marshalling overhead but with broader codec support.

## When to use it

`imageio` shines for:

- **Ad-hoc scripts.** "Read this one MP4, dump every 10th frame to PNG." Two lines of code.
- **Batch frame export.** Training data assembly, ground-truth labeling pipelines, debugging clip generation.
- **Notebook work.** The API is friendlier than `cv2.VideoCapture` for exploratory data analysis.
- **Cross-format I/O.** `iio.imread("foo.tiff")` and `iio.imread("foo.heic")` and `iio.imread("foo.exr")` all just work via plugins.
- **Environments where system [[ffmpeg-entity|ffmpeg]] installation is annoying.** The lazy-install [[ffmpeg-entity|ffmpeg]] binary path means you can `pip install imageio-ffmpeg` on a fresh container or a dev laptop and have a working video reader without `apt-get install ffmpeg`.

## When not to use it

- **Production decode pipelines.** The subprocess boundary adds latency, prevents fine-grained control, and has crash recovery characteristics that don't fit a long-running puller. Use [[pyav-entity|PyAV]].
- **Anything requiring PTS or codec metadata.** Same gap as [[cv2-videocapture-internals|`cv2.VideoCapture`]].
- **Low-latency streaming.** [[ffmpeg-entity|ffmpeg]] subprocess has its own buffer; you're stacking buffers on top of buffers.
- **Memory-bounded scenarios.** [[ffmpeg-entity|ffmpeg]] subprocess + raw-pixel pipe means the whole frame goes through a UNIX pipe per frame -- not a problem for batch work, occasionally a problem at scale.

## `imageio-ffmpeg` as a binary acquisition path

Even when you don't use `imageio`'s reader API, `imageio-ffmpeg` is sometimes pulled in as a **lightweight [[ffmpeg-entity|ffmpeg]]-binary delivery mechanism**. `imageio_ffmpeg.get_ffmpeg_exe()` returns the path to the bundled binary; you can `subprocess.run([get_ffmpeg_exe(), ...])` directly. This is the cleanest "I need [[ffmpeg-entity|ffmpeg]] in a Python deployable but I don't want to manage system packages" pattern. Worth knowing about even if `imageio` itself isn't in the dep tree.

## Comparison snapshot

| | imageio | [[opencv-entity\|OpenCV]] | [[pyav-entity\|PyAV]] | [[ffmpeg-entity\|ffmpeg CLI]] |
|---|---|---|---|---|
| Python ergonomics | excellent | good | medium | poor (shell only) |
| Codec coverage | full ([[ffmpeg-entity|ffmpeg]]) | full (vendored [[ffmpeg-entity|ffmpeg]]) | full (libav\*) | full (libav\*) |
| PTS / DTS access | no | no | yes | yes |
| Hwaccel control | no | no | yes | yes |
| Per-packet filtering | no | no | yes | yes (filter graph) |
| Subprocess boundary | yes (slow) | no | no | yes |
| Install footprint | medium (~30 MB on first use) | medium (~80 MB wheel) | medium (~50 MB wheel) | system pkg |
| Best for | scripts, notebooks, batch | image ops, fallback decode | streaming decode | shell + filtergraphs |

## Actuate usage: not currently used

`imageio` is **not** present in [[actuate-pullers]], actuate-pipeline, [[actuate-alarm-senders]], or any other actuate-libraries package as of the 2026-04-27 scout. The decode story is split between [[opencv-entity|OpenCV]] (legacy, batch-file pullers) and [[pyav-entity|PyAV]] (streaming pullers); neither needs a third option, and the imageio subprocess model wouldn't be a good fit for a long-running Lambda or daemon process anyway.

That said, `imageio` would be a **reasonable choice** for:

- One-off scripts in `actuate-libraries/scripts/` or repo-local utilities (e.g. dataset prep for model training).
- Internal debugging tools (e.g. "extract every 5th frame from this S3 clip and dump as PNGs").
- Notebook-based investigation of clip files in alert-clip generation work.

If we ever pick it up, the lazy-install binary path is a particularly clean way to get [[ffmpeg-entity|ffmpeg]] into a Lambda layer without depending on a system install.

## Actuate touchpoints

- **None today.** Listed here as a candidate library for ad-hoc scripting and dataset work.
- See [[opencv-entity]] for current legacy-decode usage.
- See [[pyav-entity]] for the canonical streaming-decode path.
- See [[knowledgebase/topics/billing/reading-list]] for adjacent libraries (decord, vidgear, moviepy, scikit-video) that occupy the same "friendly Python video I/O" niche.
- See [[ffmpeg-entity]] / [[ffmpeg-python-bindings]] for the underlying [[ffmpeg-entity|FFmpeg]] toolchain `imageio-ffmpeg` wraps.
