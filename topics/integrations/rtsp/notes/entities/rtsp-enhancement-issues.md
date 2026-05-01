---
title: "RTSP Enhancement Issue Tracker"
type: entity
topic: integrations/rtsp
tags: [rtsp, issues, tracking, enhancements, github]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# RTSP Enhancement Issues

GitHub issues created from the [[rtsp-robustness-enhancement-plan]] analysis.

## vms-connector Issues

| Issue | Title | Tier | Effort | Status |
|-------|-------|------|--------|--------|
| [#1648](https://github.com/aegissystems/vms-connector/issues/1648) | Exponential backoff with jitter on reconnection | Tier 1 | 1-2 hrs | Open |
| [#1649](https://github.com/aegissystems/vms-connector/issues/1649) | [[rtsp-deep-dive|RTSP]] error code classification (401/403/453/461) | Tier 2 | 4-6 hrs | Open |
| [#1650](https://github.com/aegissystems/vms-connector/issues/1650) | Transport fallback chain (TCP→UDP→interleaved) | Tier 2 | 4-6 hrs | Open |
| [#1651](https://github.com/aegissystems/vms-connector/issues/1651) | Connection health scoring and graceful degradation | Tier 2-3 | 2-3 days | Open |
| [#1652](https://github.com/aegissystems/vms-connector/issues/1652) | Fix bare except: blocks in [[rtsp-deep-dive|RTSP]] puller code | Tier 1 | 30 min | Open |

## actuate-libraries Issues

| Issue | Title | Tier | Effort | Status |
|-------|-------|------|--------|--------|
| [#337](https://github.com/aegissystems/actuate-libraries/issues/337) | Expose stream diagnostics metadata from AvUrlFramePuller | Tier 1 | 2-3 hrs | Open |

## CHM Integration (tracked in CHM phase proposals, not separate issues)

| Enhancement | CHM Phase | Reference |
|-------------|-----------|-----------|
| Replace RTSPDiagnostics HTTP GET with TCP+[[rtsp-deep-dive|RTSP]] DESCRIBE | [[chm-phase1-network-probe]] | Phase 1 core deliverable |
| Surface AvUrlFramePuller metadata to diagnostics | [[chm-phase2-stream-probe]] | Phase 2 core deliverable |
| Black/frozen frame detection at puller level | [[chm-phase5-frame-probe]] | Phase 5 RTSP-specific checks |

## Pre-Existing CHM Bug Issues

| Issue | Title | Errors/Week |
|-------|-------|-------------|
| [#1645](https://github.com/aegissystems/vms-connector/issues/1645) | DW healthcheck NoneType | 184 |
| [#1646](https://github.com/aegissystems/vms-connector/issues/1646) | Exacq healthcheck KeyError | 163 |
| [#1647](https://github.com/aegissystems/vms-connector/issues/1647) | [[hikcentral-components|HikCentral]] healthcheck NoneType | 167 |
