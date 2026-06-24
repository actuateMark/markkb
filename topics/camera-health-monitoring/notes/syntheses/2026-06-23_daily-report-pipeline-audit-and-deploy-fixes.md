---
title: "Daily CHM Report Pipeline: Architecture Audit & Deploy Bug Fixes"
type: synthesis
topic: camera-health-monitoring
tags: [chm, health-report, lambda, eventbridge, deployment, architecture]
jira: "CS3"
created: 2026-06-23
updated: 2026-06-23
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-06-24
---

# Daily CHM Report Pipeline: Architecture Audit & Deploy Bug Fixes

Comprehensive audit of the [[health-report]] email pipeline (repo: `aegissystems/health_report`) conducted 2026-06-23. Verified live production state in us-west-2 (account 388576304176), discovered and fixed critical deploy bug, and identified orphaned EventBridge resources.

## Pipeline Architecture (Verified Live)

The daily CHM report email is a **two-lambda fan-out**:

**Stage 1: Generator** — `healthcheck_report_job_generator` (src/report_email_job_generator/)
- Triggered by EventBridge RULE `daily-chm-report-send` (rate(1 day), ENABLED)
- Pages Admin API `GET /healthcheck/?deployment=3` for all sites
- Groups sites by customer `report_emails` field
- Always adds two internal all-fleet debug recipients: `mark+allreports@actuate.ai`, `laura+allreports@actuate.ai`
- Async invokes worker lambda once per recipient with payload: `{"email": ..., "site_ids": [...]}`

**Stage 2: Worker** — `healthcheck_report_email` (src/report_email/) with files lambda_function.py, email_data.py, email_template.py
- Per-recipient invocation receives email + site list
- Fetches per-customer config and today's + yesterday's healthcheck rollups from Admin API (`/healthcheck_result/rollup`)
- Maps non-healthy results to typed packets (ConnectivityPacket, ImageQualityPacket, StreamQualityPacket, RecordingPacket, SceneChangePacket, ServerStatusPacket, MotionStatusPacket)
- Renders HTML and sends via SES (LightSesAlertSender / ChmAlertData) from `healthmonitoring@actuate.ai`

**Key Detail:** The `site_ids` payload key actually holds CUSTOMER ids (worker uses them as `customer_id`). True per-camera site_id/camera_id come from the rollup response.

## Production Verification

- **master branch is live production code** — byte-for-byte identical to deployed AWS lambda zips (all 4 source files verified by download + diff). No unmerged live code.
- **Feature branch `report_email_revamp` is gone** — fully merged via PR #1 (commit 46e22f7) and deleted locally + remotely. It was merge history, not stranded WIP.
- **Generator runs daily** — CloudWatch confirms executions through 2026-06-22; worker fans out correctly.

## Critical Deploy Bug (FIXED)

Both `src/report_email/deploy_prod.sh` and `src/report_email_job_generator/deploy_prod.sh` started with:
```bash
rm -rf /job_lambda_package
rm -rf /email_lambda_package
```

**Issue:** Leading slash `/` targets filesystem root, never cleaned the cwd package directory between deploys. Stale dependency versions accumulated in shipped zips:
- email lambda bundled 7 stale `actuate_alarm_senders` versions
- email lambda bundled ~12 stale `actuate_healthcheck_objects` versions

**Fix:** Dropped leading slash. Now correctly cleans package dirs before rebuild. Committed and pushed to master.

## EventBridge Scheduler Housekeeping

Discovered **orphaned EventBridge SCHEDULER** `healthcheck-report-gen` (rate(1 days), America/New_York):
- Targeted deleted `healthcheck_report` lambda from legacy single-lambda design (code in `report_old/`)
- Was firing into void since 2026-11-12
- Live pipeline unaffected (uses separate EventBridge RULE `daily-chm-report-send`)

**Action:** DISABLED the scheduler. Opened GitHub issue aegissystems/health_report#3 to delete it entirely.

## Documentation & Configuration

Updated README.md (was stale, pointed at deleted lambda), added:
- **docs/ARCHITECTURE.md** — two-lambda fan-out design with payload flow
- **CLAUDE.md** — session conventions for this project (deployment process, deployment bugs, Admin API contract details)

All changes committed to master.

## Open Issues & Next Steps

| Issue | Scope | Notes |
|-------|-------|-------|
| aegissystems/health_report#2 | Feature: weekly report cadence | Requires admin field (daily/weekly), per-site setting, two EventBridge rules each passing `{"cadence":...}`, generator to read event arg, worker rollup window threaded through payload. Currently hardcodes 1-day window. |
| aegissystems/health_report#3 | Delete orphaned EventBridge Scheduler | Disabled; needs formal cleanup. |

## Design Gotchas

1. **Generator ignores its event arg** — currently unused. Needed to thread cadence or other metadata through for future features.
2. **Hardcoded 1-day rollup window** — email lambda uses `timedelta(days=1)` / days-2..1 comparison. Any non-daily cadence needs window parameter in payload.
3. **Payload key naming confusion** — `site_ids` actually holds customer ids. True per-camera identifiers come from rollup response.

## Related

- [[health-report]] — entity summary (outdated; update recommended)
- [[actuate-admin-api]] — backend API contract
- [[actuate-libraries]] — healthcheck objects + alarm senders
