---
title: "Admin DB Access Hardening — Problem Map, Approaches, Migration Plan"
type: synthesis
topic: data-access-control
tags: [security, postgres, rbac, api-keys, secrets, admin-db, planning, proposal, vms-connector]
created: 2026-05-11
updated: 2026-05-13
author: kb-bot
status: draft-for-discussion-amended-2026-05-13
outgoing:
  - topics/admin-api/_summary.md
  - topics/admin-api/notes/entities/actuate-admin-rds.md
  - topics/data-access-control/_summary.md
  - topics/data-access-control/notes/concepts/2026-05-11_admin-incident-catalog.md
  - topics/data-access-control/notes/concepts/2026-05-11_admindao-call-site-inventory.md
  - topics/data-access-control/notes/concepts/2026-05-11_open-question-developer-tokens.md
  - topics/data-access-control/notes/concepts/2026-05-11_open-question-vini-gateway.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-reliability-fix-plan.md
  - topics/data-access-control/team-brief.md
  - topics/external-api/_summary.md
incoming:
  - topics/data-access-control/_summary.md
  - topics/data-access-control/notes/concepts/2026-05-11_admin-incident-catalog.md
  - topics/data-access-control/notes/concepts/2026-05-11_admindao-call-site-inventory.md
  - topics/data-access-control/notes/concepts/2026-05-11_open-question-developer-tokens.md
  - topics/data-access-control/notes/concepts/2026-05-11_open-question-vini-gateway.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-reliability-fix-plan.md
  - topics/data-access-control/notes/syntheses/2026-05-13_dig-followups.md
  - topics/data-access-control/team-brief.md
  - topics/personal-notes/notes/concepts/2026-05-11_next-session-handoff.md
  - topics/personal-notes/notes/concepts/2026-05-19_handoff-anomaly-branches-triage.md
incoming_updated: 2026-05-27
---

# Admin DB Access Hardening

> **Status:** Draft for discussion between Mark, Tati, and Adam. Not yet a commitment. Synthesizes a 2026-05-11 Slack exchange with the current state of code in `actuate_admin` and `actuate-libraries`.
>
> **Amended 2026-05-13** after a scripted re-audit (see `/home/mork/work/scripts/data-access-control/`) surfaced two missed direct-DB consumers (`sales-dashboard`, `actuate-integration-calls/milestone_service.py`), corrected the wireguard framing (already in admin API), and identified that the scope-vocabulary work spans ~89 admin endpoints. See [[2026-05-13_dig-followups]] for the full pressure-test record.

## TL;DR

Today the admin Postgres DB is reached three ways, all backed by a single shared "admin" credential in AWS Secrets Manager: (1) humans via psql/CLI, (2) services via [[actuate-daos|actuate-daos]] / [[actuate-wireguard|actuate-wireguard]] / raw `psycopg2`, (3) services via the admin REST API using DRF tokens. The third channel has scope structure (`ExternalApiSetUp` per-group tokens) but tokens are coarse; the first two channels have effectively superuser power.

