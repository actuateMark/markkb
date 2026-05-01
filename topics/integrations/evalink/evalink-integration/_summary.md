---
title: Evalink Integration
type: summary
topic: integrations/evalink
tags: [evalink, alarm-management, protectas, integration]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/232325125"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Evalink Integration

**[[evalink-components|Evalink]]** is a cloud-based alarm management platform used by monitoring centers (ARCs). Initial customer: **Protectas** (Swiss security company).

## What It Does

Outbound alert push: when Actuate detects a threat, the alert is forwarded to the customer's [[evalink-components|Evalink]] alarm management console via REST API.

## Configuration

- **Site level:** evalink company ID, device ID
- **Fields:** Server URL, API token, device ID
- **Delivery:** SQS FIFO queue -> `EvalinkAlertConfig` alarm sender

## Status

Near-production / shipped. Oldest integration doc (Dec 2025). Alarm sender exists in `actuate-alarm-senders` codebase. Fields being moved from camera level to site level (UI-204, UI-202).

## Confluence

- [Integration Requirements](https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/232325125)
