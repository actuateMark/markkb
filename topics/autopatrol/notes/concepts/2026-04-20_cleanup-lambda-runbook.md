---
title: "AutoPatrol Stale-Schedule Cleanup Lambda — Operations Runbook"
type: concept
topic: autopatrol
tags: [runbook, ops, lambda, sqs, dynamodb, autopatrol, cleanup, immix, immix, immix, immix, immix]
created: 2026-04-20
updated: 2026-04-20
author: kb-bot
outgoing:
  - topics/autopatrol/notes/concepts/2026-04-21_cleanup-lambda-stage-verify.md
  - topics/autopatrol/notes/entities/autopatrol-cleanup-lambda.md
  - topics/autopatrol/notes/syntheses/2026-04-23_alarm-dashboard-sketch.md
  - topics/engineering-process/notes/concepts/2026-04-20_overnight-check-skill-pattern.md
  - topics/personal-laptop/notes/concepts/2026-04-30_morning-prep-scripts-runbook.md
  - topics/personal-notes/notes/concepts/2026-04-29_cleanup-handoff.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/runbooks/_backlog.md
  - topics/runbooks/_summary.md
incoming:
  - topics/autopatrol/notes/concepts/2026-04-21_cleanup-lambda-stage-verify.md
  - topics/autopatrol/notes/concepts/2026-04-28_tenant-status-sync-gap.md
  - topics/autopatrol/notes/concepts/2026-05-07_handoff-cleanup-lambda-interpretive-checks.md
  - topics/autopatrol/notes/entities/autopatrol-cleanup-lambda.md
  - topics/autopatrol/notes/syntheses/2026-04-23_alarm-dashboard-sketch.md
  - topics/engineering-process/notes/concepts/2026-04-20_overnight-check-skill-pattern.md
  - topics/personal-laptop/notes/concepts/2026-04-30_morning-prep-scripts-runbook.md
  - topics/personal-notes/notes/concepts/2026-04-29_cleanup-handoff.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-05-08
---

# AutoPatrol Stale-Schedule Cleanup Lambda — Operations Runbook

Operational commands for the `immix-autopatrol-schedule-cleanup` + `immix-autopatrol-schedule-reenable` Lambdas. Assumes `AWS_PROFILE=prod` (account `388576304176`) and `us-west-2` unless otherwise noted.

Design + architecture: [[2026-04-17_stale-schedule-cleanup-design]]. Entity: [[autopatrol-cleanup-lambda]]. Playbook this was distilled from: [[2026-04-20_lambda-creation-and-tuning-playbook]].

## Admin API dependencies

The cleanup Lambda calls admin via `GET /api/auto_patrol_schedule/?customer=<actuate_customer_id>&scheduleId=<uuid>` on first sighting of each schedule_id. Two things that must be live for this to work:

- **`scheduleId` filter** (added in `actuate_admin#2361`, merged to develop 2026-04-20) — server-side filter narrows the response to the one matching schedule. **Verified live on develop (stage) 2026-04-21**.
- **Provenance fields** (`disabled_by`, `disabled_at`, `reenabled_by`, `reenabled_at` on `AutoPatrolSchedule`) — nullable, no backfill, exposed by serializer. **Verified live on develop 2026-04-21** (returned as null for non-disabled schedules).

The Lambda's `admin_api_handler.py` also has a **client-side `scheduleId` match** as a safety net — harmless if the server-side filter works; load-bearing if an older admin build is running. Both paths return the same result in steady state.

Quick verification:
```bash
ADMIN_TOKEN=$(AWS_PROFILE=prod aws secretsmanager get-secret-value \
  --secret-id prod/actuate/postgres --query SecretString --output text | \
  python3 -c "import json,sys; print(json.load(sys.stdin).get('api-token-develop',''))")

curl -s -H "Authorization: Token $ADMIN_TOKEN" \
  "https://dev.actuateui.net/api/auto_patrol_schedule/?scheduleId=<uuid>" | \
  python3 -m json.tool | head -30
```

Expected: exactly 1 result, schedule record with `scheduleId`, `disabled_by` (null), etc.

## Resource inventory (prod acct / us-west-2)

