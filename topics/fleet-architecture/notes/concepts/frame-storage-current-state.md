---
title: "Frame Storage Current State (VMS Connector)"
type: concept
topic: fleet-architecture
tags: [frame-storage, current-state, pipeline, s3, ddb, image-cache, clips, autopatrol]
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
incoming:
  - topics/engineering-process/notes/syntheses/2026-04-21_rd-agent-pilot-learnings.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
  - topics/fleet-architecture/reading-list.md
  - topics/fleet-architecture/sources/ffmpeg-movflags-fragmented-mp4.md
  - topics/personal-notes/notes/daily/2026-04-21.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-05-01
---

# Frame Storage Current State (VMS Connector)

Grounding inventory for the frame-storage redesign feeding into the [[fleet-architecture/_summary|5-proposal evaluation]]. Every hop from camera pull through alert dispatch and downstream persistence. See [[memory-and-fork-safety]] for the memory topology context.

## 1. Pull-stage buffering

Three tiers hold frames between puller and pipeline, all per-camera:

- **Puller `frame_queue`** — `Queue(maxsize=max_fps * 30)` (~30 s of headroom) at `camera/shared/base_stream_camera.py:137`. Overflow is drained/discarded by the puller (`base_stream_camera.py:684-693`, and `actuate-pullers` `base_puller.py:637-639`).
- **`image_cache`** — a per-camera `TTLImageCache` or `PooledTTLImageCache`, default `base_slots = min(max(max_fps*20, 20), 60)` with `ttl=60 s` at `base_stream_camera.py:150-184`. Pool-backed variant at `actuate-image-cache/src/actuate_image_cache/pooled_ttl_image_cache.py:52` (`pool_size=2` per shape, copy-on-get).
- **`LRUImageCache` for patrol** — AutoPatrol / Patrol cameras use LRU rather than TTL because runs are bounded. Size derived via `PatrolCameraMixin.compute_patrol_cache_size` at `camera/patrol/patrol_camera_mixin.py:22-28`: `product_count → patrol_timeout = clamp(product_count*2, 5, 30) → cache_size = max(60, patrol_timeout * multiplier * 15)`. AutoPatrol uses `multiplier=2` (`autopatrol_camera.py:41-45`), PatrolCamera uses `multiplier=1` (`patrol_camera.py:22`). For a typical 3-product camera: `patrol_timeout=6s → cache_size=180` (AP) / `90` (Patrol).

Result buffer between pipeline and camera: `Queue(maxsize=20)` at `base_camera.py:169`; result cache `FIFOCache(maxsize=1)` at `base_stream_camera.py:246` (`last_data`).

## 2. Pipeline in-flight storage

The pipeline is **stateless w.r.t. frames** — `ImageDataPacket` carries only `frame_id` and metadata; actual pixels stay in the camera's `image_cache` and are fetched on demand by steps via `data.frame(self.image_cache)` (`actuate-pipeline/src/actuate_pipeline/core/pipeline_runner.py:47` and pattern in `save_frame_meta_step.py:85-91`). No per-step hand-off cache. Pre-processing converts numpy → JPEG via `turbojpegencode_step`, updating the same `image_cache` entry (`set_frame_jpg_bytes`). `remove_raw_frame.py` calls `evict_frame_numpy()` so only JPEG bytes remain post-encode (see [[memory-management]] §"Frame Lifecycle").

## 3. Detection-window frames

The open window itself retains **timestamps only**, not frames. `WindowDataPacket.approx_capture_timestamps` (`actuate-pipeline-objects/src/actuate_pipeline_objects/window_packet.py:31, 105-110`) is a bare Python list of `Decimal` capture timestamps — never pixels. Window bookkeeping (`__window_hits: list[bool]`, `tag_zone_hits: set`) is also metadata-only.

Frame bytes required for the alert are re-fetched from `image_cache` at send time (`base_stream_camera.py:1021` in `flush_deferred_alerts`) or from S3 if expired (`_fetch_frame_from_s3`, `base_stream_camera.py:1000-1007`). `BaseStreamCamera` keeps a `_frame_timestamps: deque` of `(frame_id, capture_ts)` pairs (`base_stream_camera.py:211`) only for eviction tracking, not for alert assembly.

