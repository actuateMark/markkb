---
title: "vms-connector PR #1654 — stage → rearchitecture"
type: entity
topic: releases
tags: [vms-connector, release, rearchitecture, autopatrol, patrol-mode, s3-fallback, executor-drain]
pr: "https://github.com/aegissystems/vms-connector/pull/1654"
merge_commit: "eeab2b43"
merged_at: "2026-04-20T14:53:49Z"
status: deployed-monitoring
created: 2026-04-20
updated: 2026-04-20
author: kb-bot
---

# vms-connector PR #1654: stage → rearchitecture

37-commit squash merge to production on 2026-04-20T14:53:49Z. Core themes: **[[generic-patrol-mode|generic patrol mode]]** (PatrolCamera / PatrolFactory / PatrolSiteManager), **[[s3-frame-fallback|S3 frame fallback]] for deferred alerts**, **executor-drain fix** to prevent silent alert loss, **shared-observer-pool revert** (restore per-camera FIFO serialization), DW alarm OAuth2 + 307 redirect fix, SMTP degenerate frame guard.

## Library Bumps

| Library | Before | After | What It Brought |
|---------|--------|-------|-----------------|
| [[actuate-alarm-senders]] | 1.9.14 | 1.9.17 | Executor drain + DW OAuth2 + 307 redirect |
| [[actuate-config]] | 1.9.10 | 1.9.12 | AutoPatrol prod defaults, PatrolConfig, S3 alerts, staging API |
| [[actuate-daos]] | 3.2.12 | 3.2.13 | AP release support |
| [[actuate-integration-calls]] | 1.11.5 | 1.11.7 | Executor drain |
| [[actuate-pullers]] | 1.17.10 | 1.17.11 | SMTP image clips counter + degenerate frame guard |
| actuate-threadpool | 1.2.0 | 1.3.0 | Executor drain at run exit (feature; minor bump) |

## Pre-Merge Testing

**Stage regression check** (Fri 2026-04-17 16:00Z → Mon 2026-04-20 ~14:30Z, 72h):
- LOW risk, no new error patterns vs prod baseline
- Zero OOMKills; per-integration memory ≤ 1-week baseline across all 13 integration types
- "puller not initialized" rate proportionally lower than prod (no FIFO backpressure signature)

**Functional validation on `:stage` image:**
- **AutoPatrol:** 282 starts / 210+ Finished / 759 dispatches at HTTP 200; 12,674 executor drains with 0 silent drops
- **VCH:** 224 starts / 210 Finished / 94% completion
- **CHM cronjobs:** healthy across 16+ CHM jobs on `:stage` image; 0 AttributeError / NameError / Traceback

**Stale branch note:** Subagent flagged `KeyError: 'monitoring'` on `:rearch-dev` VCH CHM cronjobs (branch last updated 2025-12-10, pins `actuate-config==1.4.4.dev6+ed.1` predating Jan 2 2026 guard). **PR #1654 itself is clean** — `:stage` image pins [[actuate-config]] 1.9.12 with the guard. Remediation: 14 staging VCH CHM cronjobs retargeted from `:rearch-dev` to `:stage` via kubectl; 11 customer deployment_phase entries updated to `STAGE` in admin (IDs: 35271, 35276, 35279, 35280, 35282, 35283, 35288, 35289, 35290, 35291, 35292).

## Post-Deploy Patterns to Watch

### Feature Canaries (PR-specific)

| Area | Canary Query | Baseline / Clean Signal |
|------|--------------|------------------------|
| Executor drain | `%silent drop%` / `%executor shutdown%drop%` | 0 hits; flush_deferred_alerts INFO logs only |
| Patrol mode | `%Patrol%` + ERROR/Traceback | 0 errors; heartbeats + init logs present |
| [[s3-frame-fallback|S3 frame fallback]] | `%S3%frame%fallback%` / `%flush_deferred_alerts%attempting S3%` | INFO-level; >0 hits = feature in use |
| Observer pool revert | `%puller not initialized%` rate | flat or ↓ (per-camera FIFO restored) |
| DW OAuth2 + 307 | `%DW%auth%` / `%307%` / `%Bearer%` errors | transient burst on rolling OK; steady 0 new |
| SMTP degenerate frame | `%degenerate frame%` errors | 0 errors; INFO acceptable |
| Fork safety | `restartCount > 3` pod FACET | no new entrants (pre-existing chronic-OOM only) |
| Memory | `avg(memoryWorkingSetBytes)/1e9` timeseries | flat ±5% of pre-deploy baseline |

### Runner Alert Flow (standard for every release)

Alert flow must be verified for each core runner type. Missing alert volume post-deploy is a silent failure mode that error rate alone won't catch.

| Runner | Pod pattern | Alert flow signal | Clean canary |
|--------|-------------|-------------------|--------------|
| **Analytics** (always-on detection) | `connector-*` (no `-chm`/`-vch`/`-autopatrol`) | SQS send to `event_queue_analytics.fifo` / `event_queue_immix_alarm.fifo`; `Sending event_info` + `site_product_ended` with `act_a` ∈ {Intruder, Loitering, Crowd, vehicle, gun, ...} | > 0 sends/min fleet-wide with multiple `act_a` types represented |
| **AutoPatrol** (AP) | `connector-*-autopatrol-*-chm-cronjob` | `patrolStatus: Started` → `All camera threads have ended, exiting site manager` → `raise_patrol_alert succeeded` (HTTP 200) | Started-to-finish parity; successful dispatches or legitimate no-alert runs |
| **VCH** (Virtual Camera Health) | `connector-*-vch-*-chm-cronjob` | `patrolType=VisualCameraHealth` Started/Finished; `send_healthcheck_alert` thread; `successfully updated hc` | Started/Finished parity ≥90%; healthcheck API posts confirmed |
| **CHM** (Continuous Health Monitor) | `hc_*` threads inside analytics + cronjob pods | `hc_*_run: {"run_timestamp"%"` heartbeats; `site_product_ended` with `'act_a': 'healthcheck'` | Heartbeats flowing continuously; `site_product_ended` healthcheck count > 0 |

