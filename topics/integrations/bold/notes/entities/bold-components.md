---
title: "Bold Integration Components"
type: entity
topic: integrations/bold
tags: [integration, bold, alarm-sender, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-config.md
  - topics/actuate-platform/notes/concepts/job-executor-architecture.md
  - topics/admin-api/notes/concepts/integration-architecture.md
  - topics/camera-health-monitoring/notes/syntheses/chm-diagnostics-gap-analysis.md
  - topics/fleet-architecture/notes/concepts/downstream-consumer-impact.md
  - topics/integrations/bold/_summary.md
  - topics/vms-connector/_summary.md
incoming_updated: 2026-05-01
---

# Bold Integration Components

The `BoldAlertSender` class in [[actuate-alarm-senders]] sends detection alerts to Bold monitoring stations over raw TCP sockets using an XML-based SIA protocol. Unlike most other senders, Bold does not use an SQS queue -- it connects directly to the Bold server at send time.

## Class Hierarchy

`BoldAlertSender` extends `AttachmentAlertSender` -> `BaseAlertSender`. It does not use `EventListenerAlertSender` because delivery is synchronous TCP, not queue-based. The sender accepts an `ses_client` at construction (mirroring the Immix pattern) though it is not actively used in the current `send()` flow.

## BoldSocket Helper

The `BoldSocket` class encapsulates the TCP connection and SIA XML protocol. It constructs XML packets with `<Packet ID="{id}">` as the root, containing a `<Signal>` element with `EvType="SIA"`, an `Event` attribute (alarm type code like `"RP"`), a `<Zone>` child set to `"1"`, and a `<URL>` element for the alert link. Packets are framed with STX (`\x02`) and ETX (`\x03`) delimiters. The class also supports heartbeat packets via `<Heartbeat>` elements. Binary image attachment support (base64-encoded JPEG in `<Binary>` / `<Data>` elements) exists in the code but is currently commented out.

## Delivery Mechanism

`BoldAlertSender.send()` iterates over each configured recipient, instantiates a `BoldSocket` with the recipient's `server` IP, `port`, and `id`, then calls `sendBoldAlert()`. This opens a raw TCP socket (`socket.AF_INET, socket.SOCK_STREAM`), sends the XML packet via `sendall()`, waits briefly for a response, and disconnects. Each send is a fresh TCP connection.

## Key Config Fields

Per-recipient: `server` (IP list), `port` (port list), `id` (Bold account/panel ID), and `alarmtype` (SIA event code, e.g. `"RP"` for panic alarm). The alert URL is passed through from `alert_data.alert_url`.

## Auth Method

No authentication -- Bold relies on the `id` field in the XML packet to identify the alarm source. Network-level security (firewall rules, VPN) is assumed for the TCP connection.
