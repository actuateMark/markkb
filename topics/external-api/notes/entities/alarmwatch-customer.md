---
title: "AlarmWatch / Crosbies (NZ)"
type: entity
topic: external-api
tags: [alarmwatch, crosbies, customer, new-zealand, schedule, arm-disarm]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# AlarmWatch / Crosbies (NZ)

AlarmWatch (also referred to as Crosbies) is an Actuate customer based in New Zealand. They are the primary driver behind two [[external-api/_summary|External API Initiative]] workstreams: **schedule management** and **arm/disarm per site**.

## Schedule Management (ENG-123)

AlarmWatch needs to programmatically manage detection schedules through an API rather than through the Actuate UI. This workstream is the most progressed of the [[external-api/_summary|External API Initiative]] initiative.

**Key milestones:**
- **PR #4 merged** (April 10, 2026) -- DynamoDB mapping layer for schedule data
- **Kubernetes deployment merged** (k8s #328)
- Currently in test phase

**Assignee:** [[vinicius-flores|Vinicius Flores]]

The implementation provides endpoints for managing schedules and flex-schedules, backed by the [[admin-api/_summary|Actuate Admin API]]'s existing scheduling models (`schedule`, `schedule_location`, `calendar`, `calendar_event`, `flex_schedule`).

**Open question:** Should the `/schedule` and `/flex-schedule` endpoints be restricted to AlarmWatch only, or made available to all external API consumers? This decision affects whether the endpoints are generic (reusable by future partners) or customer-specific.

## Arm/Disarm Per Site (ENG-125 / ENG-34)

AlarmWatch also needs the ability to arm and disarm detection on a per-site basis via API. This allows their monitoring operators to enable or disable Actuate AI detection for specific locations without logging into the Actuate platform.

**Assignee:** [[vinicius-flores|Vinicius Flores]] (working in parallel with schedule management)
**Status:** To Do

## Architecture

Both AlarmWatch workstreams follow the standardized [[shared-auth-pattern]]:

```
AlarmWatch -> AWS API Gateway -> Rust Lambda Authorizer -> K8s pods (Admin API endpoints)
```

The endpoints are built on top of the [[admin-api/_summary|Actuate Admin API]] (Django/DRF) but exposed externally through API Gateway with authentication handled by the [[rust-lambda-authorizer]] and DynamoDB key lookup.

## Context

AlarmWatch represents a class of customer that needs deeper API integration than what the Actuate UI provides. Their requirements are driving the design of the external API's admin-facing endpoints, much as [[integrations/ebus/_summary|EBUS]] is driving the detection-facing v5 endpoints. The patterns established for AlarmWatch (schedule CRUD, arm/disarm) are expected to generalize to other customers.
