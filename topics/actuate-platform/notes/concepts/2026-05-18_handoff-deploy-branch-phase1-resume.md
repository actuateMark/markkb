---
title: "Handoff: §29 deploy-branch API Phase 1 — resume 2026-05-18"
type: concept
topic: actuate-platform
tags: [handoff, deploy-branch, customer-api, phase-1, internal-test-deploy-lane, eng-247, in-progress]
created: 2026-05-18
updated: 2026-05-18
author: kb-bot
incoming:
  - topics/admin-api/notes/syntheses/2026-05-20_deploy-branch-full-scope.md
  - topics/personal-notes/notes/daily/2026-05-15.md
  - topics/personal-notes/notes/daily/2026-05-18.md
  - topics/personal-notes/notes/daily/2026-05-19.md
incoming_updated: 2026-05-27
---

# §29 deploy-branch API — Phase 1 mid-stream handoff (2026-05-18)

Supersedes [[2026-05-13_handoff-deploy-branch-phase1]]. The Friday-2026-05-15 afternoon session began Phase 1 in earnest but ran out of session before endpoint bodies landed. Pick up from the WIP commit on the local branch.

## Entry point — read these in order

1. This file (you are here).
2. [[2026-05-12_internal-test-deploy-lane]] — design synthesis with endpoint contract + schema deltas.
3. [[2026-05-13_handoff-deploy-branch-phase1]] — original Phase-1 plan (the substantive next-steps list still applies).
4. Local commit on `feat/customer-deploy-branch-api` — see "Current state" below.

## Current state (2026-05-18)

