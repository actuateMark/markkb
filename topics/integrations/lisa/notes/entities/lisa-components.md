---
title: "Lisa Integration Components"
type: entity
topic: integrations/lisa
tags: [integration, lisa, alarm-sender, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-06-25
---

# Lisa Integration Components

The Lisa integration spans two libraries: `LisaAlertSender` in [[actuate-alarm-senders]] for queuing alerts, and `LisaClient` in [[actuate-integration-calls]] for direct HTTP communication with the Lisa (Leitstellensoftware) monitoring platform API.

## Class Hierarchy -- LisaAlertSender

`LisaAlertSender` extends `EventListenerAlertSender` -> `AttachmentAlertSender` -> `BaseAlertSender`. It is the only sender currently wired for the clips pipeline -- `send()` is a no-op (returns immediately), while `send_clips()` handles `ClipsAlertData` objects. Only clips with `tag == "Verified"` are forwarded; unverified clips are silently skipped.

## Alert Format

The `_send_to_lisa()` method constructs a payload with `account_number`, `area` (from the camera's frontel fields), `zone`, `event` (first detected label uppercased, e.g. `"INTRUDER"`), `text` (description string), and a `url` pointing to the Actuate clips viewer with frontel tab pre-selected. For direct frontel events (no detected labels), the event and text are taken from the clip data's `event` attribute. Additional fields include `timezone`, `ref`, `connection` (cnxtype), and `sourcetype`.

## LisaClient (actuate-integration-calls)

`LisaClient` is a standalone HTTP client for the Lisa webhook API. It supports four POST endpoints: `/events/actuate` (structured JSON), `/ev/event/{ObjectNumber}/{event}`, `/ev/oevent/{oid}/{event}`, and `/ev/device/{id}/{event}` (text body). The `make_event_payload()` method produces a dict matching the Lisa event schema: `TYPE` set to `"ACTUATEEVENT"`, a UUID `MID`, ISO8601 `CREATED` timestamp, `ID` (account number), `AREA`, `ZONE`, `EVENT`, `TEXT`, `URL`, `REF`, `CONNECTION`, `SOURCETYPE`, and an empty `additionalData` dict.

## Delivery Mechanism

`LisaAlertSender` sends to SQS FIFO queue `event_queue_lisa_alarm.fifo`, iterating over each `lisa_config` in `self.config.recipients`. The downstream consumer uses `LisaClient` to POST to the Lisa server. The default Lisa server is `lisaapi.leitstellensoftware.de:16123` over HTTP.

## Key Config Fields

Per-recipient: `lisa_server` (base URL) and `lisa_token` (bearer token). Clip-level fields: `frontel_area`, `zone`, `customer_account`, `timezone`, `ref`, `cnxtype`, `sourcetype`.

## Auth Method

Bearer token authentication -- `lisa_token` is sent as an `Authorization: Bearer` header by `LisaClient`. The token is configured per-recipient and passed through the SQS queue to the consumer.
