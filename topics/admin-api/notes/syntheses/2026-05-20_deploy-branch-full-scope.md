---
title: "§29 deploy-branch — full scope, CI/CD-integrated lifecycle"
type: synthesis
topic: admin-api
tags: [admin-api, deploy-branch, customer-api, ci-cd, vms-connector, lifecycle, eng-269, adr, design]
created: 2026-05-20
updated: 2026-05-20
author: kb-bot
outgoing:
  - topics/actuate-platform/notes/syntheses/2026-05-12_internal-test-deploy-lane.md
  - topics/actuate-platform/notes/concepts/2026-05-18_handoff-deploy-branch-phase1-resume.md
  - topics/admin-api/notes/concepts/2026-05-20_actuate-admin-local-bringup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/actuate-platform/notes/entities/branch-conventions.md
  - topics/admin-api/notes/concepts/2026-05-20_actuate-admin-local-bringup.md
  - topics/admin-api/notes/concepts/2026-05-21_deploy-branch-e2e-cycle-verified.md
  - topics/admin-api/notes/entities/actuate-admin-safe-test-sites.md
  - topics/admin-api/notes/entities/admin-api-auth.md
  - topics/personal-notes/notes/daily/2026-05-21.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_cv2-dst-soak-status.md
incoming_updated: 2026-05-27
---

# §29 deploy-branch — full scope, CI/CD-integrated lifecycle

> **Status (2026-05-21):** **Local end-to-end cycle VERIFIED** — see [[2026-05-21_deploy-branch-e2e-cycle-verified]]. Cycle: STAGE customer → `register_branch` → `deploy_branch` → `delete_branch` orchestrator → customer flipped back to STAGE. All 4 audit events written. Safe-test-site gate codified at [[actuate-admin-safe-test-sites]] (STAGE under Actuate root group id=641). Outstanding before merge: `expire_custom_branches` cron body, `ConnectorController` constructor signature fix, fill 16 test stubs + add ~20 new tests, Seam-A ADR.
> **Status (2026-05-20):** Scope expanded beyond the original 2026-05-12 design. Admin running locally on `localhost:8001` for end-to-end testing (see [[2026-05-20_actuate-admin-local-bringup]]). Customer-side model fields + migration `0546` landed on local DB. Migration `0547_custombranch_branchdeploymentevent` (hand-curated, both models + indexes in one file) applied. Endpoint bodies + `CustomBranchViewSet` + mixin wiring complete.
> **Workstream:** [[mark-todos|§29]]. **Jira:** ENG-269.
> **Supersedes (in part):** [[2026-05-12_internal-test-deploy-lane]] (original 3-endpoint design — still valid for the per-customer surface; this note adds the branch-scoped surface, site-cleanup semantics, and CI/CD lifecycle).
> **Order of work:** local-first. **Do NOT wire anything into CI/CD until the full endpoint family is exercised end-to-end locally with passing tests.**

## What changed since 2026-05-12

The original design (`internal-test-deploy-lane`) was a per-customer surface only:

1. `POST .../{customer_id}/deploy_branch/` — assign tag to one customer
2. `POST .../{customer_id}/revert_branch/` — revert one customer
3. `GET .../{customer_id}/branch_status/` — read one customer's state
4. `expire_custom_branches` cron — TTL hygiene per-customer

Field gaps surfaced when we tried to operationalize this against an actual feature-branch lifecycle:

- **No first-class "custom branch" object.** A custom branch today is implicit — it's just an `image_tag` string attached to one or more `Customer.connector_version` FKs. We can't ask "which sites are on `feature-1234-foo` right now?" without a `SELECT ... GROUP BY tag` against the fleet. We can't cleanly delete a branch and walk its dependents.
- **No bulk cleanup.** When a vms-connector feature branch gets merged and the image tag is no longer published, sites pinned to that tag silently rot — pods crash-loop on missing-image until someone notices. The original TTL covers individual expiries but nothing handles the "branch went away" case.
- **No upstream signal.** CI/CD doesn't tell admin when a branch is born or dies. Today this is purely manual — an operator must remember to flip sites back when work is merged.

## Expanded scope — full lifecycle

### A. Per-customer surface (unchanged from 2026-05-12)