Pre-alarm buffer (when `feature_deployment.pre_alarm > 0`) retains `abs(pre_alarm)` frame IDs in `data.previous_frame_ids` / `data.previous_timestamps` — see `cleanup_step.py:76-90`. Frames themselves stay pinned in `image_cache`; `CleanupStep` surfaces evicted IDs via `data.frames_to_delete` for proactive cache removal.

## 4. Clip assembly & S3 upload

**The connector does not assemble clips locally.** `SlidingWindowStep.close_window` submits a POST to `{config.create_detection_window_url}/create-video` with just `{"window_id": ...}` at `actuate-daos/src/actuate_daos/window_ids.py:62-89`. An external lambda/service composes the clip from the already-uploaded per-frame JPEGs.

Per-frame JPEG upload happens per window tick in `save_frame_meta_step.py` → `actuate-frames/src/actuate_frames/save_frame_meta.py:45`. Key pattern: `{custcam_id}{label}/{window_timestamp}/{uuid}` in the `detection_bucket` S3 bucket (config field `detection_bucket`). Each uploaded frame also writes a DDB row (see §9). `alerts_during_run` for patrol only carries `{window_id, window_timestamp, frame_approx_capture_timestamps}` (`patrol_camera_mixin.py:170-174`) — no bytes.

## 5. AutoPatrol / VCH `run_frame_s3_key`

The per-run "hero" frame (first decoded frame of the run) is captured once by the puller: `run_frame_bytes = cv2.imencode(".jpg", main_frame)[1].tobytes()` at `actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py:249-251`.

`PatrolCameraMixin._upload_run_frame` (`patrol_camera_mixin.py:247-256`) uploads it to `{customer}/patrol/{camera}/run_frame.jpg`; AutoPatrol override at `autopatrol_camera.py:125-136` uses `{customer}/autopatrol/{camera}/run_frame.jpg` and is skipped for `patrol_type == "VisualCameraHealth"`. The returned `run_frame_s3_key` goes into the `task_result` dict (`patrol_camera_mixin.py:244`). It is **separate from clip frames** because it represents the camera's baseline at run start for patrol-result UI display, whereas clip frames are per-detection-window.

## 6. Alert-dispatch frame handling

For detection alerts (VCH `raise_alert`, `healthcheck/alerts/senders/vch_alert_sender.py:63-92`), frame content is delivered as **S3 presigned URLs**, not bytes:
- `current_image_url = s3_dao.get_download_url(spray_bucket, healthcheck.stream_quality.frame_key, expires_in=604800)` (7-day expiry)
- `reference_image_url` from `healthcheck.scene_change.background_frame_key`

The `spray_bucket` S3 keys are populated upstream by `spray_step.py:35` (for current-frame captures) and scene-change tracking. Immix receives URLs — the connector never streams raw JPEG to downstream via SMTP/webhook in this path. Detection-alert send (`MultiAlertSender.trigger_alert`) pulls `frame_jpg_bytes` from `image_cache` on dispatch (`flush_deferred_alerts`, `base_stream_camera.py:1021-1022`).

## 7. Deferred / pending alert state

After commit `946d149f` (drain-executor fix), lifetime of pending alert frames is bounded by:

- The tag-zone window remains open → frame remains in `image_cache` until TTL (60 s) expires OR the window closes.
- `flush_deferred_alerts` (`base_stream_camera.py:1009-1129`) pulls the last frame synchronously before submission, then `drain_alert_executors(timeout=30)` (`base_stream_camera.py:1131-1161`) waits for all in-flight Immix/DDB tasks to finish before process exit.
- `_flush_all_tracked_frames` (`base_stream_camera.py:777-793`) then releases every remaining tracked frame.

**Worst-case footprint per camera:** one JPEG (~150 KB) per open tag-zone window + the full `image_cache` (`cache_size * ~2.7 MB` if numpy kept, or `cache_size * ~150 KB` after `evict_frame_numpy`). For patrol: `cache_size ≤ 900` entries (30×multiplier×15 cap) × ~150 KB ≈ ~135 MB max bounded, typically much less since cache turnover is continuous.

## 8. Existing video-reconstruction work

