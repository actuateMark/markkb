---
title: "CHM Diagnostics Gap Analysis"
type: synthesis
topic: camera-health-monitoring
tags: [chm, diagnostics, gap-analysis, integrations]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# CHM Diagnostics Gap Analysis

A cross-reference of every VMS integration against every CHM diagnostic type, mapping what each integration's API can provide, what CHM currently implements, and what is feasible to add.

## Diagnostic Coverage Matrix

### Tier 1: Full or Partial Native Diagnostics

**[[digital-watchdog-components|Digital Watchdog]]** -- Richest diagnostic implementation today: full connectivity checks (DW REST API login + camera listing) and full recording-status checks. [[digital-watchdog-components|DW utils]] supports system config queries, camera existence checks, and multi-auth fallback (cloud OAuth2, Digest, Basic). **Gap**: DW REST API exposes camera health status, storage info, server diagnostics, and stream quality metrics (`mediaStreams` bitrate/codec) that CHM does not query.

**[[exacq-components|Exacq]]** -- Full connectivity checks (via `get_session_id`) and full recording-status checks. [[exacq-components|exacq_utils]] provides session-based auth with legacy/new server fallback. **Gap**: Exacq's web interface exposes camera status, recording health, and server status pages that CHM does not scrape. No motion or stream quality diagnostics implemented.

**[[milestone-components|Milestone]]** -- Full server diagnostics via `MilestoneService`: management server connectivity (`try_server_connection`), recording server connectivity, and configuration comparison (`run_comparison` for camera-to-recording-server drift). **Gap**: SOAP API exposes camera recording status, device health, and storage status that CHM ignores. `MilestoneJpgFramePuller` failover detection signals could feed back into diagnostics.

**[[avigilon-components|Avigilon]]** -- Stub implementations for all five diagnostic types. The [[avigilon-components|ACC REST API]] provides camera listing, alarm management, and `camera_exists_avigilon()`. **Gap**: Stubs need fleshing out -- camera status, recording state, and stream parameters are all accessible through existing API endpoints.

### Tier 2: API Capability Exists But No CHM Implementation

**[[hikcentral-components|HikCentral]]** -- Artemis API provides HMAC-authenticated access to cameras, events, recording status, and device health. `subscribe_to_motion` already subscribes to motion events; API exposes device online/offline, recording plan status, and storage health. **Feasibility**: High -- [[hikcentral-components|hikcentral_calls]] auth pattern is established.

**[[eagle-eye-components|Eagle Eye]]** -- Most comprehensive integration-calls module (v2/v3 APIs + Camera Manager). `get_camera_list()` returns camera status/capabilities; v3 API exposes bridge health, recording status, and bandwidth metrics. **Feasibility**: High -- OAuth2 lifecycle and multi-account proxy support are robust.

**[[genetec-components|Genetec]]** -- Web SDK (port 4590) exposes `EntityConfiguration` queries for camera status (online/offline/recording). **Feasibility**: Medium -- Basic Auth pattern established via alarm sender.

**[[orchid-components|Orchid]]** -- Low-Bandwidth API provides `get_stream_state`, `list_streams`, and connection status tracking. **Feasibility**: Medium -- puller already monitors health internally; needs wiring to CHM.

### Tier 3: RTSP/URL-Only Integrations (Generic Checks Only)

These integrations rely on the generic [[camera-health-monitoring/_summary|CHM]] base camera checks (blur detection, scene change, stream quality validation, puller connectivity, motion signal status). They have no VMS-specific API for deeper diagnostics.

| Integration | Notes |
|---|---|
| [[rtsp-components\|RTSP]] | HTTP GET connectivity check exists (basic). No VMS API. |
| [[salient-components\|Salient]] | Server-level credentials, multi-server structure. No integration-calls module. |
| [[luxriot-components\|Luxriot]] | Embedded-credential HTTP URLs. No integration-calls module. |
| [[video-insight-components\|Video Insight]] | Token-based REST API exists (`/api/v1/`) but no integration-calls module built. Custom site manager suggests health data could be extracted. |
| [[openeye-components\|OpenEye]] | OWS cloud API exists (`actuate.api.gp4f.com`) but no integration-calls module built. |
| [[kvs-components\|KVS]] | AWS-native; [[kvs-components|KVS]] API provides stream health metrics (via CloudWatch) but no CHM integration. |
| [[adpro-components\|Adpro]] | Rust binary re-serves as [[rtsp-deep-dive|RTSP]]. No Python-side API access to Adpro hardware. |

### Tier 4: Alarm-Sender-Only Integrations (Not Applicable)

These integrations are outbound alert senders, not video sources. CHM diagnostics do not apply to them directly, though their reachability could be monitored as a meta-diagnostic.

| Integration | Protocol |
|---|---|
| [[immix-components\|Immix]] | SMTP to monitoring station |
| [[sentinel-components\|Sentinel]] | Pipe-delimited text via SQS |
| [[bold-components\|Bold]] | SIA XML over raw TCP |
| [[patriot-components\|Patriot]] | REST API via SQS |
| [[sureview-components\|Sureview]] | SMTP (mirrors Immix) |
| [[softguard-components\|Softguard]] | Proprietary TCP via SQS |
| [[evalink-components\|Evalink]] | Cloud API via SQS |
| [[lisa-components\|Lisa]] | HTTP webhook via SQS |
| [[webhook-components\|Webhook]] | Generic HTTP POST |
| [[autopatrol-integration-components\|AutoPatrol]] | Direct REST API (Azure APIM) |

## Priority Recommendations

1. **Avigilon** -- Highest ROI: stubs already exist, ACC REST API is accessible, just needs implementation.
2. **[[hikcentral-components|HikCentral]]** -- Auth pattern established, API is rich, growing customer base.
3. **Eagle Eye** -- Cloud API makes diagnostics reliable (no VPN/firewall issues), v3 API is comprehensive.
4. **Milestone** -- Recording status and camera health queries would complement existing server checks.
5. **[[video-insight-components|Video Insight]] / OpenEye** -- Both have REST APIs that could be wrapped in integration-calls modules.
