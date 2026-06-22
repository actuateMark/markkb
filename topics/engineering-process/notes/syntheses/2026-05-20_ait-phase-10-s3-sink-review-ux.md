---
title: "AIT Phase 10 — S3 sink + AIT review UX"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, brain-in-jar, s3, lambda, ttl, dumps, ds-terraform-eks-v2, roadmap]
created: 2026-05-20
updated: 2026-05-20
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-brain-in-jar-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-9-site-dump-crash-hook.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-dovetail.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-integration-plan.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-05-27
---

# AIT Phase 10 — S3 sink + AIT review UX

Closes the loop. Dumps written locally by Phase 9 get uploaded to S3 in the background. A separate Lambda compacts each raw dump into a long-lived summary. The AIT CLI gains `ait dumps list` / `ait dumps fetch` for next-day review.

## Why this is Phase 10

Phase 9 captures dumps on the pod. Without S3 upload, those dumps die with the pod — the whole point is that **the dev sees them the next morning**, after the pod has been restarted or rolled. Phase 10 makes that work.

## Design

### S3 layout

Dedicated bucket: **`actuate-crash-dumps`** (NOT `actuate-settings` — different RBAC, different lifecycle).

```
s3://actuate-crash-dumps/
├── raw/
│   └── <deployment_id>/
│       └── <run_id>/
│           └── <timestamp>-<reason>.zip       # uploaded by background uploader
└── summaries/
    └── <deployment_id>/
        └── <timestamp>-<reason>.json          # written by compaction Lambda
```