All provisioned by CLI (2026-04-20 stage tier, 2026-04-21 prod tier) pending terraform resolution.

| Resource | Identifier |
|---|---|
| **Stage queue** | `arn:aws:sqs:us-west-2:388576304176:autopatrol_stale_schedule_cleanup_dev.fifo` |
| **Stage DLQ** | `arn:aws:sqs:us-west-2:388576304176:autopatrol_stale_schedule_cleanup_dlq_dev.fifo` (maxReceiveCount=3) |
| **Prod queue** | `arn:aws:sqs:us-west-2:388576304176:autopatrol_stale_schedule_cleanup.fifo` |
| **Prod DLQ** | `arn:aws:sqs:us-west-2:388576304176:autopatrol_stale_schedule_cleanup_dlq.fifo` (maxReceiveCount=3) |
| Counter table | `autopatrol_cleanup_counters-dev` (PK=`schedule_id` S, PAY_PER_REQUEST, TTL on `ttl`) — **shared by stage and prod; UUID keys prevent collision** |
| Cleanup Lambda | `immix-autopatrol-schedule-cleanup` (py3.13 x86_64, 512MB / 60s, reserved concurrency=2). **Two event source mappings** — consumes from both stage and prod queues. |
| Reenable Lambda | `immix-autopatrol-schedule-reenable` (py3.13 x86_64, 256MB / 30s) |
| Reenable Function URL | `https://p4e6ns5yndxxgicmhr2bycjdia0bastt.lambda-url.us-west-2.on.aws/` (AWS_IAM auth) |
| Cleanup IAM role | `immix-autopatrol-schedule-cleanup-role` (basic-exec + SecretsManagerRW + SQS full + DDB full — broad; tighten post-ship) |
| Reenable IAM role | `immix-autopatrol-schedule-reenable-role` (basic-exec + SecretsManagerRW) |
| Stage DLQ alarm | `autopatrol-cleanup-dlq-has-messages-dev` — ≥1 message, 5min period |
| Prod DLQ alarm | `autopatrol-cleanup-dlq-has-messages-prod` — ≥1 message, 5min period |

**Prod queue is empty and will stay empty** until prod pods are explicitly opted in via `AUTOPATROL_EMIT_CLEANUP_SIGNALS=true` env var on the pod spec. Prod pods' default gating (non-dev-queue) keeps them silent.

EU-west-1 infrastructure NOT yet provisioned — Step G of rollout.

## Watching the pipeline

### Queue depth

```bash
# Main queue
AWS_PROFILE=prod aws sqs get-queue-attributes \
  --queue-url https://sqs.us-west-2.amazonaws.com/388576304176/autopatrol_stale_schedule_cleanup_dev.fifo \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --region us-west-2

# DLQ
AWS_PROFILE=prod aws sqs get-queue-attributes \
  --queue-url https://sqs.us-west-2.amazonaws.com/388576304176/autopatrol_stale_schedule_cleanup_dlq_dev.fifo \
  --attribute-names ApproximateNumberOfMessages --region us-west-2
```

Healthy state = main ~0 (Lambda drains fast), DLQ ALWAYS 0. Any DLQ message → alarm fires.

### Peek at messages (without consuming)

Good for debugging payload shape.

```bash
AWS_PROFILE=prod aws sqs receive-message \
  --queue-url https://sqs.us-west-2.amazonaws.com/388576304176/autopatrol_stale_schedule_cleanup_dev.fifo \
  --visibility-timeout 0 --max-number-of-messages 5 --region us-west-2 \
  --attribute-names All --message-attribute-names All
```

`--visibility-timeout 0` means messages stay visible to other consumers (i.e. the Lambda). Don't accidentally delete-message or you bypass the pipeline.

### Tail Lambda logs

```bash
AWS_PROFILE=prod aws logs tail /aws/lambda/immix-autopatrol-schedule-cleanup \
  --region us-west-2 --follow --format short
```