| Endpoint | Verb | URL | Purpose |
|---|---|---|---|
| `deploy_branch` | POST | `/api/customers/{id}/deploy_branch/` | Pin a customer to an image tag with TTL |
| `revert_branch` | POST | `/api/customers/{id}/revert_branch/` | Restore `pre_custom_deployment_phase` |
| `branch_status` | GET  | `/api/customers/{id}/branch_status/` | Read effective image + history |

Bodies / schema deltas / save-hook behavior all per [[2026-05-12_internal-test-deploy-lane]].

### B. Branch-scoped surface (NEW)

A custom branch becomes a first-class object. Promote `image_tag` from an implicit string to a `CustomBranch` model — owns its own lifecycle, expiry, and the cleanup orchestration.

**New model: `CustomBranch`**

| Field | Type | Purpose |
|---|---|---|
| `image_tag` | `CharField(max_length=128, unique=True)` | The feature-branch image tag — primary identity |
| `source_repo` | `CharField(max_length=64, null=True)` | `vms-connector` / `actuate-libraries` (for provenance + cleanup webhook routing) |
| `source_ref` | `CharField(max_length=128, null=True)` | e.g. `refs/heads/feature/foo-1234`, `pull/1700/head` |
| `created_by` | `FK(User)` | The CI bot or operator who registered the branch |
| `created_at` | `DateTimeField(auto_now_add=True)` | Provenance |
| `expires_at` | `DateTimeField` | TTL — default `created_at + 7d`, configurable per branch |
| `status` | `CharField` | `active` / `expired` / `deleted` (status-only — actual site state lives on `Customer`) |
| `notes` | `TextField(null=True, blank=True)` | Free-form (PR link, ticket, reason) |

**New endpoints:**

| Endpoint | Verb | URL | Purpose |
|---|---|---|---|
| `register_branch` | POST | `/api/custom_branches/` | CI-bot calls on feature branch create |
| `branch_detail` | GET  | `/api/custom_branches/{tag}/` | List active assignments (which customers are on this tag) |
| `list_branches` | GET  | `/api/custom_branches/` | Active + recently expired/deleted (paginated) |
| `delete_branch` | POST | `/api/custom_branches/{tag}/delete/` | The cleanup orchestrator — marks branch deleted AND iterates dependent customers to flip them back. Replaces today's manual remediation. |
| `extend_expiry` | POST | `/api/custom_branches/{tag}/extend/` | Bump expiry — for long-running customer tests |

**`delete_branch` semantics** (the cleanup core):

1. Resolve `CustomBranch` by tag. Mark `status=deleted`.
2. Query `Customer.objects.filter(deployment_phase="CUSTOM", connector_version__tag=tag)`.
3. For each matched customer, run the same revert logic as `revert_branch` endpoint (factor into `_revert_customer_to_pre_custom_phase(customer, reason)` helper):
   - Read `pre_custom_deployment_phase` (default `PROD`).
   - Set `deployment_phase` to that, `connector_version=None`, `image_tag_override_expires_at=None`.
   - Save (triggers the K8s namespace switch + image flip).
   - `ConnectorController(customer).reboot_connector(is_manual_action=True)`.
   - Write `BranchDeploymentEvent(action="revert", reason=f"branch_deleted:{tag}", ...)`.
4. Return summary: `{branch_tag, sites_flipped: N, errors: [...]}`.
5. Body-side audit row: `BranchDeploymentEvent(action="branch_deleted", customer=None, image_tag=tag, ...)`.

**Idempotency:** if `status=deleted` already, return 200 with zero-effect summary. If a customer in the loop fails to revert (e.g. deployer unreachable), record the error in the summary but continue — partial cleanup beats abort-on-first-error.

### C. TTL cleanup (extended)

`expire_custom_branches` mgmt command becomes a two-phase pass:

**Phase 1 — per-customer TTL (existing behavior):**
- Find customers whose `image_tag_override_expires_at < now()` and revert them individually.
- Audit rows tagged `reason="ttl_expiry"`.

**Phase 2 — per-branch TTL (NEW):**
- Find `CustomBranch.objects.filter(expires_at__lt=now(), status="active")`.
- For each: call the same `delete_branch` orchestrator. This catches branches abandoned without explicit CI cleanup signal.
- Audit rows tagged `reason="branch_ttl_expiry"`.

Run frequency: daily (existing cron infra).

### D. CI/CD integration (gated on local end-to-end pass)

> **EXPLICITLY: do not wire any of this until Section E acceptance criteria are all met.** CI/CD integration is the operationalization phase, not the development phase.

