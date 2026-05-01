---
title: "CHM Phase 4: GenericDiagnostics -- Replacing DummyDiagnostics"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, diagnostics, proposal, phase-4]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# CHM Phase 4: GenericDiagnostics -- Replacing DummyDiagnostics

## Problem Statement

The `DiagnosticRunner.get_runner()` dispatch in `diagnostic_runner.py` maps only five integration types to concrete diagnostics classes: `rtsp` to [[rtsp-components|RTSPDiagnostics]], `digital_watchdog` to [[digital-watchdog-components|DWDiagnostics]], `avigilon` to [[avigilon-components|AvigilonDiagnostics]], `exacq` to [[exacq-components|ExacqDiagnostics]], and `milestone` to [[milestone-components|MilestoneDiagnostics]]. Every other integration type -- SMTP, AILink, [[sentinel-components|Sentinel]], Frontel, Yousix, [[ajax-components|Ajax]], [[kvs-components|KVS]], Luxriot, Salient, OpenEye, [[video-insight-components|Video Insight]], Orchid, [[hikcentral-components|HikCentral]], Eagle Eye, Genetec, Adpro, and approximately 12 more -- falls through to `DummyDiagnostics`.

`DummyDiagnostics` is a complete no-op. Every method (`connectivity_diagnostics`, `recording_diagnostics`, `stream_quality_diagnostics`, `motion_status_diagnostics`, `server_diagnostics`) returns `healthcheck_data` unmodified. This means 24 integration types receive zero diagnostic enrichment beyond the generic base-camera checks (blur, scene change, resolution validation). When a camera on one of these integrations goes offline, the system knows THAT it failed but provides no root-cause information in the incident data or alert email.

## Proposed Solution: GenericDiagnostics

Replace `DummyDiagnostics` with a `GenericDiagnostics` class that provides baseline diagnostic enrichment for ANY integration type by leveraging the shared [[chm-enhanced-diagnostics-proposal|NetworkProbe and StreamProbe]] utilities introduced in Phases 1 and 2.

### File Location

`healthcheck/alerts/diagnostics/core/generic_diagnostics.py`, replacing `dummy_diagnostics.py` as the fallback class.

### Diagnostic Method Design

Each method in `GenericDiagnostics` performs integration-agnostic checks that are universally applicable:

**`connectivity_diagnostics(puller, healthcheck_data)`** -- Runs the [[chm-enhanced-diagnostics-proposal|NetworkProbe]] cascade. If the camera has a known IP or hostname (extracted from `puller.camera` config), performs DNS resolution, TCP port probe (554 for RTSP-capable, 80/443 for HTTP-based), and WireGuard tunnel check for cameras on a WG subnet. Populates `healthcheck_data.diagnostics["network"]` with structured results. For frame-delivery integrations (SMTP, AILink) where no direct network path exists, falls back to frame recency analysis: `time.time() - last_frame_timestamp`.

**`stream_quality_diagnostics(puller, healthcheck_data)`** -- Invokes [[chm-enhanced-diagnostics-proposal|StreamProbe]] to extract metadata already collected by the puller: codec, resolution, actual FPS vs configured, bandwidth via `BandwidthTracker`, decode error rate, and frame jitter. Populates `healthcheck_data.diagnostics["stream"]`. For non-RTSP integrations without a puller stream, skips gracefully.

**`motion_status_diagnostics(puller, healthcheck_data)`** -- Performs a frame recency check. Compares `time.time()` against the timestamp of the most recent frame available to the puller. A gap exceeding a configurable threshold (default 300 seconds for RTSP-capable, 3600 seconds for SMTP/AILink) signals a motion or delivery failure.

**`recording_diagnostics(puller, healthcheck_data)`** -- Analyzes frame gap patterns. Using timestamps from the puller's frame buffer, calculates max gap duration and gap frequency. Gaps exceeding 2x the expected inter-frame interval suggest recording interruptions. Reports gap statistics in `healthcheck_data.diagnostics["recording"]`.

**`server_diagnostics(puller, healthcheck_data)`** -- If the camera config includes an NVR base URL or server IP, performs a TCP probe to standard NVR management ports (80, 443, 554, 7001). Reports server reachability without integration-specific API calls.

### DiagnosticRunner Dispatch Change

The final `return DummyDiagnostics(config)` line in `DiagnosticRunner.get_runner()` changes to `return GenericDiagnostics(config)`. This is a one-line change that immediately provides diagnostic coverage for all 24 previously-uncovered integration types. `DummyDiagnostics` is retained only for the local-override case (`config.customer.local`).

### Per-Integration Configuration

Not all generic checks are applicable to every integration type. A capability mapping dictionary within `GenericDiagnostics` controls which diagnostics execute:

```python
INTEGRATION_CAPABILITIES = {
    "smtp":    {"network_probe": False, "stream_probe": False, "frame_recency": True},
    "ailink":  {"network_probe": False, "stream_probe": False, "frame_recency": True},
    "kvs":     {"network_probe": False, "stream_probe": True,  "frame_recency": True},
    "default": {"network_probe": True,  "stream_probe": True,  "frame_recency": True},
}
```

SMTP cameras deliver frames via SQS, not [[rtsp-deep-dive|RTSP]], so TCP probes to the camera are meaningless. AILink cameras connect via WebSocket from the camera side, so network probes from the server are similarly inapplicable. The `default` entry applies to all unmapped types and enables all checks.

### Data Model

Generic diagnostics write to the same `healthcheck_data.diagnostics` dict structure defined in the [[chm-enhanced-diagnostics-proposal|tooling architecture proposal]]. Results are logged to [[new-relic|New Relic]] as custom attributes for queryability and used by alert generators to enrich email subjects.

## Dependencies

- **Phase 1 (NetworkProbe)** -- Required for TCP probe, DNS, WireGuard checks.
- **Phase 2 (StreamProbe)** -- Required for puller metadata extraction.
- If Phases 1-2 are not yet complete, `GenericDiagnostics` can still be deployed with frame recency checks only, providing partial value immediately.

## Effort Estimate

1-2 days. The implementation is straightforward: a new class extending `BaseDiagnostics` that delegates to NetworkProbe and StreamProbe, plus a one-line dispatch change. The capability mapping dictionary requires minimal integration-type research since it defaults to enabling all checks.

## Related

- [[chm-enhanced-diagnostics-proposal]] -- parent proposal defining NetworkProbe, StreamProbe, FrameProbe
- [[chm-diagnostics-architecture]] -- current DiagnosticRunner dispatch and BaseDiagnostics contract
- [[chm-diagnostics-gap-analysis]] -- per-integration gap matrix showing 24 types on DummyDiagnostics
- [[chm-phase5-frame-probe]] -- FrameProbe visual quality analysis (Phase 5)
- [[chm-phase6-smtp-ailink-diagnostics]] -- SMTP/AILink-specific diagnostics (Phase 6)
