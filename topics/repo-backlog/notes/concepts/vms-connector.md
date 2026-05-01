---
title: "vms-connector backlog"
type: concept
topic: repo-backlog
tags: [backlog, github, vms-connector, rtsp]
repo: aegissystems/vms-connector
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
issue_count_open: 100
issue_count_high_impact: 10
issue_count_lhf: 10
issue_count_stale: 0
high_impact_issue_numbers: [1656, 1658, 1629, 1622, 1559, 1549, 1483, 1642, 1640, 1623]
lhf_issue_numbers: [1502, 1596, 1656, 1594, 1552, 1549, 1544, 1529, 1528, 1523]
stale_issue_numbers: []
full_issue_numbers: [1658, 1656, 1652, 1651, 1650, 1649, 1648, 1647, 1646, 1645, 1642, 1640, 1636, 1635, 1630, 1629, 1628, 1626, 1625, 1623, 1622, 1618, 1616, 1606, 1600, 1599, 1598, 1597, 1596, 1594, 1591, 1589, 1584, 1582, 1572, 1571, 1570, 1565, 1563, 1560, 1559, 1558, 1557, 1556, 1555, 1554, 1553, 1552, 1549, 1544, 1531, 1529, 1528, 1525, 1524, 1523, 1522, 1520, 1518, 1517, 1516, 1515, 1514, 1511, 1509, 1508, 1503, 1502, 1500, 1499, 1497, 1496, 1495, 1492, 1491, 1490, 1489, 1488, 1487, 1486, 1485, 1484, 1483, 1481, 1480, 1479, 1478, 1477, 1476, 1475, 1474, 1472, 1471, 1470, 1469, 1468, 1467, 1466, 1465, 1464]
---

# vms-connector backlog

