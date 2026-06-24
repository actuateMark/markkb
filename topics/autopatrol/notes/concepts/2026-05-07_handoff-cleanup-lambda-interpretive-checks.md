---
title: "Handoff — cleanup-lambda interpretive checks (Step 8b/8c/8d)"
type: concept
topic: autopatrol
tags: [handoff, cleanup-lambda, dashboard-check, autopatrol, interpretive, signal-conversion]
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
status: partial
incoming:
  - topics/offboarding/notes/concepts/2026-06-23_autopatrol-handoff.md
  - topics/personal-notes/notes/daily/2026-05-07.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-24
---

# Handoff — cleanup-lambda Step 8b / 8c / 8d (interpretive checks)

> **PARTIAL 2026-05-07.** Step 8c converted: new `onboarder_healthcheck_hotfix_in_effect` git_local signal (boolean, red_below=1, dispatcher inspects the failure-branch of `get_healthcheck()` for `logging.warning(...)` and absence of `return`). Catches the 2026-04-23 silent-early-return regression on the next cron tick after a revert lands locally. 5 unit tests cover in-effect / reverted / no-warning / no-call / missing-file cases. **8b and 8d still queued** per recommended order — see "Recommended order if pursuing conversion" below.

Queued after the 2026-05-07 cleanup-lambda signal-conversion work ([[2026-05-07_firebat-enhancements-batch]]). The mechanical checks (event-source mapping state, queue depths, error/disable rates) were converted to dashboard signals; these three are the **interpretive** checks that stayed LLM-only inside the `/autopatrol-cleanup-lambda-check` skill. Each could become a signal eventually but doing so would either (a) lose meaningful judgment, or (b) require building a custom collector source type. This note is the decision record + concrete handoff if/when conversion is revisited.

## What stayed LLM (and why)

| Step | What it does | Why it's not a signal |
|---|---|---|
| **8b** Retry-idempotency fix validation | Post-PR-#5 (2026-04-23): walk DDB rows, look for `last_message_id` attribute (proves the fix is in effect), check for `count > threshold * 2` drift (would mean retry-overcount regression). | Logic is computational (DDB scan + per-row arithmetic) but the verdict needs context: "drift in this schedule" could be expected for known flapping schedules, vs unexpected for new ones. Pure threshold misses the distinction. |
| **8c** Onboarder healthcheck hotfix in effect | Code-grep `autopatrol_onboarder/lambda_function.py` for the `get_healthcheck` block — must `logging.warning(...)` with NO `return` after. Reverting this hotfix recreates the 2026-04-23 silent-early-return incident. | Technically convertible to a `git_local` signal via `grep` + boolean. Worth doing as a permanent regression check. **Mark as the easiest of these three to convert.** |
| **8d** Deploy workflow integrity | Inspect the latest `deploy.yml` `gh run view --log` output: count `AccessDeniedException` / `ServiceException` (must be 0) and `CODEARTIFACT_AUTH_TOKEN=eyJ...` plaintext leaks (must be 0). | Conditional ("only if there were deploys since yesterday") and the gh log is large. Per-line analysis fits an LLM tool more naturally than a grep-pipe. Could be a `gh_log_grep` signal but the source-type isn't built. |

## Concrete check recipes (lift from SKILL.md, kept here for handoff completeness)

### 8b — DDB retry-idempotency validation

```bash
LOGS=$(AWS_PROFILE=prod aws logs tail /aws/lambda/immix-autopatrol-schedule-cleanup \
  --region us-west-2 --since 24h --format short 2>&1)

# (1) Retry-dedup hits — proves ConditionExpression fired (post-PR #5)
echo "retry-dedup hits: $(echo "$LOGS" | grep -c 'retry of message_id=.*skipping increment')"

# (2) DDB rows with last_message_id (post-fix rows)
AWS_PROFILE=prod aws dynamodb scan \
  --table-name autopatrol_cleanup_counters-dev --region us-west-2 \
  --filter-expression "attribute_exists(last_message_id)" \
  --select COUNT --query 'Count' --output text

# (3) Counter drift — count > threshold * 2 = retry-overcount regression
AWS_PROFILE=prod aws dynamodb scan \
  --table-name autopatrol_cleanup_counters-dev --region us-west-2 \
  --projection-expression "schedule_id, #c, #t" \
  --expression-attribute-names '{"#c":"count","#t":"threshold"}' \
  --output json 2>&1 | python3 -c "
import json, sys
for item in json.load(sys.stdin).get('Items', []):
    c = int(item.get('count',{}).get('N',0) or 0)
    t = int(item.get('threshold',{}).get('N',0) or 0)
    if t > 0 and c > t*2:
        print(f\"DRIFT: {item['schedule_id']['S'][:12]}... count={c}/{t}\")
"
```

