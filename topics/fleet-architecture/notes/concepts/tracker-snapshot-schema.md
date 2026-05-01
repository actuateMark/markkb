---
title: "BoTSORT Tracker Snapshot Schema"
type: concept
topic: fleet-architecture
tags: [botsort, tracker, serialization, snapshot, failover, state]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/frame-storage-current-state.md
  - topics/fleet-architecture/notes/concepts/pod-termination-sequence.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_graceful-failover-design.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-d-event-driven.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_frame-storage-design-deltas.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
incoming_updated: 2026-05-01
---

# BoTSORT Tracker Snapshot Schema

The graceful-failover requirement (see [[2026-04-16_graceful-failover-design]]) demands that a replacement worker resume in-flight tracking without a 2-30s gap. BoTSORT state is the harder half of that problem (window state already has a persistence precedent via `WindowIdsDAO`). This note defines the snapshot format.

## State to capture

Per `actuate-libraries/actuate-botsort/src/actuate_botsort/botsort.py:15-100`:

### `BoTSORT` instance
- `frame_id` (int) — current frame counter
- `kalman_filter` (KalmanFilter) — **stateless**, do not snapshot; reconstruct on resume
- `tracked_stracks`, `lost_stracks`, `removed_stracks` (list[STrack]) — live tracking state
- Configuration (`track_thresh`, `high_thresh`, `match_thresh`, etc.) — reconstruct from camera config

### `STrack` instance (per active track)
- `track_id` (int)
- `mean` (numpy 1×8 float) — Kalman state vector
- `covariance` (numpy 8×8 float) — Kalman covariance
- `cls`, `cls_hist` (int, list) — class label and history
- `score` (float) — last detection confidence
- `is_activated`, `state` (flags)
- `smooth_feat` (numpy 1×N float) — normalized feature vector (re-ID)
- `features` (deque, maxlen 50) — 50-frame feature history
- `tracklet_len`, `frame_id`, `start_frame` (int)

All fields are `numpy` arrays, scalars, or small deques. **All picklable.**

## Snapshot format (proposed)

```json
{
  "schema_version": 1,
  "camera_id": "cam-abc-123",
  "site_id": "site-xyz-456",
  "captured_at": "2026-04-16T14:03:22.100Z",
  "botsort": {
    "frame_id": 18432,
    "tracked": [ { "track_id": 7, "mean": [...8...], "covariance": [...64...], "cls": 0, "cls_hist": [0, 0, 0], "score": 0.87, "state": "Tracked", "is_activated": true, "smooth_feat": [...N...], "features": [[...], [...], ...], "tracklet_len": 42, "frame_id": 18432, "start_frame": 18390 }, ... ],
    "lost":    [ ... ],
    "removed": [ ... ]
  }
}
```

### Encoding choices

- **JSON for schema_version, IDs, timestamps** — human-debuggable, diffable.
- **MessagePack or Arrow for the numpy arrays** inside the track list — ~5× smaller than JSON float arrays; native numpy round-trip. Alternative: base64-encoded `np.save` bytes if we want zero new deps.
- **Gzip the whole payload** before writing — per-track state for a busy scene compresses ~3×.

For v1, start with pure JSON + base64-encoded `np.save` for arrays. Optimize after profiling.

## Snapshot cadence

Options, in increasing RPO-safety order:

| Cadence | RPO | Write cost | Notes |
|---------|-----|-----------|-------|
| On window open/close | ~window duration (2-30s) | Low (~1 write/camera/30s) | Matches existing `WindowIdsDAO` lifecycle. Cheapest. |
| Fixed interval (1s) | ≤1s | Moderate (1 write/camera/s × N cameras) | Predictable load. Simple. |
| Per-frame | Frame-perfect | **Too high** — at 32K cameras × 3 FPS = 96K writes/s. Rejected. | — |
| On tracker state change | Event-driven | Variable | Complex; skip unless profiling demands it. |

**Recommendation: fixed 1-second interval, coalesced to single write per camera.** Combined with window-level snapshots via the existing `WindowIdsDAO`.

**K8s cadence bound:** `terminationGracePeriodSeconds` is the hard bound on the 1-second cadence — SIGKILL cuts off any snapshot already in flight. Size the grace period as (preStop drain + snapshot write latency + buffer). See [[pod-termination-sequence]] for the full shutdown flow, and the K8s Mechanics section of [[2026-04-16_graceful-failover-design]] for the typical 10-30 s sizing.

## Storage target

Three candidates — see [[2026-04-16_graceful-failover-design]] for the full comparison. In brief:

| Store | Latency | Durability | Cost at 32K cams | Notes |
|-------|---------|------------|-----------------|-------|
| Redis (new cluster) | <5ms | TTL-persist + AOF | Moderate | Fastest. New infra. |
| DynamoDB (extend WindowIdsV2) | ~10ms | High | Higher | Reuses existing DAO pattern. |
| S3 (partitioned prefix) | ~50ms | Highest | Low | Too slow for 1s cadence unless we batch. |

Leading choice: **Redis with AOF persistence**, fallback to DynamoDB for the first week post-launch so we have two storage paths during the bed-in period.

## Resume protocol

When a worker boots and claims cameras:

1. For each claimed camera, read the latest snapshot by key `tracker:{camera_id}`
2. If `captured_at` is older than 60s, **discard** (stale — cold-start is safer than resuming drifted state)
3. Rebuild `BoTSORT` instance from config, then inject `tracked/lost/removed` STrack state
4. Set `frame_id` to snapshot's `frame_id`; next frame will tick it forward
5. Kalman filter is deterministic from config — no need to snapshot it

## What this doesn't cover

- **Detection windows** — already persisted via `WindowIdsDAO` (`actuate-libraries/actuate-daos/src/actuate_daos/window_ids.py:15-136`). The failover design extends that pattern.
- **Observer state beyond tracking** — e.g., `StationaryFilter` cooldowns. These are typically short-lived (seconds) and may be acceptable to cold-start. Revisit if profiling shows observable regressions.
- **Pipeline step state** — mostly stateless. Exception: `SlidingWindowStep` (covered by window snapshots).
