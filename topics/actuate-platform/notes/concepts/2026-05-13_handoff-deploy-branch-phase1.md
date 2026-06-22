---
title: "Handoff: §29 deploy-branch API Phase 1 (2026-05-13 EOD)"
type: concept
topic: actuate-platform
tags: [handoff, deploy-branch, customer-api, phase-1, internal-test-deploy-lane, eng-247]
created: 2026-05-13
updated: 2026-05-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/concepts/2026-05-18_handoff-deploy-branch-phase1-resume.md
  - topics/personal-notes/notes/daily/2026-05-13.md
incoming_updated: 2026-05-27
---

# §29 deploy-branch API — Phase 1 handoff (2026-05-13 EOD)

Carry-forward for tomorrow's `/daily-scope` pickup. Scaffolded but paused at end of day; Phase 1 impl deferred to 2026-05-14.

## Entry point

Start here: [[2026-05-12_internal-test-deploy-lane]] — design synthesis with endpoint contract, schema deltas, scaffolded file inventory.

## Current state

- **Branch:** `feat/customer-deploy-branch-api` in `actuate_admin`, off `origin/staging` tip `ab5f93e0`. **Not pushed.**
- **Commit:** `7ed88a36 feat(deploy-branch): scaffold ...` — 4 files / 278 insertions:
  - `api/serializers/site/customer_deploy_branch_view.py` — `DeployBranchActionMixin` with `deploy_branch` / `revert_branch` / `branch_status` `@action`s. `NotImplementedError` stubs. Superuser guard on the two mutators.
  - `inframap/sites/customer/branch_deployment_event_model.py` — `BranchDeploymentEvent` audit-row model (`action`, `image_tag`, `pre_custom_deployment_phase`, `expires_at`, `reason`, `user` FK, `created_at`, indexes on `(customer, -created_at)` and `(-created_at)`).
  - `inframap/management/commands/expire_custom_branches.py` — `expire_custom_branches` Django mgmt command with `--dry-run` and `--customer-id` flags. `NotImplementedError` body.
  - `api/tests/test_customer_deploy_branch.py` — pytest.skip stubs for the endpoint contract.

- **Stakeholder pings** descoped 2026-05-13 (user call). Going direct to impl.

## Next steps in order

1. **Decide: extend `Customer` in-place vs start Seam A extraction.** Per [[2026-05-13_customer-model-dissection]], "deployment configuration" is the highest-leverage seam to split, and both §29 and AI-184 (incoming Sensitivity FK) and the recent `f1ad8fcb` regression all cluster there. In-place is fast (~hours); extraction compounds (multi-day, also helps AI-184). Decide before model edits land — once a migration ships with the fields on `Customer`, the extraction cost goes up.
2. **Add 2 fields to `Customer`** at `inframap/sites/customer/customer_model.py`:
   - `image_tag_override_expires_at: DateTimeField(null=True, blank=True)`
   - `pre_custom_deployment_phase: CharField(max_length=20, null=True, blank=True)`
   The `actuate_admin/CLAUDE.md` was updated 2026-05-13 with an explicit `null=True, blank=True` rule for optional string fields (rollout-safety reason: brief window where new column exists but old pods still run, omitting `null=True` causes IntegrityError on writes from lagging pods). Follow it.
3. `python manage.py makemigrations inframap` — inspect output before committing as a separate commit.
4. **Implement endpoint bodies in this order:**
   - `branch_status` first (read-only — validates the read path, no risk of side effects on first run)
   - `deploy_branch` next (the workhorse — assign image tag, snapshot pre-CUSTOM phase, save, reboot, write `BranchDeploymentEvent`)
   - `revert_branch` last (revert flow + audit row)
5. **Wire `DeployBranchActionMixin`** into `CustomerViewSet` bases at `customer_view.py:145`.
6. **Fill the 16 test stubs** in `test_customer_deploy_branch.py` against the live endpoint. Run with `COVERAGE=1 uv run pytest api/tests/test_customer_deploy_branch.py -v` per CLAUDE.md.
7. **Defer to a separate synthesis (not this PR):** vms-connector GHA auto-revert hook design. Open questions: branch-delete event vs. branch-merge event; idempotency; per-customer vs batch; partial-failure semantics when revert fails for one customer in a batch.

## ENG-247 cross-cutting decision

§29 is a fresh 3-endpoint API surface. Worth deciding **now** rather than in the Phase 3 sweep:

- **Option A: Declare scopes now.** `customer:deploy_branch` / `customer:revert_branch` / `customer:branch_status` (~2h additional work; sets the ENG-247 precedent on a small in-hand surface).
- **Option B: Ship under `legacy_full` scope, annotate in Phase 3 sweep.** 0h now, but 3 endpoints worth of mop-up later when the scope vocabulary is finalized.

See [[2026-05-13_dig-followups]] for the broader scope-vocabulary scale finding (89 view classes in admin, only 7 use TokenAuthenticationStrict today).

## Gotchas

- The `customer_deploy_branch_view.py` deploy_branch docstring references `ConnectorController(customer).reboot_connector(is_manual_action=True)`. Verify that's a real method when implementing (likely `inframap/sites/customer/connector_controller.py` or similar); the design synthesis assumes it exists.
- `BranchDeploymentEvent` references `"auth.User"` as the user FK target via string-app-label — admin uses Django's default User model so this should be fine, but worth verifying the migration generates clean.
- The `expire_custom_branches` cron is not wired into Django's scheduler yet — it's just the command. Scheduler wiring is a separate task once the body is implemented.
- Don't push the branch until at least Step 6 (tests filled) — the scaffold-only commit isn't useful in isolation.
- When eventually opening the PR, target `staging`. Mind the squash-commit-tag rules in global CLAUDE.md (e.g. no CI-skip tokens anywhere in the message).

## Links

- §29 in mark-todos: `topics/personal-notes/notes/entities/mark-todos.md`
- Design: [[2026-05-12_internal-test-deploy-lane]]
- Sibling syntheses written 2026-05-13:
  - [[2026-05-13_customer-model-dissection]] — Seam A decision context
  - [[2026-05-13_v8-release-postgres-context]] — AI-184's incoming Customer FK
  - [[2026-05-13_dig-followups]] — ENG-247 cross-cutting context
- Scaffold commit: `7ed88a36`
- Branch: `feat/customer-deploy-branch-api` ([[actuate_admin]], off `origin/staging`)
- Adjacent: ENG-247 — scope-annotation precedent question
