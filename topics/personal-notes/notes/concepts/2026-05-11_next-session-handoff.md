---
title: "Handoff — next session after 2026-05-11"
type: concept
topic: personal-notes
tags: [handoff, session-boundary, next-session, billing, fleet-architecture, software-architecture, admin-db-access, pr-1688]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
---

# Handoff — next session after 2026-05-11

Read this, then [[mark-todos]] §28/§5/§6/§17/§20/§3/§29. This handoff is the entry point for the next session.

The prior handoff [[2026-05-11_billing-and-followups-handoff]] is **COMPLETE** (all 8 items closed in one massive session). This successor handoff captures the new state — there's no single hot path now; pick from the menu below based on bandwidth.

## Running operations to check on first

| What | Where | When to check |
|---|---|---|
| **NF2 billing-reconcile timer** | `mork-firebat:~/.config/systemd/user/billing-reconcile-check.timer` (daily 04:00 PT) | Verify first auto-fire produces `~/.local/state/minipc-tasks/billing/reconciliation-2026-05.json` with `exit_status=ok`. Expected ~05:00 ET on 2026-05-12. |
| **PR #1688 soak T+7h re-check** | Scheduled at **02:00Z** (T+7.1h from merge). Tier-1 systemd one-shot on Firebat. | Read `~/.local/state/minipc-tasks/pr-1688-soak/T+7h-*.json` for verdict. T+1h was GREEN on new-code-attributable signals + RED on `dw_url_up_json_decode_errors` (expected, pre-rolling-restart). |
| **PR #1689 (workflow_dispatch recovery triggers)** | vms-connector `chore/add-workflow-dispatch-recovery-triggers` | Open PR awaiting review. Defensive fix for the CI-skip token incident; not urgent. |
| **ENG-242** | Jira | Closed Done. No follow-up expected unless data team re-engages on the SPRD-swap-`IF EXISTS` finding (NF7) or SQL/TF drift (NF8). |

## Menu — pick from these next session

Listed in rough priority order. **No item is critical-path; choose by mood / bandwidth.**

### Tier 1 — Highest value-per-effort

1. **NF3 — share the 803→2024 unbilled-cameras trend with sales-ops.** Demonstrates the system the [[2026-05-11_nf2-deployment-state|NF2 deploy]] just shipped is surfacing real revenue gaps in the wild (4× growth since Feb 2026; signal would have caught Cohort F two months early per [[billing/_todos]] NF9). Tactic: short Slack message to the billing/sales-ops channel with the trend graph + top accounts. Filing target TBD — start by identifying the right channel/audience. **~15-30 min.**

2. **Bundle NF7 + NF8 to data team.** Single Slack message / ENG ticket combining the two actuate_bi findings: (NF7) SPRD daily-swap is not transactional, first RENAME has no `IF EXISTS` guard, clip-swap *does* have it — suggest copying the guard; (NF8) `sql/snowflake/*.sql` drifts silently from deployed Terraform state — suggest a CI drift check OR delete the reference SQL. Both are defense-in-depth; not urgent. **~30 min.**

3. **§9 dashboard — replay tests for 7 historical incidents.** Per [[mark-todos]] §9 Phase 1b — highest-value open item; locks in the "would have caught" promises. NF9's pattern (run wrapper against historical month, compare to current signal threshold) is a working precedent. **~1-2h.**

### Tier 2 — Fleet PoC selection conversation

4. **Surface the rubric ranking + collector findings to the team.** The session-2026-05-11 closures produced two updates the team probably hasn't seen: handoff #4 added M&A + B&R dimensions, and handoff #7's collector revised Migration Risk scores. **E's lead over C widened from 0.45 → 0.675**, with C demonstrably harder than gut-check thought (because connector_factories hub-coupling is real). Worth surfacing before PoC scoping. Output: a tight 1-page Confluence post or Slack message summarizing the addendum. **~30-60 min.**

5. **PoC selection blockers (per [[mark-todos]] §5 carry-over):**
   - Pre-PoC open question — Tier3 replication driver investigation ($44k/year, 11.1% of S3 spend). 1h analyst-level dive into S3 Storage Lens or CUR+Athena.
   - WireGuard/tunnel inventory (blocks Proposal C if material site-share uses it).
   - PyAV GIL budget measurement at frame rate (load-bearing for D/E motion-gate cost case).
   - These are pre-existing fleet items, not new.

### Tier 3 — Sketch workstream (§6) continuation