**vms-connector triggers:**

| GH event | Admin call | Notes |
|---|---|---|
| `pull_request: opened` on `feature/*` | `POST /api/custom_branches/` (register) | Body: `{image_tag, source_repo="vms-connector", source_ref, notes=PR URL}`. Expiry default 7d. Run only if the PR's image tag matches a deployable convention (`feature-<branch-slug>` or `pr-<number>`). |
| `pull_request: closed` (merged OR closed) | `POST /api/custom_branches/{tag}/delete/` | Same image-tag derivation. Triggers site cleanup automatically. |
| `pull_request: synchronize` (force-push) | none | The existing branch already covers it — extending expiry is optional polish. |
| (out of band) PR labels like `keep-branch-2w` | `POST /api/custom_branches/{tag}/extend/` | Manual escape hatch. |

**actuate-libraries triggers:**

Library feature branches don't have their own image tag — they get pulled in via `connector_deployer` pins on a vms-connector branch. So the library side doesn't need a separate webhook layer; the vms-connector path covers it transitively. (Revisit if we ever ship per-library connector images.)

**Auth for CI calls:** CI bot uses a dedicated admin-API token with scope limited to `custom_branches:write` (or whatever the ENG-247 scope vocabulary lands on — see open question below).

**Implementation path:**
- GH Actions workflow file in `vms-connector/.github/workflows/admin-custom-branch-sync.yml`.
- Triggers on `pull_request: [opened, closed]`.
- Uses `gh api` or `curl` against admin API. Single-step jobs — no matrices.
- Failures should be non-blocking on the PR pipeline (cleanup is best-effort; the TTL cron is the safety net).

### E. Acceptance criteria — LOCAL-FIRST

Before ANY CI/CD wiring, these MUST pass on the local stack ([[2026-05-20_actuate-admin-local-bringup]]):

- [ ] Migration `0547_branchdeploymentevent` hand-curated and applied locally
- [ ] Migration `0548_custombranch` (or equivalent) hand-curated and applied locally
- [ ] All 5 endpoints in Section B have working bodies (no `NotImplementedError`)
- [ ] All 3 endpoints in Section A have working bodies
- [ ] `DeployBranchActionMixin` wired into `CustomerViewSet`
- [ ] Mgmt command `expire_custom_branches` Phase 1 + Phase 2 bodies implemented
- [ ] **Unit tests:** all 16 existing stubs in `test_customer_deploy_branch.py` filled + passing; new tests added for the 5 branch-scoped endpoints (estimate +20 tests); end-to-end test that creates a `CustomBranch`, attaches 3 customers, deletes the branch, asserts all 3 reverted
- [ ] **Local manual run-through:** working curl/httpie session against `localhost:8001` exercising:
  1. Register a branch
  2. Assign 2 customers to it (via per-customer endpoint)
  3. List the branch, confirm both customers in detail response
  4. Delete the branch
  5. Verify both customers reverted to their `pre_custom_deployment_phase`
  6. Verify `BranchDeploymentEvent` rows for all 5 state changes
- [ ] `ConnectorController.reboot_connector` is **mocked** in tests (we never actually reboot real customers from local). Confirm the mock matches today's call signature in `connector_controller.py:422`.
- [ ] Seam-A 1-pager ADR per [[2026-05-13_customer-model-dissection]] — decision to keep endpoints on `CustomerViewSet` vs extract to a new `DeployBranchViewSet`. Likely "extract" given the surface is no longer customer-scoped.
- [ ] All endpoints behave correctly when the deployer is unreachable (graceful degrade — audit row still written; return 500 with retry guidance).

Only when all of the above pass: proceed to Section D CI/CD wiring as a separate PR.

### F. Test data shape

Local DB has 22,022 customers as of bring-up. For testing:

- Pick 2-3 throwaway / testing customers (Securitas-trial cohort?) to exercise the deploy/revert path.
- DO NOT touch any prod-like customers in local DB — `reboot_connector` is mocked but the audit rows are real.
- Consider creating a fixture file with 3 dummy customers explicitly tagged for `deploy_branch` test runs.

## Open design questions