Key log lines to watch for:
- `cleanup_lambda invoked: enabled=<bool> dry_run=<bool> records=<n>` — every invocation
- `processing schedule_id=... reason=<r> bucket=<patrol_exit|site_disabled> target_hours=<N>` — per-message
- `counter schedule_id=... bucket=<b> count=<c>/<threshold>` — counter state after increment
- `Immix reports schedule ... status=<s> — treating as gone|active` — Immix verdict when threshold hits
- `[DRY_RUN=True ENABLED=False] would PATCH auto_patrol_schedule/<pk>/ ...` — dark-mode "would disable"
- `disabled admin schedule_pk=<pk> for Immix schedule_id=...` — real disable (only when CLEANUP_ENABLED=true)
- `anomaly: bucket=<b> threshold hit but Immix reports schedule ... still active` — anomaly reset
- `unrouted reason=<r> for schedule_id=...; dropping` — expected for deleted/no_stream until we wire those

### Inspect DDB counters

```bash
# Scan (dev/stage table is small; prod scan TBD)
AWS_PROFILE=prod aws dynamodb scan \
  --table-name autopatrol_cleanup_counters-dev --region us-west-2 --max-items 20

# Specific schedule
AWS_PROFILE=prod aws dynamodb get-item \
  --table-name autopatrol_cleanup_counters-dev \
  --key '{"schedule_id":{"S":"<UUID>"}}' --region us-west-2
```

Row fields you'll see:
- `admin_pk` — resolved admin-side schedule PK (cached after first sighting)
- `cadence_hours` — stringified float ("24.0" etc.)
- `ttl` — unix seconds, row auto-expires after
- `count`, `threshold`, `first_failure_at`, `last_failure_at` — patrol_exit bucket (reasons: no_patrols, error, exception)
- `count_site_disabled`, `threshold_site_disabled`, `first_site_disabled_at`, `last_site_disabled_at` — site_disabled bucket

Both buckets can coexist on the same row.

### Event source mapping health

```bash
AWS_PROFILE=prod aws lambda list-event-source-mappings \
  --function-name immix-autopatrol-schedule-cleanup --region us-west-2 \
  --query 'EventSourceMappings[0].[State,StateTransitionReason,LastProcessingResult]' --output text
```

Healthy: `Enabled  USER_INITIATED  OK` (or similar). If `State=Disabled` or `LastProcessingResult` indicates errors, check Lambda logs.

## Flipping enable / disable

### Enable real disables (stage gate E)

```bash
# Fetch current env → add CLEANUP_ENABLED=true → update
CURRENT=$(AWS_PROFILE=prod aws lambda get-function-configuration \
  --function-name immix-autopatrol-schedule-cleanup --region us-west-2 \
  --query 'Environment.Variables' --output json)

UPDATED=$(echo "$CURRENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['CLEANUP_ENABLED'] = 'true'
print(json.dumps({'Variables': d}))
")

AWS_PROFILE=prod aws lambda update-function-configuration \
  --function-name immix-autopatrol-schedule-cleanup \
  --environment "$UPDATED" --region us-west-2
```

### Kill switch (emergency disable)

```bash
# Same pattern but set CLEANUP_ENABLED=false
# OR disable the event source mapping to stop consuming entirely:
AWS_PROFILE=prod aws lambda update-event-source-mapping \
  --uuid <mapping-uuid> --no-enabled --region us-west-2
```

Get the UUID with `aws lambda list-event-source-mappings --function-name ...`.

### Purge the queue (last resort)

```bash
AWS_PROFILE=prod aws sqs purge-queue \
  --queue-url https://sqs.us-west-2.amazonaws.com/388576304176/autopatrol_stale_schedule_cleanup_dev.fifo \
  --region us-west-2
```

Only use if queue is flooded with stale/bad messages. Purge has a 60s cooldown.

## Audit queries

### NR custom events (once NR layer is attached)

```nrql
-- All disable decisions over 7 days, by bucket + reason
SELECT count(*) FROM AutoPatrolScheduleDisabled
FACET bucket, reason SINCE 7 days ago TIMESERIES

-- Dry-run vs real disables
SELECT count(*) FROM AutoPatrolScheduleDisabled
FACET dry_run, enabled SINCE 1 day ago

-- Re-enables
SELECT count(*) FROM AutoPatrolScheduleReenabled
FACET user_email SINCE 30 days ago

-- Schedules that hit threshold repeatedly (flappy)
SELECT count(*) FROM AutoPatrolScheduleDisabled
FACET schedule_id SINCE 30 days ago LIMIT 50
```

