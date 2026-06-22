---
title: "Database Performance (Recursive CTE CPU Spike)"
type: concept
topic: admin-api
tags: [database, postgresql, performance, aurora, cte, bug]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/concepts/multi-region-deployment.md
  - topics/admin-api/_summary.md
  - topics/admin-api/notes/syntheses/2026-05-13_customer-model-dissection.md
  - topics/data-access-control/notes/concepts/2026-05-11_admin-incident-catalog.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-reliability-fix-plan.md
  - topics/product-roadmap/_summary.md
  - topics/product-roadmap/notes/syntheses/improvement-opportunities.md
  - topics/team-structure/notes/entities/tatiana-hanazaki.md
incoming_updated: 2026-05-27
---

# Database Performance -- Recursive CTE CPU Spike

## The Problem

The [[admin-api/_summary|Actuate Admin API]] experienced severe Aurora PostgreSQL CPU spikes reaching 98.7%, traced to the `get_descendants()` function. This is tracked as **BT-926** (support/ops ticket) and **BACK-623** (engineering ticket).

## Root Cause: get_descendants()

The `get_descendants()` function uses a recursive Common Table Expression (CTE) to traverse the `inframap_group` table hierarchy. Groups in the Actuate platform form a tree structure (customers contain sites, sites contain camera groups, etc.), and `get_descendants()` walks this tree to find all child groups of a given parent.

The recursive CTE pattern looks roughly like:

```sql
WITH RECURSIVE descendants AS (
    SELECT id, parent_id FROM inframap_group WHERE id = <root>
    UNION ALL
    SELECT g.id, g.parent_id FROM inframap_group g
    JOIN descendants d ON g.parent_id = d.id
)
SELECT * FROM descendants;
```

When called frequently (as it is across many Admin API views that need to resolve group hierarchies for permission checks), and against a table with thousands of groups, this query becomes expensive. Without proper indexing, each recursive step performs a sequential scan.

## Impact

At 98.7% CPU utilization, the Aurora cluster is effectively saturated. This manifests as:

- Slow API responses across all Admin API endpoints
- Timeouts on endpoints that trigger group hierarchy lookups
- Cascading effects on downstream services that depend on the [[admin-api/_summary|Actuate Admin API]] for metadata (camera configs, customer data, schedule lookups)

## Remediation Plan

Two complementary fixes have been identified:

### 1. Index on `inframap_group.parent_id`

The `parent_id` column lacks a dedicated index. Adding a B-tree index allows the recursive join (`g.parent_id = d.id`) to use an index lookup instead of a sequential scan, dramatically reducing the cost of each recursive step.

### 2. Caching

The group hierarchy changes infrequently (groups are added/moved rarely compared to how often they are queried). A caching layer -- either in-application (Django cache framework with Redis, already available via Django-Q's broker) or as a materialized view -- would eliminate most recursive queries entirely.

## Current Status (April 2026)

The issue is identified and the remediation is planned but not yet deployed. It sits alongside several other active workstreams including the Django 6.0 upgrade (BACK-604, in QA/QC) and the monitoring API upgrade (BACK-638, in progress).

## Database Infrastructure

- **Engine:** PostgreSQL on Amazon Aurora
- **Cluster:** `actuateadminprodcluster`
- **Connected service:** [[admin-api/_summary|Actuate Admin API]] (Django 6.0, Gunicorn, ECS)

## Related Tickets

- **BT-926** -- Original support/ops report of CPU spike
- **BACK-623** -- Engineering ticket for remediation
