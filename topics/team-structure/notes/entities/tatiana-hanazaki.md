---
type: entity
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [person, engineering, admin-api, database, backend, autopatrol]
---

# Tatiana Hanazaki

Tatiana Hanazaki is a senior backend engineer at Actuate and the **core maintainer of the Admin API** ([[admin-api/_summary|Actuate Admin API]]), with an extraordinary **3,336 commits** to the codebase. This commit count makes her by far the most prolific contributor to the platform's configuration and management layer.

## Current Work (April 2026)

Tatiana's active tickets span backend infrastructure, product features, and performance:

- **PROD-116 -- Line crossing separation.** [[line-crossing-detection|Line crossing detection]] is near GA (beta showed 86-98% alert reduction). Tatiana's work involves separating line crossing logic from the intruder [[detection-pipeline|detection pipeline]] so it can be independently configured and deployed. This uses the intruder model combined with a TrajectoryManager component.
- **BACK-638 -- [[database-performance|Database performance]].** A critical ongoing effort addressing Aurora PostgreSQL CPU spikes caused by recursive CTEs. This is tracked as a key platform risk (see also BT-926 / BACK-623). The Admin API's Django ORM queries are a primary source of these expensive database operations.
- **AUTO-500 -- AutoPatrol backend.** Backend support for the AutoPatrol initiative (H1.2), ensuring the Admin API exposes the necessary endpoints and data models for AutoPatrol's flex ignore-zone and scheduling features.

## Technical Domain

The [[admin-api/_summary|Actuate Admin API]] is a Django 6.0 + Django REST Framework application deployed on ECS. It serves as the central configuration hub for the entire Actuate platform -- managing customers, sites, cameras, analytics settings, integrations, schedules, and user accounts. With 3,336 commits, Tatiana has shaped virtually every aspect of this service.

Her [[database-performance|database performance]] work is particularly significant because the Admin API's PostgreSQL database (Aurora) underpins configuration for all of Actuate's camera processing. CPU spikes from inefficient queries can cascade into delayed configuration updates, which in turn affect connector pod behavior and alert delivery.

## Cross-Team Impact

Tatiana's Admin API work is a dependency for nearly every other engineer:

- [[vinicius-flores]] needs Admin API endpoints for external API schedules.
- [[mark-barbera]] needs Admin API support for AutoPatrol and CHM.
- [[brad-murphy]] consumes Admin API endpoints from the frontend.
- Integration work ([[integrations/morphean/_summary|Morphean]], [[integrations/evalink/_summary|Evalink]]) requires Admin API configuration models for partner-specific settings.

## See Also

- [[admin-api/_summary|Actuate Admin API]] -- the service she maintains
- [[data-flow-architecture]] -- the Admin API's role in the data flow
- [[active-risks]] -- DB CPU spike risk
