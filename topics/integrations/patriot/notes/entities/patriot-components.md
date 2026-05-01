---
title: "Patriot Integration Components"
type: entity
topic: integrations/patriot
tags: [integration, patriot, alarm-sender, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Patriot Integration Components

The `PatriotAlertSender` class in [[actuate-alarm-senders]] delivers detection alerts to Patriot Systems monitoring stations. Patriot is a New Zealand-based central station platform that accepts alerts via its REST API.

## Class Hierarchy

`PatriotAlertSender` extends `EventListenerAlertSender` -> `AttachmentAlertSender` -> `BaseAlertSender`. It uses the event listener queue pattern for asynchronous delivery. The constructor also checks for a `DEPLOYMENT_ID` environment variable to set an `is_container` flag (used to detect containerized vs. EC2 deployments).

## Alert Format

The alert payload for each recipient includes a Patriot-specific `alert` dict with fields: `media` (a `url:` prefixed link to the Actuate alert viewer), `clientNo` (Patriot client number), `rawData` (human-readable text: "ACTUATE ALERT: {camera} at {site} possible {labels} at {time}"), `typeNo` (Patriot type number, defaults to 100), and `zoneUser` (Patriot zone number). The `label_to_event()` method exists with the same label mapping as [[sentinel-components|Sentinel]] (postal vehicles, fire, gun, intruder, loitering, etc.) but the event name is not included in the queue payload -- Patriot uses `typeNo` and `zoneUser` instead.

## Delivery Mechanism

Alerts are dispatched via SQS FIFO queue `event_queue_patriot_alarm.fifo`. The queue message contains the serialized recipients list (each with `patriot_server`, `patriot_client_no`, `patriot_username`, `patriot_password`, `send_video`, `draw_ignore_zones`, and the `alert` dict), plus `custcam_id`, `s3_folder` (window_id), `start_time`, `attachment_frames`, and `label`. A downstream consumer reads the queue and posts to the Patriot REST API.

## Key Config Fields

Per-recipient: `patriot_server` (API base URL), `patriot_client_no`, `patriot_username`, `patriot_password`, `patriot_type_number` (alarm type, defaults to 100), `patriot_zone_number`, `send_video` (boolean), and `draw_ignore_zones`. The `message_group_id` is the customer ID for FIFO deduplication.

## Auth Method

Patriot uses HTTP Basic authentication -- `patriot_username` and `patriot_password` are passed through the queue message to the downstream consumer, which authenticates against the Patriot server's REST API.
