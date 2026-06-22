---
title: "Team Brief — Admin DB Access Hardening"
type: brief
topic: data-access-control
tags: [team-brief, summary, shareable]
created: 2026-05-11
updated: 2026-05-13
author: mark
---

# Team Brief — Admin DB Access Hardening

> **Audience:** Tati, Adam, Vini, anyone touching admin or its consumers.
> **Purpose:** Bring the team up to speed on a planning effort started 2026-05-11 to harden how applications, services, and humans access the admin Postgres DB. Two specific decisions need team input.
> **Full plan:** [[2026-05-11_admin-db-access-hardening|the synthesis doc]] has the complete writeup; this brief is the shareable summary.

## The problem in one paragraph

Today, the admin Postgres DB is reached three ways, all backed by a single shared admin credential in AWS Secrets Manager: (1) humans via psql/CLI, (2) services via `AdminDAO` / `actuate-wireguard` / raw psycopg2 — all using that same shared secret, (3) services via the admin REST API using DRF tokens. The third channel has scope structure (`ExternalApiSetUp` per-group tokens) but tokens are coarse; a token with any access can broadly do everything its group can do. Channels (1) and (2) effectively grant superuser power. The risk profile is the obvious one: a single leaked or misused secret today permits arbitrary destructive SQL anywhere it reaches; as agents (LLMs / scripts) increasingly need DB access, this grows.

## What we've already partially solved

- Admin already uses multiple DB users for `sqlexplorer` (read-only), `django_q`, `jobscheduler`, `closeinfo`.
- `ExternalApiSetUp` mints per-group API tokens; `TokenAuthenticationStrict` already exists for strict auth on integration endpoints.
- `actuate-admin-api` exists as the HTTP-client library; vms-connector is hybrid (uses AdminApi for some reads, AdminDAO for others).
- Vini's [[external-api/_summary|external-API work]] (ENG-122 family) has built the API Gateway + Rust authorizer pattern for partner-facing endpoints.

This isn't greenfield. It's finishing a trajectory the team has already started.

## What we've decided in this planning round (2026-05-11)

- **Funnel applications through admin API, not direct DB.** Admin retains direct Postgres access for its data model (Django ORM, mgmt commands, Django-Q, jobscheduler). Everyone else goes through the API. The point: separate the data model from the contract so schema can evolve without breaking consumers.
- **`AdminDAO` is deprecated-and-replaced, not flipped-in-place.** No generic "execute SQL via HTTP" shortcut. Consumers migrate to `AdminApi` with typed methods.
- **Audit landed:** **~10–14 `AdminDAO` call sites total** across all repos (scripted re-audit 2026-05-13 corrected the initial "12"). 4 vms-connector sites all need one new endpoint (`get_product_by_metrics` for billing). 4 are mechanical swaps to existing AdminApi methods (~4h). 4+ stay direct-DB (BI notebooks, admin mgmt commands). **Plus** 2 non-AdminDAO direct-DB consumers surfaced by the broader audit: `sales-dashboard` (own psycopg2 client) and `actuate-integration-calls/milestone_service.py:715` (`pg_connection()` already flagged `# TODO remove this entirely`). Authoritative inventory: `/home/mork/work/scripts/data-access-control/output/`.
- **Admin API reliability is a parallel workstream.** Target 4-to-5 nines. Phase 0 of this initiative bakes in a baseline reliability bar (postmortem audit, release-gate hardening, read replica, statement_timeout, slow-query alerts) **before** Phase 2 cuts consumers over.
- **Admin incident catalog (last 12 months) landed today.** 5 incidents Feb–Apr 2026. Dominant pattern: runaway query / N+1 / unoptimized CTE (worst was 15 min at 98.7% RDS CPU). Top-ROI controls identified.
- **Consumer degradation is mandatory.** Every service that depends on admin API must have a documented "what happens if admin is down" behavior. Default: last-known-good config (a slightly stale settings file is materially better than not running).
- **Observability primary venue: [[new-relic|New Relic]].** Not CloudWatch, not Datadog. Per-token, per-endpoint, per-service signals + audit trail.
- **Residual direct-DB after Phase 2:** admin itself, actuate_bi (read replica). `actuate-wireguard` correction (2026-05-13): WireGuardDAO is already exposed via admin's `wireguard_tunnel_view.py` API; no application-side migration needed. Only the library's own ops CLI scripts use it directly — those fall under the SSO-CLI policy below.
- **Human CLI access:** SSO-issued ephemeral creds, read-only default, audited break-glass writer.

## Phased plan (high level)

- **Phase 0** — Reliability baseline. Postmortem audit (done); release-gate hardening; read replica; statement_timeout; slow-query alerts; per-consumer degradation review.
- **Phase 1** — Tighten what exists. Rotate the shared admin secret; restrict `pg_hba`; turn on `pg_audit`; CI lint blocking new direct-DB code in non-admin repos.
- **Phase 2** — Deprecate-and-replace `AdminDAO`. Build the missing endpoint(s); cut over each consumer behind a flag; remove `AdminDAO` import from non-admin services.
- **Phase 3** — Scoped tokens + per-service Postgres roles for the residual direct-DB principals + SSO CLI policy.

Phases 0, 1 can start immediately. Phase 2 begins once the team-discussion items below land.

## Reliability investigation — what we found in the admin code

