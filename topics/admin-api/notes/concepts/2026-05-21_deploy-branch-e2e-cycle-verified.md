---
title: "§29 deploy-branch — end-to-end cycle verified locally"
type: concept
topic: admin-api
tags: [deploy-branch, e2e, local-dev, runbook, eng-282, custom-branch, verified]
created: 2026-05-21
updated: 2026-05-21
author: kb-bot
outgoing:
  - topics/admin-api/notes/syntheses/2026-05-20_deploy-branch-full-scope.md
  - topics/admin-api/notes/concepts/2026-05-20_actuate-admin-local-bringup.md
  - topics/admin-api/notes/entities/actuate-admin-safe-test-sites.md
incoming:
  - topics/admin-api/notes/concepts/2026-05-20_actuate-admin-local-bringup.md
  - topics/admin-api/notes/entities/actuate-admin-safe-test-sites.md
  - topics/admin-api/notes/syntheses/2026-05-20_deploy-branch-full-scope.md
  - topics/personal-notes/notes/daily/2026-05-21.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-27
---

# §29 deploy-branch — end-to-end cycle verified locally (2026-05-21)

> First clean local end-to-end cycle of the [[2026-05-20_deploy-branch-full-scope|expanded §29 scope]]. Pinned a STAGE customer under the Actuate root group onto a feature-branch tag via API, then deleted the branch via API and watched the same customer flip back to STAGE. All audit rows written. This note codifies the **how**, the **safety gate**, and the **failure modes encountered** so the next session reproduces in minutes.

## TL;DR — the verified cycle

| Step | HTTP | What happened |
|---|---|---|
| 1. `POST /api/custom_branches/` (body: `{image_tag, source_repo, source_ref, notes}`) | 201 | `CustomBranch` row created, 7-day TTL by default |
| 2. `POST /api/customer/{id}/deploy_branch/` | 200 | Customer flipped to `deployment_phase=CUSTOM`, `pre_custom_deployment_phase` snapshotted, `BranchDeploymentEvent(action=deploy)` written, `would_deploy` payload returned (mirror of what `reboot_connector` would have sent) |
| 3. `GET /api/customer/{id}/branch_status/` | 200 | Shows CUSTOM phase + last 25 audit rows |
| 4. `GET /api/custom_branches/{tag}/` | 200 | Shows `assignments` (1 customer pinned), `active_customer_count=1` |
| 5. `POST /api/custom_branches/{tag}/delete/` (orchestrator) | 200 | `sites_flipped: 1, errors: []`. Customer flipped CUSTOM → STAGE (the original phase). Branch marked `status=deleted`. |
| 6. Audit trail | — | 4 rows: `register / deploy / revert / branch-deleted` |

End-state: customer back where it started; branch marked `deleted`; complete audit trail captured.

## Safety gate — ALWAYS use STAGE under "Actuate" root group

**Hard rule for any deploy-branch testing:** the candidate customer must satisfy **both**:

1. `deployment_phase == "STAGE"` — never touch a prod/rearch/dev/custom-already site
2. Group ancestry includes the Actuate-owned root group at `id=641` (`Group.objects.get(pk=641).name == "Actuate"`, `parent=None`)

This gate narrows the blast radius even though the local deployer call no-ops (see "Safety mechanism" below). DB writes are real — restrict to fleet you own.

Snapshot of the candidate pool on the local restore (2026-05-21):

```
STAGE customers total: 99
Of which under Actuate (id=641) root: 25
First 5 safe candidates:
  id=705   'Alibi Vigilant'       group_id=10641   cv=111
  id=5353  'Star4Live Test'       group_id=6408    cv=None    ← used in the cycle below
  id=5599  'DEMO 2 (Hikvision)'   group_id=6702    cv=111
  id=5647  'Alibi P2P'            group_id=6774    cv=104
  id=7291  'Openeye Test 1'       group_id=9041    cv=99
```

Full registry of safe candidates + the convention's rationale: [[actuate-admin-safe-test-sites]].

## Safety mechanism — why local-mode DB writes don't reach the fleet

