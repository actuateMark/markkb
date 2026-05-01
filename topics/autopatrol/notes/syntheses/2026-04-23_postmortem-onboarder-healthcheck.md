---
title: "Post-Mortem: AutoPatrol Onboarder Silent Failure (2026-04-21 → 2026-04-23)"
type: synthesis
topic: autopatrol
tags: [postmortem, incident, onboarder, lambda, deploy, process, kb-bot, autopatrol]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
severity: medium
duration_hours: ~47
incoming:
  - topics/autopatrol/notes/concepts/2026-04-22_cleanup-lambda-bake-state.md
  - topics/autopatrol/notes/concepts/2026-04-23_cleanup-rollout-day.md
  - topics/autopatrol/notes/concepts/2026-04-24_morning-watch-list.md
  - topics/autopatrol/notes/entities/autopatrol-cleanup-lambda.md
  - topics/autopatrol/notes/entities/autopatrol-onboarder.md
  - topics/engineering-process/_summary.md
  - topics/engineering-process/notes/syntheses/2026-04-14_feature-development-lifecycle.md
  - topics/operational-health/notes/concepts/2026-04-23_dashboard-phase-1b-pickup.md
  - topics/operational-health/notes/concepts/2026-04-24_dashboard-1b-continuation.md
  - topics/operational-health/notes/concepts/2026-04-27_dashboard-signal-cookbook.md
incoming_updated: 2026-05-01
---

# Post-Mortem — AutoPatrol Onboarder Silent Failure

> **One-line:** A new healthcheck early-return guard, introduced as part of the cleanup-Lambda merge, silently disabled every 5-min invocation of the onboarder Lambda for ~47 hours because the gated endpoint had been 404'ing unnoticed. Users could not activate new schedules. Lambda `Errors=0` the whole time — nothing alarmed. Found via a customer report. Fixed in 1h once reported.

## Severity + impact

| Field | Value |
|---|---|
| Severity | Medium (customer-facing but workaround-able by waiting or manual activation) |
| Duration | ~47 hours (2026-04-21T16:20:36Z deploy → 2026-04-23T15:04:04Z hotfix) |
| Blast radius | Both production regions: US (us-west-2) + EU (eu-west-1) onboarder Lambdas |
| Users affected | All customers trying to onboard new AutoPatrol schedules. User-reported symptom: "create new schedule using Actuate and have it set to active, just hangs and never finishes making it to active" |
| Revenue/SLA | None quantified — feature was unavailable; no billing impact |
| Data loss / corruption | None — onboarder is additive; silent failure caused no writes, no bad writes |

## Timeline (UTC)

| Time | Event |
|---|---|
| 2026-04-21 16:20:12 | PR #3 `[STAGE BAKE ONLY — DO NOT MERGE YET] AutoPatrol stale-schedule cleanup Lambdas` merged to master |
| 2026-04-21 16:20:36 | Deploy workflow completed; US + EU onboarder Lambdas updated with new code containing the healthcheck early-return guard |
| 2026-04-21 16:25 | First post-deploy cron invocation hits the 404 branch, logs ERROR, returns early — silent break begins |
| 2026-04-21 → 2026-04-23 | ~14,400 invocations across US+EU, all early-exiting after ~400ms. Lambda `Errors=0`. No alarm. No dashboard signal. |
| 2026-04-23 ~14:35 | Customer reports "can't activate new schedule" with tenant `dfda7621…` / schedule `1615C337…` |
| 2026-04-23 14:45 | Triage begins: confirmed both regions 404-bailing via log grep |
| 2026-04-23 14:55 | Root cause identified — new healthcheck guard in the cleanup-Lambda merge |
| 2026-04-23 15:00 | Hotfix branch `hotfix/onboarder-healthcheck-bail` pushed; PR #4 opened |
| 2026-04-23 15:01 | PR #4 merged to master |
| 2026-04-23 15:03:39 | Deploy Lambda workflow triggered |
| 2026-04-23 15:04:04 | US Lambda updated |
| 2026-04-23 15:04:11 | EU Lambda updated |
| 2026-04-23 15:04:52 | First post-hotfix invocation observed running 3+ minutes processing contracts (vs previous 400ms exit) — **resolved** |

## Root cause

### Technical

