---
title: "CHM Phase Proposal Review: Findings and Required Edits"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, review, proposals, corrections]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# CHM Phase Proposal Review Findings

Comprehensive review of all 7 phase proposals against source code, NR operational data, and existing KB context. Conducted 2026-04-15.

## Critical Issues (Must Fix Before Implementation)

### 1. `HealthcheckDataPacket.diagnostics` Does Not Exist
ALL 7 phases assume they can write to `healthcheck_data.diagnostics["network"]` etc. But `HealthcheckDataPacket` uses typed private attributes (`__connectivity`, `__stream_quality`) with property setters. No freeform `diagnostics` dict exists.

**Resolution:** Add a Phase 0 prerequisite: extend `HealthcheckDataPacket` in `actuate-healthcheck-objects` with a `diagnostics: dict` attribute. This is a shared library change requiring version bump + CI publish + connector pin update.

### 2. Phase 1/Phase 4 GenericDiagnostics Scope Collision
Phase 1 proposes creating `GenericDiagnostics` at `integrations/generic_diagnostics.py`. Phase 4 is entirely about creating `GenericDiagnostics` at `core/generic_diagnostics.py`. Different paths, duplicated scope.

**Resolution:** Remove GenericDiagnostics from Phase 1 scope entirely. Phase 1 = NetworkProbe + RTSPDiagnostics only. Phase 4 = GenericDiagnostics (in `integrations/`, not `core/`). Reduce Phase 1 effort from 3-5 to 2-3 days.

### 3. Missing Incident Escalation
NR data shows camera AXISP3265V stuck in `ongoing` incident for 264+ consecutive runs (likely weeks). No phase addresses escalation (if incident doesn't resolve after N runs, increase severity). This is a high-severity operational gap.

**Resolution:** Add escalation logic to Phase 7 or as a standalone Phase 3.5.

## Revised Phase Ordering

Based on NR data (volume of impact):

| Priority | Phase | Rationale |
|----------|-------|-----------|
| **0** | Prerequisites | `HealthcheckDataPacket.diagnostics` extension, fix 3 production bugs (DW/[[hikcentral-components|HikCentral]]/Exacq), investigate "No runner available" pattern |
| **1** | Phase 1: NetworkProbe | Foundational, fixes [[rtsp-deep-dive|RTSP]] BadStatusLine (102/week) |
| **2** | Phase 4: GenericDiagnostics | **Promoted** -- 18K+ skips/week, lowest effort (1-2 days) |
| **3** | Phase 2: StreamProbe | Low effort, prerequisite for Phase 7 |
| **4** | Phase 6: SMTP/AILink | **Promoted** -- covers ~32K cameras (fleet majority) |
| **5** | Phase 3: Correlation | High value but depends on Phase 1 data |
| **6** | Phase 5: FrameProbe | Visual quality enhancements |
| **7** | Phase 7: Historical Trending | Depends on Phases 2, 5 |

## Per-Phase Edit Summary

### Phase 1 (Network Probe)
- Remove GenericDiagnostics from scope (Phase 4 owns it)
- Add `HealthcheckDataPacket` extension prerequisite
- Add `ping` binary availability check/fallback
- Reduce effort: 3-5 days -> 2-3 days

### Phase 2 (Stream Probe)
- Fix `generate()` reference -> should be `check()` (lines 118-152 of runner)
- Add timing caveat: `_avdiscard_video_stream` may be None before `connect_stream()`
- Add `HealthcheckDataPacket` extension prerequisite

### Phase 3 (Cross-Camera Correlation)
- Add WireGuard DAO cache sharing with Phase 1 NetworkProbe
- Specify `job_data` key type: `Dict[str, HealthcheckDataPacket]` keyed by `admin_camera_id`
- Add `HealthcheckDataPacket` extension prerequisite

### Phase 4 (Generic Diagnostics)
- Move file to `integrations/generic_diagnostics.py` (not `core/`)
- Clarify sole ownership (Phase 1 no longer creates this)
- Investigate "No runner available" vs DummyDiagnostics distinction
- Add `HealthcheckDataPacket` extension prerequisite

### Phase 5 (Frame Probe)
- Fix BlurHandler DynamoDB constructor issue: use static method or pass existing instance
- Clarify frame buffer [[memory-management|memory management]] (10 frames = ~60MB at 1080p)
- Add reconciliation with existing VIDEO_LOSS alert (avoid duplicates)

### Phase 6 (SMTP/AILink)
- Clarify SQS queue architecture: shared FIFO vs per-camera queues
- Fix gap analysis tier reference (SMTP cameras ≠ SMTP alarm senders)
- Add effort for [[actuate-ailink|actuate_ailink]] API discovery

### Phase 7 (Historical Trending)
- Revise DynamoDB cost: ~$100/month not $30/month (reads dominate)
- Add cold-start/backfill strategy
- Add explicit Phase 2 hard dependency
- Add incident escalation logic

## Production Bugs to Fix Pre-Phase-1

| Bug | Integration | Count/Week | Likely Fix |
|-----|------------|------------|------------|
| `NoneType.lower` | DW | 184 | Null check on config fields in `dw_diagnostics.py` |
| `NoneType not subscriptable` | [[hikcentral-components|HikCentral]] | 167 | Null check on API response in `hikcentral` calls |
| `KeyError: 'Cameras'` | Exacq | 163 | Defensive parsing in `exacq_diagnostics.py` |

These are ~500 errors/week from missing null checks. Quick defensive fixes, independent of the phase work.

## NR Data Cross-References

| NR Finding | Validated Phase | Status |
|------------|----------------|--------|
| [[rtsp-deep-dive|RTSP]] BadStatusLine (102/week) | Phase 1 | Directly addressed |
| "No runner available" (18K+/week) | Phase 4 | Addressed (partially -- needs investigation) |
| connector-12749 (9.3K unable to connect) | Phase 3 | Would collapse to 1 alert |
| AXISP3265V stuck 264+ runs | **None** | Needs escalation logic (add to Phase 7) |
| Scene change detections trending up | Phase 5 (IR mode suppression) | Would reduce false positives |
| DW/[[hikcentral-components|HikCentral]]/Exacq errors (500/week) | **Pre-phase bug fixes** | Quick defensive coding |

## Critical Path

```
Phase 0 (Prerequisites)
    |
    v
Phase 1 (NetworkProbe) ---------> Phase 3 (Correlation)
    |                                   |
    v                                   v
Phase 4 (GenericDiagnostics)    Phase 5 (FrameProbe)
    |                                   |
    v                                   v
Phase 2 (StreamProbe) ----------> Phase 7 (Trending + Escalation)
    |
    v
Phase 6 (SMTP/AILink)
```

Phase 1 -> Phase 2 -> Phase 7 is the longest path. Phases 4 and 6 can run in parallel once Phase 1 ships. Phase 5 can start independently (only needs the HealthcheckDataPacket prerequisite).
