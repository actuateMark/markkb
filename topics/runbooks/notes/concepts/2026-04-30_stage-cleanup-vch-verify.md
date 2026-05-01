---
title: "Runbook: Stage→cleanup VCH no_patrols verify (24h post-merge)"
type: concept
topic: runbooks
tags: [runbook, autopatrol, vms-connector, cleanup-lambda, stage, verify, vch]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
---

# Stage→cleanup VCH no_patrols verify

## When this applies

Any change to `vms-connector`'s `emit_no_patrols_signal` decision logic (or any code path that gates the `no_patrols` SQS emission) merges to `stage`. After the merge a 24h soak window is needed before promoting to rearchitecture/prod, because the cleanup Lambda's anomaly-reset map is scoped to a 7-day rolling window and signal in/out of that window dominates the ROI calculation.

Recent precedent: [vms-connector#1662](https://github.com/aegissystems/vms-connector/pull/1662) merged stage 2026-04-28T20:01Z, dropped `no_patrols` emission for VCH-integration schedules. Verified clean 2026-04-30 morning.

## Symptoms (what triggers running this runbook)

- A vms-connector PR touching `emit_no_patrols_signal` or VCH integration code path just merged to `stage`.
- The cleanup Lambda's anomaly-reset 7-day map shows specific chronic flappers you expect the change to retire.
- Signal `connector_no_patrols_to_run_24h` dropped (or didn't drop, which is the failure case).

## Diagnose (3 commands, ~10s)

**1. Confirm the merge landed and capture the merge timestamp:**

```bash
gh pr view <PR#> --repo aegissystems/vms-connector \
  --json mergedAt,baseRefName --jq '{m:.mergedAt, base:.baseRefName}'
# Expect: base="stage", mergedAt=<recent ISO timestamp>
```

**2. DDB scan the cleanup Lambda counters for each chronic flapper schedule_id:**

The table is `autopatrol_cleanup_counters-dev` in `us-west-2`. Schedule IDs are full UUIDs; the first 8 hex chars are unique enough for `begins_with` matching.

```bash
for prefix in c3808175 fbdfdba6 ee1822f1; do
  echo "=== $prefix ==="
  AWS_PROFILE=prod aws dynamodb scan \
    --table-name autopatrol_cleanup_counters-dev \
    --region us-west-2 \
    --filter-expression "begins_with(schedule_id, :p)" \
    --expression-attribute-values "{\":p\":{\"S\":\"$prefix\"}}" \
    --max-items 3 \
    --query 'Items[*].[schedule_id.S, count.N, last_emit_at.S]' \
    --output text
done
```

What each row tells you:
- `count` = number of `no_patrols` emit events the Lambda has buffered for that schedule.
- `count >= threshold` (default `3`) means "would have proposed disable" but the anomaly-reset will gate it if Immix reports the schedule as Active.
- `count` stable across consecutive verifies = no new growth = the change is taking effect.

**3. Pull the dashboard signal history for `connector_no_patrols_to_run_24h`:**

```bash
curl -s "http://mork-firebat/app/api/observations/history?signal_id=connector_no_patrols_to_run_24h&hours=72" \
  | python3 -c "
import json, sys
rows = json.load(sys.stdin).get('rows', [])
for r in rows[-12:]:
    print(f'  {r[\"timestamp\"]}: value={r[\"value\"]} status={r[\"status\"]}')
"
```

Expect a monotonic-or-flat trend post-merge (e.g. 34 → 33 → 32). A *climb* post-merge means the change isn't taking effect — investigate.

## Fix (rare path)

If the soak fails — counts climbing instead of flat, signal trending wrong, new flappers appearing — the right move is **not** to revert; the cleanup Lambda's safety net (anomaly-reset) means there's no customer-visible blast. Instead:

1. Capture the anomalous schedule_ids in a KB note (`autopatrol/notes/concepts/<date>_<slug>.md`).
2. Re-open the source PR for follow-up; comment with the DDB counts.
3. If the trend is severe (cleanup_lambda_actual_disable_rate or DLQ depth spike), flip `CLEANUP_ENABLED=false` per [[2026-04-20_cleanup-lambda-runbook]].

## Verify

The soak passes when:

- DDB counts for the targeted chronic flappers are **stable or zero** (not climbing) after a full 24h post-merge window.
- `connector_no_patrols_to_run_24h` is trending down or flat, not climbing.
- `cleanup_lambda_dlq_depth` stayed at 0.
- `cleanup_lambda_anomaly_reset_rate` didn't spike.

Once those are clean, the PR is cleared for stage→rearchitecture promotion.

**Note on auto-clearing:** the `autopatrol_cleanup_counters-dev` table doesn't have DDB TTL enabled (open backlog item per §3 follow-ups), so chronic flappers won't naturally drop off — they'll freeze at their pre-merge count and stay there. That's still a pass.

## Prevent

- The dashboard signal `connector_no_patrols_to_run_24h` is the cheap-poll proxy for this runbook; trust it before scanning DDB by hand.
- After the cleanup-Lambda DDB TTL ships, this runbook can collapse to "watch the dashboard signal" since flappers will physically expire from the table.
- Any future change to `emit_no_patrols_signal` should drop a one-line note into the `vms-connector` PR template referencing this runbook so the soak period isn't skipped.

## Cross-refs

- [[2026-04-20_cleanup-lambda-runbook]] (autopatrol topic) — the parent operational guide for the cleanup Lambda
- [[skill-autopatrol-cleanup-lambda-check]] — the daily health-check skill
- mark-todos §17 (VCH connector emits `no_patrols` for genuinely-Active schedules) — the workstream that prompted this runbook
- mark-todos §3 follow-ups — DDB TTL is the durable fix for the "won't auto-clear" caveat above
- [[runbooks/_summary|Runbooks]]