**No evidence of production video encoding.** Searches for `ffmpeg`, `av.open`, `VideoWriter`, `imageio`, `MediaRecorder`, `fragmented mp4`, `moov` turn up:
- `av.open()` for **decoding** [[rtsp-deep-dive|RTSP]] streams (`camera/shared/base_stream_camera.py:1692`, `scripts/test_connection_timing.py:156`).
- [[ffmpeg-entity|FFmpeg]] built into Docker images for [[pyav-entity|PyAV]] runtime (`docker_files/dependencies/build_ffmpeg.sh`, `docker_files/x86_dockerfile.gpu`).
- One dev-only script `scripts/visualize_fdmd.py:939-940` uses `cv2.VideoWriter` with `mp4v` for FDMD debugging output.

Clip assembly is entirely delegated to the external `/create-video` service (see §4). No `.webm`, `.mp4` writing, fragmented MP4, or moov-box manipulation in the connector or libraries.

## 9. DynamoDB storage

Frame-adjacent tables (schema per `actuate-daos/docs/daos.md`):

| Table | Purpose | Row ~ size |
|-------|---------|-----------|
| `WindowIdsV2` | One row per detection window; centroids, first-frame S3 key, alert_url, TTL 30 d (`window_ids.py:91-131`) | ~500 B – 2 KB |
| `EnrichedFrameV2` | One row per saved frame: `frame_id`, `s3_key`, `labels`, `unfiltered_raw_model_response`, TTL 180 d (`save_frame_meta.py:54-74`) | ~1-3 KB (raw model response dominates) |
| `DetectedV2` | One row per detection (per label in a frame) | ~500 B |
| `clips-metadata` | Clip processing metadata, 30 d TTL (`clips_metadata_dao.py:upload_metadata`) | ~1 KB |
| `autopatrol_results` / `autopatrol_alerts` / `autopatrol_chm_issues` | Patrol outputs with alert_window_ids, clips list, TTL 30 d | ~2-10 KB for result (clip array) |
| `MotionFrame` | Motion boxes per frame, TTL 30 d | ~500 B |
| `Heartbeat`, `Blacklist`, `SceneChange*`, `PeopleFlow`, `ImageData`, `CameraStatus`, `Token` | Per-camera / per-site state | variable |

Volume dominator per detection window: `EnrichedFrameV2` rows (one per saved frame across the window; a 10-frame window × K products ≈ 10-30 rows × ~2 KB).

## 10. Rough memory-per-camera frame footprint

From `/home/mork/work/vms-connector/CLAUDE.md` (Diagnostics §"Memory sizing") and [[memory-management]]: **~270 MB/camera steady-state RSS**, broken down as:

| Slice | ~MB | Frame-adjacent? |
|-------|-----|-----------------|
| libavcodec internal decode state | ~189 | No (decoder) |
| `image_cache` (PooledTTLImageCache + FrameBufferPool copies) | ~44 | **Yes** |
| [[h264-deep-dive|H.264]] decode reference frames | ~19 | Partial (decoder buffers) |
| Threads / Python / motion / misc | ~18 | Mixed |

**Frame storage dominates ~44 MB/camera** of the 270 MB — roughly 16%. The 32 MB/camera K8s formula (`cameras*32MB + 500MB base`) is significantly under-provisioned vs actual RSS; VPA inflates requests further (see [[vpa-bimodal-workload-limitation]] and ENG-78). The `FrameBufferPool` already caps per-camera pool memory at `~5.4 MB` (2 buffers × 2.7 MB @ 720p) on top of the live cache — see [[memory-management]] §"PooledTTLImageCache and FrameBufferPool".

## 11. Cost shape — API calls dominate, not data volume *(added 2026-04-21)*

**Working hypothesis from stakeholder input:** the S3 bill for frame storage is dominated by **API call volume**, not by stored-byte volume. Needs billing-data validation (TODO in [[mark-todos]]).

The current-state API-call math per detection window (10-frame window, 1 product):

