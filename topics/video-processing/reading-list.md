# Reading List: Video Processing

Catalog of alternatives, peripheral tools, and reference material for the [[_summary|video-processing topic]]. Major players are covered as full entity / concept notes inside `notes/`; this file is for **everything else worth knowing about** -- alternatives, niche tools, learning resources, and decision-relevant material.

Entries are unchecked checkboxes (`[ ]`) -- check them as we read / synthesize / decide they're not worth a deeper look.

## Open-source tools and libraries

### Frame & stream I/O (Python)
- [ ] **[[pyav-entity]]** -- Pythonic FFmpeg bindings via libav* (`av.open`, container/stream/packet/frame model). https://pyav.basswood-io.com/
- [ ] **ffmpeg-python** -- thin wrapper that builds shell commands. Different ergonomics from [[pyav-entity]]. https://github.com/kkroening/ffmpeg-python
- [ ] **[[imageio-entity]]** + **imageio-ffmpeg** -- friendlier read/write API, [[ffmpeg-entity|ffmpeg]] subprocess under the hood. https://imageio.readthedocs.io/
- [ ] **decord** -- random-access video reader optimized for ML training (returns batched tensors). https://github.com/dmlc/decord
- [ ] **vidgear** -- "high-level video processing library" with multi-threaded readers, [[rtsp-deep-dive|RTSP]] helpers, NetGear streaming. https://github.com/abhiTronix/vidgear
- [ ] **[[opencv-entity]]** -- ubiquitous, but `VideoCapture` quirks are legendary. See [[opencv-entity]].
- [ ] **scikit-video** -- mostly abandoned, but historically the "easy [[ffmpeg-entity|ffmpeg]]" library.
- [ ] **moviepy** -- editing-oriented API, [[ffmpeg-entity|ffmpeg]]-backed. https://github.com/Zulko/moviepy
- [ ] **aiortc** -- pure-Python [[webrtc-deep-dive|WebRTC]] + ORTC implementation. https://github.com/aiortc/aiortc
- [ ] **av1an** -- [[av1-vp9-future|AV1]] chunked-encoding orchestrator. Niche but illustrates parallel encode patterns. https://github.com/master-of-zen/Av1an

### Streaming servers / proxies / restreamers
- [ ] **MediaMTX** (formerly rtsp-simple-server) -- Go [[rtsp-deep-dive|RTSP]]/[[rtmp-and-srt|RTMP]]/[[hls-and-dash|HLS]]/[[webrtc-deep-dive|WebRTC]]/[[rtmp-and-srt|SRT]] bridge. Excellent for testing and edge restreaming. https://github.com/bluenviron/mediamtx
- [ ] **Wowza Streaming Engine** -- legacy commercial streaming server. Often present in security-industry deployments.
- [ ] **NGINX-[[rtmp-and-srt|RTMP]]** -- the classic open-source [[rtmp-and-srt|RTMP]] relay. Increasingly replaced by MediaMTX.
- [ ] **Janus Gateway** -- [[webrtc-deep-dive|WebRTC]] SFU. Reference architecture for broadcast / many-to-many [[webrtc-deep-dive|WebRTC]]. https://janus.conf.meetecho.com/
- [ ] **Pion** -- Go [[webrtc-deep-dive|WebRTC]] stack. Lower-level than aiortc but production-grade. https://github.com/pion/webrtc
- [ ] **LiveKit** -- [[webrtc-deep-dive|WebRTC]] SFU + room model on top of Pion. Open core. https://livekit.io/
- [ ] **Restreamer** -- "easy" [[rtmp-and-srt|RTMP]]/[[rtsp-deep-dive|RTSP]] to [[hls-and-dash|HLS]] bridge with a UI. https://datarhei.github.io/restreamer/
- [ ] **[[gstreamer-entity|GStreamer]] rtsp-server** -- C library exposing [[gstreamer-entity|GStreamer]] pipelines as [[rtsp-deep-dive|RTSP]]. https://gstreamer.freedesktop.org/modules/gst-rtsp-server.html
- [ ] **Live555** -- C++ [[rtsp-deep-dive|RTSP]]/RTP/SIP libraries; the OG reference implementation embedded in many cameras. http://www.live555.com/
- [ ] **GO2RTC** -- Go-based bridge similar to MediaMTX with strong camera-protocol coverage. https://github.com/AlexxIT/go2rtc
- [ ] **OBS Studio** -- broadcaster reference; useful as a [[rtmp-and-srt|RTMP]]/[[rtmp-and-srt|SRT]] publisher in test rigs. https://obsproject.com/

