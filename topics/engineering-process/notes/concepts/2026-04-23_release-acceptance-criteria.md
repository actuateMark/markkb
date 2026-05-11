---
title: "Release Acceptance Criteria — The CI-Green-Is-Not-Verified Rule"
type: concept
topic: engineering-process
tags: [release, acceptance-criteria, post-deploy, verification, process]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
outgoing:
  - topics/autopatrol/notes/concepts/2026-04-23_cleanup-rollout-day.md
  - topics/autopatrol/notes/entities/autopatrol-onboarder.md
  - topics/autopatrol/notes/syntheses/2026-04-23_alarm-dashboard-sketch.md
  - topics/autopatrol/notes/syntheses/2026-04-23_postmortem-onboarder-healthcheck.md
  - topics/engineering-process/_summary.md
  - topics/engineering-process/notes/concepts/code-review-checklist.md
  - topics/engineering-process/notes/syntheses/2026-04-14_feature-development-lifecycle.md
  - topics/operational-health/notes/concepts/2026-04-23_dashboard-phase-1b-pickup.md
  - topics/operational-health/notes/concepts/2026-04-23_oom-surge-connector-limit-drift.md
  - topics/operational-health/notes/concepts/2026-04-24_dashboard-1b-continuation.md
incoming:
  - topics/autopatrol/notes/concepts/2026-04-23_cleanup-rollout-day.md
  - topics/autopatrol/notes/concepts/2026-05-04_autopatrol-server-release-process.md
  - topics/autopatrol/notes/entities/autopatrol-onboarder.md
  - topics/autopatrol/notes/syntheses/2026-04-23_alarm-dashboard-sketch.md
  - topics/autopatrol/notes/syntheses/2026-04-23_postmortem-onboarder-healthcheck.md
  - topics/autopatrol/notes/syntheses/2026-05-04_autopatrol-server-nr-upgrade-plan.md
  - topics/autopatrol/notes/syntheses/2026-05-05_admin-deploy-customer-name-incident.md
  - topics/autopatrol/notes/syntheses/2026-05-05_autopatrol-group-demotion-design.md
  - topics/engineering-process/_summary.md
  - topics/engineering-process/notes/concepts/code-review-checklist.md
incoming_updated: 2026-05-08
---

# Release Acceptance Criteria

**Core rule: every non-trivial merge needs explicit acceptance criteria that cover the core flow working in prod/stage, and those criteria MUST be verified post-deploy EVERY TIME. "CI green" is not "release verified."**

## Why this rule exists

Incident — 2026-04-23, autopatrol_onboarder.

- A PR merged to master and auto-deployed to US + EU.
- CI was green (test stub passed, build built, lock-diff clean).
- The merge included a new `if res.status_code not in [200, 201]: return` healthcheck gate on an upstream endpoint that had been silently 404'ing for a long time.
- Every 5-min onboarder invocation bailed early before doing any real work.
- Lambda CloudWatch `Errors` metric stayed at 0 because `return` is a normal exit.
- Break persisted for ~2 days until a customer reported "can't activate schedules."

"CI green" caught nothing. The metrics didn't alarm. The deploy workflow reported success. Only a human hand-grep of activity-marker log lines would have caught it — and nobody ran that check.

## The four-part rule

### 1. Write acceptance criteria in every PR body

Not "tests pass." Concrete, observable, grep-able assertions about post-deploy behavior. Examples:

**For a cron-triggered Lambda:**
- [ ] Within 10 min of deploy, CloudWatch logs contain `"Fetched N contracts"` with N > 0 (per region)
- [ ] A test input of type X, after one cron cycle, produces output Y (observable where?)
- [ ] No new `[ERROR]` patterns in the log that weren't there pre-deploy

**For an API service:**
- [ ] Key endpoints return 200 on representative inputs (include curl example in PR)
- [ ] p50/p99 latency within X% of pre-deploy baseline 30 min post-deploy
- [ ] No 5xx rate bump on production traffic

**For a library bump:**
- [ ] Consumer repo's `uv sync` resolves against the new version
- [ ] Import-check passes on all modules that consume changed symbols
- [ ] At least one functional unit test exercises the new code path

### 2. Verify post-deploy, EVERY TIME

Run the acceptance criteria against prod/stage after the deploy. Not "CI passed" — actually execute the behavioral check. If the check surfaces nothing, confirm in words: *"Acceptance criteria verified: [specific log pattern observed] / [specific metric in range] / [specific endpoint returning 200]."*

Timing matters:
- Cron Lambdas → wait at least one full cron cycle.
- Scheduled jobs → wait for at least one execution.
- Request-driven services → need real production traffic, not just synthetic pings.

Don't declare "clean" before the first real run.

### 3. Behavioral signals, not surface metrics

`Errors=0` is not a health signal if a Lambda is early-returning. `200 OK` is not a health signal if the endpoint returns empty. The check must surface **the work actually happening**, not just absence of errors.

Good signals:
- Activity-marker log lines (`"Fetched N"`, `"processing schedule_id="`, `"activating contract"`)
- Downstream side effects (a DB row appeared, a message was posted to a queue, a file was written)
- End-to-end synthetic tests that hit the public surface

