# Reading List: Fleet Architecture

Sources informing the VMS-Connector fleet redesign ([[knowledgebase/topics/fleet-architecture/_summary|topic summary]]). Organized by theme; each proposal (A-E) has natural affinity with specific sections — see the end of this file for a per-proposal crosswalk.

Convention: `- [ ] [Title](url) -- short description`. Check off as you read + extract notes into the topic's concept/synthesis notes.

---

## Internal — Confluence & KB Cross-refs

### Confluence
- [ ] *(seed)* Architecture review meeting notes, fleet-redesign kickoff — find in `CD` Engineering Design space
- [ ] *(seed)* Current connector sizing / cost dashboard — find in the ops-cost Confluence page (link from infra team)
- [ ] *(seed)* VPA/HPA behavior writeup from ENG-78 investigation — cross-ref to [[memory-and-fork-safety]]

### Companion KB notes (already exist — read before external material)
- [x] [[knowledgebase/topics/fleet-architecture/_summary]] — topic overview, 5-proposal matrix
- [x] [[2026-04-16_evaluation-rubric]] — scoring criteria
- [x] [[2026-04-16_proposal-a-minimal-split]]
- [x] [[2026-04-16_proposal-b-stage-fleets]]
- [x] [[2026-04-16_proposal-c-camera-worker]]
- [x] [[2026-04-16_proposal-d-event-driven]]
- [x] [[2026-04-16_proposal-e-hybrid-sidecar]]
- [x] [[2026-04-17_preliminary-pilot-option]]
- [x] [[customer-site-connectivity]] — **incomplete**, blocks C most
- [x] [[library-decomposition-required]]
- [x] [[memory-and-fork-safety]]
- [x] [[observability-and-tracing]]
- [x] [[frame-transport-comparison]]

---

## Kubernetes — Multi-Deployment Patterns