| Operation | API calls | Note |
|---|---|---|
| Per-frame `save_frame_meta` PUT | 10 × S3 PUT | One per frame written to `detection_bucket` |
| Per-frame `EnrichedFrameV2` DDB write | 10 × DDB PutItem | (not S3, but API-priced similarly at scale) |
| `/create-video` GET pass | 10 × S3 GET | External lambda fetches every per-frame JPEG to assemble the clip |
| `/create-video` PUT assembled clip | 1 × S3 PUT | Single final clip object |
| Alert dispatch — presigned URL generation | 0 | Local op, no S3 API |
| Alert consumer (Immix) clip retrieval | 1 × S3 GET | Triggered when operator views the alert |

**Total per window: ~22 S3 API calls + 10 DDB calls** → roughly **2.3 S3 API calls per frame**. Multiplied by the per-camera per-day window rate × fleet size, this is the cost driver.

**Why video-reconstruction in-process is the real lever:**

If the connector encoded the window into a single MP4/WebM locally before upload:

| Operation | API calls | Delta vs current |
|---|---|---|
| Per-window encoded-clip PUT | 1 × S3 PUT | -9 (vs. 10 per-frame PUTs) |
| `/create-video` eliminated | 0 × S3 GET | -10 (no per-frame assembly fetches) |
| `/create-video` eliminated | 0 × S3 PUT | -1 (no assembled-clip PUT — it's already assembled) |
| Alert retrieval | 1 × S3 GET | unchanged |

**New total per window: ~2 S3 API calls** → **10x+ reduction in API volume.** Data-volume savings from the encoding ([[h264-deep-dive|H.264]]/[[h265-hevc-deep-dive|H.265]]/[[av1-vp9-future|AV1]] vs raw JPEGs) are a secondary benefit; the primary benefit is the flat PUT/GET call count.

**Implications for the redesign (surfaces in each fleet proposal):**

1. **Current architecture's `/create-video` service is the API-cost hotspot.** Any redesign that leaves it in place leaves the N-frame-fetch-per-clip cost structure untouched.
2. **In-process encoding** requires CPU budget ([[h264-deep-dive|H.264]] ≈ 1-2× real-time on a single core for 720p; [[av1-vp9-future|AV1]] is heavier). This cost moves from S3 to compute — worth modeling against EKS node-hours.
3. **DDB frame-metadata rows** (`EnrichedFrameV2`) are also per-frame; if we eliminate per-frame S3 writes, consider consolidating the frame metadata into a single per-window JSON blob in the clip's sidecar or embedding in the video container (metadata atom in MP4).
4. **Consumers must adapt** — the `/create-video` lambda is downstream of us but owned by someone. Changing the contract (single-clip object vs per-frame objects) is a cross-team negotiation.

See [[fleet-architecture/reading-list]] §"Chunk 6 — Alternative Compression" for S3 Intelligent-Tiering references (orthogonal — tiering attacks the minority cost driver, per-byte storage, not the majority driver, API calls). See also the [[aws-kvs-entity|AWS KVS]] warm-storage-tier reference in the reading-list — [[kvs-components|KVS]] explicitly discusses the API-call vs data-volume pricing dimensions.

## 12. Proposed direction: in-cluster blob + conditional S3 promotion *(added 2026-04-21, user-surfaced)*

**High-priority strategy currently in consideration:** replace per-frame S3 writes with **in-cluster blob storage** for window accumulation, and promote to S3 **only when a window closes with a detection-positive outcome** (as a single encoded clip). Drop frames from non-eventful windows entirely — no S3 calls, no persistent storage.

This composes with §11 (API-call cost dominance) to collapse the current pattern:

| Event | Current (per 10-frame window) | Proposed (in-cluster + conditional promotion) |
|---|---|---|
| Window accumulation | 10 × S3 PUT + 10 × DDB PUT | 0 S3 calls (in-cluster blob only) |
| Window close, no detection | — (no cleanup; all 10 frames stay in S3 w/ TTL) | Drop in-cluster blob; **0 S3 calls, 0 persistent** |
| Window close, detection-positive | 10 × S3 GET (`/create-video`) + 1 × S3 PUT (clip) | 1 × S3 PUT (encoded in-process from blob) |
| Alert consumer retrieval | 1 × S3 GET | 1 × S3 GET (unchanged) |

**Per-window API calls:** 22 (current) → 2 (eventful) / 0 (non-eventful). If most windows are non-eventful (typical for always-on camera fleets), the fleet-aggregate reduction is **>50x** — not just the 10× in-process encoding alone.

## Open design questions (for the synthesizer pass)

1. **In-cluster storage backend** — options:
   - `emptyDir` (pod-ephemeral, simple, capped via `sizeLimit`)
   - `emptyDir.medium: Memory` (tmpfs — near-zero-latency, trades durability for speed)
   - `hostPath` (per-node; risks with fork-safety, pod rescheduling)
   - `PersistentVolumeClaim` (per-pod PVC with local-path-provisioner / OpenEBS LocalPV)
   - In-cluster Redis with streams / RedisJSON (already deployed for other purposes)
   - MinIO / Ceph / Garage / SeaweedFS (full S3-compatible blob stores in-cluster)
   - AWS EKS local NVMe (i3en / d3 / m5d instance families) via Karpenter NodePool selection
   Each has capacity / resilience / operational tradeoffs; ties into [[scaling-layer-taxonomy]] and [[memory-and-fork-safety]].
2. **Retention policy for in-cluster storage** — TTL after window close? LRU cap by total size? Both? Today's `TTLImageCache` is per-camera 60 s TTL; can that pattern scale to the fleet-level "per camera-group blob pool"?
3. **Blob locality** — frames must co-locate with whichever pod encodes them at window close. Topology-spread + pod-affinity design (see [[k8s-placement-primitives]] and [[pod-affinity-anti-affinity]]) becomes load-bearing.
4. **Clip-encoding location** — same pod that owns the window (simplest, one context), or offload to a dedicated encode fleet (better VPA isolation per [[vpa-bimodal-workload-limitation]] since encoding is bursty CPU)?
5. **Consumer-contract migration** — `/create-video` lambda either rewrites around in-cluster-pull semantics, or is retired entirely (connector does the encode and promotes the finished object). Cross-team coordination with whoever owns `/create-video`.
6. **Failure handling** — if a pod crashes mid-window, in-cluster blob is lost. S3 was the durable substrate by default; need to decide whether mid-window frame loss matters (pre-detection frames are disposable; what about frames that triggered the detection but were never promoted?). This ties into [[tracker-snapshot-schema]] and [[pod-termination-sequence]].

## Relevance to fleet proposals (direction-sensitive)

This design favors proposals with **per-camera-group storage locality**:

- **E — Hybrid Sidecar** ✅ Strong fit. Detection core already holds camera-group state; adding blob store in the same StatefulSet pod is natural. Aligns with proposal E's "stateful core" premise.
- **C — Camera-Worker** ✅ Strong fit. Worker already holds N cameras; blob-per-worker is a direct extension. `karpenter.sh/do-not-disrupt` for encode-in-progress needed.
- **B — Stage Fleets** 🟡 Awkward. Frame handoff across stateless stages breaks blob ownership; would need an explicit "blob-holding" stage (e.g. observer) that's effectively stateful, eroding B's stateless-stage premise.
- **D — Event-Driven** 🟡 Natural alternative: NATS JetStream as durable in-cluster buffer. JetStream already handles in-cluster persistence; the "blob store" is the NATS cluster itself. Heavier infrastructure but aligned with D's premise.
- **A — Minimal Split** ❌ Weak fit. Monolithic pipeline pod already holds frames in `image_cache`; no architectural change needed to do in-process encoding — but also no natural place to share blob storage across sites if that's ever wanted.

The synthesizer pass should fold this into the per-proposal frame-storage delta.

## Consumers that constrain redesign

Any redesign that changes where frames live must preserve:
- **S3 `detection_bucket` key format** `{custcam_id}{label}/{window_timestamp}/{uuid}` — consumed by `/create-video` lambda and [[alert-ui|alert-UI]].
- **`EnrichedFrameV2.s3_key` → S3 pointer contract** — consumed by alert reprocessing, [[downstream-consumer-impact]].
- **`spray_bucket` run-frame keys** — consumed by Immix CHM dashboards via presigned URL.
- **Per-window DDB `WindowIdsV2`** — consumed by `/create-video` to enumerate frames for a clip.

## Related

- [[memory-and-fork-safety]]
- [[memory-management]]
- [[frame-transport-comparison]]
- [[library-decomposition-required]]
- [[downstream-consumer-impact]]