**Recommendation:** Drive all *application* DB access through the admin REST API behind per-service, scoped API tokens, with a small number of explicit per-service Postgres roles for things that genuinely cannot fit an API (today, that's primarily `actuate-wireguard`-style ops and bulk analytic reads). Keep direct human DB access only via SSO-issued ephemeral credentials, with a read-only default and a documented break-glass write user. Migrate in three phases: (1) tighten what already exists, (2) finish the AdminDAO → AdminApi migration in vms-connector / queue-consumer / autopatrol-server, (3) introduce scoped tokens + per-service DB roles for everything that can't fit the API.

---

## 1. Problem Map

The control surface decomposes along two axes: **who** is accessing (human vs. application) and **how** (direct DB vs. through admin API). Four quadrants:

|  | **Direct DB (psql / psycopg2)** | **Via admin API (Token auth)** |
|---|---|---|
| **Human** | Q1: firefighter CLI, ad-hoc SQL, BI notebook authors | Q3: admin web UI (Cognito), curl scripts using a personal token |
| **Application / agent** | Q2: AdminDAO consumers, wireguard CRUD, dump/restore scripts, mgmt commands | Q4: AdminApi consumers, external partners |

What "access control" needs to mean in each quadrant:

- **Q1 (human direct DB)** — the riskiest quadrant. Today: one shared secret; anyone with it can `DROP TABLE` on prod. Goal: SSO-issued, ephemeral, read-only by default; explicit elevation for writes; full audit log.
- **Q2 (app direct DB)** — the biggest blast radius by volume. Today: every service that pulls `actuate-daos` uses the same shared secret. Goal: per-service Postgres role with the narrowest grants the service can tolerate, *or* migrate the service out of Q2 entirely into Q4.
- **Q3 (human API)** — already in good shape via Cognito + DRF group permissions. Mostly out of scope unless we widen `ExternalApiSetUp` to also cover human personal tokens.
- **Q4 (app API)** — the target state for most services. Today: tokens exist (`ExternalApiSetUp`) and are group-bound, but a token's authorization is effectively "everything that group can do," not "GET /cameras and POST /command_history only."

Four sub-problems fall out:

1. **No CLI access policy.** No SSO, no read-only default, no audit. (Q1)
2. **No per-service DB users for most services.** `sqlexplorer`/`django_q`/`jobscheduler`/`closeinfo` are carved out; everyone else uses the shared admin user. (Q2)
3. **AdminDAO is still pulled by services that could go through AdminApi.** vms-connector is hybrid; queue-consumer + autopatrol-server are still mostly direct-DB. (Q2 → Q4 migration)
4. **API tokens are coarse.** No endpoint/operation-level scopes; no per-call rate limiting on the internal API. (Q4)

---

## Locked-in decisions (2026-05-11 review)

The following calls were made in the 2026-05-11 review with Mark and are baseline for everything below:

### Architecture

- **Authorization lives at the API tier; admin retains direct Postgres access for the data model layer (Django ORM + mgmt commands + Django-Q/jobscheduler workers).** Decoupling rationale: API contracts / versions become the consumer contract, and the underlying schema is free to evolve without breaking consumers as long as the contracts are upheld.
- **The Postgres surface of `actuate-daos` is narrowly scoped to `admin_dao.py`.** Verified 2026-05-11: every other file in the library is DynamoDB / S3 / CloudWatch / NR / SQS — that surface is **out of scope** for this initiative. Only `admin_dao.py` is in scope.
- **`AdminDAO` is deprecated-and-replaced (Option Y), not flipped-in-place.** Consumers migrate from `AdminDAO.execute(sql, ...)` to `actuate-admin-api`'s `AdminApi` with typed methods (`list_cameras`, etc.). We do **not** ship a generic "tunnel SQL over HTTP" endpoint as a shortcut. **Each application supplies its own API key** so calls are attributable per-service. Phase 2 begins with a system-wide audit of `AdminDAO` call sites and a mapping table to required admin API endpoints or replacement scripts (see [[#Follow-up — `AdminDAO` call-site audit|follow-up below]]).

### Reliability & dependencies

- **Hybrid reliability workstream.** Phase 0 of this initiative bakes in a *baseline* reliability bar (postmortem audit + release-gate hardening + read-replica for inframap-heavy reads) **before** Phase 2 cuts consumers over. Beyond the baseline, full 5-nines-target work runs as a continuous sibling workstream rather than blocking this initiative.
- **Internal hardening dovetails with Vini's external-API throughput work** ([[external-api/_summary]] / ENG-122 family). Plan: reference that work, ensure compatibility, document any gaps. Whether to *extend* Vini's API Gateway + Rust authorizer chain for internal traffic vs. run a parallel-but-compatible internal stack is **deferred to team discussion** — see §6.
- **Consumers must degrade gracefully when admin API is unavailable.** Default behavior: serve the last-known-good configuration (most settings rarely change), detect the outage, attempt re-access on a backoff schedule, auto-heal. Per-service degradation review is part of Phase 0 — options + tradeoffs documented in §5e.

### Observability

- **[[new-relic|New Relic]] is the primary observability home** for everything in this initiative — per-token request signals, per-endpoint volume / scope-denied counts, consumer degradation events, audit-trail emit. CloudWatch and Datadog are not primary venues for this work.
- **High observability is a design requirement, not Phase-3 polish.** Per-token, per-endpoint, per-service signals; audit trail for privileged actions; staleness detection for unused tokens.

### Residual direct-DB principals after Phase 2

- **Admin itself** (Django ORM, mgmt commands, Django-Q, jobscheduler) — canonical writer.
- **`actuate_bi`** — read-only role against a **read replica**. Acceptable for now; future review on whether BI should ultimately move to a Snowflake-style export so even read-replica access goes away.
- **`actuate-wireguard`** — `WireGuardDAO` is **already exposed inside admin via `wireguard_tunnel_view.py`**; no non-admin Python callers found in the scripted audit (corrected 2026-05-13). The only direct-DB usage outside admin is in the library's own ops CLI scripts (`integration_check.py`, `rms_register_device.py`, etc.), which are Q1 (human/CLI), not Q2. Migration scope is therefore: nothing for the application side; CLI scripts fall under the SSO + read-only-default CLI policy in §4.
- **`closeinfo` / `sqlexplorer` / Django-Q / jobscheduler** — already carved out with dedicated DB users; stay as-is until otherwise.

### Tokens for humans

- **Personal / "developer-tier" tokens use the same scope system** as service tokens (resource:verb scopes), to keep one auth model. Requires a frictionless pathway to add new endpoints when developers hit something missing — an API composition library / scaffolding approach is worth exploring. Final shape deferred to team discussion — see §6.

### Django's own DB role

- **Tightening Django's role is acknowledged as diminishing returns** once everyone else is off the shared cred. A scoped review will land in Phase 3 to identify cheap wins (e.g., revoking `SUPERUSER`, `CREATEDB`) **without breaking any standard Django flow** (migrations, ORM features). If the review concludes "not worth it," that's a documented decision rather than a silent gap.

## 2. Current State (verified 2026-05-11)

### 2.1 Admin DB credentials

`actuate_admin/admin/settings_secrets.py` already wires multiple DB users from Secrets Manager, but they're a thin slice of what's needed:

| Django DB alias | Postgres user (Secret key) | Purpose |
|---|---|---|
| `default` | `username` | Main app — effectively superuser-equivalent |
| `sqlexplorer` | `username-sqlexplorer` | Read-only via DRF SQL Explorer (gated by configured query whitelist) |
| `django_q` | `username-django-q` | Async task queue |
| `job_scheduler` | `username-jobscheduler` | Job scheduler |
| `closeinfo` | `username-close` | closeinfo module DB |

No `pg_hba.conf` IP-level restrictions visible in app config. Trust-the-secret throughout.

### 2.2 Auth / token model in admin

- **Human auth:** AWS Cognito (prod/staging/dev). Local fallback: username/password.
- **Service auth:** DRF `rest_framework.authtoken.models.Token`. Per-service "users" are minted via `ExternalApiSetUp` (`actuate_admin/external_api/external_api_set_up.py`):
  - Username pattern: `external-api-{group_pk}-{slug}`
  - Bound to **one Group** via `GroupUser(is_external_api_user=True)`
  - Default access level `LIMITED_GROUP`; can be escalated to `CUSTOMER_GROUP`, `SELF_SERVICE`, etc.
- **Strict mode:** `TokenAuthenticationStrict` rejects anonymous fallback. Used by integration endpoints (Umbo, [[sentinel-components|Sentinel]], Frontel, AISync).
- **Permission model:** Django model-level perms (`add_*`, `change_*`) checked via `CheckModelPermission` / `DjangoModelPermissions`. **No endpoint-level scope on tokens.** A token authorized at all is broadly capable for everything its bound user/group has permissions for.

### 2.3 SQL Explorer

The closest existing thing to a "scoped DB read" pattern:
- Dedicated `sqlexplorer` Postgres user with read-only grants.
- Endpoint (`sqlexplorer_view.py`) gates by Django `add_` permission *and* a configured query whitelist (`Configuration.sqlexplorer_download_queries`).
- Read-only enforced both at the DB user level *and* by an allow-list of approved queries.
- Blacklist in `settings.py` blocks `ALTER` / `CREATE` / `DELETE` / etc. as a defense-in-depth layer.

This is the existing shape of "small explicit surface, narrow grants" — worth mirroring.

### 2.4 Direct-DB Postgres surface (the Q2 blast radius)

Revised 2026-05-13 from the scripted re-audit (`postgres-direct-callers.py` + `admindao-inventory.py`):

| Library / file | Pool | Surface | Used by |
|---|---|---|---|
| **`actuate-daos/admin_dao.py`** (one file in the larger library — rest is DynamoDB/S3/metrics, out of scope) | psycopg2 ThreadedConnectionPool (1–8 conns) | `AdminDAO.execute / query_dict_array / bulk_execute / get_product_by_metrics / list_webhooks / get_cameras / get_new_relic_mute_rule_id / ...` — both reads and writes. Tables: `inframap_group`, `inframap_customer`, `inframap_integrationtype`, `authtoken_token`, `auth_user`, plus generic wildcards. | vms-connector, queue-consumer (webhook + health), actuate_bi, [[actuate_admin]] (mgmt commands), `actuate-monitoring` (library), `actuate-config` (library; wrapper-only — uses `.admin_api`) |
| **`actuate-libraries/actuate-integration-calls/.../milestone/milestone_service.py:715`** | own psycopg2.connect (autocommit=True) | `pg_connection()` — reads `prod/actuate/postgres`, connects directly. Already carries `# TODO remove this entirely.` Library-level direct-DB inherited by every consumer that pulls the library. | callers of [[actuate-integration-calls]] — historically deployed inside Lambda zips (autopatrol_onboarder, health_report) |
| **`sales-dashboard/src/sales_dashboard/clients/postgres.py:31` + `scripts/reconcile_cameras.py:87`** | psycopg2.connect | `_connect()` reads the admin secret, connects to `actuateadmin` DB. Self-documented as "READ ONLY" but enforced only by convention. | `sales-dashboard` (a Q2 consumer **not previously enumerated**) |
| **`actuate-wireguard`** | same as admin (when invoked via Django connection) | `create_tunnel`, `update_tunnel`, `delete_tunnel`, `get_all_tunnels`, `validate_subnet`. Tables: `inframap_wireguard*`. | Already exposed inside [[actuate_admin]] via `wireguard_tunnel_view.py` (admin API endpoint). **No non-admin Python callers found in the scripted audit.** Direct-DB usage is limited to the [[actuate-wireguard]] library's own ops CLI scripts (`integration_check.py` etc.) — those are Q1 (human/CLI), not Q2. |

All non-CLI consumers fetch the **same** prod admin secret (`prod/actuate/postgres`) and reuse it pool-wide.

**Scope note — [[actuate-daos]] library:** the rest of `actuate-daos` (`base_dynamo_dao.py`, `healthcheck_dao.py`, `heartbeat_dao.py`, `scene_change_dao.py`, `token_dao.py`, `window_ids.py`, `s3.py`, `sqs.py`, `*_metrics.py`, etc.) is out of scope — that's DynamoDB / S3 / metrics access, governed by AWS IAM, not Postgres. Within the library, only `admin_dao.py` is the Postgres-touching file.

**Scope note — consumer-side migration is broader than "one file":** the per-library statement above is about which files in `actuate-daos` need touching. The *consumer-side migration* spans every library/service that instantiates `AdminDAO` (admin-config, admin-monitoring) plus the non-AdminDAO direct-DB consumers (`sales-dashboard`, `actuate-integration-calls/milestone_service`) — so the migration scope is "every Q2 row in the table above" not "one file in [[actuate-daos]]." See [[2026-05-11_admindao-call-site-inventory]] for the per-site bucketing.

### 2.5 API-layered alternative (the Q4 target)

`actuate-admin-api` is the library that wraps the admin REST API:
- `AdminApi` issues authenticated `requests` calls with `Authorization: Token {api_token}` (token also fetched from Secrets Manager).
- Methods: `list_cameras`, `get_camera`, `list_webhooks`, `save_command_history`, `list_configurations`, etc.
- **vms-connector is already a hybrid:** uses `AdminApi` for many reads but still pulls `AdminDAO` for edge cases. Migration path is partially in flight.

### 2.6 CLI / firefighter surface

- `actuate-wireguard/scripts/integration_check.py` — standalone script with `--add-tunnel` etc., reads `.env` or Secrets Manager.
- `actuate_admin/inframap/management/commands/admin_dao_db_cleanup.py` — Django mgmt command that runs `DROP DATABASE`, `pg_terminate_backend`.
- `actuate_bi/noteboooks/src/sql/*.sql` — raw SQL files loaded from disk and executed via AdminDAO. No version control on the queries.
- Plus the obvious: any engineer with the shared secret can run psql.

---

## 3. Approaches Considered

Three candidate target architectures, ordered roughly by ambition. They're not mutually exclusive — the recommendation pulls from more than one.

### Approach A — Funnel everything through the admin API, scoped tokens

Make the admin REST API the only sanctioned application access path. Direct DB stays only for: (a) Django's own connection, (b) the SQL Explorer flow that already exists, (c) a small set of break-glass / ops paths.

**What changes:**

- Add per-token scopes (endpoint-level grants) to `ExternalApiSetUp`. Token model gains a `scopes` field; `TokenAuthenticationStrict` enforces it; each viewset declares its required scope.
- Migrate `AdminDAO` consumers to `AdminApi`. Where no equivalent API exists, build it.
- Retire `actuate-daos` pool from non-admin services (it stays inside admin itself).
- Rate-limit / throttle per-token at the API layer (Vini's external API throughput controls are the reference).

**Tradeoffs:**

- ✅ Tight blast radius. Compromising one service's token grants only what that token can call.
- ✅ Auditable: every change is an HTTP call against admin, which can log + emit metrics.
- ✅ Schema changes don't break consumers — the API is the contract.
- ❌ Big migration. AdminDAO is pulled by 4+ services with non-trivial query volume.
- ❌ Admin becomes a harder dependency on the critical path; performance + availability of admin matters more.
- ❌ Some workloads (bulk reads, analytic queries) are awkward over HTTP.

### Approach B — Per-service Postgres roles, keep direct DB

Don't try to remove direct DB access. Instead, define a Postgres role per service with the narrowest GRANTs that service can tolerate. Use AWS RDS IAM authentication so each service authenticates as itself with a rotating credential instead of a static shared secret.

**What changes:**

- Carve roles: `vms_connector_ro`, `queue_consumer_ro`, `autopatrol_rw`, `wireguard_rw`, `bi_ro`, etc.
- Each role: explicit `GRANT SELECT ON ...` / `GRANT INSERT,UPDATE ON ...`; nothing else.
- Switch services to IAM auth (or per-service secret); rotate via AWS.
- Audit via Postgres `log_statement = 'mod'` plus IAM auth log.

**Tradeoffs:**

- ✅ Smaller migration than A — services keep their existing code.
- ✅ Bulk + analytic workloads stay efficient.
- ✅ Doesn't add admin as a runtime dependency for services that don't already have it.
- ❌ Schema becomes the contract for many consumers. Any column rename is a coordinated rollout.
- ❌ Postgres role grants are coarser than HTTP scopes; row-level security (RLS) is possible but operationally heavy.
- ❌ Doesn't fix the "raw SQL is too easy" problem — it just narrows who can run which kind.

### Approach C — Hybrid: API by default, per-service roles for legitimate direct-DB

Use Approach A as the default and Approach B for the explicit exceptions where HTTP is the wrong shape (large bulk reads, infra-tier writes like WireGuard tunnels, BI analytics).

**What changes:**

- Same as Approach A for all of vms-connector / queue-consumer / autopatrol-server / typical service code.
- Per-service Postgres roles created *only* for the services that retain direct access (today: probably `actuate_bi`, `actuate-wireguard`, and admin's own mgmt commands).
- All other services lose their `actuate-daos` import.

**Tradeoffs:**

- ✅ Best of both: tight surface for everyday access, escape hatch for legitimate exceptions.
- ✅ Forces a deliberate decision each time someone wants direct DB ("which role do I need, and why isn't there an API for this?").
- ✅ Aligns with the existing trajectory (vms-connector hybrid → AdminApi-only).
- ❌ Two architectures to maintain.
- ❌ Has to define and police "what qualifies for direct DB" — discipline lapses → drift back to today.

### CLI / Human access — orthogonal

For Q1 specifically, the candidate is: AWS SSO-issued temporary Postgres credentials → mapped to a `readonly_human` role by default → explicit elevation to a `breakglass_writer` role with audit + post-incident review. This sits alongside whichever of A/B/C we pick for services.

---

## 4. Recommendation

**Adopt Approach C (Hybrid), with admin as the only sanctioned direct-DB principal for the data model layer.** Plus the SSO + read-only-default CLI policy for humans.

Per the 2026-05-11 review: admin retains direct Postgres access (Django ORM + mgmt commands + Django-Q/jobscheduler workers); every other application loses direct DB and goes through the admin API. Schema becomes a private implementation detail of admin; API contracts (with versioning) are the consumer-facing contract.

Reasons:

1. The existing trajectory already points this way — vms-connector is hybrid, `AdminApi` exists, `ExternalApiSetUp` exists, partial DB users exist. We're choosing the destination, not a new direction.
2. Pure B (per-service DB roles for everyone) leaves schema as the contract for too many callers — every column rename becomes a coordinated rollout. Funneling through admin's API lets the data model evolve freely.
3. The 80/20 win is finishing AdminDAO → admin-API for the three big consumers (vms-connector, queue-consumer, autopatrol-server). That alone removes the majority of Q2 surface area and lets us bound the discussion of "what stays direct" to a small set (admin itself, BI, wireguard ops).

What this commits to:

- **Tokens become the unit of access.** Per-service, with scopes. Mint via `ExternalApiSetUp` extended; revoke when a service is decommissioned.
- **Direct DB becomes the exception, not the default.** Each exception has a named role with audited grants and a one-page justification in this topic.
- **Humans use SSO, not the shared secret.** The shared admin secret stops being a credential humans hold; it becomes a service identity for admin itself.

---

## 5. Phased Migration Plan

Rough sequencing — each phase is a separable workstream with its own design + Jira ticket.

### Phase 0 — Reliability baseline (parallel-able, lands before Phase 2 cutover)

Goal: bring admin API up to a baseline good enough that Phase 2 can safely make it a runtime dep. Full 5-nines work continues as a sibling workstream after Phase 0 lands.

**Reconciled 2026-05-13** — the original synthesis, the incident catalog "Phase 0 starter set," and the reliability fix plan "Tier 1" each carried slightly different Phase 0 lists. The canonical list below is the merger; **operational/infra items only**. Code-level admin reliability fixes (Fix 1A `GroupAdmin.sites()` prefetch, Fix 2A `CustomerAdmin` prefetches, Fix 4C data-quality gates) ship in parallel as "Near-term admin reliability fixes" — they address specific known incidents, not the pre-emptive baseline.

- [x] **Postmortem audit** — completed 2026-05-11. See [[2026-05-11_admin-incident-catalog]]: 5 incidents over Feb–Apr 2026, runaway-query/N+1 dominant.
- [ ] **Read replica for inframap-heavy reads.** Camera/customer/site reads from the connector fleet are read-only and don't need primary. Read replica reduces blast radius of any single bad query and gives consumers a fallback path.
- [ ] **`statement_timeout` on the read-replica role** used by the connector fleet. Caps blast radius — a 15-min RDS-pinning event becomes a fast failure for the offending caller. Conservative timeout (5–10s) initially.
- [ ] **Slow-query log verification + NR pipeline.** First: `aws rds describe-db-cluster-parameters --db-cluster-parameter-group-name actuateadminprodcluster-pg16-logical-replication` to confirm current values. If `log_min_duration_statement` is off, turn on at ~1000ms. Then build the slow-query log → NR pipeline (CloudWatch subscription or NR Postgres integration).
- [ ] **Terraformize the RDS parameter group.** `actuateadminprodcluster-pg16-logical-replication` currently lives only in AWS console; move definition into `ds-terraform-eks-v2` so all RDS tuning is PR-reviewable.
- [ ] **CI query-count assertion.** Integration tests run under a query logger; failing if a baseline + margin is exceeded. Catches new N+1s before merge. One-time setup, ongoing benefit.
- [ ] **Per-token rate-limit policy.** No single consumer can DoS admin. Limits align with the throughput controls Vini built for the external API.
- [ ] **Consumer-side degradation reviews.** One per high-volume consumer (vms-connector first). Output: documented "what does this service do when admin API is down for N minutes" decision. See §5e for the menu of options.

### Near-term admin reliability fixes (parallel to Phase 0)

These address specific incidents identified in [[2026-05-11_admin-incident-catalog]]; they ship now but aren't Phase 0 baseline because they're targeted bug fixes, not pre-emptive controls. See [[2026-05-11_admin-reliability-fix-plan]] for code-grounded detail.

- [ ] **Fix 1A** — Replicate `_compute_camera_counts()` precompute pattern for `GroupAdmin.sites()` at `group_view.py:272`. Eliminates BT-926 hot path. <100 lines, one PR.
- [ ] **Fix 2A** — Add missing prefetches/select_related to `CustomerAdmin.get_queryset()` at `customer_view.py:677` (`customer_monitoring`, `integration_type`, `connector_version`). Per-row queries → constant.
- [ ] **Fix 4C** — Post-deploy data-quality gates for integration-linked fields. Sample audit queries before mark-live. Catches the next BACK-648.

### Phase 1 — Tighten what exists (low effort, immediate wins, can run alongside Phase 0)

Goal: stop the bleeding without architectural change.

- [ ] **Inventory + rotate.** Audit who has the shared `prod/actuate/postgres` secret today. Rotate. Re-distribute only to services + a controlled break-glass IAM group.
- [ ] **Add `pg_hba.conf` / security-group restrictions** — the admin RDS should only accept connections from EKS pod identity, ECS task roles, and the break-glass jump host. No "wide open inside the VPC."
- [ ] **Default `sqlexplorer`-style read-only user for new ad-hoc reads.** Document it as the right tool instead of `psql` with the superuser secret.
- [ ] **Audit logging on.** `log_statement = 'mod'` on the admin RDS at minimum; ideally `pgaudit` for selective verbose logging.
- [ ] **Lint:** add a CI rule that flags `psycopg2` imports / `actuate-daos` adds in PRs against repos that should be API-only.

### Phase 2 — Deprecate-and-replace `AdminDAO` (medium effort, biggest blast-radius reduction)

Goal: remove direct Postgres from every non-admin consumer by replacing `AdminDAO` with `AdminApi`. **Following Option Y** — no generic "execute SQL via HTTP" shortcut.

- [x] **System-wide call-site audit.** Initial pass 2026-05-11 ([[2026-05-11_admindao-call-site-inventory]]); scripted re-audit 2026-05-13 (`/home/mork/work/scripts/data-access-control/admindao-inventory.py` + `postgres-direct-callers.py`). Authoritative output: `output/*.csv` in the script dir. **Consumers requiring migration** (revised 2026-05-13): vms-connector, queue-consumer (webhook + health), `actuate-libraries/actuate-monitoring`, `actuate-libraries/actuate-config`, **`sales-dashboard`** (newly identified, 2 sites), **`actuate-libraries/actuate-integration-calls/milestone/milestone_service.py`** (newly identified — already carries `# TODO remove this entirely`). Stay direct-DB: admin itself, `actuate_bi` (read-replica only), admin mgmt commands. Wireguard correction: no non-admin Python callers; CLI ops scripts fall under §4 CLI policy.
- [ ] **Build missing admin API endpoints** for every "needs-new-API" entry in the mapping. Reuse existing `ViewSet` patterns; declare a `required_scope` per endpoint. **Constraint:** no generic SQL-tunneling endpoint. If a query is too exotic to express as an endpoint, the right answer is either a stored procedure on the admin side or moving the workload to admin itself.
- [ ] **Per-service API tokens** minted via `ExternalApiSetUp`, stored in Secrets Manager with per-service paths (`prod/actuate/admin-api/vms-connector`, `prod/actuate/admin-api/queue-consumer`, etc.). No more shared "admin" token either. DAO library (or its `AdminApi` replacement) takes the token as a constructor / config argument — not via module-init Secrets Manager call, so swapping identities is testable.
- [ ] **Cut each consumer over** behind a feature flag where possible; verify in stage, then prod. Each cutover includes a degradation review (see Phase 0).
- [ ] **Drop `actuate-daos.AdminDAO` import** from each consumer's `pyproject.toml` / source once the cutover is complete. (Other DAO classes — Dynamo, S3, metrics — stay; they're out of scope.)
- [ ] **Eventually remove `admin_dao.py` from the published `actuate-daos` package** once no non-admin consumer depends on it. If admin still needs `AdminDAO` for internal use, it moves into admin's own source tree.

### Phase 3 — Scoped tokens + per-service Postgres roles (higher effort, finishes the policy)

Goal: make least-privilege real on both rails.

- [ ] **Extend the Token model** with `scopes: list[str]` (or join through a `TokenScope` table). Migration + backfill: existing tokens get a `legacy_full` scope that we deprecate over time.
- [ ] **Annotate viewsets** with required scopes; enforce in `TokenAuthenticationStrict`. **Scale finding (2026-05-13):** the scripted re-audit (`admin-api-surface.py`) counted **89 view classes** in admin. 76 of 89 (85%) have no `authentication_classes` attribute and 70 of 89 (79%) have no `permission_classes` attribute — they fall back to DRF defaults. Only 7 use `TokenAuthenticationStrict` today. **Annotating every viewset with a required scope is ~89 endpoints to touch**, much larger than the synthesis originally implied. Implies the scope vocabulary needs to be substantial (or hierarchical) and the rollout needs phasing (annotate batches by viewset group rather than all-at-once). See `/home/mork/work/scripts/data-access-control/output/admin-api-surface.csv` for the list.
- [ ] **Define per-service Postgres roles** for the residual direct-DB consumers — primarily admin mgmt commands and BI's read-replica role (wireguard correction 2026-05-13: WireGuardDAO is already exposed via admin API; no application-side migration to roles needed there).
- [ ] **Switch to RDS IAM auth** for those roles — kills the static password.
- [ ] **CLI policy:** SSO → read-only role by default; documented break-glass with audit hook. Includes ops scripts in `actuate-libraries/actuate-wireguard/scripts/` and similar.
- [ ] **Track scope coverage** as a dashboard metric: % of tokens with non-legacy scopes, % of viewsets with non-legacy required-scope annotation, % of services with per-service DB role (if direct).

### Phase 4 — Continuous (steady state)

- [ ] Quarterly review of who holds the break-glass writer creds.
- [ ] Each new service or library that wants DB access: must go through admin API; direct DB requires written justification and a named role.
- [ ] `actuate-daos` library becomes admin-internal only; remove the public package as a forcing function once Phase 2 is done.

---

## 5e. Consumer degradation strategy

When admin API is unavailable (deploy gap, RDS hiccup, network), every consumer of admin API must have a documented behavior. **Baseline policy (2026-05-11):** prefer serving the last-known-good configuration over failing — a slightly stale settings file is materially better than not running.

### Options menu (per service)

| Option | What it means | Best for | Concerns |
|---|---|---|---|
| **a. Last-known-good cache** | Settings loaded at startup; if admin is unreachable on a refresh attempt, keep using the last-good snapshot. Detect, log, retry on backoff, auto-heal when admin returns. | vms-connector (settings rarely change mid-run); autopatrol scheduling | Stale config can persist hours/days if the failure mode is silent. Need a hard staleness cap + a loud alert when exceeded. |
| **b. Read-replica fallback** | On primary-API failure, read directly from the read replica with a narrow read-only role. | Services that need fresher reads than (a) allows; queue-consumer maybe. | Reintroduces direct DB for a subset of paths. Needs a per-service Postgres role even after Phase 2. |
| **c. Fail fast** | If admin is down, the consumer exits or refuses traffic. Caller (or k8s) restarts when admin returns. | Services where stale config is materially worse than downtime. | Couples consumer uptime tightly to admin uptime. |
| **d. Degraded mode** | Specific endpoints/features disabled when admin is unreachable; others continue. Service stays up with reduced capability. | Complex consumers with separable feature sets. | Hardest to test; needs explicit feature-by-feature decisions. |

### Cross-cutting requirements (apply to whatever option a service picks)

- **Detection.** Every admin-API failure is logged and emits an NR event with reason + duration.
- **Re-access loop.** Exponential backoff with jitter; cap at a sane retry interval (~60s).
- **Auto-heal.** When admin returns, the consumer transitions back to live behavior without manual intervention.
- **Staleness alarm.** If a consumer has been on cached config / fallback for > N minutes (per-service N, probably 15–60), alert.

### Open per-service questions

- **vms-connector:** option (a) with what staleness cap? Connectors run for days at a time; a 24h cap is probably fine for typical settings, but billing config has tighter freshness needs.
- **queue-consumer:** option (a) or (b)? Webhook config staleness has customer-visible failure modes.
- **autopatrol-server:** option (a) likely fine — schedule data changes infrequently.

These get answered in the Phase 0 degradation reviews.

## 5b. Companion workstream — Admin API reliability

**Target: 4-to-5 nines for admin API availability.** (4 nines ≈ 52 min/yr downtime; 5 nines ≈ 5 min/yr.) Because Phase 2 makes admin API a hard runtime dependency for vms-connector, queue-consumer, and autopatrol-server, admin's availability cap becomes those services' availability cap.

In scope:

- **Postmortem audit.** Review the [March 27, 2026 admin postmortem](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/472252417/Camera+Admin+Postmortem+-+March+27+2026) and any other admin incidents in the last ~12 months. Identify recurring failure modes (deploy regressions, runaway queries, RDS CPU, etc.) and harden against them.
- **Release process hardening.** What gate let the failure ship? Add the corresponding pre-merge / canary / rollback control.
- **Read-path resilience.** Likely a read-replica for the inframap-heavy read traffic from vms-connector; consider edge caching for very-hot reads (camera metadata).
- **Capacity & throttle policy.** Per-token rate limits so a runaway consumer can't take down admin for everyone. Aligns with the throughput controls Vini built for the external API.
- **Consumer-side degradation.** Every service that depends on admin API needs a documented "what happens if admin is down" behavior — cache last-known-good config, retry with backoff, fail closed vs fail open. This is a per-service review.

Tracking shape: either fold into this initiative as Phase 0 + ongoing, or spin a sibling workstream that Phase 2 depends on. **Open question** — see §6.

## 5c. Relationship to Vini's external-API work

[[external-api/_summary]] (ENG-122 family) is the partner-facing API hardening initiative. Vini already has throughput controls; the standard pattern is `Client → AWS API Gateway → Rust Lambda Authorizer → K8s/ALB`.

Plan: **build on top of Vini's foundation rather than parallel to it.** That means:

- **Reuse the same authorizer pattern.** If the [[rust-lambda-authorizer|Rust Lambda authorizer]] can validate internal service tokens, internal callers get the same auth backbone as external partners.
- **Reuse the API Gateway tier (where it makes sense).** Internal callers may use the gateway too, giving us rate limiting + request logging + IAM at no extra build cost. Open question: does that hop cost matter for internal latency-sensitive callers?
- **Share scope vocabulary.** Internal token scopes and external token scopes should be the same shape (`resource:verb`-style), so a viewset's `required_scope` annotation is meaningful to both.
- **Enhancements documented here.** Where the internal use case needs something Vini's work doesn't provide — for example, finer-grained service-to-service scopes, mutual-TLS between internal services, IRSA-issued tokens — document those gaps in this topic as concept notes.

We'll need a working session with Vini early to confirm compatibility before committing Phase 2.

## 5d. Observability requirements

Treat as a first-class design requirement, not Phase-3 polish. **Primary venue: [[new-relic|New Relic]]** (not CloudWatch, not Datadog) — keeps everything in the same query surface the connector fleet already uses.

Per-token signals (NR events / custom attributes):
- Request count, error rate, p50/p95/p99 latency
- Scope-denied count (how many times did this token try to do something it can't?)
- Last-used timestamp (for stale-token detection / cleanup)

Per-endpoint signals:
- Caller distribution (which tokens are hitting this endpoint, with what frequency?)
- Status code distribution
- Cache hit rate (once we add caching)

Per-service signals:
- Admin API call volume + error rate
- Cumulative consumer time spent in admin API calls (latency budget)
- Degradation events (consumer fell back to cache / failed closed) — see §5e

Audit trail:
- Every write through admin API: `(timestamp, token_id, principal, endpoint, payload_hash, status)` — emitted as an NR event, additionally persisted to a Postgres audit table or S3 for ≥ 1-year retention (NR retention may be shorter than required). Eventual goal: an "I changed X yesterday, who else changed X this month?" query is one search.
- Every direct-DB write from the residual roles (admin Django, BI replica reads, post-Phase-2 wireguard if any direct-DB lingers): same shape via `pgaudit`, shipped to NR.
- Every break-glass CLI write: same shape, plus a Slack/PagerDuty echo.

Dashboard surfaces:
- A [[new-relic|New Relic]] dashboard for the initiative — token health, endpoint usage, scope-denied trend, audit-event rate, consumer degradation events.
- Integration with Mark's local dashboard (`/dashboard-check`) for daily-driver visibility of token / scope health signals.

## 6. Open Questions (for team discussion)

Most blocking items from the 2026-05-11 review are now resolved (see the "Locked-in decisions" section at the top). What remains for team discussion:

### Needs team discussion — please raise in the next planning session

- **Build on Vini's API Gateway + Rust authorizer, or run parallel?** If we extend Vini's API Gateway / Rust authorizer chain to handle internal traffic, internal callers share the partner-API auth backbone and rate-limit infra for free, but we couple to ENG-122's pace and add a gateway hop for east-west calls. If parallel-but-compatible (same scope vocabulary, same token model, separately deployed), we duplicate some infra but keep internal latency low and decouple delivery from ENG-122. Mark leans parallel-but-compatible for the latency reason but wants team input. **This is a fork-in-the-road decision.**
- **Personal / "developer-tier" tokens — final shape.** Mark leans toward the same resource:verb scope system as service tokens, but raised a real ergonomic concern: developers need a frictionless pathway to add new admin API endpoints when they hit something missing. An "API composition" library / scaffolding tool may be appropriate here. Worth a focused design conversation. Without that pathway, devs default to the shared CLI cred, and we drift back.

### Refinement / inputs needed

- **Scope vocabulary enumeration.** Resource:verb (`cameras:read`) is the working default, but some viewsets (bulk operations, sqlexplorer, mgmt actions) don't map cleanly to a single resource. Need a one-pass enumeration of admin's viewsets → declared resource → required scope. Probably a Phase-3 starter task.
- **Degradation behavior per consumer (specifics).** §5e lists the options menu. Per-service decisions for vms-connector, queue-consumer, autopatrol-server land during Phase 0 reviews.
- **Audit-log durable storage.** NR events for near-term querying, plus durable retention of ≥ 1 year. Postgres audit table on the admin DB itself, or S3 + Athena, or a dedicated audit DB? Tradeoff: same-DB has nice transactional semantics but adds write volume to the very DB we're hardening.
- **Staleness alarm thresholds per service.** §5e specifies a "consumer-has-been-on-cached-config-for-N-minutes" alert. N is per-service; needs per-service estimates.

### Follow-up — `AdminDAO` call-site audit ✓ landed 2026-05-11

See [[2026-05-11_admindao-call-site-inventory]] for the full inventory. Headline: **only 12 call sites total**, of which **6 are mechanical swaps** to existing `AdminApi` methods (~4h), **4 need one new endpoint** (`GET /api/option/?metric_names=...` for billing pipeline `get_product_by_metrics()` lookups, ~16h), and **3+ are out of scope** (BI notebooks, admin's own mgmt commands). Migration is tractable in roughly one focused sprint. The billing path (vms-connector) is the riskiest cutover and needs careful test coverage of the emit invariant.

### Follow-up — admin incident catalog ✓ landed 2026-05-11

See [[2026-05-11_admin-incident-catalog]] for the full catalog. Headline: **5 incidents over Feb–Apr 2026** clustering into three failure-mode categories. **Runaway query / N+1 / unoptimized CTE is the dominant pattern** (BT-926 + BACK-623; worst was 15 min at 98.7% RDS CPU). Highest-ROI Phase 0 controls: CI query-count assertion, slow-query log → NR alert, `statement_timeout` on the read-replica role used by the connector fleet, read replica itself, and dry-run migrations on prod snapshot before major-version upgrades.

---

## 7. Prior Discussion (distilled, 2026-05-11)

Mark and Tati picked up a long-standing thread on Slack. Tati had been arguing for years that "nothing should have direct DB access," while Mark — at the time — was pigeonholed by a different problem (Genesis 10k-camera sync) and pushed back. The 2026-05-11 conversation is Mark conceding the point and asking how to scaffold the change.

Key positions:

- **Tati** frames it as three concentric layers: (1) user client access — should be SSO, not username/password, with Adam's preference being no CLI access at all, though Tati notes firefighting realities; (2) other applications with direct DB — specific user with specific permissions; (3) actuate-libraries through admin API — each application its own API key with specific permissions. Notes that **admin already has** something to mint per-user API tokens with specific permissions, but "it's more of a matter of enforcing so not everything is using the same superuser access." Suggests **read-only CLI default with a break-glass writer** for emergencies.
- **Mark** agrees superuser CLI access is okay for one-offs while the model hardens but should go long-term, agrees on per-service users for app-direct, and suggests API-key-based access for libraries — possibly via an AWS API Gateway layer mapping to IAM groups. Argues *all* DB writes should funnel through admin's API surface so the "where did this change come from" search starts and ends in admin code; today a write could come from anywhere with the secret.
- **Adam** (referenced, not in the thread) is against direct CLI DB access at all.
- **Vini** (referenced) is already running a throughput-managed external API — a partial reference for what scoped-token + rate-limit looks like.

The recommendation in §4 reflects all four positions: SSO + read-only-default CLI (Tati's framing of layer 1, accommodating Adam's preference with Tati's firefighter realism); per-service Postgres roles for the small set that stays direct (Tati's layer 2); scoped API tokens for everyone else, routed through admin's REST API (Tati's layer 3 + Mark's "writes must go through admin" framing + Vini's pattern).

---

## 8. Next Actions

After the 2026-05-11 decisions landed, the action set is:

1. **Completed 2026-05-11:**
   - [x] System-wide `AdminDAO` call-site audit → [[2026-05-11_admindao-call-site-inventory]]
   - [x] Admin incident catalog (last ~12 months) → [[2026-05-11_admin-incident-catalog]]
2. **Schedule team discussion** on the two remaining open decisions in §6 (Vini's gateway: extend vs. parallel; developer-tier token shape + API-composition library question).
3. **File the Jira epic** once §6 decisions are made — likely a BACK epic with linked child tickets per phase. Phase 2's child tickets are now well-bounded thanks to the call-site inventory.
4. **Phase 1 work can start immediately** — secret rotation + `pg_hba` tightening + audit logging are wins regardless of any remaining decisions.
5. **Phase 0 baseline reliability work** can start with the high-ROI controls identified in the incident catalog: CI query-count assertion, slow-query log → NR alert, `statement_timeout` on the connector read-replica role, read replica itself, prod-snapshot dry-run for migrations.
6. **Concept notes to spin up next:**
   - `concepts/2026-XX-XX_scope-vocabulary.md` — resource:verb enumeration across admin viewsets
   - `concepts/2026-XX-XX_audit-log-durability.md` — answers the "where does the ≥1-year audit trail live" question (Postgres audit table vs. S3+Athena vs. dedicated audit DB)
   - `concepts/2026-XX-XX_consumer-degradation-vms-connector.md` (one per high-volume consumer) — finalizes the per-service option from the §5e menu
