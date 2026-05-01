---
title: "BlacklistFilter Locality — Verification Finding"
type: concept
topic: fleet-architecture
tags: [blacklist, state-locality, filters, verification, camera-worker]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/downstream-consumer-impact.md
  - topics/fleet-architecture/notes/concepts/library-decomposition-required.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-a-minimal-split.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
incoming_updated: 2026-05-01
---

# BlacklistFilter Locality — Verification Finding

**Claim verified: cross-camera state in the [[vms-connector|VMS Connector]] is per-camera, not per-site.** Splitting cameras from the same site across different worker pods does not break filter correctness.

This was the open question blocking [[2026-04-16_proposal-c-camera-worker|proposal C (Camera-Worker)]] and simplifies state-locality assumptions for all other proposals.

## What was checked

Claim under test: "BlacklistFilter's R-tree is site-level — splitting a site across workers would corrupt blacklist detection."

**Result: false.** The R-tree is instance-local per `BlacklistFilter`, which is constructed per camera.

## Evidence

### 1. BlacklistFilter is per-camera

`actuate_filters/blacklist/blacklist_filter.py:17,25`

```python
class BlacklistFilter:
    def __init__(self, feature_deployment, site_id=None, camera_id=None, ...):
        ...
        self.r_tree_manager = RTreeManager()  # instance-local
```

`site_id` and `camera_id` are stored for logging/metrics but **not** used as R-tree partition keys. Each `BlacklistFilter` owns its own `RTreeManager`. The constructor is invoked per camera during pipeline wire-up.

### 2. Image cache is per-camera

`vms-connector/camera/shared/base_stream_camera.py:144-183`

Each camera creates its own `TTLImageCache` or `PooledTTLImageCache` and passes it into its pipeline. No site-level cache sharing.

### 3. Observer pool is shard-local, not site-local

`vms-connector/site_manager/connector/analytics_site_manager.py:260-321`

The 4-worker `ActuateThreadPoolExecutor` is created per **shard process**, shared across all cameras in that shard:

```python
# line 260-268: single pool per shard
self._observer_pool = ActuateThreadPoolExecutor(max_workers=4, ...)
# line 320: pool attached per-camera at runtime
camera.observable_manager.executor = self._observer_pool
# line 321: per-camera lock
camera.observable_manager._camera_lock = threading.Lock()
```

ObservableManager instances are per-camera. The pool is shared at the shard scope, not the site. This has two implications:

- Camera split across pods: each pod has its own pool. Safe.
- Site split across pods: same as above. Safe.

### 4. Async inference pool is shard-local and stateless

Lines 247-254 of the same file show one `AsyncInferencePool` per shard. Inference calls are stateless HTTP — different pools in different pods is operationally equivalent to different shards in one pod.

### 5. Config access is per-camera

`base_stream_camera.py:229` — `self.camera_config` is camera-level. Connector config (`self.config`) holds site settings but no per-site cross-camera runtime state.

## What breaks if you split cameras from the same site across workers?

**Nothing architectural.** Every coupling is shard-local (process-local), not site-global. The only caveat:

> If someone later adds a feature that requires cross-camera correlation within a site (e.g., multi-camera tracking, site-wide crowd aggregation), it would need **external coordination** (Redis, DynamoDB, or similar) rather than in-process observer pools. Today no such feature exists in the base architecture.

## Consequences for proposals

- **[[2026-04-16_proposal-c-camera-worker|Proposal C]]** becomes viable — bin-packing cameras regardless of site does not corrupt detection.
- **[[2026-04-16_proposal-b-stage-fleets|Proposal B]]** observer split is simpler than feared — observer state is already camera-scoped.
- **[[2026-04-16_proposal-e-hybrid-sidecar|Proposal E]]** detection core can use camera-affinity rather than site-affinity without losing detection quality.
- Any proposal that introduces a cross-camera feature must also introduce a coordination layer — budget for it in that proposal.

## Residual verification before migration

Before any of these proposals lands in production, re-confirm by running the existing filter test suite with R-trees instantiated per-camera from two different site IDs and checking for cross-contamination. This is a safety net; current static-analysis evidence is already unambiguous.
