---
title: "Adpro Integration"
type: summary
topic: integrations/adpro
tags: [integration, puller, adpro, rtsp]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Adpro Integration

Adpro manufactures the XO range of IP video transmission devices, commonly used in perimeter security and remote monitoring deployments. These transmitters aggregate video from multiple cameras at a site and re-serve the streams for upstream consumers. Actuate integrates with Adpro to pull video from XO transmitters and run AI analytics on the resulting feeds.

## Components

### Puller -- Custom Rust Binary ([[adpro-puller]])

Unlike most Actuate integrations whose pullers live inside [[actuate-pullers]], the [[adpro-puller|Adpro puller]] is implemented as a **standalone Rust binary** hosted in a separate repository ([[adpro-puller]]). The binary connects to an Adpro XO transmitter, retrieves the native video stream, and re-serves it locally as [[rtsp-deep-dive|RTSP]]. The [[vms-connector]] then consumes this local RTSP stream using the standard RTSP/[[gstreamer-entity|GStreamer]] puller path already present in [[actuate-pullers]]. This two-stage approach was chosen because the Adpro proprietary protocol is more efficiently handled in Rust, while the rest of the Actuate pipeline remains in Python.

### Alarm Sender

There is **no dedicated alarm sender** for Adpro. Alert delivery is handled by whichever monitoring-platform sender (e.g., Immix, SureView, webhook) is configured on the site. Adpro is purely a video-source integration.

### Integration Calls

There is no `actuate-integration-calls` module for Adpro. All communication with the transmitter happens inside the Rust puller binary.

## Auth Method

Authentication to the Adpro XO transmitter is handled inside the Rust puller. Credentials (typically username/password) are passed to the binary at startup via environment variables or command-line arguments. Once the binary re-serves the stream as local [[rtsp-deep-dive|RTSP]], no further Adpro-specific auth is needed on the Python side.

## Key Config Fields

Adpro sites use a standard [[rtsp-deep-dive|RTSP]] connector config because the Python-side puller only sees the locally re-served RTSP URL. The Rust binary's own configuration (transmitter IP, port, credentials, channel mappings) is managed outside of [[actuate-config]].

## Relationship to Other Components

- [[adpro-puller]] -- the Rust binary that handles the Adpro-proprietary protocol
- [[actuate-pullers]] -- the local [[rtsp-deep-dive|RTSP]] stream is consumed by the standard [[gstreamer-entity|GStreamer]]/RTSP puller
- [[vms-connector]] -- orchestrates the pipeline; treats the Adpro stream like any other RTSP source
- [[actuate-alarm-senders]] -- no Adpro-specific sender; alerts go through whatever monitoring sender the site configures
