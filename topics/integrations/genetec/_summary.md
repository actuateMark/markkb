---
title: "Genetec Integration"
type: summary
topic: integrations/genetec
tags: [integration, vms, genetec, security-center]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Genetec Integration

Genetec Security Center is a major enterprise VMS and unified security platform. Actuate integrates with Genetec as an alert destination, triggering alarms in Security Center via the **Web SDK REST API**.

## Components

### GenetecAlertSender (alarm sender)

Defined in [[actuate-alarm-senders]] at `genetec/genetec_alert_sender.py`. Extends `AttachmentAlertSender`. Alerts are sent **synchronously via HTTP REST** to the Genetec Web SDK -- no SQS queue is involved.

The alert flow is a three-step process:

1. **Resolve alarm GUID** -- `GET http://{server_ip}:4590/WebSdk/report/EntityConfiguration?q=EntityTypes@Alarm,Name={label}` -- Queries the Security Center entity configuration to find an alarm entity matching the detection label name. Parses the XML response to extract the alarm's GUID.

2. **Resolve camera GUID** -- `GET http://{server_ip}:4590/WebSdk/report/EntityConfiguration?q=EntityTypes@Camera,Name={camera_name}` -- Queries for the camera entity matching the Actuate camera name. Parses XML for the camera GUID.

3. **Trigger alarm** -- `GET http://{server_ip}:4590/WebSdk/alarm?q=TriggerAlarm({alarm_guid},{camera_guid})` -- Triggers the alarm with the associated camera as the source.

This design means:
- Alarm entities must be **pre-configured** in Genetec Security Center with names matching Actuate detection labels (e.g., "intruder", "gun").
- Camera entities in Security Center must have names matching the Actuate camera names.
- The Web SDK runs on port **4590** (hardcoded).

The sender retries up to 3 times on failure.

Config fields: `customer.server_ip`, `customer.server_username`, `customer.password`.

## Auth Method

**HTTP Basic Auth** using `server_username` and `password` from the customer configuration. All three API calls use the same credentials passed via `requests` auth parameter.

## Alert Delivery

Genetec alerts are fully **synchronous** within the [[actuate-alarm-senders]] `MultiAlertSender` thread pool. Each alert involves three sequential HTTP requests (alarm lookup, camera lookup, trigger), making it one of the heavier alert flows. The XML response parsing uses Python's built-in `xml.etree.ElementTree`.

## Architecture

The [[vms-connector]] builds the `GenetecAlertSender` via the alarm sender factory when a Genetec config is present. Streams from Genetec cameras are consumed via standard RTSP URL-based pullers in [[actuate-pullers]] (no Genetec-specific puller). There are no Genetec-specific integration calls in [[actuate-integration-calls]] -- the sender handles all Genetec API communication internally.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- GenetecAlertSender lives here, extending AttachmentAlertSender
- [[vms-connector]] -- builds the sender via the factory during camera initialization
- [[actuate-pullers]] -- standard URL pullers used (no Genetec-specific puller)
- No corresponding module in [[actuate-integration-calls]]