### Hardware accel / GPU pipelines
- [ ] **NVIDIA DeepStream SDK** -- [[gstreamer-entity|GStreamer]]-based pipeline for video AI on NVIDIA GPUs. The reference for "fast YOLO over many streams". https://developer.nvidia.com/deepstream-sdk
- [ ] **NVIDIA Video Codec SDK (NVENC / NVDEC)** -- the underlying [[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]]/[[av1-vp9-future|AV1]] encode/decode primitives DeepStream uses.
- [ ] **NVIDIA DALI** -- data loading library with hardware-decoded video support, common in training pipelines.
- [ ] **Intel QuickSync (libmfx, oneVPL)** -- Intel iGPU encode/decode. [[ffmpeg-entity|ffmpeg]] `h264_qsv`.
- [ ] **VAAPI** -- Linux acceleration API; [[ffmpeg-entity|ffmpeg]] `h264_vaapi`. Common on AMD/Intel.
- [ ] **AMD AMF** -- AMD encode/decode SDK. [[ffmpeg-entity|ffmpeg]] `h264_amf`.
- [ ] **Apple VideoToolbox** -- macOS/iOS hardware codec API. [[ffmpeg-entity|ffmpeg]] `h264_videotoolbox`.

### Inspection / diagnostics
- [ ] **MediaInfo** -- the canonical "what's actually in this file" tool. https://mediaarea.net/en/MediaInfo
- [ ] **ExifTool** -- metadata, including video metadata in MOV/MP4. https://exiftool.org/
- [ ] **ffprobe** -- [[ffmpeg-entity|ffmpeg]]'s stream/format inspector. Always shipped with [[ffmpeg-entity|ffmpeg]]. Use `-show_streams -show_format -of json`.
- [ ] **GPAC / MP4Box** -- MP4 muxer/demuxer with ridiculous capability surface. https://gpac.io/
- [ ] **gst-inspect-1.0**, **gst-launch-1.0** -- [[gstreamer-entity|GStreamer]]'s pipeline introspection / runner.
- [ ] **VLC** -- not a tool exactly, but `vlc -vvv` is great for ad-hoc protocol diagnosis.
- [ ] **[[webrtc-deep-dive|WebRTC]]-Internals** -- chrome://webrtc-internals -- ICE / DTLS / RTP debugging.

### Container / codec deep-dive resources
- [ ] **L. Madhulika, "[[ffmpeg-entity|FFmpeg]] Basics"** book.
- [ ] **Cole Lawrence, "Digital Video and HD"** -- reference for codec internals.
- [ ] **The [[h264-deep-dive|H.264]] spec (ITU-T Rec. [[h264-deep-dive|H.264]])** -- the actual normative document. Surprisingly readable for stream-syntax questions.
- [ ] **codec-wiki / multimedia.cx** -- community-maintained codec internals.
- [ ] **trac.ffmpeg.org** -- [[ffmpeg-entity|ffmpeg]]'s wiki has the best practical encoding recipes anywhere.

## AWS-specific reading

> Major services ([[aws-kvs-entity]], MediaConvert, MediaLive, MediaPackage, Elemental Live, Rekognition Video, IVS) are full entity notes in `notes/entities/`. This list is for **adjacent / supporting** AWS services and reference material.

- [ ] **Amazon Rekognition Video** -- general video analytics (label detection, faces, content moderation). Distinct from Custom Labels.
- [ ] **AWS Elemental Server / Conductor / Statmux** -- on-prem encoders / orchestrators. Mostly broadcast-industry, but worth knowing the heritage.
- [ ] **AWS IVS Real-Time** -- [[webrtc-deep-dive|WebRTC]]-based broadcast variant of IVS, low-latency.
- [ ] **AWS MediaTailor** -- ad insertion into [[hls-and-dash|HLS]]/[[hls-and-dash|DASH]] streams. Probably never relevant to us, but lives in the same family.
- [ ] **AWS MediaStore** -- legacy "S3 for video", being deprecated in favor of MediaPackage v2 + S3.
- [ ] **AWS S3 multipart upload tuning for video clips** -- chunk size / parallelism for large upload throughput.
- [ ] **AWS SDK for [[aws-kvs-entity|Kinesis Video Streams]] Producer (C++ / Java / [[gstreamer-entity|GStreamer]] plugin)** -- the canonical [[aws-kvs-entity|KVS]] publish path. The Python boto3 client is _not_ a producer client.
- [ ] **[[aws-kvs-entity|KVS]] [[webrtc-deep-dive|WebRTC]] signaling channels** -- how to use [[aws-kvs-entity|KVS]] for ultra-low-latency live preview.
- [ ] **AWS GroundTruth video labeling** -- annotation tool for video; relevant if model training scope expands.
- [ ] **EC2 G5 / G6 instance families** -- NVIDIA T4 / L4 / L40S; the hardware substrate for any GPU decode/inference path on AWS.

