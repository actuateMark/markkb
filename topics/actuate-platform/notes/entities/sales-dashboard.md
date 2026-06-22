---
title: "sales-dashboard"
type: entity
topic: actuate-platform
tags: [sales, dashboard, ordway, hubspot, snowflake, fastapi, internal-tool]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/_summary.md
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/aws-cost/_summary.md
  - topics/aws-cost/notes/entities/actuate-cost-analysis.md
  - topics/aws-cost/notes/syntheses/2026-04-27_aws-cost-topic-spinoff.md
  - topics/aws-cost/notes/syntheses/cost-architecture.md
  - topics/billing/_todos.md
  - topics/billing/notes/concepts/2026-05-11_billing-reconciliation-dashboard-design.md
  - topics/billing/notes/concepts/2026-05-11_eng-242-substantially-answered.md
  - topics/billing/notes/entities/sales-dashboard-repo.md
incoming_updated: 2026-05-27
---

# sales-dashboard

A unified internal dashboard that merges account growth, infrastructure cost, and revenue data from four external sources into a single view. Built as a read-only FastAPI service with a static vanilla JS + Chart.js frontend.

**Repo:** `aegissystems/sales-dashboard` (GitHub, private)
**Language:** Python (FastAPI/uvicorn backend), JavaScript (static frontend)
**Last updated:** 2026-04-10

## Data Sources

| Source | Role |
|---|---|
| **Ordway** | Master account list -- invoices, revenue, payment status, camera counts |
| **S3 CSVs** | Daily per-site infrastructure cost (compute, inference, slicing, storage) |
| **HubSpot** | CRM enrichment -- company type, status, owner |
| **Snowflake** | Site hierarchy, billed cameras, usage trends |

## Architecture

The backend follows a layered design: routers (API + page routes) call into services (`dashboard.py` for orchestration, `account_matcher.py` for name normalization), which fan out to stateless clients (one per data source). A two-layer cache (L1 in-memory TTL, L2 backed by the `actuate-sales-dashboard` S3 bucket) eliminates cold-start latency across pod restarts.

Account matching uses a two-pass algorithm: Pass 1 builds from Ordway customers (the master list), Pass 2 adds S3 cost-only accounts not matched in Pass 1. Manual cross-system name mappings are stored in S3 (`links/manual_links.json`) and loaded into an in-memory alias dictionary at startup.

## Deployment and Local Dev

Runs on Kubernetes with multiple replicas. S3 provides shared state (cache and manual links) across pods. Credentials are stored in AWS Secrets Manager (`prod/actuate/sales-dashboard`) and pulled into `.env` during local setup. The server runs via `uvicorn sales_dashboard.main:app`.

Key operational note: the `reports@actuate.ai` Snowflake account locks after multiple failed login attempts and may require a Snowflake admin to manually unlock it. Developers should verify the password before starting the server.

## Related Services

- **Ordway** -- billing/revenue source of truth
- **Snowflake (GOLD database)** -- analytics warehouse for site hierarchy and usage
- **Admin Postgres** -- used by supplementary scripts like `reconcile_cameras.py`

## Related Topics

- [[aws-cost/_summary]] — cost-research topic. This dashboard is the operational surface that exposes per-site daily AWS cost data (compute / inference / slicing / storage) to the team. The data ingest pipeline (S3 CSV feed in `actuate-sales-dashboard` bucket) is where Cost Explorer numbers become per-site rows. Live UI is auth-walled (Cognito) at <https://sales-dashboard.internal.actuateui.net/> — schema documented above.