Full open-issue inventory for [aegissystems/vms-connector](https://github.com/aegissystems/vms-connector/issues). The auto-refresh block is overwritten by [[skill-repo-scan|/repo-scan]]; **Curated notes** are hand-maintained and preserved across refreshes.

## Curated notes

*(Hand-maintained. Not touched by /repo-scan.)*

### Active clusters

Groups of related open issues — when picking one up, consider whether adjacent ones move together. Numbers are GitHub issue numbers.

| Cluster | Issues | Notes |
|---------|--------|-------|
| **[[rtsp-deep-dive|RTSP]] robustness suite** | 1648, 1649, 1650, 1651, 1652 | Coherent 5-issue burst filed 7d ago (backoff+jitter, error classification, transport fallback chain, health scoring, bare-except cleanup). Natural candidates to pick up together as a single epic — one [[rtsp-deep-dive|RTSP]] puller rewrite pass. |
| **Healthcheck bugs (multi-integration)** | 1558, 1597, 1599, 1600, 1645, 1646, 1647 | Same failure shape (Nones / KeyErrors from partial API responses) reappearing across [[hikcentral-components|HikCentral]], Exacq, DW, CHM. Candidate for a defensive-parsing utility at the Puller / Healthcheck base class. |
| **Deferred alert / tag zone lifecycle** | 1628, 1629, 1630, 1636 | Filed together — same author, design work on analytic (continuous-run) tag-zone alert semantics. Likely picked up as a unit. |
| **DDB throttling / WindowIdsV2** | 1640, 1642 | Paired: observed throttling (1640) → remedy (drop 3 unused GSIs, 1642). 1642 is the actionable one; 1640 is the symptom ticket. Close 1640 when 1642 ships. |
| **Memory / resource optimization** | 1497, 1499, 1503, 1511, 1616, 1625 | Recurring theme. 1616 is actually a "won't-fix / document irreducible cost" — convert to a doc and close. 1503 SMTP 37×-overhead is the highest-ROI one. |
| **AP/VCH prod issues** | 1656, 1658 | Both 2-3d old, current session closed admin#2235 from this cluster. Monitor for reaction from connector_deployer#158. |
| **Test coverage expansion** | 1465, 1466, 1467, 1468, 1469, 1470, 1489 | Seven test-writing tickets. LHF-worthy but only if the underlying code is already stable — several targets (VMS integrations, frame processing) are in flux. |
| **CHM consolidation** | 1475, 1556, 1599, 1600 | Thematic — CHM logic is spreading across multiple containers / jobs. Consider whether to consolidate before fixing each piece. |
| **Infra / k8s nodepool** | 1495, 1518, 1528, 1529, 1531, 1544 | 1528 (ECR lifecycle policy) is near-done LHF. 1544 (Graviton 4 / Kleidicv) needs a real perf experiment. |
| **YOLO / local inference** | 1478, 1479, 1480, 1481 | Proposal-stage. Not prioritized until v5 detect is fully rolled out. |

### Known ownership / in-flight
- **Mark:** 1658 (AP/VCH WebSocket SSL cert chain, assigned; ≤3d)
- All other open items unassigned.

### Misfiled / noise
- **1525** (Git actions diff not showing new files in actuate-libraries) — cross-repo misfile; belongs in actuate-libraries. Candidate for transfer.

### Codebase-scan follow-up
vms-connector currently has **zero** issues >180d idle — active repo. If stale accumulates in future scans, walk `git log --since=...` for the relevant subsystem before commenting, then either bump with new context or close with `addressed by <commit>`. **Never bulk-close.**

<!-- BEGIN-AUTO-REFRESH repo-scan -->
_Last refreshed: **2026-05-01** by [[skill-repo-scan]] — 100 open issues._

### 🔥 High-impact (top 10 by score)

| # | Title | Labels | Assignee | Score | Idle |
|--:|-------|--------|----------|------:|------|
| 1656 | [AP/VCH: Immix rejects CNCTNFAIL alerts with HTTP 400 — streamId null when strea…](https://github.com/aegissystems/vms-connector/issues/1656) | `bug` | — | 10 | 10d |
| 1658 | [AP/VCH: WebSocket frame retrieval fails fleet-wide — dev.powerplus.com serves i…](https://github.com/aegissystems/vms-connector/issues/1658) | `bug` | actuateMark | 4 | 10d |
| 1629 | [Eliminate 300s frame retention buffer for deferred tag-zone alerts](https://github.com/aegissystems/vms-connector/issues/1629) | — | — | 4 | 1mo |
| 1622 | [Intermittent create-video 502 errors from detection-window service](https://github.com/aegissystems/vms-connector/issues/1622) | `bug` | — | 3 | 1mo |
| 1559 | [[BUG] SMTP_per_camera integration type missing camera runner implementation](https://github.com/aegissystems/vms-connector/issues/1559) | — | — | 3 | 2mo |
| 1549 | [Enable ruff T201 rule to catch print statements](https://github.com/aegissystems/vms-connector/issues/1549) | — | — | 3 | 2mo |
| 1483 | [[BUG] Scene Change Analyzer Not Cleaned Up Before Replacement (AutoPatrol)](https://github.com/aegissystems/vms-connector/issues/1483) | `bug` | — | 3 | 3mo |
| 1642 | [WindowIdsV2: drop 3 unused GSIs to fix write amplification + hot partition thro…](https://github.com/aegissystems/vms-connector/issues/1642) | — | — | 2 | 22d |
| 1640 | [DynamoDB ThrottlingException on WindowIdsV2 PutItem during arm/disarm burst](https://github.com/aegissystems/vms-connector/issues/1640) | — | — | 2 | 27d |
| 1623 | [Rate-limit JpgFrameQueuePuller to target FPS instead of pulling at native rate](https://github.com/aegissystems/vms-connector/issues/1623) | — | — | 2 | 1mo |

### 🧹 Low-hanging fruit (top 10 by score)

| # | Title | Labels | Assignee | Score | Idle |
|--:|-------|--------|----------|------:|------|
| 1502 | [📚 Architecture Documentation: RTSP Connector Lifecycle Diagram](https://github.com/aegissystems/vms-connector/issues/1502) | `documentation` | — | 8 | 3mo |
| 1596 | [Adopt squash merge for stage → rearchitecture PRs](https://github.com/aegissystems/vms-connector/issues/1596) | — | — | 6 | 1mo |
| 1656 | [AP/VCH: Immix rejects CNCTNFAIL alerts with HTTP 400 — streamId null when strea…](https://github.com/aegissystems/vms-connector/issues/1656) | `bug` | — | 5 | 10d |
| 1594 | [Pod state checkpoint: persist camera state across rolling restarts](https://github.com/aegissystems/vms-connector/issues/1594) | `enhancement` | — | 5 | 2mo |
| 1552 | [Daily Log Report Automation - Agent-Generated Monitoring](https://github.com/aegissystems/vms-connector/issues/1552) | — | — | 5 | 2mo |
| 1549 | [Enable ruff T201 rule to catch print statements](https://github.com/aegissystems/vms-connector/issues/1549) | — | — | 5 | 2mo |
| 1544 | [Optimize OpenCV for Graviton 4 with Kleidicv](https://github.com/aegissystems/vms-connector/issues/1544) | — | — | 5 | 3mo |
| 1529 | [Create dedicated c8g nodepool for CPU-heavy workloads (gun detection)](https://github.com/aegissystems/vms-connector/issues/1529) | — | — | 5 | 3mo |
| 1528 | [Add ECR lifecycle policy to delete untagged images after 90 days](https://github.com/aegissystems/vms-connector/issues/1528) | — | — | 5 | 3mo |
| 1523 | [Support muting alerts at camera/site level from Camera UI](https://github.com/aegissystems/vms-connector/issues/1523) | — | — | 5 | 3mo |

### 🔍 Codebase-scan follow-up candidates (idle >180d)

*These are **not** bulk-close candidates — each needs case-by-case review. Many may already be addressed by later work; some deserve a bump. Walk the codebase for context before commenting.*

_(none)_

### 📊 Labels

| Label | Count |
|-------|------:|
| `enhancement` | 13 |
| `bug` | 4 |
| `documentation` | 1 |

### 🗃️ Full open inventory

<details><summary>All 100 open issues (click to expand — sorted newest first)</summary>

| # | Title | Labels | Assignee | Age | Idle |
|--:|-------|--------|----------|-----|------|
| 1658 | [AP/VCH: WebSocket frame retrieval fails fleet-wide — dev.powerplus.com serves i…](https://github.com/aegissystems/vms-connector/issues/1658) | `bug` | actuateMark | 10d | 10d |
| 1656 | [AP/VCH: Immix rejects CNCTNFAIL alerts with HTTP 400 — streamId null when strea…](https://github.com/aegissystems/vms-connector/issues/1656) | `bug` | — | 10d | 10d |
| 1652 | [[Cleanup] Fix bare except: blocks in [[rtsp-deep-dive|RTSP]] puller code](https://github.com/aegissystems/vms-connector/issues/1652) | — | — | 15d | 15d |
| 1651 | [[Enhancement] [[rtsp-deep-dive|RTSP]]: Connection health scoring and graceful degradation](https://github.com/aegissystems/vms-connector/issues/1651) | — | — | 15d | 15d |
| 1650 | [[Enhancement] [[rtsp-deep-dive|RTSP]]: Transport fallback chain (TCP → UDP → interleaved)](https://github.com/aegissystems/vms-connector/issues/1650) | — | — | 15d | 15d |
| 1649 | [[Enhancement] RTSP: Error code classification (401/403/453/461)](https://github.com/aegissystems/vms-connector/issues/1649) | — | — | 15d | 15d |
| 1648 | [[Enhancement] RTSP: Exponential backoff with jitter on reconnection](https://github.com/aegissystems/vms-connector/issues/1648) | — | — | 15d | 15d |
| 1647 | [[BUG] [[hikcentral-components|HikCentral]] healthcheck NoneType when API response data is null](https://github.com/aegissystems/vms-connector/issues/1647) | — | — | 15d | 15d |
| 1646 | [[BUG] Exacq healthcheck KeyError 'Cameras' when API response format differs](https://github.com/aegissystems/vms-connector/issues/1646) | — | — | 15d | 15d |
| 1645 | [[BUG] DW healthcheck NoneType error when config fields missing](https://github.com/aegissystems/vms-connector/issues/1645) | — | — | 15d | 15d |
| 1642 | [WindowIdsV2: drop 3 unused GSIs to fix write amplification + hot partition thro…](https://github.com/aegissystems/vms-connector/issues/1642) | — | — | 27d | 22d |
| 1640 | [DynamoDB ThrottlingException on WindowIdsV2 PutItem during arm/disarm burst](https://github.com/aegissystems/vms-connector/issues/1640) | — | — | 27d | 27d |
| 1636 | [Tag zones on analytic (continuous-run) sites: deferred alert lifecycle](https://github.com/aegissystems/vms-connector/issues/1636) | — | actuateMark | 1mo | 1mo |
| 1635 | [feat: Generic patrol mode — integration-agnostic patrol runs](https://github.com/aegissystems/vms-connector/issues/1635) | — | actuateMark | 1mo | 1mo |
| 1630 | [Optimize alert frame source: use S3 frames instead of in-cache for deferred ale…](https://github.com/aegissystems/vms-connector/issues/1630) | — | actuateMark | 1mo | 1mo |
| 1629 | [Eliminate 300s frame retention buffer for deferred tag-zone alerts](https://github.com/aegissystems/vms-connector/issues/1629) | — | — | 1mo | 1mo |
| 1628 | [Deferred alerts: send without frame fallback + cache optimizations](https://github.com/aegissystems/vms-connector/issues/1628) | — | — | 1mo | 1mo |
| 1626 | [feat: evaluate and migrate annotation rendering to improve visual quality and r…](https://github.com/aegissystems/vms-connector/issues/1626) | `enhancement` | — | 1mo | 1mo |
| 1625 | [Exacq JPEG connector-34880 has linear memory growth ~30 MB/min](https://github.com/aegissystems/vms-connector/issues/1625) | — | — | 1mo | 1mo |
| 1623 | [Rate-limit JpgFrameQueuePuller to target FPS instead of pulling at native rate](https://github.com/aegissystems/vms-connector/issues/1623) | — | — | 1mo | 1mo |
| 1622 | [Intermittent create-video 502 errors from detection-window service](https://github.com/aegissystems/vms-connector/issues/1622) | `bug` | — | 1mo | 1mo |
| 1618 | [Reduce exacq session/frame retrieval error log noise when VMS is unreachable](https://github.com/aegissystems/vms-connector/issues/1618) | — | — | 1mo | 1mo |
| 1616 | [Memory accounting: ~189 MB/cam C-level overhead is irreducible FFmpeg decode co…](https://github.com/aegissystems/vms-connector/issues/1616) | — | — | 1mo | 1mo |
| 1606 | [Route per-frame pipeline logs to S3 instead of New Relic](https://github.com/aegissystems/vms-connector/issues/1606) | — | — | 1mo | 1mo |
| 1600 | [[BUG] Event sender crashes with 'customer_id must be a str' in CHM container](https://github.com/aegissystems/vms-connector/issues/1600) | — | — | 1mo | 1mo |
| 1599 | [[BUG] CHM cronjob crashes with 'integration doesn't exist' TypeError](https://github.com/aegissystems/vms-connector/issues/1599) | — | — | 1mo | 1mo |
| 1598 | [[BUG] Avigilon/Sirix puller threads crash simultaneously with unreadable interl…](https://github.com/aegissystems/vms-connector/issues/1598) | — | — | 1mo | 1mo |
| 1597 | [[BUG] CHM healthcheck email fails with TypeError when attachment image is None](https://github.com/aegissystems/vms-connector/issues/1597) | — | — | 1mo | 1mo |
| 1596 | [Adopt squash merge for stage → rearchitecture PRs](https://github.com/aegissystems/vms-connector/issues/1596) | — | — | 1mo | 1mo |
| 1594 | [Pod state checkpoint: persist camera state across rolling restarts](https://github.com/aegissystems/vms-connector/issues/1594) | `enhancement` | — | 2mo | 2mo |
| 1591 | [VPA checkpoints lost during daily arm/disarm cycle — pods cold-start with stale…](https://github.com/aegissystems/vms-connector/issues/1591) | — | — | 2mo | 2mo |
| 1589 | [DW/NX: Send detection bounding boxes via Analytics REST API](https://github.com/aegissystems/vms-connector/issues/1589) | — | — | 2mo | 2mo |
| 1584 | [Investigate repeated 'open_email_sent is blank' retry errors in connector cronj…](https://github.com/aegissystems/vms-connector/issues/1584) | — | — | 2mo | 2mo |
| 1582 | [Downgrade 'No cameras found in config' from ERROR to WARN with notification](https://github.com/aegissystems/vms-connector/issues/1582) | — | — | 2mo | 2mo |
| 1572 | [DW login() returns Exception objects as response, causing type confusion](https://github.com/aegissystems/vms-connector/issues/1572) | — | — | 2mo | 2mo |
| 1571 | [Healthcheck thread.join() has no timeout, causing potential hangs](https://github.com/aegissystems/vms-connector/issues/1571) | — | — | 2mo | 2mo |
| 1570 | [Pipeline result timestamp mismatch race condition in get_result()](https://github.com/aegissystems/vms-connector/issues/1570) | — | — | 2mo | 2mo |
| 1565 | [CI/CD Quick Optimizations Proposal](https://github.com/aegissystems/vms-connector/issues/1565) | — | actuateMark | 2mo | 2mo |
| 1563 | [### Hardcoded credentials committed to version control, move to secrets](https://github.com/aegissystems/vms-connector/issues/1563) | — | — | 2mo | 2mo |
| 1560 | [Log Severity Cleanup: Downgrade operational errors per LOG-CLEANUP.md guidelines](https://github.com/aegissystems/vms-connector/issues/1560) | — | — | 2mo | 1mo |
| 1559 | [[BUG] SMTP_per_camera integration type missing camera runner implementation](https://github.com/aegissystems/vms-connector/issues/1559) | — | — | 2mo | 2mo |
| 1558 | [[BUG] Healthcheck: 'cannot set end_timestamp on ongoing incident' race condition](https://github.com/aegissystems/vms-connector/issues/1558) | — | — | 2mo | 2mo |
| 1557 | [[BUG] RTSPCustomerConfig missing 'lead' attribute causes camera creation failur…](https://github.com/aegissystems/vms-connector/issues/1557) | — | — | 2mo | 2mo |
| 1556 | [Add structured logging to DW and Eagle Eye healthcheck cameras](https://github.com/aegissystems/vms-connector/issues/1556) | `enhancement` | — | 2mo | 2mo |
| 1555 | [settings load failure uses success code on exit rather than failure](https://github.com/aegissystems/vms-connector/issues/1555) | — | — | 2mo | 2mo |
| 1554 | [### Duplicated camera existence checking pattern](https://github.com/aegissystems/vms-connector/issues/1554) | — | — | 2mo | 2mo |
| 1553 | [Healthcheck Duration Variable Decoupling](https://github.com/aegissystems/vms-connector/issues/1553) | — | — | 2mo | 2mo |
| 1552 | [Daily Log Report Automation - Agent-Generated Monitoring](https://github.com/aegissystems/vms-connector/issues/1552) | — | — | 2mo | 2mo |
| 1549 | [Enable ruff T201 rule to catch print statements](https://github.com/aegissystems/vms-connector/issues/1549) | — | — | 2mo | 2mo |
| 1544 | [Optimize OpenCV for Graviton 4 with Kleidicv](https://github.com/aegissystems/vms-connector/issues/1544) | — | — | 3mo | 3mo |
| 1531 | [Multi-tenant pod architecture with shared worker pool](https://github.com/aegissystems/vms-connector/issues/1531) | — | — | 3mo | 3mo |
| 1529 | [Create dedicated c8g nodepool for CPU-heavy workloads (gun detection)](https://github.com/aegissystems/vms-connector/issues/1529) | — | — | 3mo | 3mo |
| 1528 | [Add ECR lifecycle policy to delete untagged images after 90 days](https://github.com/aegissystems/vms-connector/issues/1528) | — | — | 3mo | 3mo |
| 1525 | [Git (actions) diff not showing new files in actuate-libraries](https://github.com/aegissystems/vms-connector/issues/1525) | — | — | 3mo | 3mo |
| 1524 | [RoboMladen needs image height and image width](https://github.com/aegissystems/vms-connector/issues/1524) | — | — | 3mo | 3mo |
| 1523 | [Support muting alerts at camera/site level from Camera UI](https://github.com/aegissystems/vms-connector/issues/1523) | — | — | 3mo | 3mo |
| 1522 | [Filter sensitivities may need adjustment based on product FPS](https://github.com/aegissystems/vms-connector/issues/1522) | — | — | 3mo | 3mo |
| 1520 | [Make filters adaptive to FPS](https://github.com/aegissystems/vms-connector/issues/1520) | — | — | 3mo | 3mo |
| 1518 | [Local Development: Cannot access Kubernetes services and AWS endpoints](https://github.com/aegissystems/vms-connector/issues/1518) | — | — | 3mo | 3mo |
| 1517 | [Star4Live: Per-camera restart fails due to socket binding issues](https://github.com/aegissystems/vms-connector/issues/1517) | — | — | 3mo | 3mo |
| 1516 | [Review Star4live stability](https://github.com/aegissystems/vms-connector/issues/1516) | — | — | 3mo | 3mo |
| 1515 | [Skip Stationary Filter for Products >1 FPS, Run Motion at Fixed 1 FPS](https://github.com/aegissystems/vms-connector/issues/1515) | — | — | 3mo | 3mo |
| 1514 | [Adaptive SAHI Slice Count Based on Motion/Detection Size](https://github.com/aegissystems/vms-connector/issues/1514) | — | — | 3mo | 3mo |
| 1511 | [Optimize Autopatrol Memory](https://github.com/aegissystems/vms-connector/issues/1511) | — | — | 3mo | 3mo |
| 1509 | [Create Shadow Mode that uploads more information to DBs instead of logs](https://github.com/aegissystems/vms-connector/issues/1509) | — | — | 3mo | 3mo |
| 1508 | [Reduce New Relic Log Volume - Cost Optimization](https://github.com/aegissystems/vms-connector/issues/1508) | — | — | 3mo | 3mo |
| 1503 | [SMTP Integration Memory Optimization Needed - 37x worse memory/CPU ratio than o…](https://github.com/aegissystems/vms-connector/issues/1503) | `enhancement` | — | 3mo | 3mo |
| 1502 | [📚 Architecture Documentation: RTSP Connector Lifecycle Diagram](https://github.com/aegissystems/vms-connector/issues/1502) | `documentation` | — | 3mo | 3mo |
| 1500 | [Route SMTP sites to clips service (actuate_ailink) for better resource efficien…](https://github.com/aegissystems/vms-connector/issues/1500) | — | — | 3mo | 3mo |
| 1499 | [Clear motion detector background and release memory after extended disconnect](https://github.com/aegissystems/vms-connector/issues/1499) | — | — | 3mo | 3mo |
| 1497 | [Memory optimization: JPEG-encoded storage for sparse SMTP integrations](https://github.com/aegissystems/vms-connector/issues/1497) | — | — | 3mo | 3mo |
| 1496 | [Cleanup flex schedules](https://github.com/aegissystems/vms-connector/issues/1496) | — | — | 3mo | 3mo |
| 1495 | [Add alerting for connector pods in CrashLoopBackOff](https://github.com/aegissystems/vms-connector/issues/1495) | — | — | 3mo | 3mo |
| 1492 | [Evaluate if multiprocessing sharding is still needed with OpenCV thread pinning](https://github.com/aegissystems/vms-connector/issues/1492) | — | — | 3mo | 3mo |
| 1491 | [FFmpeg Build: Add missing codecs from PyAV pre-built for feature parity](https://github.com/aegissystems/vms-connector/issues/1491) | — | — | 3mo | 3mo |
| 1490 | [Ensure H265 stream is in staging for testing](https://github.com/aegissystems/vms-connector/issues/1490) | — | — | 3mo | 3mo |
| 1489 | [VideoInsight Startup When Camera Missing](https://github.com/aegissystems/vms-connector/issues/1489) | — | — | 3mo | 3mo |
| 1488 | [Eagle Eye V3 pullers sometimes fail to initialize due to race condition and mis…](https://github.com/aegissystems/vms-connector/issues/1488) | — | — | 3mo | 3mo |
| 1487 | [FDMD / Motion Detection Enhancements Proposal](https://github.com/aegissystems/vms-connector/issues/1487) | — | — | 3mo | 3mo |
| 1486 | [RFC: Advanced Alert Criteria - Beyond X out of Y Frames](https://github.com/aegissystems/vms-connector/issues/1486) | — | — | 3mo | 3mo |
| 1485 | [Log shortening: reduce verbose per-frame logging in pipeline steps](https://github.com/aegissystems/vms-connector/issues/1485) | — | — | 3mo | 3mo |
| 1484 | [Consolidate Stationary/Blacklist/IOU filters into unified filtering approach](https://github.com/aegissystems/vms-connector/issues/1484) | — | — | 3mo | 3mo |
| 1483 | [[BUG] Scene Change Analyzer Not Cleaned Up Before Replacement (AutoPatrol)](https://github.com/aegissystems/vms-connector/issues/1483) | `bug` | — | 3mo | 3mo |
| 1481 | [Async Pipeline Architecture for High-FPS Processing Independent of Model Latency](https://github.com/aegissystems/vms-connector/issues/1481) | `enhancement` | — | 3mo | 3mo |
| 1480 | [Feature: Local Model Inference Mode (--local-model flag)](https://github.com/aegissystems/vms-connector/issues/1480) | — | — | 3mo | 3mo |
| 1479 | [[Performance] Slicing server calls take 600ms - need parallel inference requests](https://github.com/aegissystems/vms-connector/issues/1479) | `enhancement` | — | 3mo | 3mo |
| 1478 | [[Feature] Support local YOLO inference without external inference server](https://github.com/aegissystems/vms-connector/issues/1478) | `enhancement` | — | 3mo | 3mo |
| 1477 | [Verifier/Video Integration should disarm itself after all videos have been proc…](https://github.com/aegissystems/vms-connector/issues/1477) | — | — | 3mo | 3mo |
| 1476 | [Stream Rebroadcast - Proxy Camera Streams to Frontend Applications](https://github.com/aegissystems/vms-connector/issues/1476) | `enhancement` | — | 3mo | 3mo |
| 1475 | [Inline Camera Health Monitoring - Run CHM Checks Within Analytics Connector](https://github.com/aegissystems/vms-connector/issues/1475) | `enhancement` | — | 3mo | 3mo |
| 1474 | [Camera/Product Mute - Temporarily Disconnect Cameras via Remote Signal](https://github.com/aegissystems/vms-connector/issues/1474) | `enhancement` | — | 3mo | 3mo |
| 1472 | [Reduce Blacklist Cleanup Timer Default from 15 min to 5 min](https://github.com/aegissystems/vms-connector/issues/1472) | `enhancement` | — | 3mo | 3mo |
| 1471 | [S3 Frame Upload Batching - Reduce PUT Costs by ~90%](https://github.com/aegissystems/vms-connector/issues/1471) | `enhancement` | — | 3mo | 3mo |
| 1470 | [Add end-to-end integration tests](https://github.com/aegissystems/vms-connector/issues/1470) | — | — | 3mo | 3mo |
| 1469 | [Enable new test files in CI](https://github.com/aegissystems/vms-connector/issues/1469) | — | — | 3mo | 3mo |
| 1468 | [Add tests for frame processing operations](https://github.com/aegissystems/vms-connector/issues/1468) | — | — | 3mo | 3mo |
| 1467 | [Add tests for signal/alert processing](https://github.com/aegissystems/vms-connector/issues/1467) | — | — | 3mo | 3mo |
| 1466 | [Add tests for camera lifecycle management](https://github.com/aegissystems/vms-connector/issues/1466) | — | — | 3mo | 3mo |
| 1465 | [Add tests for VMS integrations](https://github.com/aegissystems/vms-connector/issues/1465) | — | — | 3mo | 3mo |
| 1464 | [Enhancement: Cache frames for pre-alarm even without motion](https://github.com/aegissystems/vms-connector/issues/1464) | `enhancement` | — | 3mo | 3mo |

</details>

<!-- END-AUTO-REFRESH repo-scan -->

## Related

- [[repo-backlog/_summary|repo-backlog topic]]
- Latest scan: [[2026-05-01_scan]]
- GitHub: [aegissystems/vms-connector/issues](https://github.com/aegissystems/vms-connector/issues)
