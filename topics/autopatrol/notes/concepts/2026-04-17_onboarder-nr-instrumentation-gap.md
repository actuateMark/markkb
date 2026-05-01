---
title: "AutoPatrol Onboarder Lambda — Missing NR Instrumentation"
type: concept
topic: autopatrol
tags: [autopatrol, lambda, new-relic, observability, gap]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/autopatrol/notes/entities/autopatrol-cleanup-lambda.md
  - topics/autopatrol/notes/entities/autopatrol-onboarder.md
  - topics/autopatrol/notes/syntheses/2026-04-17_stale-schedule-cleanup-design.md
  - topics/personal-notes/notes/daily/2026-04-21.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-01
---

# AutoPatrol Onboarder Lambda — Missing NR Instrumentation

The `immix-autopatrol-onboarding` Lambda (US `us-west-2` + EU `eu-west-1`) has **zero runtime telemetry in [[new-relic|New Relic]]**.

Surfaced by [[agent-nrql-investigator]] during a 7-day query: no invocation records in `ServerlessSample` or `AwsLambdaInvocation`, no log events tagged with `aws.lambda.functionName`. Either the NR Lambda layer/decorator isn't wired up, or CloudWatch logs aren't being forwarded to NR. Until fixed, CloudWatch Logs is the only source for troubleshooting the Lambda's behavior.

## Impact

- Can't answer "did today's onboarder run finish cleanly?" from NR
- Can't trend invocation duration or error rate
- Overnight health checks can't correlate onboarder failures with downstream symptoms
- Planning for anything onboarder-adjacent has no quantitative baseline

## Fix — bundling with the stale-schedule cleanup work

See [[2026-04-17_stale-schedule-cleanup-design]] §7 (observability). Custom events to emit:

- `AutoPatrolScheduleDisabled { schedule_id, admin_pk, tenant_id, reason, bucket, count_at_disable, cadence_hours, enabled, dry_run }` (cleanup Lambda)
- `AutoPatrolScheduleReenabled { schedule_id, admin_pk, user_email, dry_run }` (re-enable Lambda)
- Existing onboarder gains invocation + error telemetry via the layer/decorator (TODO)

### Status (2026-04-20)

**Code:** done. `autopatrol_onboarder` has `newrelic_helper.py` with a `record_event()` wrapper that no-ops when the NR agent import fails (local dev). Commits `7dc6a13` adds the hook calls at the disable + re-enable paths. Local smoke tests pass — NR import silently fails on dev machines, but Lambda completes normally.

**Terraform / layer attachment:** NOT DONE. The Lambda functions need:
- `AWS_LAMBDA_EXEC_WRAPPER=/opt/nr_lambda_python` env var
- `NEW_RELIC_LAMBDA_HANDLER=<module>.lambda_handler` env var
- `NEW_RELIC_LICENSE_KEY=...` from Secrets Manager
- Attach layer ARN `arn:aws:lambda:<region>:451483290750:layer:NewRelicPythonXX:...`

These go into `ds-terraform-eks-v2#69`'s Lambda stanzas as a follow-up. Tracked in [[mark-todos]] Not-Yet-Prioritized.

**Onboarder retrofit:** also not done. Same layer attachment applies. Handler name `lambda_function.lambda_handler`.

## Until the fix

Use CloudWatch Logs Insights against the `/aws/lambda/immix-autopatrol-onboarding` log group for US/EU debugging. Log format is `%(asctime)s:%(levelname)s:(%(threadName)s):%(message)s` — filter by `ERROR` or specific tenant IDs.

## Related

- [[autopatrol-onboarder]] — the affected Lambda entity
- [[autopatrol-cleanup-lambda]] — sibling Lambda (new, will ship instrumented)
- [[2026-04-17_stale-schedule-cleanup-design]] — parent design