6. **Next sketch — tech-debt agent OR tooling landscape.** Enforcement sketch (handoff #7) + metrics sketch (2026-04-23) both shipped with findings notes. The remaining 3 of 5 sketches per [[2026-04-17_local-sketches-plan]]:
   - [[2026-04-16_tech-debt-agent|Tech debt agent]] — minimal patrol-and-report pass over one repo. Findings note pattern is established now.
   - [[2026-04-16_tooling-landscape|Tooling landscape]] — pick 2-3 tools (vulture, bandit, pydeps?) from the catalog to actually try locally. Per [[software-architecture/reading-list]] §"Python Static-Analysis Tooling."
   - [[2026-04-16_code-health-dashboard|Code health dashboard]] — wire the dashboard to read from the other sketches so integration points are real. Already has Flask + Chart.js shell; just needs the actual reads.
   - **Pick by mood; each is ~2-4h.** Recommend tooling-landscape if you want quick wins, debt agent if you want a substantial design exercise.

7. **Billing-emit-site pytest sibling.** Per [[2026-05-11_sketch-findings-enforcement]] §"Suggested follow-up — billing-emit-site fitness functions" — import-linter can't fully express the centralization + idempotency-reach checks. Need an AST-walker pytest in `tests/architecture/billing/` per the [[2026-04-16_architecture-enforcement]] §"Architecture Tests (pytest)" pattern. **~2-3h.**

### Tier 4 — Admin DB access hardening (new initiative)

8. **`data-access-control` topic just stood up today** (parallel session). Driven by the Tati↔Mark thread; not on this handoff's critical path but a real multi-quarter workstream. Two team-discussion notes posted: [[2026-05-11_open-question-vini-gateway]] (parallel-but-compatible internal stack vs extend Vini's API GW) and [[2026-05-11_open-question-developer-tokens]] (composition approaches for new admin endpoints). Async items in team brief: `Group → Server CASCADE` (Mark leans SET_NULL), slow-query log verification, Terraformize parameter group. **Wait for team responses before more deep work.**

9. **Admin reliability Tier 1 fixes** (per [[2026-05-11_admin-reliability-fix-plan]]) — 7 fixes, all cheap, none blocked. Headline: BT-926 N+1 has a precedented in-codebase fix (`GroupAdmin._compute_camera_counts()`); just needs replication for `sites()`. CustomerAdmin one-line prefetch adds. Slow-query log status verification (5-min) + Terraformize parameter group (drift-risk follow-up).

## What's quietly running (let it run)

- **NF2 daily timer** — fires 04:00 PT every day. Three dashboard signals on Firebat will reflect the latest reconciliation.
- **PR #1688 soak monitor** — T+7h scheduled 02:00Z. T+1h was GREEN on new code; RED on dw_url_up_json_decode_errors + connector_pod_errors_1h expected pre-rolling-restart (rearch fleet still on old image without #1671 guard).
- **`dashboard-check-rolesanywhere`** — now grants SM:GetSecretValue on `prod/actuate/postgres-*` via inline policy `billing-reconcile-readonly`. Stable; no follow-up.

## Pending unpushed commits

| Repo | Commits | Local-only because |
|---|---|---|
| KB (`master`) | `3784ba7`, `6480922`, `b93512c` (3 commits, 25 files this session) | Personal KB; push at /daily-wrap discretion |
| local_network_scripts (`main`) | `6165a24`, `b8d3ab5` (2 commits) | Toolkit repo; push when ready to share with team |
| software-arch-sketches (`main`) | `8ca62b5` (1 commit) | Personal sketches; not yet pushed to a remote (check if remote exists) |

## Re-eval triggers

This handoff retires when:
- Tier 1 items (NF3, NF7+NF8 bundle, §9 replay tests) are all closed OR explicitly de-prioritized.
- A new bigger fish surfaces (most likely: PoC selection moves to active work, or admin-team responses unblock S1/S2 cascade hooks).
- 7 days elapsed without progress on any item → audit which items are stale.

## Cross-references

- [[2026-05-11_billing-and-followups-handoff]] — predecessor handoff (Status: COMPLETE)
- [[mark-todos]] — workstream tracker; all referenced §N live here
- Today's daily note [[2026-05-11]] — 19+ closures captured under `## Closed Line Items`
- [[billing/_todos]] — billing topic todos with NF1-NF10 follow-ups
- [[2026-05-11_nf2-deployment-state]] — current state of the deployed billing-reconciliation signal
- [[2026-05-11_sketch-findings-enforcement]] — handoff #7 collector findings + calibration caveats
- [[2026-05-11_rubric-monitoring-billing-dimensions]] — fleet rubric extension + collector MR addendum
- [[2026-05-11_admin-db-access-hardening]] — new multi-quarter initiative scaffolded today
- PR #1688 (vms-connector, merged), PR #1689 (vms-connector, open) — recent connector chain
- ENG-242 (Jira, Done) — closed same-day via sales-dashboard + actuate_bi inventory
