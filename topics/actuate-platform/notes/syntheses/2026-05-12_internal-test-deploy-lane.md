---
title: "Internal-test deploy lane — admin-API design for per-site feature-branch swap"
type: synthesis
topic: actuate-platform
tags: [admin-api, deploy, customer, feature-branch, internal-test, design, adr]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
outgoing:
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/admin-api/notes/syntheses/2026-04-30_autopatrol-state-audit.md
[]
incoming:
  - topics/engineering-process/notes/concepts/2026-05-12_stale-pr-triage-punchlist.md
  - topics/personal-notes/notes/daily/2026-05-12.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-13
---

# Internal-test deploy lane — admin-API design

> **Status (2026-05-12):** Design pass written; endpoint stubs scaffolded but uncommitted. Awaiting stakeholder ping (connector_deployer owner + admin owner) before any model migration or business-logic implementation.
> **Workstream:** [[mark-todos#29]] — Internal-test deploy lane.
> **Goal:** flip a customer (a.k.a. site) onto a feature-branch connector image and back via API calls, with TTL hygiene so the override doesn't drift off latest-known-good.

## Problem

Untested dev branches today must be promoted through `stage` to be exercised against real workload — every iteration noises up the stage→rearch promotion path (see #1681 → #1686 → #1687 → #1688). We need a lane where Alibi / Securitas-trial / internal-eval customers can run a custom branch image directly, without touching stage.

## Existing primitives — what's already there

Surveyed `/home/mork/work/actuate_admin/` and `/home/mork/work/connector_deployer/`:

| Primitive | File | Behavior |
|---|---|---|
| `Customer.deployment_phase` | `inframap/sites/customer/customer_model.py:76` | CharField. Values include `PROD`, `STAGE`, `DEV`, `REARCH`, `REARCHDEV`, `CUSTOM`. Save-time hook at `:806` deletes the old deployment when phase changes. |
| `Customer.connector_version` FK | `customer_model.py:165` | ForeignKey to a ConnectorVersion model with a `.tag` field (the image tag). |
| `Customer.get_image_tag()` | `customer_model.py:1833` | Returns `connector_version.tag` ONLY when `deployment_phase == "CUSTOM"`. Phase-gated by design to prevent stale-tag leak when a site moves away from CUSTOM without clearing the FK. |
| `ConnectorController.call_deployer(action, json)` | `inframap/connector/connector_controller.py:196` | HTTP POST to connector_deployer (FastAPI). Exponential-backoff retry. |
| `ConnectorController.reboot_connector()` | `connector_controller.py:422` | Already includes `image_tag: self.customer.get_image_tag()` in the deployer payload (`:461`). |
| Deployer mechanics | `connector_deployer/src/methods.py` | Generates K8s manifest with `image_tag` from request, applies via `kubectl rollout restart`. No [[argocd|ArgoCD]] layer for this path. |

**The takeaway:** flipping a site is already supported by the data model and deploy chain. What's missing is an admin-API surface that exposes it ergonomically with safety rails (TTL, revert-to-phase memory, audit).

## Design — endpoint family

Three endpoints on `CustomerViewSet` (`api/serializers/site/customer_view.py:145`), mirroring the existing `@action def reboot` style (`:399`):

### 1. `POST /api/customers/{id}/deploy_branch/`

Assign a feature-branch image tag to one customer and roll the pod.

**Request body:**
```json
{
  "image_tag": "feature-1234-foo",
  "expires_at": "2026-05-19T12:00:00Z",   // optional; default = now + 7d
  "reason": "Alibi smoke-test for PR #1234" // required for audit
}
```

**Server behavior:**
1. Resolve or create a `ConnectorVersion(tag=image_tag)` row.
2. If `Customer.deployment_phase != "CUSTOM"`, capture current phase into a new `pre_custom_deployment_phase` field.
3. Set `Customer.deployment_phase = "CUSTOM"`, `Customer.connector_version = <resolved>`, `Customer.image_tag_override_expires_at = expires_at`.
4. Save Customer (the existing `:806` save-hook handles deployment switching at the K8s namespace level).
5. Call `ConnectorController(customer).reboot_connector(is_manual_action=True)`.
6. Write a `BranchDeploymentEvent` row (new model — minimal: `customer_id`, `action`, `image_tag`, `expires_at`, `reason`, `user_id`, `created_at`).
7. Return the new effective image tag + expiry.

### 2. `POST /api/customers/{id}/revert_branch/`

Clear the override and restore the previous deployment_phase.

**Request body:** `{"reason": "..."}`

**Server behavior:**
1. Read `Customer.pre_custom_deployment_phase` (default to `"PROD"` if null — site was born custom?).
2. Set `Customer.deployment_phase = pre_custom_deployment_phase`, `Customer.connector_version = None`, `Customer.image_tag_override_expires_at = None`.
3. Save + reboot (same path as above).
4. Audit row.

### 3. `GET /api/customers/{id}/branch_status/`

Read-only state probe. No reboot.

**Response:**
```json
{
  "current_image_tag": "feature-1234-foo",
  "deployment_phase": "CUSTOM",
  "pre_custom_deployment_phase": "PROD",
  "expires_at": "2026-05-19T12:00:00Z",
  "expired": false,
  "history": [...recent BranchDeploymentEvent rows...]
}
```

## Schema deltas (one migration)

Two new fields on `Customer`:
- `image_tag_override_expires_at: DateTimeField(null=True, blank=True)`
- `pre_custom_deployment_phase: CharField(max_length=20, null=True, blank=True)`

One new model: `BranchDeploymentEvent` (audit log).

No changes to `ConnectorVersion` or to `connector_deployer` — they already do the right thing.

## TTL hygiene — separate from the API

A daily Django management command `expire_custom_branches`:
1. Find all `Customer` with `deployment_phase == "CUSTOM"` and `image_tag_override_expires_at < now()`.
2. For each, call the internal revert logic (same as endpoint #2).
3. Write audit events with `reason="ttl-expiry"`.

Scheduled via the existing cron infra. Idempotent (skips customers without expiry set or already reverted).

## Auth + audit

- `permission_classes`: existing `CheckModelPermission` requiring `inframap.change_customer`.
- Hard gate: `request.user.is_superuser` (mirroring the `rebuild_group_tree` precedent at `api/serializers/group/group_view.py:359`). Branch swap is dangerous enough to warrant superuser-only initially; can loosen later.
- Audit: `BranchDeploymentEvent` rows. Not free-form Django admin log entries — we want structured queryability ("show me all custom-branch swaps in the last 7d").

## What's deferred

| Item | Why | Where it goes |
|---|---|---|
| Bulk / cohort apply | Single-customer first; cohort layer is a separate endpoint that takes a list of customer IDs | Phase 2 |
| Billing-emit suppression | §29 lists this as a related concern but it's orthogonal to the deploy lane — internal-test customers may still emit billing | §28 / next ADR |
| Image-tag validation against ECR / GHCR | Nice-to-have; skip on v1 since the deployer fails fast on a missing tag anyway | Phase 2 |
| `lead_implies_dev` heuristic generalization | The patrol-queue routing at `actuate-libraries/actuate-config/src/actuate_config/connector/patrol/patrol_config.py:31` already handles SQS routing; the connector image lane is a parallel concern, not a unification | Future |
| Cohort definition (lead vs explicit flag) | API takes explicit customer ID; cohort layer decides who to enroll | Phase 2 |

## Stakeholder pings — to do before code

1. **connector_deployer owner** — confirm there's no hidden state in the deployer that breaks when `image_tag` is a feature-branch identifier (vs `latest` / `stable` / `dev`). Particularly: does ECR have a retention policy that could evict the image mid-test?
2. **admin-side owner** — sanity-check the `pre_custom_deployment_phase` field naming and TTL default (7d).
3. **autopatrol owner** — confirm that flipping a CUSTOM site does NOT silently re-route patrol traffic onto dev queue. The `lead_implies_dev` heuristic is name-based, not phase-based, so this should be safe, but worth a verbal confirm.

## File layout for the scaffold

```
actuate_admin/
├── api/
│   ├── serializers/site/
│   │   ├── customer_deploy_branch_view.py     # NEW — endpoint logic
│   │   └── branch_deployment_event_serializer.py  # NEW — audit row serializer
│   └── tests/
│       └── test_customer_deploy_branch.py     # NEW — endpoint tests
├── inframap/
│   ├── management/commands/
│   │   └── expire_custom_branches.py          # NEW — TTL cleanup cron
│   └── sites/customer/
│       ├── customer_model.py                  # MODIFIED — add 2 fields + (later) save-hook guard
│       ├── migrations/
│       │   └── 0497_customer_branch_override_fields.py  # NEW — generated, not hand-written
│       └── branch_deployment_event_model.py   # NEW — audit model
```

Scaffold lands the four NEW files (stubs only — `NotImplementedError` for the action bodies, scaffolded test names, empty management command body). Migration is NOT scaffolded — let `makemigrations` generate it after the model edit lands.

## Related

- §29 in [[mark-todos]]
- [[2026-04-30_autopatrol-state-audit]] — recent admin-API ops-action precedent (audit_autopatrol_state); chose mgmt command over REST because the operation was read-only; this workstream is the opposite (mutating + idempotent → REST is correct)
- `actuate-libraries/actuate-config/src/actuate_config/connector/patrol/patrol_config.py:31` — `lead_implies_dev` patrol-queue heuristic (parallel concern, not unified here)
