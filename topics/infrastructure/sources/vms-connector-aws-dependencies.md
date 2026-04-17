---
title: "Source: VMS Connector AWS Dependency Inventory"
type: source
topic: infrastructure
tags: [worklog, vms-connector, aws, workshop, dependencies]
ingested: 2026-04-14
author: kb-bot
---

# VMS Connector AWS Dependency Inventory

Source: workshop inventory of AWS services the VMS connector depends on.

## AWS Services

- **DynamoDB** -- primary data store for frames, heartbeats, camera status, etc.
- **S3** -- object storage for images and artifacts
- **Redshift** -- analytics/BI data warehouse
- **API Gateway** -- internal API access
- **Lambda** -- event-driven functions triggered by the connector
- **SES** -- outbound email (alerts, reports)
- **SNS** -- topic-based message publishing (alert fan-out)
- **SQS** -- message queue consumption
- **Kubernetes** -- direct calls to model servers (inference endpoints)
- **External internet inbound** -- inbound path for receiving VMS events
- **External internet outbound** -- outbound calls through firewall to customer systems

## Observations

The VMS connector has the broadest AWS dependency surface of any single service, touching 11 distinct AWS services plus external network paths. This makes it a key focus area for:
- IAM role scoping and least-privilege work
- Dependency mapping when planning infrastructure changes
- Blast radius analysis during outages