- **Branch:** `feat/customer-deploy-branch-api` in `actuate_admin`. **Not pushed.** Tip is local-only WIP commit `b0ce8cb0` on top of staging-merge commit `cdb24f53`.
- **Friday 2026-05-15 deliverables that landed elsewhere:**
  - **PR [#77](https://github.com/aegissystems/actuate-inference-api/pull/77) — merged to develop.** Refined `detect_motion` response shape: `stationary` always populated, `reason` (benign skip) vs `error` (real failure) split. See [[2026-05-14_v5-motion-history-single-frame-design#contract-refinement-2026-05-15-pr-77]].
  - **PR [#78](https://github.com/aegissystems/actuate-inference-api/pull/78) — merged to develop.** Per-detection `stationary_detection` + `stationary_object` tags via S3-cached prior frame + new sibling-JSON cache of prior detections. Live-verified on dev-api with the partner parking-lot JPEG: cold call → no tags, two warm calls → all 6 detections tagged with both. PR #60 cutover today picks both up automatically.
- **§29 Customer-side scaffold (1 WIP commit on the branch):**
  - `inframap/sites/customer/customer_model.py` — two new nullable fields on `Customer`:
    - `image_tag_override_expires_at: DateTimeField(null=True, blank=True)`
    - `pre_custom_deployment_phase: CharField(max_length=20, null=True, blank=True)`
  - `inframap/migrations/0546_customer_deploy_branch_override_fields.py` — focused migration with only the 4 AddField operations (Customer + historicalcustomer × 2 fields). Hand-curated to exclude the unrelated timezone-choice alters Django proposed in the same `makemigrations` run.
  - `inframap/sites/customer/branch_deployment_event_model.py` — FK corrected from `"sites.Customer"` to `"inframap.Customer"` (the original lazy-reference was unresolvable, which is why makemigrations had never picked the model up since 2026-05-13).
  - `inframap/admin.py` — added `import BranchDeploymentEvent` (with `# noqa: F401`) so Django registers the model in the inframap app namespace.
- **Scaffold from 2026-05-13 still in place (untouched):**
  - `api/serializers/site/customer_deploy_branch_view.py` — `DeployBranchActionMixin` with `deploy_branch` / `revert_branch` / `branch_status` `@action`s, `NotImplementedError` bodies, superuser guard on the two mutators.
  - `inframap/sites/customer/branch_deployment_event_model.py` — full `BranchDeploymentEvent` model (now Django-registered after this session's FK fix + import).
  - `inframap/management/commands/expire_custom_branches.py` — `expire_custom_branches` mgmt command shell, `NotImplementedError` body.
  - `api/tests/test_customer_deploy_branch.py` — pytest.skip stubs (16 of them) covering the endpoint contract.

## Pre-condition: BranchDeploymentEvent table is not yet in any migration

The audit model is now Django-registered (this session's commit), but its table-creation migration was never generated because makemigrations couldn't see the model previously. **First step on resume: regenerate the migration**, which will pick up the `BranchDeploymentEvent` `CreateModel` operation. Verify the new migration only has that one op (plus possibly a historical-mirror table if django-simple-history is wired for it — check).

```bash
cd /home/mork/work/actuate_admin
# Refresh creds first — see Gotchas below
set -a; source .env; set +a
COVERAGE=1 uv run python manage.py makemigrations inframap
```

Expect a new migration `0547_branchdeploymentevent.py` (or similar). Inspect, commit as a separate commit on the branch, push together at the end.

## Next steps in order

1. **Refresh creds** (see Gotchas).
2. **`uv sync`** to ensure local venv has current packages.
3. **`makemigrations inframap`** — generate the `BranchDeploymentEvent` table migration. Commit as a separate commit.
4. **Implement endpoint bodies** in this order:
   - `branch_status` first (read-only — safest validation path).
   - `deploy_branch` next (workhorse: resolve/create `ConnectorVersion(tag=image_tag)`, snapshot deployment_phase into `pre_custom_deployment_phase`, set `deployment_phase=CUSTOM` + `image_tag_override_expires_at`, save, `ConnectorController(customer).reboot_connector(is_manual_action=True)`, write `BranchDeploymentEvent(action="deploy", ...)`).
   - `revert_branch` last (restore `pre_custom_deployment_phase`, clear override, reboot, audit row).
5. **Wire `DeployBranchActionMixin`** into `CustomerViewSet` bases at `inframap/sites/customer/customer_view.py:145`.
6. **Implement `expire_custom_branches` cron body** — share revert logic with the endpoint via a small helper. Scheduler wiring is a follow-up.
7. **Fill 16 test stubs** in `api/tests/test_customer_deploy_branch.py`. Run with `COVERAGE=1 uv run pytest api/tests/test_customer_deploy_branch.py -v` per `actuate_admin/CLAUDE.md`.
8. **Write the Seam-A 1-pager ADR** at `topics/admin-api/notes/syntheses/2026-05-18_adr-seam-a-deployment-config.md`. Per Friday's call: in-place today; capture the extraction plan + revisit conditions (post AI-184 / `f1ad8fcb` cluster maturity). Cross-link: [[2026-05-13_customer-model-dissection]] (recommends Seam D pilot before A).
9. **Push branch + open PR targeting `staging`.** Mind squash-commit-message rules in global CLAUDE.md (no CI-skip token forms anywhere in the message — paraphrase if reference is needed).

## Gotchas

- **AWS SSO token expired** at end of Friday's session. Refresh with `aws sso login --profile prod` (interactive — user terminal).
- **CodeArtifact token convention** for `actuate_admin`: the project's `pyproject.toml` declares the index as `name = "private-registry"`. The right env vars are `UV_INDEX_PRIVATE_REGISTRY_USERNAME=aws` + `UV_INDEX_PRIVATE_REGISTRY_PASSWORD=<token>` (uppercase, underscores), not `UV_INDEX_CODEARTIFACT_*`. The `~/.config/uv/uv.toml` global config also stashes a token under index name `codeartifact` — easy to confuse the two.
- **.env must be sourced before `uv run`** — Django reads `SECRET_KEY` from os.environ, not via python-dotenv. `set -a; source .env; set +a` before any management command. STAGE=local in the .env is correct for makemigrations.
- **makemigrations may also propose unrelated `timezone` choice alters** on `Customer/Group/HistoricalCustomer/HistoricalGroup/HistoricalServer/Location/Server`. These are noise from a Django/zoneinfo upgrade pending elsewhere — **do not include them in this PR**. The 0546 migration was hand-curated to exclude them; do the same for the BranchDeploymentEvent migration if Django bundles them in.
- **`ConnectorController(customer).reboot_connector(is_manual_action=True)`** is referenced in the deploy_branch docstring but unverified. Confirm the method exists (likely `inframap/sites/customer/connector_controller.py` or similar) before assuming the signature.
- **Don't push the branch until at least the test stubs are filled** — the scaffold + WIP commits aren't useful in isolation.
- **Squash-commit message hygiene** for the eventual PR: never write the literal CI-skip token text in any PR body or commit message, even in instructional prose. Paraphrase only ("the CI-skip markers"). The auto-generated bump commits embed these tokens — strip from the squash body entirely. See `feedback_ci_skip_tokens_anywhere.md` in memory.

## ENG-247 cross-cutting decision (carry-forward from 2026-05-13 handoff)

Still open. §29 is a fresh 3-endpoint API surface; worth deciding **now** rather than in the Phase 3 sweep:

- **Option A:** Declare scopes now — `customer:deploy_branch` / `customer:revert_branch` / `customer:branch_status` (~2h additional work; sets ENG-247 precedent on a small in-hand surface).
- **Option B:** Ship under `legacy_full` scope, annotate in Phase 3 sweep — 0h now, 3 endpoints of mop-up later.

See [[2026-05-13_dig-followups]] for the scope-vocabulary scale finding (89 view classes in admin, only 7 use TokenAuthenticationStrict today).

## Today's calendar context (2026-05-18)

PR #60 (develop → main, v5 prod release) is the headline event for today. §29 work is secondary to that. If the next session needs to choose, drive PR #60 cutover first. §29 has no hard deadline.

## Other Friday-wrap follow-ups (not on this branch, separate tracks)

- EU region int07 model swap + prod tfvars int07 swap (post-cutover).
- New E2M rules for per-camera + detect_motion dimensions in `EventsToMetricRules.graphql`.
- Dashboard signals for new E2M rules (§9 discipline rule — value-validation at signal creation).
- NR account-ID resolution (7081731 vs 3421145) — still unresolved.
- `actuate_camera_id`-backed E2M rule creation.
- `chore(v4)` issue for `infer_intruder_plus_with_vehicle_sequence` lost `logger.append_keys(request_id=id)`.
- Confluence sync (PR #67) silent-403'ing — pre-existing, not in this session's scope.
- Tooling stash: `generate_api_key.py --v5_detect` flag + parity scripts — small follow-up PR.

## Local environment state at session wrap

- `actuate_admin` branch `feat/customer-deploy-branch-api` has 1 WIP commit (`b0ce8cb0`) on top of staging-merge; **not pushed**.
- `actuate-inference-api` was on `chore/add-write-external-docs-skill` at session end — unrelated to this work, leftover from prior session.
- **Local v5 dev server still running on port 8000** (uvicorn, started 2026-05-15 for the per-detection-tag demo verification). Background task id `byj8i0p2o`, log at `/tmp/v5-dev-server.log`. Kill if not needed today.

## Links

- Branch: `feat/customer-deploy-branch-api` in [[actuate_admin]]
- Design: [[2026-05-12_internal-test-deploy-lane]]
- Prior handoff (superseded): [[2026-05-13_handoff-deploy-branch-phase1]]
- Related syntheses:
  - [[2026-05-13_customer-model-dissection]] — Seam-A decision context
  - [[2026-05-13_v8-release-postgres-context]] — AI-184's incoming Customer FK
  - [[2026-05-13_dig-followups]] — ENG-247 cross-cutting context
  - [[2026-05-14_v5-motion-history-single-frame-design]] — detect_motion feature (now production-bound on PR #60 via PRs #77, #78)
- Adjacent: ENG-247 — scope-annotation precedent question
- mark-todos §29 entry: `topics/personal-notes/notes/entities/mark-todos.md`
