---
type: entity
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [person, engineering, external-api, scheduling]
---

# Vinicius Flores

Vinicius Flores is a software engineer at Actuate whose primary focus is the **External API** initiative -- the effort to expose partner-facing REST endpoints for detection, scheduling, image ingestion, and arm/disarm operations.

## Current Work (April 2026)

Vinicius is the primary developer on schedule-related external API endpoints, with three active tickets:

- **ENG-123 -- External API schedule endpoints (Primary).** This is the main deliverable: RESTful endpoints that allow integration partners (e.g., EBUS, AlarmWatch, Alarmquip) to programmatically create, read, update, and delete monitoring schedules for cameras. Schedules control when Actuate processes frames for a given camera, which directly affects billing and alert delivery.
- **ENG-34 -- Arm/disarm functionality.** Closely related to scheduling, arm/disarm lets partners enable or disable monitoring for a site or camera on demand -- essentially an immediate schedule override. This is a commonly requested feature from monitoring center partners who need real-time control during guard responses or customer requests.
- **ENG-125 -- Additional schedule endpoint work.** A companion ticket to ENG-123 covering edge cases or supplementary schedule operations.

## Technical Context

The External API is built on [[inference-api/_summary|Actuate Inference API]] (FastAPI + Mangum, deployed as Lambda containers). Vinicius's schedule endpoints interact with the [[admin-api/_summary|Actuate Admin API]] (Django 6.0 + DRF on ECS) where schedule data is persisted, likely via internal service calls or shared database access.

The six workstreams of the External API initiative are: detection, scheduling, image ingestion, arm/disarm, camera management, and site management. Vinicius owns the scheduling and arm/disarm workstreams.

## Strategic Importance

The External API initiative is critical to Actuate's partner integration strategy. Partners like EBUS (European, v5 API update pending with [[mark-barbera]]), AlarmWatch, and Alarmquip need programmatic access to Actuate's capabilities. Schedule endpoints specifically enable partners to automate monitoring windows, reducing manual configuration overhead and improving time-to-value for new deployments.

## See Also

- [[external-api/_summary|External API Initiative]] -- the parent initiative
- [[data-flow-architecture]] -- where the external API fits in the overall system
- [[mark-barbera]] -- EBUS v5 API work, a related external API effort
