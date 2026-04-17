---
title: "Source: Queue Consumer AWS Permissions Inventory"
type: source
topic: infrastructure
tags: [worklog, queue-consumer, aws, permissions, iam, workshop]
ingested: 2026-04-14
author: kb-bot
---

# Queue Consumer AWS Permissions Inventory

Source: workshop inventory of AWS services accessed by queue consumers.

## Services Required

The queue consumer currently requires permissions for:

- **S3** -- object storage (frames, artifacts)
- **DynamoDB** -- state/metadata tables
- **API Gateway** -- calling internal APIs
- **Redshift** -- analytics data warehouse
- **SQS** -- message consumption
- **External internet outbound** -- calls through firewall to customer endpoints

## Noted Concern

The original note flags that this permission set is overly broad: "split this up later so as to limit consumers that don't need like half of these permissions." The recommendation is to apply **least-privilege** by creating separate IAM roles scoped to each consumer's actual needs, rather than sharing a single permissive role across all queue consumers.
