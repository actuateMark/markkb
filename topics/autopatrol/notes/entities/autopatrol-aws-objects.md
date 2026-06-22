---
title: "AutoPatrol AWS Object Set"
type: entity
topic: autopatrol
tags: [autopatrol, aws, s3, dynamodb, billing, chm]
status: live
created: 2026-05-21
updated: 2026-05-21
author: kb-bot
outgoing:
  - topics/autopatrol/notes/entities/autopatrol-server.md
  - topics/autopatrol/notes/entities/autopatrol-cleanup-lambda.md
  - topics/vms-connector/_summary.md
[]
incoming:
  - No backlinks found.
incoming_updated: 2026-05-27
---

# AutoPatrol AWS Object Set

The durable storage for AutoPatrol-related artifacts is **2 S3 buckets + 3 DynamoDB tables**, all in `us-west-2`. The "core" AP object set is the 2 buckets + the `autopatrol_results` index table; the other two DDB tables (`autopatrol_alerts`, `autopatrol_chm_issues`) are sibling event tables written from the same AP runs but consumed independently.

Naming convention is `autopatrol-*` (S3, kebab) and `autopatrol_*` (DDB, snake). [[watch-entity|Watch]] out for the kebab/snake split — easy to typo when copy-pasting between AWS consoles.

## Core 3 — patrol object set

| Resource | Type | Region | Purpose | Key shape | Writer | Reader |
|---|---|---|---|---|---|---|
| `autopatrol-patrols` | S3 | us-west-2 | Final patrol payload — the outbound `task results` JSON (cameras, clips, window_ids, motion frames). One object per patrol run. | `<patrol_uuid>.json` | `autopatrol-server/utils/aws_calls.py:186` `save_patrol_to_s3()` | admin (`autopatrol_results_view.py:36`, `autopatrol_report_view.py:53`) reads it for the patrol summary UI |
| `autopatrol-queue-archive` | S3 | us-west-2 | Inbound queue-message archive — the SQS message body that triggered the patrol. Useful for replay / forensic. | `<patrol_uuid>_message.json` | `autopatrol-server/utils/aws_calls.py:202` `save_message_to_s3()` | not regularly consumed; on-demand for debugging |
| `autopatrol_results` | DDB | us-west-2 | Index/query surface. One row per patrol with `patrol_id`, `site_id`, `schedule_id`, `timestamp` (run_timestamp), `alert_window_ids`, `group_id`, `tenant_id`, `integration_type`, `ttl` (30 days). The DDB row is what consumers query against; the matching S3 object holds the full payload. | partition key `patrol_id` (composite with `timestamp` sort key, typical DDB pattern) | **vms-connector** via `AutoPatrolDAO.save_patrol_result()` at `actuate-libraries/actuate-daos/src/actuate_daos/autopatrol_dao.py:25` — called from `vms-connector/site_manager/connector/integrations/autopatrol_site_manager.py:187` (AP) and `patrol_site_manager.py:175` (CHM-bound patrol) | admin Django views, [[autopatrol-server]] post-processing, [[autopatrol-cleanup-lambda]] stale-schedule scans (`autopatrol_onboarder/scripts/ops/stale_schedule_scan.py:158`) |

Important: **the connector writes the DDB row; the AP server writes the S3 objects.** Different services own different halves of the same patrol's footprint. A patrol that exits before the connector hands off (early-exit / SIGTERM) writes only the DDB row; one that exits after handoff but before the AP server processes writes only the DDB row + queue-archive S3. Both halves should be present for a "complete" patrol.

## Sibling event tables (also `autopatrol_*`, written from AP/CHM runs)

These exist alongside `autopatrol_results` in the same DAO (`AutoPatrolDAO` at `actuate-daos/src/actuate_daos/autopatrol_dao.py`) but represent different per-run event classes. Each row is one event, not one patrol — so a single patrol run can write zero-to-many rows here.

| Table | Purpose | Writer | Row per |
|---|---|---|---|
| `autopatrol_alerts` | Real AP threat/intrusion alerts that fire to Immix (or whatever downstream). | `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/immix/autopatrol_sender.py:156` `save_autopatrol_alert()`. Fires inside the connector when an AP run produces a tier-2/3 detection. | one alert (patrol_id × window_id) |
| `autopatrol_chm_issues` | Visual-confirmation healthcheck issues — blurred view, no signal, dark frame, etc. | `vms-connector/healthcheck/alerts/senders/vch_alert_sender.py:156` `save_chm_issue()`. Fires from **any** VCH/CHM run, whether standalone `*-vch-cronjob` or the CHM portion of an AP cronjob. | one CHM issue (patrol_id × detection_code × stream) |

So: **the connector writes all three DDB tables.** The `autopatrol_*` prefix on `autopatrol_chm_issues` is historical naming — the actual writer is the VCH alert sender, and standalone VCH cronjobs also populate it. Don't read the prefix as "AP-only."

## IAM / Terraform anchors

`ds-terraform-eks-v2/modules/eks-irsa/`:

- `connector.tf:96-101` — vms-connector role gets read+write on all 3 DDB tables (+ their GSIs).
- `camera-admin.tf:102-103, 248-253` — camera-admin role gets `autopatrol-patrols` (S3) + all 3 DDB tables (read-mostly for the admin UI views).
- `autopatrol-microservice.tf:137-144` — autopatrol-server role gets both S3 buckets (R/W). Worth noting: the Terraform-managed names use a `${var.project_name}-autopatrol-patrols-${var.stage}-${var.region}` template, but production today uses the bare names `autopatrol-patrols` and `autopatrol-queue-archive` (camera-admin.tf is the source of truth for the prod ARNs; autopatrol-microservice.tf appears to be a parallel/future pattern). Confirm before touching IAM on either side.

## Operations notes

- **TTL on all DDB tables:** 30 days (`timedelta(days=30)` in every save method). Anything older than that is gone from DDB; the S3 objects persist independently (no bucket lifecycle policy enforcing parallel expiry as of 2026-05-21 — worth auditing if storage cost becomes a question).
- **No bucket versioning** on `autopatrol-patrols` / `autopatrol-queue-archive` AFAICT — unlike `actuate-settings` which has versioning enabled (confirmed 2026-05-19). Consequence: an accidental overwrite of `<patrol_uuid>.json` is irrecoverable.
- **Cross-service split:** connector writes DDB, AP server writes S3. If you're debugging "missing patrol data" symptoms, check which half is missing before assuming a single root cause.
- **localstack support:** `vms-connector/.claude/settings.local.json:288-289` whitelists `aws --endpoint-url=http://localhost:4566 s3 ls s3://autopatrol-patrols/` for local-test-stack work — both bucket names exist in the localstack profile, queue-archive included.

## Related

- [[autopatrol-server]] — service that consumes the connector's SQS handoff and writes the two S3 buckets
- [[autopatrol-cleanup-lambda]] — uses `autopatrol_results` (read) for the stale-schedule scan
- [[autopatrol-onboarder]] — schedule lifecycle that ultimately produces the patrol_ids that key these objects
- vms-connector `AutoPatrolSiteManager` / `PatrolSiteManager` — call sites for the DDB writes
