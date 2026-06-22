---
title: "v8 Intruder Rollout: Postgres Impact & Unassigned Schema Work"
type: synthesis
topic: models/intruder-v8
tags: [v8-intruder, ai-180, ai-211, postgres, actuate-admin, schema-changes, model-registry, blocker-cleared]
jira: AI-180
created: 2026-05-13
updated: 2026-05-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/concepts/2026-05-13_handoff-deploy-branch-phase1.md
  - topics/actuate-platform/notes/concepts/2026-05-18_handoff-deploy-branch-phase1-resume.md
  - topics/admin-api/notes/syntheses/2026-05-13_customer-model-dissection.md
  - topics/personal-notes/notes/daily/2026-05-13.md
incoming_updated: 2026-05-27
---

# v8 Intruder Rollout: Postgres Impact & Unassigned Schema Work

**The headline:** AI-211 (YAM re-evaluation blocker) resolved 2026-04-13 by Vlad. All 6 AI-180 sub-tasks remain To Do and unassigned. The KB summary claims "13 sub-tasks"—actual count is 6. No deployment lead assigned yet.

## Current State vs. KB Summary

The topic's `_summary.md` (updated 2026-04-14) claims "13 sub-tasks" for the AI-180 rollout epic. Actual sub-task inventory shows 6 tickets in Medium priority, all unassigned, all To Do. Either the April snapshot conflated related work or sub-tasks were consolidated. **Action:** flag summary for refresh (separate task; won't block this).

The critical blocker, AI-211 (YAM re-evaluation after chip-generation change to original-frame), **cleared 2026-04-13** when Vlad completed the re-baseline. The KB correctly identified it as "highest priority" — that was right. Now it's resolved, and nothing has picked up the schema work.

## The 6 Unassigned Sub-tasks

| Ticket | Work | Schema Touch | Notes |
|---|---|---|---|
| **AI-181** | Deploy v8 endpoint in EKS | None | Standard `ds-model-prod` namespace, follows `int07-actuate003-v8-svc` pattern from summary. Infra-only. |
| **AI-182** | Configure pilot customer sites | Light | Likely a per-customer flag or cohort. Could reuse existing `deployment_phase` or new admin-feature flag. See risk below. |
| **AI-183** | Extend AIModel metadata | **Yes** | Adds `deploy_date`, `architecture`, `version`, `classes` (JSONField), `weights_location`. Foundation for downstream tasks. |
| **AI-184** | Model-aware sensitivity w/ scope overrides | **Yes + FK** | Adds `ai_model` FK, `customer` FK, `group` FK, `lead` FK to `Sensitivity`. Enables per-customer/group/lead threshold tuning. **Touches Customer row — coordinate with §29 if same migration.** |
| **AI-185** | Decouple raw metrics from AIModel | **Yes, load-bearing** | Restructures `Stream → RawMetric → MetricLabel → AIModel` chain. Moves default-model assignment from direct FK to separate mapping table. High migration risk; may need shadow-table cutover. |
| **AI-186** | Bulk model swap tooling + audit trail | **Yes** | Adds audit log table (`timestamp`, `user`, `old_value`, `new_value`). ~2000+ intruder streams to migrate v5→v8 cutover. Depends on AI-185 chain working. |

## Ordering & Dependencies

- **AI-183 → AI-184:** Metadata fields in AIModel are prerequisites for the scope-override logic in Sensitivity.
- **AI-185 → AI-186:** The load-bearing chain restructure must land before bulk swap tooling (AI-186 relies on the new chain for its repoint logic).
- **AI-182 (pilot) ↔ AI-184 (model-aware thresholds):** If pilots use per-customer overrides, AI-184 must land first or pilots can't configure. If pilots use simpler cohort flags, can run in parallel.
- **AI-184 + §29 coordination:** Customer FK on Sensitivity — if both the v8 rollout and the deployment-branch work land in the same admin migration cycle, need explicit coordination on the Customer row schema.

## Recent Admin Precedents (Last 60 Days)

- `f1ad8fcb` — fixed custom-tag regression when `deployment_phase` flips to PROD. Relevant if AI-182 reuses CUSTOM phase for pilot sites.
- AUTO-551 chain (`27b2514c`, `d5f2b34f`, etc.) — added VLM-per-camera flag scoping. Precedent for per-camera/per-customer model config; similar problem space to AI-184 generalizing scope overrides.
- `51e494d2` — moved `endpoint_stage` + `queue_stage` onto Customer row. Signals the model team still consolidates per-customer config inline rather than factoring into separate tables. Tension with AI-184's design choice (separate Sensitivity row w/ FKs vs. inline fields).

## Owner & Escalation

- **[[vlad-sapeshka|Vlad Sapeshka]]** — finished YAM re-eval; owns v8 DS readiness. Talk to first for AIModel metadata changes and their downstream implications.
- **[[zack-schmidt|Zack Schmidt]]** — broader YAM epic (AI-158). Drives v5→v8 cutover decision and likely owns assigning these 6 sub-tasks.
- **No explicit deployment lead yet** — that's the missing role. One of these sub-tasks (probably AI-184 or AI-185 given their Postgres touch) should have a single owner.

## Outstanding Questions

1. **AI-184 ownership:** This adds Customer FK to Sensitivity. If admin-side, might be Mark's pickup. If DS-side, needs coordination check.
2. **AI-185 migration strategy:** "Load-bearing infrastructure" suggests careful staging. Shadow table + cutover? Or direct migration?
3. **AI-186 audit format:** Does it generalize the AUTO-551 / `b56c0343` `simple_history` pattern, or a new event log like §29's `BranchDeploymentEvent`?
4. **AI-182 pilot mechanism:** Explicit cohort table, AdminFeature flag, `deployment_phase = CUSTOM`, or new? §29 is building deploy_branch/revert_branch surface — could pilots ride on that?

## Recommended First Move

**Ping [[zack-schmidt|Zack Schmidt]]** to clarify who owns the AI-180 sub-task assignments now that AI-211 cleared. If no one's named, propose assigning Mark to AI-184 (overlaps Customer model + §29 coordination needs). Lock the owner before schema code to avoid fragmentation across the v5→v8 migration.

## Related

- [[models/intruder-v8/_summary]] — topic summary (flagged for refresh: claims 13 sub-tasks; actual 6)
- [[models/intruder-v5]] — predecessor model
- [[ai-models/_summary]] — model evaluation methodology
- [[vlad-sapeshka]] — YAM re-eval owner
- [[zack-schmidt]] — YAM epic owner
- [[actuate-admin]] — schema context

## See Also

- Jira AI-180, AI-211, AI-181–186
- **ENG-247** — Research: move away from raw SQL access to postgres in non-admin contexts. v8's 4 Postgres-impacting sub-tasks (AI-183/184/185/186) are an opportunity to set the access-pattern precedent rather than ship four more raw-SQL callers.
- `topics/personal-notes/notes/entities/mark-todos.md` — escalation coordination (flag which §N if this blocks a workstream)