The NR Lambda layer isn't attached yet (tracked in mark-todos Not-Yet-Prioritized). Until then, `AutoPatrolScheduleDisabled` / `Reenabled` events don't reach NR — CloudWatch logs are the only source.

### CloudWatch Logs Insights

```
fields @timestamp, @message
| filter @logStream like /cleanup/
| filter @message like /counter schedule_id/
| parse @message /count=(?<count>\d+)\/(?<threshold>\d+).*admin_pk=(?<admin_pk>\S+)/
| stats count(*) by admin_pk, threshold
```

## Re-enabling a cleanup-disabled schedule

The `immix-autopatrol-schedule-reenable` Lambda is invoked via its Function URL with IAM auth:

```bash
# Assumes caller's IAM role has lambda:InvokeFunctionUrl on the function
curl -X POST https://p4e6ns5yndxxgicmhr2bycjdia0bastt.lambda-url.us-west-2.on.aws/ \
  --aws-sigv4 "aws:amz:us-west-2:lambda" \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
  --header "Content-Type: application/json" \
  --data '{"schedule_id":"<UUID>","user_email":"<email>"}'
```

Easier: once the admin UI "Re-enable" button is built, it'll sign the request with the admin backend's IAM role. Manual curl above is the interim workflow.

**Refuses to re-enable when:**
- Schedule isn't currently `is_deleted=True` on admin side
- `disabled_by` isn't `"cleanup_lambda"` (i.e. it was manually deleted by someone, don't auto-undo)
- Immix reports the schedule as still Paused / Suspended / Removed / Deleted (user must re-arm in Immix first)

## Common scenarios

### "Messages piling up in queue"

Check:
1. Event source mapping state — should be `Enabled`
2. Lambda concurrency — should not be 0
3. Lambda errors — `aws logs tail` for exceptions
4. IAM role attached — `get-function-configuration` shows the role ARN

### "DLQ alarm fired"

A message failed Lambda processing 3 times.

```bash
# Peek at the DLQ message
AWS_PROFILE=prod aws sqs receive-message \
  --queue-url https://sqs.us-west-2.amazonaws.com/388576304176/autopatrol_stale_schedule_cleanup_dlq_dev.fifo \
  --visibility-timeout 0 --max-number-of-messages 5 --region us-west-2
```

Usually indicates:
- Admin API unreachable (5xx streak) — the Lambda raises `_TransientError`, SQS retries, eventually DLQ
- Unexpected message payload shape — parse error

Fix: check Lambda logs for the Immix schedule_id in the DLQ message, diagnose.

### "Lambda disabled a schedule we didn't want disabled"

Use the reenable Lambda (see above). If the schedule is still Paused in Immix, the reenable will refuse — first un-pause in Immix, then re-run reenable.

### "Need to pin Lambda to an older code version"

Lambda doesn't publish versions by default. To roll back:
1. Build the older zip locally (`git checkout <sha>`, `deploy.sh`)
2. `aws lambda update-function-code --function-name ... --zip-file fileb://autopatrol_lambdas.zip`

Or use Lambda versioning explicitly via `aws lambda publish-version` before changes.

## Rollout state snapshot (2026-04-20)

- Step A (vms-connector → stage): merged `4f08afc4`, stage pods emitting
- Step B ([[actuate_admin]] → develop): merged `aa2cbdfd`, migration applied
- Step C (Lambda + infra): **done** (this runbook)
- Step D (merge autopatrol_onboarder#3 to master): NOT DONE, still draft
- Step E (flip `CLEANUP_ENABLED=true`): NOT DONE
- Step F (prod-tier queue + prod opt-in): NOT DONE
- Step G (EU): NOT DONE

## Related

- [[2026-04-17_stale-schedule-cleanup-design]] — architecture
- [[autopatrol-cleanup-lambda]] — entity
- [[2026-04-20_lambda-creation-and-tuning-playbook]] — general Lambda playbook
- [[2026-04-17_local-testing-strategies-per-repo]] — local test ceiling
- `/home/mork/.claude/plans/sequential-questing-creek.md` — the plan
