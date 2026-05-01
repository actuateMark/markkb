---
title: "Alarmquip (AU)"
type: entity
topic: external-api
tags: [alarmquip, customer, australia, image-ingestion, smtp]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Alarmquip (AU)

Alarmquip is an Actuate customer based in Australia. They are the driver behind the **image ingestion** workstream (ENG-124) within the [[external-api/_summary|External API Initiative]] initiative.

## Image Ingestion -- SMTP Alternative (ENG-124)

Alarmquip's core need is an alternative path for getting images into the Actuate platform for AI detection. The standard Actuate pipeline ingests images via direct camera connections managed by the [[vms-connector]]. Alarmquip requires an alternative that accepts images via an API endpoint, bypassing the need for direct camera-to-Actuate connectivity.

This workstream is described as an "SMTP alternative" -- the existing image ingestion path for some customers uses SMTP (email-based image delivery), and the ENG-124 endpoint would provide a modern REST API equivalent.

**Status:** To Do
**Assignee:** Unassigned (as of April 2026)

## Use Case

The image ingestion endpoint would allow Alarmquip (and potentially other customers) to:

1. Capture a JPEG frame from their own camera infrastructure
2. POST it to an Actuate API endpoint
3. Receive detection results back (or have them delivered asynchronously)

This is conceptually similar to the [[v5-api-design]] detection endpoint used by [[integrations/ebus/_summary|EBUS]], but focused on customers who want to push images from their own systems rather than having Actuate pull from cameras directly.

## Architecture

Like the other [[external-api/_summary|External API Initiative]] workstreams, the image ingestion endpoint is expected to follow the [[shared-auth-pattern]]:

```
Alarmquip -> AWS API Gateway -> Rust Lambda Authorizer -> K8s pods (endpoint)
```

The endpoint would be built on the [[admin-api/_summary|Actuate Admin API]] infrastructure since it involves customer and camera metadata resolution, not just raw inference.

## Relationship to Other Workstreams

| Workstream | Customer | Type | Ticket |
|-----------|----------|------|--------|
| Detection (v5) | [[integrations/ebus/_summary|EBUS]] | Inference | ENG-126 |
| Schedule Management | [[alarmwatch-customer]] | Admin | ENG-123 |
| Arm/Disarm | [[alarmwatch-customer]] | Admin | ENG-125 |
| **Image Ingestion** | **Alarmquip** | **Admin** | **ENG-124** |

## Context

Alarmquip is based in Australia, which means latency to US-based infrastructure and timezone differences are relevant considerations for the endpoint design. The [[inference-api/_summary|Actuate Inference API]] has production deployments in both us-west-2 and eu-west-1, but an Asia-Pacific region is not currently listed.