Two layers protect us:

1. **`reboot_connector` short-circuits when `settings.STAGE != "prod"`.** From `inframap/connector/connector_controller.py:430`:
   ```python
   if settings.STAGE != "prod":
       logger.warning(f"Running in {settings.STAGE}, will skip container calls. Faking reboot. ...")
       return
   ```
   Local `.env` sets `STAGE=local`, so the deployer HTTP call never fires. The K8s namespace switch in the Customer save-hook (`customer_model.py:806`) is also a no-op locally — there's no K8s API to call.

2. **`healthcheck_model` runs the same short-circuit** with an INFO line `Running in local, will skip deployer calls. <container_name>`.

Combined effect: even if you accidentally point the cycle at a non-Actuate STAGE site, no real customer pod gets touched. The audit trail will record the cycle, the DB will flip Customer.deployment_phase, but no production traffic shifts. **Treat this as defense-in-depth, not a substitute for the safety gate above.**

## Bring-up + run procedure (reproduce in ~5 min)

Prereqs: [[2026-05-20_actuate-admin-local-bringup]] complete (admin running on `localhost:8001`).

```bash
cd /home/mork/work/actuate_admin
set -a && source .env && set +a

# Demo driver — APIClient.force_authenticate, exercises full URL/view/serializer/ORM stack
PYTHONPATH=. uv run python /tmp/e2e_deploy_branch_demo.py
```

The driver `/tmp/e2e_deploy_branch_demo.py` (committed when the work lands; kept under `/tmp/` during dev):

1. Creates an idempotent superuser `e2e_demo_super`.
2. Filters customers by safety gate (STAGE phase + Actuate root descendant).
3. Picks the first non-pinned candidate (or first one if none unpinned).
4. Generates a unique branch tag `feature-e2e-{uuid8}`.
5. Walks the 6 steps above with assertions at each gate.
6. Prints the audit trail.

On clean run: terminates with `ALL ASSERTIONS PASSED` and the customer is back at its original phase.

## Verified output (2026-05-21 14:56Z run)

```
target customer: id=5353 phase=STAGE connector_version=None current_image_tag=''
branch tag: feature-e2e-f1f321fd

Step 1 (register):  HTTP 201   CustomBranch id=2 created
Step 2 (deploy):    HTTP 200   STAGE -> CUSTOM, pre_phase=STAGE captured
Step 3 (status):    HTTP 200   history shows 1 event
Step 4 (detail):    HTTP 200   active_customer_count=1, assignments=[5353]
Step 5 (delete):    HTTP 200   sites_flipped=1, errors=[]
Step 6 (audit):     4 events: register / deploy / revert / branch-deleted
End-state:          STAGE -> CUSTOM -> STAGE ✓
```

`would_deploy` payload (the dry-run deployer config) returned by `deploy_branch`:

```json
{
  "deployment_id": null,
  "container_name": "actuate-star4live-test-5353",
  "image_tag": "feature-e2e-f1f321fd",
  "lead": "Actuate",
  "deployment_phase": "CUSTOM"
}
```

This mirrors what `reboot_connector` would have sent to `connector_deployer`'s `POST /reboot` in production. Constructed inline in the endpoint because `reboot_connector` short-circuits before building it locally.

## Failure modes encountered + fixes applied

These were discovered driving the cycle on a fresh local DB. The runbook ([[2026-05-20_actuate-admin-local-bringup]]) was updated to surface them.

### 1. Missing `endpoint_stage` / `queue_stage` columns on `inframap_customer`

**Symptom:** `django.db.utils.ProgrammingError: column inframap_customer.endpoint_stage does not exist` on any Customer SELECT (Django wraps the field in the default queryset).

**Root cause:** Migration `0539_historicalcustomer_endpoint_stage_and_more` adds these columns to `inframap_historicalcustomer` but NOT to `inframap_customer` itself. Production has the columns from a **manual ALTER** that was never captured in a migration file. A fresh local restore is missing them.

