---
title: Data Access Control
type: summary
topic: data-access-control
tags: [security, postgres, rbac, api-keys, secrets, admin-db, db-access]
created: 2026-05-11
updated: 2026-05-13
author: kb-bot
jira: ENG-247
---

# Data Access Control

How services, libraries, and humans authenticate to and are authorized against the Actuate admin Postgres database and the admin API in front of it. The goal of this topic is to track the work of replacing today's broad shared-secret DB access with **per-principal least-privilege access** — typically by funneling reads/writes through the admin API with scoped credentials, and reserving direct DB access for narrow, audited cases.

## Scope

Three concentric layers, all in scope:

1. **Human CLI / firefighter access** to Postgres directly (today: one shared admin secret in Secrets Manager that anyone with access can use to run arbitrary SQL).
2. **Application direct-DB access** — services that connect to Postgres via [[actuate-daos|actuate-daos]] / [[actuate-wireguard|actuate-wireguard]] / `psycopg2` using the same shared secret. Scripted re-audit 2026-05-13 (`/home/mork/work/scripts/data-access-control/`) found ~10–14 AdminDAO call sites plus 2 non-AdminDAO direct-DB consumers (`sales-dashboard`, `actuate-integration-calls/milestone_service.py`).
3. **Application API access** via the admin REST API using API tokens (today: `ExternalApiSetUp` mints per-group tokens, but tokens lack endpoint/operation-level scopes — a token authorized at all is broadly capable). Surface scale: ~89 view classes in [[actuate_admin]] would need scope annotation in Phase 3.

Out of scope (for now): customer-facing data access (alerts UI, partner portals), inference-side data, DynamoDB-backed inference API keys.

## Why now

- Surface area is growing: agents (LLMs / scripts / automations) increasingly need to read or change admin data, and the current model gives any new caller superuser-equivalent access.
- Incident risk: a single leaked or misused shared secret today permits arbitrary destructive SQL anywhere the secret reaches.
- Tati has been advocating per-service users since well before this revival; some structure already exists (`sqlexplorer`, `django_q`, `jobscheduler`, `closeinfo` DB users) and `ExternalApiSetUp` already exists as a foundation to build on.

## Jira

- **ENG-247** — *Research: move away from raw SQL access to postgres in non-admin contexts* (Security epic ENG-4, due 2026-05-22, assigned Mark). Tracks this workstream's deliverable. First progress comment posted 2026-05-13 summarizing direction + AdminDAO audit findings; Confluence write-up to follow once team-discussed shape lands.

## Anchor Notes

- [[2026-05-11_admin-db-access-hardening|2026-05-11 Admin DB Access Hardening]] — problem map, current state, candidate approaches, recommendation, phased migration. **Amended 2026-05-13.** Start here.
- [[team-brief|Team Brief]] — shareable summary, ~1 page, for sending to team for context. **Amended 2026-05-13.**
- [[2026-05-11_admindao-call-site-inventory|AdminDAO Call-Site Inventory]] — Phase 2 migration scope. **Amended 2026-05-13** from scripted re-audit; ~10–14 sites in narrative shorthand, script CSV is authoritative.
- [[2026-05-11_admin-incident-catalog|Admin Incident Catalog]] — 12-month look-back; failure-mode taxonomy; recommended controls.
- [[2026-05-11_admin-reliability-fix-plan|Admin Reliability Fix Plan]] — code-grounded follow-up to the catalog; specific fixes with file:line citations.
- [[2026-05-11_open-question-vini-gateway|Open Question: Vini's Gateway]] — team-discussion note.
- [[2026-05-11_open-question-developer-tokens|Open Question: Developer Tokens]] — team-discussion note.
- [[2026-05-13_dig-followups|2026-05-13 Design Dig Follow-ups]] — pressure-test record from the ENG-247 dig; lists Phase 0 reconciliation, open operational-design questions (token storage / DR / audit-log durability), blind spots in the two open-question notes.

## Scripts (authoritative inventories — re-runnable)

Located at `/home/mork/work/scripts/data-access-control/`. Each emits CSV + markdown. Re-run anytime the repo set changes.

- `admindao-inventory.py` — every AdminDAO usage across `/home/mork/work/`, bucketed A/B/C.
- `postgres-direct-callers.py` — broader Q2 surface: psycopg2, [[actuate-wireguard]], raw connections.
- `admin-api-surface.py` — every view class in [[actuate_admin]] with auth + permission attributes (the Phase 3 scope-vocabulary supply side).

Outputs live in `output/` next to the scripts.

## Related Topics

- [[admin-api/_summary|admin-api]] — what's being protected; existing `ExternalApiSetUp` and Cognito auth live here
- [[external-api/_summary|external-api]] — Vini's throughput-managed external API surface; partial pattern for what scoped tokens look like
- [[infrastructure/_summary|infrastructure]] — AWS Secrets Manager, IAM, API Gateway sit here
- [[engineering-process/_summary|engineering-process]] — review heuristics and security checklists

## Key People

- **[[tatiana-hanazaki|Tatiana Hanazaki]]** — long-standing advocate for limiting direct DB access; owns admin
- **Adam** — against any direct CLI DB access; firefighter case is the open exception
- **Vini** — already running an external API with throughput controls; reference pattern
- **[[mark-barbera|Mark Barbera]]** — revived the conversation 2026-05-11
