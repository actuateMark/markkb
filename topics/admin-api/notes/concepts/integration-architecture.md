---
title: "Integration Architecture"
type: concept
topic: admin-api
tags: [integrations, alarm-sender, config, vms-connector, admin]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Integration Architecture

The [[admin-api/_summary|Actuate Admin API]] serves as the central configuration hub for 29+ integrations with third-party monitoring platforms. Each integration connects Actuate's AI detection outputs to a customer's existing security infrastructure -- alarm monitoring stations, video management systems, and central monitoring software.

## Integration Scope

The Admin API manages configuration for the following integration types (among others):

- **Immix** -- central station monitoring
- **Axis** -- camera manufacturer integration
- **Mobotix** -- camera manufacturer integration
- **[[bold-components|Bold]]** -- monitoring platform
- **Patriot** -- monitoring software
- **LISA** -- monitoring platform
- **[[evalink-components|Evalink]]** -- alarm management
- **SureView** -- monitoring platform
- **[[sentinel-components|Sentinel]]** -- monitoring software
- **[[softguard-components|SoftGuard]]** -- monitoring software
- **Eagle Eye** -- cloud VMS
- **YourSix** -- cloud video surveillance
- **Frontel** -- monitoring platform
- **Umbo** -- AI camera platform

And many more, totaling 29+ distinct integration types as of April 2026.

## Configuration Pattern

Each integration is represented as a Django model in the Admin API with its own set of configuration fields. Common patterns across integrations include:

- **Connection settings** -- hostnames, ports, API endpoints, credentials
- **Mapping rules** -- how Actuate detection events translate to the partner's alarm format (zone IDs, event codes, priority levels)
- **Customer assignment** -- which customers have which integrations enabled
- **Per-camera overrides** -- integration behavior can vary by camera or site

The Admin API exposes CRUD endpoints for each integration type via Django REST Framework, allowing the Actuate UI and internal tools to manage these configurations.

## Alarm Sender Types

Integrations in the Actuate platform operate through "alarm senders" -- components in the [[vms-connector]] that read configuration from the Admin API and translate Actuate detection events into the format expected by each third-party platform. The Admin API manages the configuration; the vms-connector executes the alarm delivery.

This separation means:

1. The Admin API is the **source of truth** for integration config
2. The vms-connector reads this config (via API calls and config files) and performs the actual alarm sending
3. Changes to integration settings in the Admin API take effect when the vms-connector next reads the updated config

## Relationship to External API

The [[external-api/_summary|External API Initiative]] initiative is adding new integration patterns where external partners call into Actuate (rather than Actuate pushing alarms out). These partner-facing endpoints (schedule management for [[alarmwatch-customer]], image ingestion for [[alarmquip-customer]]) are built on top of the Admin API but exposed through the standardized [[shared-auth-pattern]] with API Gateway and the [[rust-lambda-authorizer]].

## Related Resources

- **API Scope:** 50+ resource types across core, AI/ML, integrations, AutoPatrol, health, scheduling, webhooks, and infrastructure
- **Swagger docs:** Available at `/swagger/` on each environment
- **Key maintainer:** [[tatiana-hanazaki|Tatiana Hanazaki]] (3,336 commits)