- [x] [Kubernetes Deployments vs StatefulSets vs DaemonSets](https://kubernetes.io/docs/concepts/workloads/controllers/) -- Ingested 2026-04-21 → [[kubernetes-workload-controllers]]. Spawned concept [[k8s-controller-selection-guide]].
- [x] [Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/) -- Ingested 2026-04-21 → [[pod-topology-spread-constraints]]. Folded into [[k8s-placement-primitives]].
- [x] [Pod Disruption Budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/) -- Ingested 2026-04-21 → [[pod-disruption-budgets]]. URL corrected (original `/disruption/` → `/disruptions/`).
- [x] [Pod Affinity & Anti-Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/) -- Ingested 2026-04-21 → [[pod-affinity-anti-affinity]]. Folded into [[k8s-placement-primitives]].
- [x] [Graceful Shutdown and Zero-Downtime Deployments](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination) -- Ingested 2026-04-21 → [[graceful-pod-termination-zero-downtime]]. URL updated from the tutorial page (404'd) to the canonical pod-lifecycle anchor. Spawned concept [[pod-termination-sequence]].
- [ ] *(seed)* Google Cloud article on "stateful workloads on Kubernetes" -- find recent GKE post on stateful session handling
- [ ] *(seed)* CNCF whitepapers on "Kubernetes at scale" — production war stories from Spotify, Shopify, etc.

## Autoscaling — HPA / VPA / Karpenter

- [x] [Vertical Pod Autoscaler (VPA) deep dive](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) -- Ingested 2026-04-21 → [[vertical-pod-autoscaler-deep-dive]]. Spawned concept [[vpa-bimodal-workload-limitation]] (ENG-78 root-cause).
- [x] [Horizontal Pod Autoscaler behavior](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) -- Ingested 2026-04-21 → [[kubernetes-hpa-behavior]]. Folded into [[scaling-layer-taxonomy]].
- [x] [Karpenter — Just-In-Time Node Provisioning](https://karpenter.sh/) -- Ingested 2026-04-21 → [[karpenter-node-provisioning]]. Folded into [[scaling-layer-taxonomy]].
- [x] [AWS EKS best-practices: Compute and Autoscaling](https://aws.github.io/aws-eks-best-practices/karpenter/) -- Ingested 2026-04-21 → [[aws-eks-karpenter-best-practices]]. Folded into [[scaling-layer-taxonomy]].
- [ ] *(seed)* KEDA (Kubernetes Event-Driven Autoscaling) docs — relevant if Proposal D's NATS backlog drives HPA
- [ ] *(seed)* Blog: "Why VPA hates bursty workloads" — search for a recent SRE postmortem

## Event-Driven / Pipeline Orchestration

### NATS JetStream (primary for Proposal D)
- [ ] [NATS JetStream docs](https://docs.nats.io/nats-concepts/jetstream) -- Primary bet for Proposal D; study retention, ack-wait, consumer groups
- [ ] [JetStream Consumer types — pull vs push vs queue groups](https://docs.nats.io/using-nats/developer/develop_jetstream/consumers) -- Per-stage fleet subscription patterns
- [ ] [JetStream message ordering and exactly-once semantics](https://docs.nats.io/nats-concepts/jetstream/streams) -- Ordering is critical for our frame pipeline

### Alternatives to NATS
- [ ] [Redpanda](https://redpanda.com/) -- Kafka-compatible, lower-ops; consider if NATS ops cost is a blocker
- [ ] [Apache Pulsar — Functions and Processing](https://pulsar.apache.org/docs/functions-overview/) -- Built-in stage processing; potentially more than we need
- [ ] [AWS MSK vs SQS vs Kinesis — when to use which](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-decomposing-monoliths/msk-vs-sqs-vs-kinesis.html) -- Already using SQS (cleanup Lambda §3); evaluate if MSK is warranted for Proposal D frame transport

### Stream-processing frameworks (for comparison, not adoption)
- [ ] [Apache Beam programming model](https://beam.apache.org/documentation/programming-guide/) -- Pipeline-per-stage abstraction; cribs for Proposal B
- [ ] [Apache Flink operator patterns](https://nightlies.apache.org/flink/flink-docs-stable/docs/concepts/stateful-stream-processing/) -- State management + checkpointing; applicable to graceful failover

## Workflow Orchestration (for control-plane fleets)

- [ ] [Temporal — durable execution](https://docs.temporal.io/) -- Heavier than we likely need; relevant if cleanup-Lambda pipeline grows into multi-step workflows
- [ ] [AWS Step Functions — Standard vs Express](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-standard-vs-express.html) -- Already an option in our infra; useful pattern reference

## Video / Streaming Fleet Architectures

- [ ] [GStreamer pipeline design](https://gstreamer.freedesktop.org/documentation/application-development/basics/index.html) -- Reference for pluggable-stage pipelines; our observer/filter/sender pattern echoes this
- [ ] [WebRTC SFU scaling — Jitsi/LiveKit architecture](https://livekit.io/blog/scaling-to-100k-users-with-livekit-servers) -- Large-scale media fleet patterns, per-worker capacity tuning
- [ ] *(seed)* Netflix Mantis architecture blog post -- video-analytics pipeline at fleet scale (multi-stage with auto-scaling per stage)
- [ ] *(seed)* Uber "Fleet Scheduler" blog post -- worker bin-packing for heterogeneous workloads, very relevant to Proposal C
- [ ] [AWS Kinesis Video Streams architecture](https://docs.aws.amazon.com/kinesisvideostreams/latest/dg/how-it-works.html) -- Reference; we already integrate with KVS

## Bin-Packing & Scheduling (for Proposal C — Camera-Worker Fleet)

- [ ] *(seed)* Google Borg paper — "Large-scale cluster management at Google" (EuroSys 2015) -- Canonical bin-packing-at-scale reference
- [ ] *(seed)* Kubernetes Scheduling Framework plugins docs -- Custom scheduler extension for camera-affinity policies
- [ ] *(seed)* Ray placement groups & resource-constrained scheduling docs -- Closest abstraction to "N cameras bin-packed across M workers"

## Distributed Tracing / Observability Across Fleets

- [ ] [OpenTelemetry Collector architecture](https://opentelemetry.io/docs/collector/architecture/) -- Required if we want cross-fleet traces for a single frame's lifecycle (Proposal B/D)
- [ ] [OTel Python auto-instrumentation](https://opentelemetry.io/docs/zero-code/python/) -- Effort estimate for instrumenting our Python fleets
- [ ] [New Relic Distributed Tracing](https://docs.newrelic.com/docs/distributed-tracing/concepts/introduction-distributed-tracing/) -- Already our NR setup; understand limits before designing for it
- [ ] *(seed)* Charity Majors blog — "Observability vs Monitoring" -- Mental model for picking metrics vs traces

## Python Distributed Compute (alternatives to multiprocessing)

- [ ] [Ray — distributed Python](https://docs.ray.io/en/latest/ray-overview/index.html) -- Alternative to shard-via-multiprocessing; higher ops overhead but cross-host scaling for free
- [ ] [Dask distributed](https://docs.dask.org/en/stable/) -- Data-parallel focus; less relevant for our stream-processing shape
- [ ] *(seed)* Python GIL / free-threaded (PEP 703) updates -- Relevant to Proposal A/E if we bet on Python 3.13 free-threaded mode to delay the split

## Frame Transport / Zero-Copy IPC

- [ ] [Apache Arrow Flight](https://arrow.apache.org/docs/format/Flight.html) -- gRPC-based fast columnar transport; heavy for frames but relevant if we move metadata
- [ ] [Linux memfd_create + fd-passing over Unix sockets](https://man7.org/linux/man-pages/man2/memfd_create.2.html) -- Zero-copy frame handoff on the same node (sidecar in Proposal E)
- [ ] [Shared memory in Python — SharedMemory / SharedMemoryManager](https://docs.python.org/3/library/multiprocessing.shared_memory.html) -- Cross-process frame cache; already used indirectly via `actuate_image_cache`
- [ ] [S3 Express One Zone — single-AZ low-latency](https://aws.amazon.com/s3/storage-classes/express-one-zone/) -- Evaluated as frame-backing-store option (Proposal D)

## Cost / Capacity Modeling

- [ ] [AWS Compute Optimizer](https://aws.amazon.com/compute-optimizer/) -- Sizing recommendation engine; calibrate our rubric cost-delta estimates
- [ ] [Kubecost](https://www.kubecost.com/) -- Per-workload cost allocation; verify fleet-level cost claims post-PoC
- [ ] *(seed)* Spotify engineering blog — "Cost allocation for platform teams" -- Mental model for cost-to-value across fleets

## Research Papers (worth seeding; find exact URLs)

- [ ] *(seed)* Google Borg paper (Verma et al, EuroSys 2015) -- bin-packing at scale
- [ ] *(seed)* Borg Omega Kubernetes retrospective (Burns et al, ACM Queue 2016) -- how K8s inherited Borg patterns
- [ ] *(seed)* Twitter/X "Heron" paper (SIGMOD 2015) -- Storm-inheritor; topology-per-stage design relevant to B
- [ ] *(seed)* Naiad: A Timely Dataflow System (SOSP 2013) -- stream-processing state semantics

---

## Per-Proposal Crosswalk

Which categories matter most for each proposal:

| Proposal | Primary categories |
|---|---|
| **A — Minimal Split** | K8s multi-deployment, VPA/HPA, Python distributed (least change) |
| **B — Stage Fleets** | Event-driven (NATS), stream-processing frameworks (Beam/Flink), observability |
| **C — Camera-Worker** | Bin-packing & scheduling, K8s custom schedulers, failover/snapshot |
| **D — Event-Driven** | NATS JetStream deep-dive, frame transport (S3 Express), Kinesis/MSK comparison, OTel |
| **E — Hybrid Sidecar** | Zero-copy IPC, memfd, Python multiprocessing replacements (Ray?), graceful failover |

## How to use this file

1. Walk category-by-category during architecture-review blocks. Tick `[x]` when read + extract notes into `notes/syntheses/` or `notes/concepts/` under this topic.
2. Items marked `*(seed)*` need URL resolution — find the canonical link before reading, then update the line.
3. New sources surfaced during PoC work or a proposal deep-dive → add here under the right category instead of scattering.
4. Cross-pollinate with [[software-architecture/reading-list]] once that exists — architectural governance has lots of overlap.

---

## Frame Storage — 2026-04-21 Prospector Pilot

Ranked reading-list produced by the `research-prospector` pilot run (see [[engineering-process/notes/syntheses/2026-04-21_rd-agent-pilot-learnings]]). 26 entries across chunks 5-7 of the frame-storage question. Grounding context lives in [[frame-storage-current-state]] (chunks 1-2, internal archaeology). Quality-score 1-5, 5=canonical/authoritative.

### Chunk 5 — Video-Reconstruction Approach (encode alert/movement windows to MP4/WebM)

- [x] [AV1 explained — comparisons with H.264/H.265](https://newsroom.axis.com/blog/av1-codec-video-surveillance) `engineering-blog` q:5 — Ingested 2026-04-21 → [[axis-av1-surveillance]]. Codec-to-codec compression ratios (AV1 vs H.264 ~40%, vs H.265 ~25%). Open gap: no software-encoder CPU-cost figures.
- [x] [FFmpeg Formats Documentation — MP4/MOV movflags](https://ffmpeg.org/ffmpeg-formats.html) `tool-doc` q:5 — Ingested 2026-04-21 → [[ffmpeg-movflags-fragmented-mp4]]. `frag_keyframe+empty_moov+default_base_moof` is the concrete pipe-output recipe.
- [ ] [Transcoding assets for Media Source Extensions — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Media_Source_Extensions_API/Transcoding_assets_for_MSE) `vendor-doc` q:5 — Mozilla's definitive fMP4 / MSE reference with exact FFmpeg commands and ISO BMFF compliance.
- [ ] [Video Compression for Remote Surveillance: H.264, H.265, AV1, Zipstream](https://www.criticalts.com/deployment-guides/video-compression-for-remote-surveillance-h-264-vs-h-265-vs-av1/) `industry-writeup` q:4 — Practitioner guide with 4K bitrate tables and smart-compression stacking (AV1 + Zipstream = 70-85% vs raw H.264).
- [ ] [Understanding Rate Control Modes (x264, x265, vpx)](https://slhck.info/video/2017/03/01/rate-control.html) `engineering-blog` q:4 — Werner Robitza's authoritative CRF vs CBR vs ABR guide; CRF is the right mode for archival event clips.
- [ ] [CRF Guide (Constant Rate Factor)](https://slhck.info/video/2017/02/24/crf-guide.html) `engineering-blog` q:4 — Companion: the CRF 0-51 scale, sane values (18-28 for x264), quality/file-size curve.
- [x] [Optimize long-term video storage costs with Amazon Kinesis Video Streams warm storage tier](https://aws.amazon.com/blogs/iot/optimize-long-term-video-storage-costs-with-amazon-kinesis-video-streams-warm-storage-tier/) `vendor-doc` q:5 — Ingested 2026-04-21 → [[aws-kvs-warm-storage-tier]]. Confirms KVS is architecturally incompatible with §12 conditional promotion (stream-wide static tier). Fragment-duration amortization principle validates §11.
- [ ] [HLS and Fragmented MP4 — hlsbook.net](https://hlsbook.net/hls-fragmented-mp4/) `engineering-blog` q:3 — How Apple's adoption of fMP4 for HLS unified HLS and MPEG-DASH packaging; segment vs fragment distinction.
- [ ] [Adopting H.265 at Scale — Verkada whitepaper](https://www.verkada.com/ebooks/h-265/) `vendor-doc` q:3 — Verkada's hybrid-cloud H.265 deployment: cameras encode, cloud transcodes for incompatible clients. Form-gated; preview only.
- [ ] [ffmpegcv — Python FFmpeg Video I/O](https://pypi.org/project/ffmpegcv/) `open-source-readme` q:3 — Drop-in OpenCV-compatible Python library with FFmpeg backend; H.264/H.265, NVENC, subprocess piping. Directly usable in connector.

### Chunk 6 — Alternative Compression / Retention Strategies

- [x] [Manage S3 storage costs granularly with S3 Intelligent-Tiering](https://aws.amazon.com/blogs/storage/manage-amazon-s3-storage-costs-granularly-and-at-scale-using-s3-intelligent-tiering/) `vendor-doc` q:5 — Ingested 2026-04-21 → [[s3-intelligent-tiering]]. 128 KB threshold near our 150 KB frame size; tiering is orthogonal to API-call reduction (secondary lever).
- [x] [Duplicate image detection with perceptual hashing — Ben Hoyt](https://benhoyt.com/writings/duplicate-image-detection/) `engineering-blog` q:4 — Ingested 2026-04-21 → [[perceptual-hash-frame-dedup]]. dHash ≤2 Hamming threshold; estimated 50-70% frame-count reduction for stationary-camera scenes. Tighter threshold (≤1) may be needed for event distinction.
- [ ] [pHash.org — perceptual hash library](https://www.phash.org/) `tool-doc` q:4 — Primary source for pHash algorithm (DCT-based, C/C++). Authoritative if implementing native perceptual hash in connector.
- [ ] [imagehash — Python Perceptual Image Hashing (GitHub)](https://github.com/JohannesBuchner/imagehash) `open-source-readme` q:4 — Production Python library for aHash/pHash/dHash/wHash/crop-resistant. Importable for frame-level similarity gating.
- [ ] [AI-Assisted Video Compression for Long-Term CCTV Storage — Medium](https://medium.com/@samriddhalama36/ai-assisted-video-compression-for-long-term-cctv-storage-dd73e476634f) `engineering-blog` q:3 — Background-Invariant Memory Compression (BIMC, 2025-12): static background once, dynamic foreground only. 50-90% reduction claims.
- [ ] [Key frame extraction algorithm for surveillance videos — Nature Scientific Reports (2024)](https://www.nature.com/articles/s41598-024-84324-0) `paper` q:4 — Peer-reviewed evolutionary approach for maximally informative keyframe selection; keyframe-only retention alternative to full-clip encoding.
- [x] [New S3 Glacier Deep Archive Storage Class](https://aws.amazon.com/blogs/aws/new-amazon-s3-storage-class-glacier-deep-archive/) `vendor-doc` q:4 — Ingested 2026-04-21 → [[s3-glacier-deep-archive]]. $0.00099/GB/month; 12h retrieval SLA disqualifies operator-interactive use; 180-day minimum storage duration. Terminal tier for compliance retention only.
- [ ] [Video Surveillance Data Storage: Cloud vs On-Prem vs Hybrid — Backblaze](https://www.backblaze.com/blog/video-surveillance-data-storage-cloud-vs-on-prem-vs-hybrid/) `industry-writeup` q:3 — Cost ranges: NAS $12-20/TB/mo vs cloud $5-25/TB/mo; B2 at $6/TB/mo egress-free alternative.

### Chunk 7 — Industry References (how big VMS / bodycam / AI-video platforms solve this)

- [ ] [Milestone XProtect VMS 2025 R1 System Architecture](https://doc.milestonesys.com/sysarch/pdf/2025r1/en-US/MilestoneXProtectVMSproducts_SystemArchitectureDocument_en-US.pdf) `vendor-doc` q:5 — Official Milestone architecture PDF: "customized high-performance Milestone media database," multistage archiving, video grooming, encryption, codec handling.
- [ ] [XProtect Storage Architecture and Recommendations — Milestone (2023-09)](https://doc.milestonesys.com/wp/pdf/en-US/XProtectStorageArchitectureAndRecommendations_2023-09.pdf) `vendor-doc` q:5 — Storage-specific white paper: 3.1 Gbps recording, retention policy design, sizing, archiving. Benchmark for our per-camera projections.
- [ ] [Amazon Kinesis Video Streams — Stream Structures (Producer SDK)](https://docs.aws.amazon.com/kinesisvideostreams/latest/dg/producer-reference-structures-stream.html) `vendor-doc` q:5 — AWS reference for Fragment (collection of frames, independently reproducible), MKV Cluster, 1-10s fragment duration recs, Producer/Service boundary.
- [ ] [Amazon Kinesis Video Streams — Features](https://aws.amazon.com/kinesis/video-streams/features/) `vendor-doc` q:4 — GetClip + GetMediaForFragmentList APIs for event-driven clip extraction. Retrieval-side design reference.
- [x] [Eagle Eye Networks — Cloud VMS Architecture](https://www.een.com/product/cloud-vms-architecture/) `vendor-doc` q:4 — Ingested 2026-04-21 → [[eagle-eye-networks-cloud-vms-architecture]]. Bridge = commercial in-cluster-blob analog; motion-gated sync = conditional-promotion trigger; Flex Storage = per-device retention tiering. Vendor-level confirmation of §12's pattern.
- [ ] [Verkada HEVC docs](https://help.verkada.com/verkada-cameras/video-streaming-and-sharing/live-streaming/camera-high-efficiency-video-encoding-hevc) `vendor-doc` q:3 — Production H.265 deployment: camera-side encode, cloud transcode for incompatible devices. Codec-compatibility tradeoff reference.
- [ ] [Why Flock Safety turned to ClickHouse for real-time vehicle traffic analytics](https://clickhouse.com/blog/why-flock-safety-turned-to-clickhouse) `engineering-blog` q:3 — 1B+ ML predictions/day, 20 MB/s peak, image-to-metadata at cloud. Validates "store structured detection data, not pixels" pattern at scale.
- [ ] [IBM Storage Offerings for Video Surveillance Systems](https://www.ibm.com/support/pages/ibm-storage-offerings-video-surveillance-systems) `industry-writeup` q:3 — Validated reference architectures combining Genetec Security Center / Milestone with IBM Storwize. Third-party benchmarking.

### Chunk 8 — S3 Cost Analysis *(added 2026-04-21 — driven by the "API calls dominate, not data volume" finding in [[frame-storage-current-state]] §11)*

**Queued for next prospector pass.** Specific search intent: validate and quantify the API-call-vs-data-volume cost breakdown for S3-backed video/frame storage at scale; find authoritative guidance on consolidating per-frame PUTs/GETs into per-clip operations.

- [ ] *(seed)* AWS S3 Pricing deep-dive — breakdown of PUT/GET/LIST request costs vs storage-byte costs at 1M+ req/day
- [ ] *(seed)* AWS Cost and Usage Reports (CUR) — documentation on how to attribute S3 line items to API-call-type (PUT vs GET vs LIST) for billing audits
- [ ] *(seed)* S3 Batch Operations — for bulk API-call consolidation (applicable to migration / backfill only, not steady-state)
- [ ] *(seed)* AWS case studies: "we switched from per-frame to per-clip and saved X" — vendor engineering blogs with before/after numbers
- [ ] *(seed)* S3 Multipart Upload mechanics — cost implication: multipart adds ~1 InitiateMultipart + N-part PUTs + 1 Complete call; for per-frame writes this dwarfs the single-PUT alternative
- [ ] *(seed)* "Why we're moving off S3" / "Cloudflare R2 vs S3" posts — R2 has zero-egress + zero-API-call pricing for similar workloads; relevant reference point
- [ ] *(seed)* Backblaze B2 pricing — egress-free alternative; relevant cost comparison for the video-clip-retrieval path
- [ ] *(seed)* DynamoDB RCU/WCU pricing — per-frame `EnrichedFrameV2` writes similarly API-priced; consolidation story parallels S3
- [ ] *(seed)* AWS Kinesis Video Streams **pricing** (we already have the architecture doc in Chunk 5) — call out per-fragment PUT costs + data-ingestion costs separately

### Gaps flagged by the prospector (follow-up search candidates)

- WebRTC recording patterns (MediaRecorder API → fMP4; server-side recording)
- GStreamer for event-clip encoding (common in IoT/edge camera stacks)
- Genetec Security Center storage architecture (seems partner-portal-gated; try industry analyst reports)
- Rhombus Systems technical architecture (marketing-only publicly; try conference talks)
- CMAF (Common Media Application Format) ISO standard (unifies fMP4 for HLS + DASH)
- `/create-video` lambda implementation (internal — archaeology hook; check repo for its source + ownership)

### Chunk 9 — In-Cluster Blob Storage *(added 2026-04-21 — high-priority direction per [[frame-storage-current-state]] §12)*

Research candidates for the "replace per-frame S3 with in-cluster blob, conditionally promote clips" strategy. Queued for the next prospector pass.

- [ ] *(seed)* MinIO on Kubernetes — official docs, distributed mode, operator, per-tenant namespace isolation
- [ ] *(seed)* Rook + Ceph on Kubernetes — heavier operator-managed S3-compatible option
- [ ] *(seed)* Garage — Rust-based S3-compatible alternative; low-operational-overhead claim
- [ ] *(seed)* SeaweedFS — designed for many small files; aligned with per-frame workload shape
- [ ] *(seed)* Kubernetes `emptyDir` with `sizeLimit` — pod-ephemeral simplest pattern
- [ ] *(seed)* `emptyDir.medium: Memory` (tmpfs) — trades durability for speed; relevant if frame TTL is seconds not minutes
- [ ] *(seed)* `hostPath` volumes — per-node; fork-safety + pod-rescheduling risks documented
- [ ] *(seed)* local-path-provisioner + OpenEBS LocalPV — per-pod PVC patterns
- [ ] *(seed)* AWS EKS local NVMe instance storage — i3en / d3 / m5d families; integrates with Karpenter NodePool selection (see [[karpenter-node-provisioning]])
- [ ] *(seed)* In-cluster Redis with streams / RedisJSON — already deployed in our stack; candidate for low-friction option
- [ ] *(seed)* NATS JetStream as ephemeral blob store — relevant to Proposal D; already tracked in Chunk 5 of the frame-transport references
- [ ] *(seed)* Open-source post-mortems on MinIO / Ceph at scale — operational war stories (search: `site:medium.com "MinIO" "production" "lessons"`)

### Broken-source revisit queue *(sources the 2026-04-21 prospector couldn't fully evaluate)*

PDF workaround validated 2026-04-21 via `curl -sSL -o _research-inbox/{name}.pdf {url}` → `Read(file, pages="1-N")`. Milestone 2023-09 storage architecture already downloaded; 1.5MB, 48 pages, opens cleanly.

- [ ] **Milestone 2023-09 storage white paper** — downloaded to `_research-inbox/milestone-xprotect-storage-architecture-2023-09.pdf`; source-reader pass pending
- [ ] **Milestone 2025 R1 architecture PDF** — not yet downloaded; curl pattern should work
- [ ] **Nature keyframe extraction paper (2024)** — 303 redirect failed WebFetch; try `curl -L --user-agent "Mozilla/5.0..."` — likely open-access, arxiv version probably exists too
- [ ] **Verkada H.265 whitepaper** — form-gated; **user manual download required** — once downloaded, drop into `_research-inbox/` and flag
- [ ] **XProtect Storage PDF second URL** — same Milestone, different doc; verify not a duplicate