The onboarder Lambda's `autopatrol_onboard_flow()` starts with:

```python
res = autopatroller.get_healthcheck()
if res is None or res.status_code not in [200, 201]:
    logging.error(f"Failed to connect to AutoPatrol API: {res}")
    return  # ← the problem
```

The `autopatroller.get_healthcheck()` call hits an Immix `/healthcheck` endpoint that **returns 404 in prod (both US and EU)** — it has been returning 404 for a long time, likely since the library was first pointed at a path that doesn't exist upstream.

**Prior code** (before the 2026-04-21 merge):

```python
autopatroller.get_healthcheck()  # result ignored
contract_res = autopatroller.get_contracts()
# ... work continues regardless of healthcheck status
```

The healthcheck was a de-facto dead call — invoked for form's sake, result ignored. The 404 was harmless.

**The 2026-04-21 merge** added what looked like a reasonable fail-fast guard. Author (me) reasoned: "if upstream is down, don't waste effort on downstream calls, log and exit cleanly." Correct in principle — wrong in context, because the *specific call being gated* was broken upstream, not a reliable indicator of upstream health.

### Process

Five contributing factors compounded the technical slip:

1. **Silent failure mode.** The Lambda returned `0` errors because `return` is a normal exit. CloudWatch alarms on `Errors > 0` — none fired. The default metric vocabulary is not sufficient to detect "Lambda is running but bailing."

2. **No acceptance-criteria discipline.** PR #3 didn't have an explicit post-deploy verification step. "CI green + deploy succeeded" was accepted as "release complete" — no behavioral check was run.

3. **No NR instrumentation on the onboarder.** Pre-existing gap — filed in KB but never prioritized. Would have caught this faster via custom event counts.

4. **No daily dashboard for the AutoPatrol system as a whole.** The only way to detect the silent failure was by log-grepping a specific pattern (`"Fetched N contracts"`) — not something anyone was doing daily.

5. **Change made during a larger unrelated merge.** The healthcheck guard wasn't the PR's main point (the PR was about adding the cleanup Lambda + dropping `allow_deletion` bookkeeping). The guard was a one-line "while I'm here" improvement. Lower visibility → lower review rigor.

### Why previous code didn't need the guard

The downstream calls `get_contracts()`, `get_sites()`, `get_devices()` **are the actual health check**. If the API is truly unreachable, they fail loudly and the Lambda errors out on them (which DOES increment the `Errors` metric). The `/healthcheck` endpoint added nothing. The "fail fast" framing was a pattern-match, not a design decision grounded in this specific system.

## Detection

- Detection method: **customer report** — worst-possible detection for a 2-day silent failure
- Detection lag: ~47h from first broken invocation to report
- Customer friction: unknown number of failed schedule-activation attempts before they escalated

## Resolution