Bad signals:
- `Errors=0` (can mean "nothing ran")
- `Invocations>0` (can mean "cron fired" not "cron did work")
- "CI green" (doesn't exercise the real flow)

### 4. Per-repo check skills + cross-repo dashboard

Every repo where silent regression could break core flow should have a Claude Code skill that codifies the acceptance criteria. The skill is runnable post-deploy and on a loop.

Examples:
- [[skill-autopatrol-overnight-check|/autopatrol-check]] — patrol pipeline health
- [[autopatrol-cleanup-lambda-check|/autopatrol-cleanup-lambda-check]] — cleanup pipeline + onboarder §0 check (added post-incident)
- *(Create for every repo that can silently regress)*

**Cross-repo surface: `/dashboard-check`** ([[2026-04-23_dashboard-sketch]]) — the canonical pre-deploy baseline + post-deploy verification tool. Aggregates per-repo signals into one static HTML dashboard at `~/Documents/worklog/dashboard/`. Every release uses it as a gate: snapshot before merge, verify GREEN after merge (for at least one cron cycle / real-traffic window).

**The launch gate:** a release is NOT verified until the dashboard is GREEN for the affected component. If the signal isn't in the dashboard catalog yet, adding it is a prerequisite to the release — not a follow-up.

If a check fires AFTER a merge goes out, that's a process failure. Audit which missing check would have caught it and **add it to the skill + the dashboard signal catalog**. Treat it the same as a missing test — write it, commit it, so the next incident doesn't repeat.

### 5. Track config-surface drift over time, not just immediate behavior

**Added 2026-04-23 after OOM-surge triage traced back to a Feb 2026 commit.**

Post-release checks that only fire at deploy time miss a whole class of regressions: **changes whose effect compounds over days or weeks until something breaks under load**. The most common shape is a change that removes or narrows a safety floor (rate limit, memory floor, retry ceiling, connection cap), where the immediate behavior looks fine because the system isn't near the floor yet. The regression surfaces only when load or entropy pushes it there.

**Case study — OOM surge 2026-04-23** (see [[2026-04-23_oom-surge-connector-limit-drift]]):

- `connector_deployer` commit `a5de5db` on 2026-02-09 removed the VPA-patch path that enforced a minimum memory floor on connector pods.
- The immediate deploy looked healthy — no pods OOMed that week.
- VPA then gradually shrank memory limits on ~2,000 connector pods over 70 days, based on observed usage, to as low as 384–480 MB (template declared 2–6 GiB).
- On 2026-04-22 overnight, load on a subset of those pods crossed the now-undersized ceiling → 423 OOMKills / 24h, 4× baseline.
- Root-cause signal (limits drifting away from the declared template) was observable at any point between Feb 9 and Apr 22, but nobody was looking.

**The rule:** post-release validation should include **config-surface invariant checks** for any release that touches:
- Resource limits (memory, CPU, disk, connection pools, timeouts)
- Autoscaling parameters (HPA min/max, VPA minAllowed/maxAllowed/mode)
- Rate limits, retry ceilings, circuit-breaker thresholds
- IAM permission scopes or TTLs
- Data-retention or lifecycle policies

Each of these has a **declared value** (in source) and a **running value** (observable from the runtime). When these can drift apart — VPA adjusting limits, operator overriding in-cluster, manual console patches, lifecycle rules being disabled — the invariant needs a periodic check, not just a deploy-time gate.

**What goes in the dashboard signal catalog:** for each drift-prone surface, add a signal that compares declared vs. running and flags mismatches. Examples:
- "% of connector pods whose `memoryLimitBytes` < template-declared floor" → should be 0.
- "Any pod whose `memoryUsedBytes / memoryLimitBytes` > 70%" → flags pre-OOM risk regardless of the declared template.
- "Count of S3 buckets with lifecycle rules disabled" → flagged 2026-04-23 for `aegis-all-frames-v2-sts`.
- "Any `UpdateMode=Off` VPA that should be `Auto`, or vice-versa" → [[vpa-behavior|VPA behavior]] drift.

**What goes in the per-repo skills:** when a PR touches a drift-prone surface, the acceptance criteria must include BOTH an immediate check (does it behave correctly right now?) AND a reference to the dashboard signal that will catch subsequent drift (so the reviewer sees the long-horizon check is wired up).

**What goes in the post-push audit** (CLAUDE.md global rule): after pushing a change that touches any drift-prone surface, explicitly confirm the dashboard signal exists for that surface. If it doesn't, add it before marking the push complete.

## Related rules

- [[2026-04-20_overnight-check-skill-pattern]] — how to build a per-repo check skill
- [[2026-04-17_local-testing-strategies-per-repo]] — local validation approaches per repo type
- [[2026-04-20_lambda-creation-and-tuning-playbook]] — Lambda-specific operational checks
- [[2026-04-23_oom-surge-connector-limit-drift]] — case study that motivated §5

## Takeaway

The user had the right phrasing (2026-04-23): *"we NEED the core flow to work in these cases and it should always be checked against post-launch EVERY TIME."* Every merge. Every deploy. Not a nice-to-have — the default.