Healthy: (1) >0 if any transient errors occurred (otherwise 0 is fine); (2) grows from 0 over time; (3) **no output** — drift is the regression signal.

**Conversion sketch (if pursued):** new `cw_dynamodb_drift_count` source. Scan DDB, count rows where `count > threshold * 2`, return integer. Threshold: `red_above: 0`. Keep the `retry-dedup hits` count as a separate informational signal (not a failure on its own). The "context-aware drift interpretation" gets dropped — we'd just flag any drift as red and let the human investigate. That's probably fine; these regressions are real and rare.

### 8c — Onboarder healthcheck hotfix in effect

```bash
cd /home/mork/work/autopatrol_onboarder
grep -A2 'autopatroller.get_healthcheck' lambda_function.py
```

Block must `logging.warning(...)` with NO `return` after. Any `return` = hotfix reverted, 2026-04-23 silent early-return recurs.

**Conversion sketch (if pursued):** new `git_local` signal `onboarder_healthcheck_hotfix_in_effect`. Boolean (1 = present, 0 = reverted). Threshold: `red_below: 1`. Implementation: dispatcher reads the file, runs the grep pattern, checks `return` doesn't appear in the next 5 lines. **This is the highest-value conversion of the three** — it's a permanent regression check on a known failure mode, doesn't need judgment, and would page on the next cron tick after a revert. ~1 hour of work.

### 8d — Deploy workflow integrity

```bash
cd /home/mork/work/autopatrol_onboarder
RUN_ID=$(gh run list --workflow deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')
JOB=$(gh run view "$RUN_ID" --json jobs --jq '.jobs[0].databaseId')

# Real errors (expected: 0)
gh run view --job $JOB --log 2>&1 | grep -cE 'AccessDeniedException|ServiceException'

# Plaintext token leaks (expected: 0) — tokens should be masked by GH Actions
gh run view --job $JOB --log 2>&1 | grep -cE 'CODEARTIFACT_AUTH_TOKEN=eyJ'
```

**Conversion sketch (if pursued):** more involved. Would need a `gh_log_grep` source that runs `gh run view --log`, then greps. Two issues: (a) `--log` output is large and rate-limited per gh API call; (b) the "only if there were deploys since yesterday" gate adds branching. **Lowest-priority conversion** — the LLM does this fine on the daily morning run, and a deploy that leaked a token would also blow up other Actuate signals fast.

## Recommended order if pursuing conversion

1. **8c first** (1h) — high-value, simple `git_local` signal. Catches the only one of these three that has a known prior incident (2026-04-23 silent early-return).
2. **8b second** (4-6h) — needs new `cw_dynamodb` source type or extension of cw_metric to handle DDB. Worth it because retry-idempotency drift is a silent corruption pattern that no current signal covers.
3. **8d last or never** (8h+) — gh-log scanning is awkward and the LLM-during-morning-prep flow handles it well. Convert only if it starts missing things.

## When to revisit

- A reverted hotfix or DDB drift incident slips past the morning LLM check → escalates 8c / 8b conversion priority.
- Cleanup-lambda goes prod (Step F: prod queue, not just dev) → all three checks become higher-stakes; consider 8c at minimum at that point.
- New cleanup-lambda failure modes surface that aren't covered by either signals or these three checks → expand the inventory before converting.

## Related

- [[2026-05-07_firebat-enhancements-batch]] — what shipped today (mechanical conversion)
- [[2026-04-23_cleanup-rollout-day]] — context for why 8b/8c/8d exist as checks (PR #4, #5 lineage)
- [[2026-04-20_cleanup-lambda-runbook]] — operational runbook
- `~/.claude/skills/autopatrol-cleanup-lambda-check/SKILL.md` — current skill (Tier-3 fallback now, was Tier-1 before today)
- `~/.claude/skills/dashboard-check/config/signals.json` — where new signals would land
- `~/.claude/skills/dashboard-check/collect.py` — where new dispatchers would land
