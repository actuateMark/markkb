---
title: "AutoPatrol handoff — cleanup Lambda (§3) + arm-miss race (§14) + alert-flow (§2)"
type: concept
topic: offboarding
tags: [offboarding, handoff, autopatrol, cleanup-lambda, arm-miss, brad]
created: 2026-06-23
updated: 2026-06-23
author: kb-bot
---

# AutoPatrol handoff

> Hands off Mark's AutoPatrol work: the **stale-schedule cleanup Lambda (§3)**, the **midnight arm-miss race (§14)**, and the **alert-flow diagnostic gaps (§2)**. Natural owner: **Brad** (already owns AUTO-351 + AUTO work) — but the **cleanup-Lambda internals are uniquely Mark's**, so the reading list below is load-bearing, not optional. Repos: `autopatrol_onboarder` (cleanup Lambda), `actuate_admin` (arm-miss), `autopatrol-server`.

## §3 — Stale-schedule cleanup Lambda  *(LIVE; verify-only)*
**What it does:** Immix-side schedule deletions never flow back to our admin DB → stale cronjobs fire forever. The cleanup Lambda counter-tracks per-schedule "no patrols" emits over a cadence-aware window, confirms 404/DEACTIVATED with Immix, then soft-disables in admin with audit fields. A sibling reenable Lambda + admin UI button reverses any disable.

- **State:** Step E (cleanup-enabled) GREEN at 4-day window; Step F (connector emit-flag flip) is the next shipping step (deferred — see [[autopatrol-deferred-backlog]]). Active path = **verify correctness across the state matrix**: Immix-Deleted (disable), Immix-Suspended (do NOT; anomaly-reset), Paused (do NOT), genuine-offline (do NOT).
- **Operate:** morning check `/autopatrol-cleanup-lambda-check`. Dashboard signals: `cleanup_lambda_dlq_depth` (must be 0), `cleanup_lambda_errors`, `cleanup_lambda_actual_disable_rate`, `cleanup_lambda_anomaly_reset_rate`, `cleanup_lambda_anomaly_repeat_offenders_7d`, `cleanup_lambda_would_patch_rate`.
- **Audit trail (manager-visible):** `GET /api/auto_patrol_schedule/?disabled_by=cleanup_lambda`.
- **Rollback:** flip `CLEANUP_ENABLED=false` via `aws lambda update-function-configuration` — instant, no data loss.
- **Reading (load-bearing):** [[2026-04-17_stale-schedule-cleanup-design]] (the design), [[2026-04-20_lambda-creation-and-tuning-playbook]] (build/tune recipe), [[2026-04-22_cleanup-lambda-bake-state]] (DDB counters + IaC drift), [[autopatrol-cleanup-lambda]] (entity), [[2026-05-07_handoff-cleanup-lambda-interpretive-checks]].

## §14 — Midnight arm-miss race  *(scoped, UNIMPLEMENTED; [actuate_admin#2310](https://github.com/aegissystems/actuate_admin/issues/2310))*
**Bug:** override start fires at 23:55 EDT but execution slips past midnight → `croniter` schedules the arm for *next* week; the site doesn't arm. Three-part race in `schedule_processor.py` / `override_timer.py` / `schedule_deployer.py`; root cause = midnight congestion (every `has_pre_start` site reboots at 00:00; Django Q drops to 10 replicas).
- **Fix path (sequenced):** (1) **Infra quick-win** — `scalerReplicasArmDown: 20` in `kubernetes-deployments` djangoq cluster-values (1-line, high value); (2) **Code Option A** — in `deploy_schedule_changes`, detect `is_override && is_running` → trigger the start action directly; tests for midnight-today / midnight-tomorrow / mid-day / end. Verify against connector-16031 / schedule 197068 on stage.
- **Detail:** mark-todos §14 + issue #2310's 4 comments (jacob-aegis's analysis).

## §2 — Alert-flow diagnostic gaps  *(waiting on Immix)*
- **vms-connector#1658** — dev.powerplus.com SSL cert chain (option-3 fallback: pin Sectigo intermediate). [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]].
- **vms-connector#1656** — `streamId: null` on `raise_patrol_alert` (waiting on Immix preferred remediation).
- Both surface as "cameras offline" in the healthcheck UI; per-failure-mode status differentiation is a future workstream.

## Handoff mechanics
- **Jira:** the cleanup-Lambda verify work + arm-miss (#2310) should land on **Brad** (or whoever owns AutoPatrol post-Mark). Confirm with Brad; if he can't take the cleanup-Lambda internals, the design + playbook notes above are the substitute for tribal knowledge.
- **One walkthrough** (Mark + Brad, ~45 min) on the cleanup-Lambda state machine + the `/autopatrol-cleanup-lambda-check` runbook would de-risk the verify-only handoff.
- **Don't-drop:** the §14 infra quick-win (`scalerReplicasArmDown: 20`) is a 1-line, high-value change that stands alone — easy first win for the inheritor.

## Related
- [[2026-06-22_offboarding-plan]] · [[2026-06-22_manual-action-checklist]] · [[autopatrol-deferred-backlog]] · [[todo-list|AutoPatrol team todo-list]]