A code-grounded follow-up to the incident catalog ([[2026-05-11_admin-reliability-fix-plan]]) traced the failure modes back to specific lines in `actuate_admin`. Concrete takeaways:

- **The BT-926 hot path (15 min at 98.7% CPU) has a precedented fix already in the codebase.** `GroupAdmin.sites()` calls a recursive-CTE method per row in the list view. An adjacent method (`_compute_camera_counts`) already implements a batched-precompute DFS pattern that avoids exactly this — but the pattern wasn't applied to `sites()`. Fix is probably <100 lines, one PR.
- **CustomerAdmin N+1 is mostly missing prefetches.** `customer_view.py:677` does `prefetch_related("group_customer", "immix_credentials")` but misses `customer_monitoring`, `integration_type`, `connector_version`. One-line adds.
- **`Customer.timing` is *not* a problem** — investigated 2026-05-11; the prefetches are already in place, per-row cost is effectively zero.
- **Validation lives in `CameraForm.clean()`, not on the model.** Any save path that bypasses the form (DRF serializer, mgmt command, direct ORM) bypasses validation. That's the BACK-648 shape.
- **No `assertNumQueries` anywhere in the test suite.** The BT-926-shaped N+1 could be reintroduced after a fix without breaking any test.
- **MPTT is explicitly disabled** in the codebase ("Because mptt is broken"). The raw CTE is the workaround, not a clever optimization. Pre-empts the "just use MPTT" suggestion.

The fix plan ranks 13 fixes into three tiers. **Tier 1 (six items) is all cheap, none blocked, can ship in Phase 0.**

## What the team needs to decide

Two open questions in the synthesis, each with a focused note that lays out options + tradeoffs:

### 1. Vini's API Gateway — extend or parallel?

See [[2026-05-11_open-question-vini-gateway]] for the full writeup.

Do internal admin API callers use Vini's API Gateway + Rust authorizer chain (one auth implementation, free rate-limit infra, but adds a gateway hop on east-west traffic and couples to ENG-122's pace), or do they hit admin directly with a parallel-but-compatible auth model (no extra hop, decoupled delivery, but two implementations of token validation)?

Mark leans **parallel-but-compatible** for east-west latency reasons, but wants Vini and Tati's input — particularly on ENG-122's timeline.

### 2. Developer-tier tokens + endpoint composition pathway

See [[2026-05-11_open-question-developer-tokens]] for the full writeup.

Personal/developer tokens should use the same scope vocabulary as service tokens — that part's straightforward. The harder question: **what makes "I need a new admin endpoint" a 30-minute task instead of a multi-day task?** If the friction is too high, developers route around it via the shared cred and we drift back to today.

Options range from DRF scaffolding generators, to a declarative API-composition library, to OpenAPI-first codegen, to accepting some shared-cred fallback. Mark leans toward a declarative composition library long-term + a scaffolding command interim, but this is the call where Mark has the least informed opinion.

### Smaller open questions from the reliability investigation

These don't need a dedicated working session — quick async input from Tati/Adam/Vini is enough:

- **`Group → Server` CASCADE — change to `SET_NULL` or `PROTECT`?** Today, deleting a Server deletes every Group referencing it. Mark's lean: yes, change it (probably `SET_NULL`). Want input on whether the current CASCADE is operationally intentional before the migration ships.
- **Is the slow-query log currently on in prod RDS?** Unconfirmed — the parameter group `actuateadminprodcluster-pg16-logical-replication` is not in Terraform IaC, so it's only inspectable via AWS console / RDS API. 5-min verification, then turn on if off.
- **Should we Terraformize the admin RDS parameter group?** Mark's lean: yes — drift risk is real and any future tuning should land via PR. This is also a prereq for clean ownership of slow-query log / autovacuum / statement_timeout settings.
- **Existing data violations of integration-format rules.** Before Fix 4A (model-level `clean()` enforcement) ships, need an audit query pass to identify pre-existing rows that would break under stricter validation. Catch them in advance, not at deploy time.

## Reading order

1. **This brief** (you're here).
2. [[2026-05-11_open-question-vini-gateway]] + [[2026-05-11_open-question-developer-tokens]] — the two decisions on the table.
3. [[2026-05-11_admin-db-access-hardening|the full synthesis]] — comprehensive plan with phased migration.
4. [[2026-05-11_admindao-call-site-inventory]] — the 12-call-site audit.
5. [[2026-05-11_admin-incident-catalog]] — admin reliability incidents + recommended controls.
6. [[2026-05-11_admin-reliability-fix-plan]] — code-grounded fix plan with file:line citations.

## What I'd like from a working session

A 30-min sync (Tati, Adam, Vini if possible) to:
- Land the two open decisions (#1 and #2 above).
- Confirm Phase 0 + Phase 1 can start immediately on the proposed shape.
- Identify the right Jira project for the epic (BACK? security? new?). Note: ENG-247 already exists as the research/proposal-stage tracker.
- Agree on a checkpoint cadence (every 2 weeks? monthly?).

---

> **2026-05-13 amendments** to be aware of: scripted re-audit landed (`/home/mork/work/scripts/data-access-control/`); inventory corrected from "12" to "~10–14" with 2 new direct-DB consumers identified; wireguard claim corrected (already in admin API); Phase 0 list reconciled in the full synthesis; scope-vocabulary work confirmed to span ~89 admin viewsets. Full pressure-test record in [[2026-05-13_dig-followups]].
