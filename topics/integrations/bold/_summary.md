---
title: "Bold Integration"
type: summary
topic: integrations/bold
tags: [integration, monitoring, bold, manitou]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Bold Integration

Bold (Manitou) is a professional alarm monitoring platform. Actuate integrates with Bold as an alert destination, sending AI-generated detection events over a **raw TCP socket** using the SIA protocol with XML-formatted packets.

## Components

### BoldAlertSender

Defined in [[actuate-alarm-senders]] at `bold/bold_alert_sender.py`. Extends `AttachmentAlertSender` (not EventListenerAlertSender -- Bold alerts are sent **synchronously** rather than via SQS). The sender iterates over configured recipients and creates a `BoldSocket` instance for each, then calls `sendBoldAlert()`.

### BoldSocket

A helper class in the same file that handles the low-level TCP communication with the Bold Manitou receiver. Key characteristics:

- **Protocol:** SIA-format XML packets wrapped with STX (`\x02`) and ETX (`\x03`) framing characters.
- **Connection:** Opens a new TCP socket connection for each alert, sends the packet, waits for acknowledgment, then disconnects.
- **Packet structure:** XML `<Packet>` with an `ID` attribute identifying the account/site, containing a `<Signal>` element with `EvType="SIA"`, the event code (e.g., `RP` for alarm), a `<Zone>` tag, and a `<URL>` tag with the Actuate alert link.
- **Heartbeat support:** `sendHeartBeat()` can send keepalive packets.
- **Image support:** Has methods for base64-encoding images (`processImage`, `addBinary`, `addData`) though image attachment is currently commented out in `sendBoldAlert` -- only the URL is sent.

Config fields: `recipients[].server` (IP), `recipients[].port`, `recipients[].id` (Bold account ID), `recipients[].alarmtype` (SIA event code, default `RP`).

## Auth Method

No API authentication. Bold uses the `ID` field in the XML packet to identify the monitored account/site. Network-level access to the Bold receiver's TCP port is the only requirement.

## Alert Delivery

Unlike most monitoring integrations that use the SQS event-listener pattern, Bold alerts go **directly over TCP** from the [[vms-connector]] process. The `BoldSocket` opens a connection, sends the XML packet, receives the response, and closes. This means alert delivery is synchronous within the `MultiAlertSender` thread pool -- if the Bold server is slow or unreachable, it blocks the sender thread for that camera.

## Architecture

The alarm sender factory in [[actuate-alarm-senders]] instantiates `BoldAlertSender` when a Bold alert config is present. The sender receives `ses_client`, `s3_dao`, and `enriched_frames_dao` dependencies (inherited from `AttachmentAlertSender`), though frame attachment is not currently active. There are no integration calls or puller components -- Bold is a send-only monitoring integration.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- BoldAlertSender lives here, extending AttachmentAlertSender
- [[vms-connector]] -- builds the sender via the factory during camera initialization
- No corresponding module in [[actuate-integration-calls]] or [[actuate-pullers]]
