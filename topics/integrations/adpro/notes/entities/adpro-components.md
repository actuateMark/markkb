---
title: "Adpro Integration Components"
type: entity
topic: integrations/adpro
tags: [integration, adpro, components, rtsp]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Adpro Integration Components

Adpro manufactures the XO range of IP video transmission devices used in perimeter security. The Actuate integration connects to Adpro XO transmitters via a custom Rust binary that re-serves the proprietary video streams as local [[rtsp-deep-dive|RTSP]]. The Python-side connector then treats the result as a standard [[rtsp-deep-dive|RTSP]] stream.

## Puller -- Rust Binary ([[adpro-puller]])

Unlike all other Actuate integrations, the [[adpro-puller|Adpro puller]] is **not** a Python class in [[actuate-pullers]]. It is a standalone Rust binary hosted in its own repository. The binary handles the Adpro-proprietary protocol to connect to XO transmitters, retrieves the native video stream, and re-serves it locally as [[rtsp-deep-dive|RTSP]]. This two-stage approach was chosen because the Adpro protocol is more efficiently handled in Rust, while the rest of the Actuate pipeline remains Python.

Once the Rust binary exposes the local [[rtsp-deep-dive|RTSP]] stream, [[vms-connector]] consumes it using the standard [[rtsp-deep-dive|RTSP]]/URL puller path (typically `AvUrlFramePuller` or `GstUrlFramePuller` from [[actuate-pullers]]). From the Python perspective, there is no difference between an Adpro stream and any other [[rtsp-deep-dive|RTSP]] source.

## Config Classes

Adpro sites use the standard [[rtsp-deep-dive|RTSP]] connector config from [[actuate-config]]. In `factory.py`, the `integration_type == "adpro"` routes to the same `RTSPConnectorFactory` as `rtsp` and `milestone_rtsp`:

```python
elif (
    integration_type == "rtsp"
    or integration_type == "milestone_rtsp"
    or integration_type == "adpro"
):
    from ..rtsp.rtsp_factory import RTSPConnectorFactory as Factory
```

This means:
- **RTSPConnectorConfig** parses the settings JSON.
- **RTSPCustomerConfig** handles customer-level fields (protocol, motion settings).
- **RTSPCamera** provides `username`, `password`, and `base_url` per camera.

The Rust binary's own configuration (transmitter IP, port, credentials, channel mappings) is managed outside of [[actuate-config]], typically via environment variables or command-line arguments passed to the binary at startup.

## Integration Calls

There is **no** `actuate-integration-calls` module for Adpro. All communication with the Adpro transmitter happens inside the Rust puller binary. The Python side has no direct API interaction with Adpro hardware.

## Alarm Sender

There is **no** dedicated alarm sender for Adpro. Alert delivery uses whichever monitoring-platform sender (Immix, SureView, webhook, etc.) is configured on the site. Adpro is purely a video-source integration.

## Key Architectural Notes

- The Rust binary must be running and exposing local [[rtsp-deep-dive|RTSP]] before the vms-connector starts pulling frames.
- Credentials for the Adpro transmitter are separate from [[rtsp-deep-dive|RTSP]] camera credentials in the settings file.
- The `base_url` in camera config points to the local [[rtsp-deep-dive|RTSP]] re-serve, not to the Adpro device directly.
- Failover, reconnection, and stream health are handled by the standard [[rtsp-deep-dive|RTSP]] puller retry logic.