**Fix:**
```sql
ALTER TABLE inframap_customer ADD COLUMN IF NOT EXISTS endpoint_stage varchar(20) NOT NULL DEFAULT 'prod';
ALTER TABLE inframap_customer ADD COLUMN IF NOT EXISTS queue_stage    varchar(20) NOT NULL DEFAULT 'prod';
```

This is a **bring-up step**, not a one-off — every fresh restore will need it until someone writes a proper migration to backfill these.

### 2. `ConnectorVersion.release_date` is NOT NULL with no auto-default

**Symptom:** `null value in column "release_date" of relation "inframap_connectorversion" violates not-null constraint` when `deploy_branch` calls `ConnectorVersion.objects.get_or_create(tag=image_tag)`.

**Root cause:** The field is `models.DateField(auto_created=True)` — `auto_created=True` is **metadata only**, it does NOT populate values. The endpoint needs to pass a default.

**Fix:** `deploy_branch` now passes `defaults={"release_date": timezone.now().date(), "display_name": f"Custom branch: {image_tag}"}` to `get_or_create`. See `api/serializers/site/customer_deploy_branch_view.py:136`.

### 3. `ConnectorController(customer)` — wrong constructor signature

**Symptom:** `TypeError: ConnectorController.__init__() missing 6 required positional arguments: 'log_group', 'cpu', 'memory', 'cluster', 'ecs_client', and 'customer'`.

**Root cause:** `ConnectorController` constructor takes 6+ positional args, not just a Customer. The endpoint's try/except absorbs this and continues with the audit write — so the cycle still completes correctly — but the deployer-call path is currently a no-op via exception, not via the proper safety short-circuit.

**Status:** Tolerable for local cycle proof (the state-flipping happens BEFORE the reboot call, so DB transitions are correct). Real fix requires looking at existing callers in `customer_view.py` to find the proper construction pattern. Open task; not a blocker.

### 4. AWS SSO token expired mid-run

**Symptom:** `TokenRetrievalError: Token has expired and refresh failed` during the e2e driver run. Affects [[new-relic|New Relic]] init + any S3-touching code.

**Impact:** None on the cycle (the demo doesn't need AWS). NR logger init logs a WARNING and continues.

**Fix when it bothers you:** `aws sso login --profile prod`.

## What still needs to be done before merging

Per the acceptance criteria in [[2026-05-20_deploy-branch-full-scope]] § E:

- [x] Migrations 0547 hand-curated and applied (`BranchDeploymentEvent` + `CustomBranch` together; single file)
- [x] All 5 branch-scoped endpoints implemented (register/list/detail/delete/extend)
- [x] All 3 per-customer endpoints implemented (deploy/revert/status)
- [x] `DeployBranchActionMixin` wired into `CustomerViewSet`
- [x] **Local manual end-to-end run-through** — this note. Cycle proven 2026-05-21 14:56Z.
- [ ] `expire_custom_branches` two-phase body (per-customer TTL + per-branch TTL)
- [ ] `ConnectorController` constructor signature — make the reboot call actually invoke the safety-short-circuit instead of failing with TypeError
- [ ] Fix 16 existing test stubs in `test_customer_deploy_branch.py` (currently `pytest.skip()`)
- [ ] Add ~20 new tests for the branch-scoped surface
- [ ] Seam-A 1-pager ADR — decide whether endpoints stay on `CustomerViewSet` or extract to a new `DeployBranchViewSet`
- [ ] Code review + commit on `feat/customer-deploy-branch-api`
- [ ] Push branch + open PR targeting `staging`
- [ ] Then (and only then) wire CI/CD per [[2026-05-20_deploy-branch-full-scope]] § D

## Cross-references

- Design: [[2026-05-20_deploy-branch-full-scope]]
- Bring-up runbook: [[2026-05-20_actuate-admin-local-bringup]]
- Safe-test-site registry: [[actuate-admin-safe-test-sites]]
- Original 3-endpoint design (now part A of expanded scope): [[2026-05-12_internal-test-deploy-lane]]
- mark-todos §29 entry: [[mark-todos]]
- Jira: ENG-269 (per-customer surface) · ENG-282 (full lifecycle + CI/CD wiring)
