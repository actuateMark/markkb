---
title: "Tomorrow's Morning Watch List — 2026-04-24"
type: concept
topic: autopatrol
tags: [watch-list, morning-check, bake, hotfix-validation, retry-idempotency]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
status: active
expires: 2026-04-25
---

# Morning Watch List — 2026-04-24

Specific things `/daily-scope` + `/autopatrol-cleanup-lambda-check` should look for tomorrow to confirm today's (2026-04-23) changes held overnight. Delete this note once all items are green.

## Why this exists

2026-04-23 landed four interlocking changes to the AutoPatrol stack:
1. **Onboarder healthcheck hotfix** (PR #4) — downgraded a broken early-return to a warning. Fixed a 47h silent-failure incident.
2. **Cleanup Lambda retry-idempotency fix** (PR #5) — DDB ConditionExpression guard on `last_message_id` prevents counter double-counting on SQS retries.
3. **Deploy workflow hardening** (PR #6) — fails on real AWS errors (not just ResourceNotFound), masks CodeArtifact token.
4. **IAM policy v2** — granted `lambda:UpdateFunctionCode` for cleanup + reenable ARNs (was missing; hid partial deploys for 3 days).

None have been exercised by real adverse conditions overnight yet. Tomorrow's check-in is the first acceptance window.

## What to verify

Run both `/autopatrol-cleanup-lambda-check` AND the skill's §8b/8c/8d validation (the latter was added today specifically for these fixes).

### 1. Onboarder hotfix still in effect
- [[autopatrol-cleanup-lambda-check]] §0: US activity > 10 lines/30m, EU activity > 2 lines/30m, 0 ERROR-level 404 lines
- §8c: `lambda_function.py` grep shows `logging.warning` + no `return` in the healthcheck block

### 2. Retry-idempotency fix exercising organically
- §8b signal 1: `retry-dedup hits` > 0 in 24h. Only populates if an Immix flap happened AND the guard fired. 0 is also OK (no flap) but means the fix remains only unit-tested.
- §8b signal 2: post-fix DDB rows with `last_message_id` > 0 (should grow from 0 at deploy time to several rows within a day)
- §8b signal 3: counter drift check — no row with `count > threshold * 2`

### 3. Deploy workflow integrity
- §8d: 0 AccessDenied lines + 0 plaintext CodeArtifact token lines in the last deploy workflow run
- All 6 Lambdas (3 functions × 2 regions) should show successful update OR correct "skipped: not yet provisioned" for EU cleanup + EU reenable

### 4. Pipeline steady-state
- §1: event source mappings still Enabled
- §2: stage main queue <100, prod main queue = 0 (not opted in yet), both DLQs = 0
- §3: Lambda Errors = 0, Throttles = 0
- §4: "ERROR" log count = 0
- §6: DDB row count reasonable (5 before the reset today; we deleted 1 so it's 4; new rows appearing is normal)
- §7: connector emits ↔ Lambda invocations correlation tight (gap <20%)

## Gates for the next rollout step

Once all the above are ✅:
- Ready for **Step E.2** — flip `CLEANUP_ENABLED=true` on stage ([[mark-todos]] §3, task #20)
- NOT ready yet if §8b signal 2 stays at 0 (no real-world evidence fix works)

## Related

- [[2026-04-23_postmortem-onboarder-healthcheck]] — why #1 above matters
- [[autopatrol-cleanup-lambda]] — entity
- [[2026-04-17_stale-schedule-cleanup-design]] — design
- `/home/mork/.claude/plans/sequential-questing-creek.md` — full rollout plan §9
- [[mark-todos]] §3 — workstream tracker, newly broken down into sub-tasks today