### AWS reference material
- [ ] AWS docs: [[aws-kvs-entity|KVS]] architecture & pricing https://docs.aws.amazon.com/kinesisvideostreams/
- [ ] AWS Solutions: Live Streaming on AWS (architecture reference) https://aws.amazon.com/solutions/implementations/live-streaming-on-aws/
- [ ] AWS docs: [[aws-mediaconvert-entity|MediaConvert]] job specification https://docs.aws.amazon.com/mediaconvert/
- [ ] re:Invent talks on Elemental media services -- worth a yearly skim

## Specs and standards (the actual normative documents)

- [ ] **RFC 2326** -- [[rtsp-deep-dive|RTSP]]/1.0
- [ ] **RFC 7826** -- [[rtsp-deep-dive|RTSP]]/2.0 (rare in practice)
- [ ] **RFC 3550** -- RTP
- [ ] **RFC 8216** -- [[hls-and-dash|HTTP Live Streaming (HLS)]]
- [ ] **ISO/IEC 23009** -- [[hls-and-dash|DASH]]
- [ ] **RFC 8825** -- [[webrtc-deep-dive|WebRTC]] overview
- [ ] **RFC 4566** -- SDP
- [ ] **ISO/IEC 14496-10 / ITU-T [[h264-deep-dive|H.264]]** -- [[h264-deep-dive|H.264]] / AVC
- [ ] **ISO/IEC 23008-2 / ITU-T [[h265-hevc-deep-dive|H.265]]** -- [[h265-hevc-deep-dive|H.265]] / HEVC
- [ ] **[[av1-vp9-future|AV1]] specification** -- AOMedia. https://aomediacodec.github.io/av1-spec/

## Adjacent industry products (not ours, useful to compare against)

- [ ] **Verkada** -- vertically integrated cloud video + AI surveillance.
- [ ] **Eagle Eye Cloud VMS** -- cloud-first VMS, RTSP and ONVIF ingest.
- [ ] **Motorola Avigilon Cloud** -- cloud variant of an integration we already support.
- [ ] **Cloudflare Stream** -- consumer-grade managed video. Useful pricing comparison.
- [ ] **Mux** -- managed video as a service; HLS/DASH/encoding pipeline. https://mux.com/
- [ ] **Bitmovin** -- managed encoding + player. Used by streaming studios.
- [ ] **api.video** -- Mux competitor.
- [ ] **Daily / 100ms / Twilio Live (sunset)** -- real-time WebRTC platforms.
- [ ] **Roboflow Inference Server** -- "drop in" video AI inference; comparable to ds-server.
- [ ] **DeepStack / Frigate** -- open-source NVR with CV inference. Frigate is the most active. https://frigate.video/

## Talks / blog posts / longreads
- [ ] **"Video on the Web is Hard"** -- Jonathan Zittrain / many flavors of this talk; useful framing.
- [ ] **Mux engineering blog** -- consistently the best practical writing on streaming infra. https://www.mux.com/blog
- [ ] **Streamroot / Lumen / Akamai delivery whitepapers** -- CDN/streaming intersection.
- [ ] **NVIDIA DeepStream blog series** -- pipeline patterns, batching, stream-mux concepts.
- [ ] **Cloudflare blog: video processing series** -- AV1 transition, edge encoding.
- [ ] **The PinT (Production in Theory) talks at Demuxed** -- annual conference on video infra. https://demuxed.com/

## Internal Confluence (TODO: link when ingested)
- [ ] vms-connector RTSP integration page (already in [[vms-connector/reading-list]])
- [ ] vms-connector Pipeline Architecture page
- [ ] AutoPatrol patrol-mode frame-pull design docs (if any)

## Niche but worth a peek
- [ ] **gst-shark** -- GStreamer profiler (latency / per-element timing).
- [ ] **trace-viewer** -- timeline profiling format used by gstreamer / chrome.
- [ ] **x264 / x265 / SVT-AV1 / aom-av1 / dav1d** -- the actual encoders/decoders ffmpeg wraps. SVT-AV1 in particular is the "fast AV1" path.
- [ ] **VVC / H.266** -- next-gen codec after HEVC. Effectively no production deployment yet.
- [ ] **LCEVC (MPEG-5 Part 2)** -- "enhancement layer" codec. Used by some broadcasters; low industry penetration.
- [ ] **Per-Title Encoding (Netflix-style)** -- adapt encoder ladder per content. Relevant for clip storage cost.
- [ ] **CMAF (Common Media Application Format)** -- HLS+DASH unified container. Increasingly the streaming default.