### Runner Alert Flow — Observed (PR #1654, T+180min)

| Runner | Pods | Runs / cycles | Alerts dispatched | Failures | Status |
|--------|------|---------------|-------------------|----------|--------|
| Analytics | ~5,452 active containers | continuous | 220,691 SQS sends; multiple detection types confirmed | ~1,000 pre-existing `dw_url_up` (not PR) | 🟢 |
| AutoPatrol | 4 pods, site 35831 | 14 Started events; 14 `All camera threads have ended` (clean exits) | 1 attempted (failed on [[2026-04-20_streamid-null-patrol-alert-bug|pre-existing streamId-null architectural bug]] — filed as GH#1656 with full API/failure-mode evidence, awaiting Immix response) — test schedules, no real alerts expected | 1 pre-existing | 🟢* |
| VCH | 3 prod pods (sites 44879, 45107, 44781) | starts=3, finished=3 | `successfully updated hc` confirmed for connectivity + stream_quality | 0 | 🟢 |
| CHM | VCH + AP pods | 39+ heartbeats | 6,781 `site_product_ended healthcheck` | 0 | 🟢 |

\* AP status: the only `:latest` AP site runs 4 test-schedule patrols (`AP 12-9`, `AP 1-7`, `4th autopatrol test`, `AP test TEST2 01-08`) that don't generate real customer alerts. `All camera threads have ended` confirms clean runs. The single `raise_patrol_alert failed` is a [[2026-04-20_streamid-null-patrol-alert-bug|pre-existing architectural bug]] where Immix rejects connectivity-failure alerts when streamId is not yet known (stream init has not succeeded). Not a PR #1654 regression; exposed by promoting AP from `:stage`-only to full `:latest` deployment. Issue filed as GH#1656 with full API call patterns, failure-mode taxonomy, and Immix coordination requests documented in the bug note. Connector-side cleanup (removing UUID fabrication, empty-string fallbacks) is unconditional; Immix response on optional streamId or lookup endpoint will unblock first-ever connection failures.

### Per-release Canary Results (PR #1654)

- **Executor drain:** 94 `flush_deferred_alerts` INFO hits (S3 fallback path exercised) | 0 silent-drop / executor-shutdown-drop (CLEAN)
- **[[s3-frame-fallback|S3 frame fallback]]:** 94 invocations, 0 errors
- **Observer pool / FIFO:** `puller not initialized` rate 61.4/min vs 2h prior 136.1/min (**−55%** — per-camera FIFO restoration working)

## Deployment Timeline

- **T+0 (14:53:49Z)** — PR #1654 merged as `eeab2b43` on rearchitecture.
- **T+3min** — CI run 24673433994 kicked off (ARM64 + x86).
- **T+5min** — Rolling deploy; pending-pod peak 176, wound down over ~45 min.
- **T+120min (~17:00Z)** — release-chain-watcher: **GREEN**. Memory 0.376–0.380 GB flat. Errors ~65/min (within 44–87/min pre-deploy band). 0 silent drops, 0 patrol errors, 0 new fingerprints. "puller not initialized" −67% vs 2h baseline. 5 OOMKilled pods (all pre-existing chronic cohort).
- **T+150min (~17:30Z)** — **YELLOW**. Error rate 84.7/min (within band). 3 new OOMKills on 42477/32312/42481 (same chronic cohort). Memory flat. Canaries clean.
- **T+210min** — scheduled final check.

## Error Attribution — Post-Deploy

**No errors attributable to PR #1654.** Deep check evidence:

- **DW `dw_url_up` JSON parse** (~1800 hits, 2.5h) — `Expecting value: line 1 column 1` in DW auth polling thread. DW endpoint returning HTTP 200 + empty body. Pre-merge rate: 860–3000/24h (equivalent). **Fires in dw_url_up polling thread, NOT in OAuth2/307 code path.** Site-side / DW server issue.
- **Milestone `HTTPSConnectionPool` refused** — host `2211vistapkwy.dyndns.org:443` unreachable. 3,701 pre-merge vs 66 post-merge; rate proportional (lower absolute = less elapsed time). VMS network unreachable.
- **OOMKill cohort (42477, 32312, 42481)** — pre-existing VPA misconfig. connector-32312 limit 0.43 GB (budget ~270 MB/camera; extremely tight). 32312 climb started 2h BEFORE merge. 42477 @ 6.44 GB limit, well within budget. Not PR-related.
- **`Trailer SCT 2562` stream-lost** (273 hits, 4 cameras) — only new fingerprint, but class ([[rtsp-deep-dive|RTSP]] reconnect) is standard stream behavior, not PR code path.

## Follow-up

- Monitor stale branch `rearch-dev` (vms-connector) — last commit 2025-12-10. Recommend retirement evaluation once ED-1 ([[evalink-components|Evalink]]) work reconciles to mainline.
- If OOMKill rate continues on chronic cohort at T+210min, open separate VPA-sizing ticket (not PR #1654 issue).

## Cross-references

- Skill chain: [[stage-regression-check]] → merge → release-chain-watcher agent → ScheduleWakeup check-ins
- [[connector-library-deployment-lifecycle]] in [[engineering-process/_summary|Engineering Process]]
- [[agents-catalog]] — release-chain-watcher, nrql-investigator used
