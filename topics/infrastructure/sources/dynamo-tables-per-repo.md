---
title: "Source: DynamoDB Table Mapping by Repository"
type: source
topic: infrastructure
tags: [worklog, dynamodb, aws, workshop, vms-connector, queue-consumer]
ingested: 2026-04-14
author: kb-bot
---

# DynamoDB Table Mapping by Repository

Source: workshop inventory mapping DynamoDB tables to the repositories that use them.

## VMS Connector Tables

- **Heartbeat** -- connection liveness tracking
- **CameraStatus** -- current camera state
- **EnrichedFrameV2** -- enriched frame metadata
- **WindowIdsV2** -- detection window identifiers
- **Image_Data_2** -- image/frame binary metadata
- **PeopleFlow** -- people-counting analytics
- **Blacklist** -- blocked entity tracking
- **Camera_Healthchecks** -- per-camera healthcheck results

## Queue Consumer Tables

- **Heartbeat** -- shared with VMS connector
- **Harddrive_Healthcheck** -- disk health monitoring
- **EnrichedFrameV2** -- shared with VMS connector

## Key Observations

- Several tables are shared across repos (Heartbeat, EnrichedFrameV2), indicating coupling points.
- The VMS connector is the heaviest DynamoDB consumer with 8 tables.
- This inventory was produced as part of an architecture workshop to map out AWS dependencies per service.
