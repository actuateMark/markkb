---
title: "Source: AdminDAO Deprecation -- Decoupling Camera Models"
type: source
topic: actuate-platform
tags: [worklog, admindao, camera-model, decoupling, monitoring, migration]
ingested: 2026-04-14
author: kb-bot
---

# AdminDAO Deprecation -- Decoupling Camera Models

Source: internal architecture discussion on decoupling the admin camera model from monitoring.

## Problem

Monitoring services depend directly on the admin Postgres database to read camera configuration. This couples the admin and monitoring domains, creates load on admin Postgres, and means changes to the admin camera model can break monitoring.

## Proposed Solution

Introduce a **separate monitoring-specific table** (location-agnostic, possibly DynamoDB) containing only the fields monitoring needs. The flow becomes:

1. During onboarding and admin updates, admin writes relevant camera data to the new monitoring table.
2. A one-time migration script copies existing camera data from admin Postgres to the new table.
3. Monitoring reads exclusively from this new table, removing its dependency on admin Postgres.
4. If monitoring encounters a connection failure for a camera, it calls a single admin API endpoint to check for updates, then patches its own row -- a lazy-refresh pattern rather than constant polling.

This fully decouples the admin concept of the camera model from the monitoring concept. As long as the admin API endpoint and the monitoring table write contract remain stable, the two systems can evolve independently.

## AdminDAO Library Migration

For `admindao` specifically, the plan is:

1. Create a new library that mirrors the existing admindao interface (same function names and signatures).
2. Behind the scenes, each function call becomes an API call to admin instead of a direct Postgres query.
3. Migrate raw SQL scripts case-by-case -- each query must be translated into an admin API call.

This is a significant effort but necessary to prevent cascading coupling problems across the platform.

## Key Insight

The same decoupling pattern (dedicated read-model table + API bridge + lazy refresh) should be applied anywhere a service directly queries another service's database.