`raw/` has a 3-day TTL lifecycle policy (per the spec's "weekend-survival" rule). `summaries/` keeps 90 days for trend analysis.

### Background uploader

A worker thread in the connector that pulls from a queue of "dump zips ready to upload" and pushes to S3:

```python
class DumpUploader:
    def __init__(self, bucket: str, queue: queue.Queue): ...
    def run(self): ...
        # blocking get from queue
        # multipart upload to s3 with server-side encryption
        # on success, remove local zip
        # on failure, requeue with backoff (max 3 retries)
```

Wired into `AnalyticsSiteManager.__init__` post-fork. Dumps written by `dump_state()` are enqueued via `recovery_sweep` (Phase 9) and the watcher thread.

The uploader is **separate from the main pipeline thread** — pipeline performance is unaffected by S3 latency. On pod shutdown (SIGTERM), the uploader drains within a grace period (configurable, default 30s), then aborts whatever's in flight.

### Per-deployment rate limit

A flapping pod that crash-loops 10x per minute should not flood the bucket. The uploader has a per-deployment rate limit:

- **Max 6 uploads per deployment per hour**, sliding window.
- Excess uploads are dropped *locally* (with a log line + a metric).
- Per-pod dump cap (Phase 9) still keeps the 3 most-recent locally, so a recovering pod can drain whatever queued up.

The rate limit is the bucket-protection layer; the per-pod dump cap is the disk-protection layer.

### Compaction Lambda

Triggered by S3 PUT on `raw/`. Reads the dump zip, extracts:

- The manifest (deployment_id, run_id, reason, timestamp, library versions).
- The last 50 log lines from the dump.
- Every captured alert payload (no frames).
- Per-camera summary (camera_name, last detection, last frame timestamp, ignore-zone count).
- Site-level metrics summary (thread counts, queue depths, memory at dump time).

Writes the summary as JSON to `summaries/<deployment_id>/<timestamp>.json`. Original raw dump expires via lifecycle after 3 days; the summary lives 90 days.

Summary size budget: **<200 KB per dump**. 90 days of summaries for a 100-deployment fleet at one crash-per-deployment-per-day is ~1.7 GB — trivial storage cost.

Lambda lives in `ds-terraform-eks-v2` next to other operational Lambdas (e.g. the AutoPatrol stale-schedule cleanup Lambda).

### AIT review UX

```bash
# List recent dumps for a deployment
ait dumps list connector-35831-autopatrol-259

# List dumps fleet-wide for a given day
ait dumps list --since 2026-05-19

# Fetch a specific dump locally
ait dumps fetch connector-35831-autopatrol-259 2026-05-19T14:23:45-exception-RuntimeError

# Show a dump's summary (reads from summaries/, fast)
ait dumps summary connector-35831-autopatrol-259 2026-05-19T14:23:45

# Top-level "what crashed overnight?" view
ait dumps overnight    # lists all summaries since 18:00 yesterday
```

`fetch` downloads the raw zip; `summary` reads the Lambda-produced JSON (much smaller, faster).

After fetch, the dev's next move is:

```bash
ait replay <fetched-dump.zip> --step pre_inference --idp 0 --diff
ait replay-alert <fetched-dump.zip> --all
```

These come from Phases 6 + 7.

### Privacy / RBAC

- Bucket policy: read scoped to the engineering IAM role only. No customer access, no per-site federation.
- Server-side encryption at rest (KMS, AWS-managed key).
- Bucket logging enabled to the audit-log bucket. Every fetch is tracked.
- Lambda strips frames before writing the summary — so the 90-day artifact has no PII.
- Raw dumps with frames TTL out at 3 days; that's the PII exposure window.

Per the spec's PII section, the dump bucket reuses the existing PII exposure class (frames already in S3 elsewhere) — not introducing a new class.

## TODOs (Phase 10)

### 10A — S3 bucket creation (Terraform)

- [ ] Create `actuate-crash-dumps` bucket in `ds-terraform-eks-v2`.
- [ ] Lifecycle policies: `raw/` 3-day TTL, `summaries/` 90-day TTL.
- [ ] Server-side encryption + bucket logging.
- [ ] Bucket policy: engineering IAM role read-only on `summaries/`; full access on `raw/` only for the connector's pod IAM role (write) + engineering (read).
- [ ] Document the bucket in `docs/ECOSYSTEM.md`.

### 10B — `DumpUploader` worker thread

- [ ] Create `actuate_integration_tools.dump_uploader` or place in `actuate-instrumentation` (decide based on whether this is brain-in-jar-specific or general).
- [ ] Implement queue-driven upload with multipart, retries, SSE-KMS.
- [ ] Per-deployment rate limit via in-memory sliding window.
- [ ] Drain on SIGTERM within configurable grace period.
- [ ] Unit tests: mock S3 client; assert multipart, retry, rate limit.

### 10C — Wire uploader into `AnalyticsSiteManager`

- [ ] Construct in `__init__` post-fork.
- [ ] Connect to Phase 9's recovery sweep + watcher.
- [ ] Integration test: capture-then-upload round-trip on a local connector against a mock S3.

### 10D — Compaction Lambda

- [ ] Create `compact-crash-dumps` Lambda in `ds-terraform-eks-v2`.
- [ ] S3-PUT trigger on `raw/*`.
- [ ] Extract summary fields per the design above.
- [ ] Write to `summaries/<deployment_id>/<timestamp>.json`.
- [ ] CloudWatch logging on success/failure.
- [ ] Unit tests for the extraction logic (independent of S3).

### 10E — `ait dumps` subcommand family

- [ ] `ait dumps list <deployment_id>` — paginated, sorted by timestamp.
- [ ] `ait dumps list --since <date>` — fleet-wide.
- [ ] `ait dumps fetch <deployment_id> <timestamp>` — downloads raw zip.
- [ ] `ait dumps summary <deployment_id> <timestamp>` — reads summary JSON.
- [ ] `ait dumps overnight` — convenience: yesterday-18:00 → now.
- [ ] CLI tests with mocked S3.

### 10F — `/dashboard-check` integration

- [ ] Add a `dumps_24h` panel showing crash dump count by deployment.
- [ ] Alert (yellow) if a deployment has >3 dumps in 24h.
- [ ] Alert (red) if a deployment has >10 dumps in 24h (likely a crash loop).
- [ ] Cross-link to [[2026-04-30_three-tier-routine-check-pattern]].

### 10G — Documentation

- [ ] Add a "Brain-in-jar review" section to `actuate-integration-tools/README.md`.
- [ ] Update [[actuate-integration-tools]] entity note with the `ait dumps` family.
- [ ] Add an "Investigating a crash" cookbook page: `/dashboard-check` red → `ait dumps summary` → `ait dumps fetch` → `ait replay`.
- [ ] Add `actuate-crash-dumps` bucket to the data-flow diagram in `docs/ECOSYSTEM.md`.

## Estimate

~3–5h. Terraform changes are ~1h; uploader thread + tests ~1.5h; Lambda + tests ~1h; CLI family ~1h; dashboard panel ~30min.

## Risk

The biggest unknown is **cost ceiling**. If crash rates are higher than expected, raw dump storage could grow faster than the 3-day TTL clears it. Mitigation: monitor bucket size via Cloudwatch for the first month; tune TTL down if necessary.

A secondary risk: **the Lambda fails and we lose summaries silently**. Mitigation: DLQ on the Lambda + alerting on DLQ depth (mirror the AutoPatrol stale-schedule cleanup pattern from [[autopatrol-cleanup-lambda-check]]).

## Cross-references

- [[2026-05-20_ait-brain-in-jar-spec]] — parent
- [[2026-05-20_ait-phase-9-site-dump-crash-hook]] — Phase 9 (writes the dumps we upload)
- [[2026-05-20_ait-phase-6-pipeline-replay]] — Phase 6 (review UX after `ait dumps fetch`)
- [[2026-05-20_ait-phase-7-alert-capture-replay]] — Phase 7 (also reviewable after fetch)
- [[autopatrol-cleanup-lambda-check]] — Lambda + DLQ pattern to mirror
- [[2026-04-30_three-tier-routine-check-pattern]] — dashboard signal pattern