- Hotfix (PR #4): downgrade the `logging.error(...)` + `return` to `logging.warning(...)` without a return. Downstream calls become the implicit connectivity check.
- Merge + auto-deploy: ~1 hour from report to verified resolution

## What went well

1. **Fast triage once reported.** From "user tells us" to "root cause confirmed" was 20 minutes; to "hotfix deployed + verified" was 60.
2. **Prior CloudWatch log retention.** Log retention long enough to walk back to the first 404 and timestamp the regression against the deploy.
3. **Lambda architecture fail-safe.** Early return meant no bad writes — the silent failure was purely additive (the expected work didn't happen), not corrupting.
4. **Sibling cleanup-Lambda pipeline unaffected.** Cleanly isolated — the cleanup Lambda (different function) continued to work normally during the incident.
5. **Hotfix pattern was low-risk.** One-line change (downgrade to warning + drop the `return`) — trivial to review, trivial to verify.

## What went wrong

1. **Two days of silent failure.** Unacceptable detection lag for a customer-facing feature.
2. **The "CI-green means release-verified" assumption.** Baked into our process; incident proved it's dangerous.
3. **Low-priority KB follow-ups (NR instrumentation) weren't prioritized** — would have shortened detection by days.
4. **A "safer" guard added without verifying the gate.** Canonical mistake: assuming a health endpoint is reliable because the client library exposes it.
5. **Incident was not detected by continuous monitoring (there is none) or periodic review (none set up).** This is a process gap, not a tooling limitation — the commands to run the check existed all along; no one ran them.

## Action items

### Completed today (2026-04-23)

| Action | Owner | Status |
|---|---|---|
| Hotfix PR #4 (drop early return on healthcheck 404) | Mark | ✓ merged + deployed + verified |
| Add §0 onboarder-liveness check to `/autopatrol-cleanup-lambda-check` skill | Mark (+ Claude) | ✓ skill updated |
| Rule: "never abort on HTTP failures unless explicitly asked" | Mark (+ Claude) | ✓ captured in feedback memory + this repo's `CLAUDE.md` |
| Rule: "every merge needs acceptance criteria + post-deploy verification" | Mark (+ Claude) | ✓ captured in feedback memory + KB synthesis [[2026-04-23_release-acceptance-criteria]] |
| Project-specific acceptance criteria for this repo | Mark (+ Claude) | ✓ written in `/home/mork/work/autopatrol_onboarder/CLAUDE.md` |

### Outstanding (high priority)

| Action | Owner | Where tracked |
|---|---|---|
| Build AutoPatrol alarm + dashboard system (5 metric families) | TBD — hand-off to planner session | [[2026-04-23_alarm-dashboard-sketch]] + mark-todos §9 |
| Wire onboarder Lambda to [[new-relic|New Relic]] (layer + custom events) | TBD | Part of §9 Phase 1 |
| Create `/autopatrol-morning-check` skill for daily consolidated review | TBD | Part of §9 Phase 3 |
| Fix DDB counter retry-idempotency bug found in cleanup Lambda (counter increments on SQS retries) | Mark | Follow-up (pre-existing, surfaced during incident-adjacent work) |

### Outstanding (medium priority)

| Action | Owner | Notes |
|---|---|---|
| File upstream bug for broken Immix `/healthcheck` endpoint | TBD | Low priority — it's been broken without anyone noticing |
| Actually-useful test suite for onboarder repo (current `Run Python Tests` is a stub `echo "TODO"`) | TBD | Separate follow-up; would NOT have caught this specific incident |
| Audit other Actuate Lambdas for similar silent-early-return patterns | TBD | Proactive hunt — any Lambda whose happy path exits via `return` deserves a look |

### Preventive rules (already in force)

These are now documented and binding on future work:

1. **HTTP error handling**: never abort unless explicitly asked. Default is `logging.warning(...)` + continue. Downstream calls are the real connectivity check.
2. **Merge acceptance criteria**: every non-trivial PR body must include observable, grep-able post-deploy assertions. CI-green is not release-verified.
3. **Post-deploy verification**: every merge that hits prod/stage must be verified against the core-flow acceptance criteria within 10 min (one cron cycle for cron-driven Lambdas).
4. **Behavioral signals over surface metrics**: `Errors=0` and `Invocations>0` are not health signals. Grep for activity-marker log lines.
5. **Per-repo check skills**: any repo where silent regression could break core flow must have a runnable Claude Code skill.

## Contributing factors worth naming explicitly

Not technical root causes, but worth documenting as cultural/operational patterns to push on:

- **"While I'm here" improvements in unrelated PRs.** A sensible-looking guard snuck into a cleanup-Lambda PR. Review attention was on the new Lambdas; the guard was a footer. **Lesson:** tangential improvements to existing flows need their own PRs or at minimum callouts in the review description.

- **Acceptance-criteria debt.** There was no forcing function to write post-deploy checks. Relied on "I'll remember to check." Fixable with CLAUDE.md discipline + per-repo check skills + the process rules above.

- **Observability debt compounding feature debt.** Onboarder NR instrumentation was a known gap from day one. Every day it wasn't done, the blast radius of a future silent failure grew. **Lesson:** observability gaps in core customer-facing flows are medium-severity bugs, not backlog items.

## Related

- [[2026-04-23_release-acceptance-criteria]] — the global rule that came out of this
- [[2026-04-23_alarm-dashboard-sketch]] — the forward-looking design
- [[autopatrol-onboarder]] — onboarder entity (should link back to this post-mortem)
- [[autopatrol-cleanup-lambda]] — cleanup entity
- PR #4 (hotfix) — `aegissystems/autopatrol_onboarder`
- PR #3 (cleanup-Lambda merge that introduced the regression) — `aegissystems/autopatrol_onboarder`