| # | Question | Default to fall back on |
|---|---|---|
| 1 | Auth scope for CI-bot calls (ENG-247) | Token with `custom_branches:write` scope; per [[2026-05-13_dig-followups]] scope vocabulary. Defer to ENG-247 if the vocabulary isn't ready. |
| 2 | Should branch-delete also delete the `ConnectorVersion` row? | No — keep it for historical traceability; only `CustomBranch.status` flips. |
| 3 | Concurrent deploy_branch + delete_branch — race? | Last-write-wins on `Customer` via DB-level row lock during save; `CustomBranch` is the coordinator and its `status=deleted` should block new deploy_branch assignments. |
| 4 | What about a feature branch whose image was never actually built? | `register_branch` doesn't validate the image exists. We rely on the per-customer `deploy_branch` to fail when the customer's pod can't pull. |
| 5 | Should we capture the GH PR # explicitly on `CustomBranch`? | Yes — adds a `source_ref` field already; PR # extracted from it for UI display. |
| 6 | Cohort opt-in vs per-customer assignment? | Per-customer for v1. Cohort-level is a Section G future enhancement. |

## Section G — future enhancements (not Phase 1)

- **Cohort-level assignment:** `POST /api/custom_branches/{tag}/assign_cohort/` with body `{cohort: "alibi-trial"}` — flips all customers matching the cohort filter. Useful for the original use case (Alibi smoke-test) once the lane is proven.
- **Branch-attachment via PR label:** `deploy-branch:alibi-trial` label on a vms-connector PR auto-triggers cohort assignment.
- **Slack notifications:** post to `#deploys` on register/delete with the cohort affected.
- **UI surface in admin:** list view + per-branch detail; today the API is sufficient.

## File-level inventory — what gets touched

### actuate_admin

| Path | Action |
|---|---|
| `inframap/sites/customer/customer_model.py` | Already touched — fields landed on local DB |
| `inframap/sites/customer/branch_deployment_event_model.py` | Already exists — apply migration 0547 |
| `inframap/sites/custom_branch/custom_branch_model.py` | **NEW** — `CustomBranch` model |
| `inframap/migrations/0547_branchdeploymentevent.py` | **NEW** — hand-curated |
| `inframap/migrations/0548_custombranch.py` | **NEW** — hand-curated |
| `api/serializers/site/customer_deploy_branch_view.py` | Already exists — fill endpoint bodies |
| `api/serializers/custom_branch/` | **NEW** — `CustomBranchViewSet` + serializer |
| `api/urls.py` | **NEW** — register `CustomBranchViewSet` routes |
| `inframap/sites/customer/customer_view.py:145` | Wire `DeployBranchActionMixin` into bases |
| `inframap/management/commands/expire_custom_branches.py` | Already exists — fill Phase 1 + Phase 2 bodies |
| `api/tests/test_customer_deploy_branch.py` | Fill 16 stubs |
| `api/tests/test_custom_branch.py` | **NEW** — branch-scoped endpoint tests |
| `api/tests/test_expire_custom_branches.py` | **NEW** — TTL cron test (both phases) |

### vms-connector (Section D — gated)

| Path | Action |
|---|---|
| `.github/workflows/admin-custom-branch-sync.yml` | **NEW** — PR-event webhook to admin |

## Estimate

| Phase | Estimate |
|---|---|
| 0547 + 0548 migrations + model wiring | 1h |
| Per-customer endpoint bodies (Section A) | 2h |
| Branch-scoped endpoints + cleanup orchestrator (Section B) | 3-4h |
| `expire_custom_branches` two-phase body | 1h |
| Unit tests — 16 existing + ~20 new | 3-4h |
| Local manual run-through + smoke fixes | 1-2h |
| ADR (Seam-A) + open-question decisions | 1h |
| **Subtotal — local-first Phase 1** | **~12-15h** |
| Section D CI/CD wiring (separate PR) | 2-3h |

Realistic split: 2-3 focused sessions for Phase 1 local. CI/CD wiring is a small follow-up once acceptance criteria pass.

## Links

- Original design: [[2026-05-12_internal-test-deploy-lane]]
- Local bring-up runbook: [[2026-05-20_actuate-admin-local-bringup]]
- Resume handoff (now superseded by this synthesis as the canonical reference): [[2026-05-18_handoff-deploy-branch-phase1-resume]]
- Customer model dissection (Seam-A context): [[2026-05-13_customer-model-dissection]]
- ENG-247 scope vocabulary context: [[2026-05-13_dig-followups]]
- mark-todos §29 entry: [[mark-todos]]
