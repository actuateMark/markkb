---
title: "actuate-libraries backlog"
type: concept
topic: repo-backlog
tags: [backlog, github, actuate-libraries]
repo: aegissystems/actuate-libraries
created: 2026-06-18
updated: 2026-06-18
author: kb-bot
issue_count_open: 34
issue_count_high_impact: 8
issue_count_lhf: 10
issue_count_stale: 0
high_impact_issue_numbers: [236, 305, 290, 243, 242, 233, 256, 234]
lhf_issue_numbers: [244, 234, 233, 327, 305, 297, 290, 285, 280, 266]
stale_issue_numbers: []
full_issue_numbers: [348, 337, 327, 305, 297, 290, 285, 283, 280, 266, 257, 256, 252, 251, 248, 247, 245, 244, 243, 242, 241, 240, 239, 238, 237, 236, 234, 233, 232, 231, 230, 229, 228, 51]
---

# actuate-libraries backlog

Full open-issue inventory for [aegissystems/actuate-libraries](https://github.com/aegissystems/actuate-libraries/issues). The auto-refresh block is overwritten by [[skill-repo-scan|/repo-scan]]; **Curated notes** are hand-maintained and preserved across refreshes.

## Curated notes

*(Hand-maintained. Not touched by /repo-scan.)*

### Landscape

33 open issues, mostly sub-library enhancements. No stale issues (all active-ish). Heavy overlap with the [[vms-connector|vms-connector backlog]] — several issues here are the library-side half of connector tickets.

### Active clusters

| Cluster | Issues | Notes |
|---------|--------|-------|
| **Test coverage expansion** | 228, 229, 230, 231, 232 | Five-way split on test-writing (video pullers, alert senders, sudden scene change, pipeline steps, re-enabling disabled tests). Coherent LHF if tackled together. Mirrors the connector-side cluster (1465-1470). |
| **Pipeline / filter tuning** | 241, 242, 243, 244, 247, 251, 252, 256, 285, 297, 327, 51 | Large cluster — blacklist filter behaviour, pre_alarm optimizations, Line Crossing semantics, FDMD adaptation, IOU math. Many small wins here; could consolidate into a "Filter Polish" epic. |
| **Puller robustness** | 233, 238, 240, 245, 337 | Bandwidth tracking, [[ffmpeg-entity|FFmpeg]] [[rtsp-deep-dive|RTSP]] flags, frame-None AttributeError, stream diagnostics, S3 batching. **240** pairs with connector-side [[rtsp-deep-dive|RTSP]] suite (1648-1652) — coordinate. |
| **Release / version automation** | 239, 248, 266, 290 | CI check for inter-package version constraints (239), auto-version on branch merge (248), 2.x release of suddenscenechange (266), commit-msg-based → PR-label tagging (290). All support /pre-merge-workflow — LHF when we next touch the release pipeline. |
| **DB / reliability** | 257, 280, 283 | **283** (BaseDynamoDAO.batch_get silently drops UnprocessedKeys) is a correctness bug — promote to high priority. 257 (retry 503s) is a thin wrapper. 280 (milestone alarm retry broken) deserves a code walk to confirm still-valid. |
| **Memory / cleanup** | 236 | Lone but real — CameraDisturbanceDetectorBank missing cleanup. Matches connector-side 1499 pattern. |
| **EU / i18n** | 237 | `actuate_base_url` parameterization for AdminDAO — ties into admin#2177 (EU prod-proxy). Coordinate with the Europe expansion workstream. |
| **Frame queue policy** | 247 | "Discard oldest instead of clear queue" — small but impactful behavior change. |
| **Logging polish** | 244, 251 | Reduce log verbosity while preserving context. LHF. |
| **New library creation** | 234 (actuate-onvif) | Blocks ONVIF integration work — not small. |

### Known cross-repo ties

| This repo | Counterpart | Move together? |
|-----------|-------------|----------------|
| 240 ([[rtsp-deep-dive|RTSP]] [[ffmpeg-entity|FFmpeg]] flags) | vms-connector 1648-1652 | Yes |
| 233 (S3 batching) | vms-connector 1471 | Yes |
| 237 (EU base URL) | [[actuate_admin]] 2177 | Yes |
| 247 (queue overflow) | vms-connector 1464 (pre-alarm caching) | Possibly |

### Codebase-scan follow-up
No >180d-idle issues. If stale accumulates: walk the relevant sub-library's `git log`, reason about whether the library method was refactored or the hooking code moved, comment with commit refs. **Never bulk-close.**

### Git-safety reminder
Never push to `actuate-libraries` **main** without explicit user approval — auto-publishes stable versions to CodeArtifact.

<!-- BEGIN-AUTO-REFRESH repo-scan -->
_Last refreshed: **2026-06-18** by [[skill-repo-scan]] — 34 open issues._

### 🔥 High-impact (top 10 by score)

| # | Title | Labels | Assignee | Score | Idle |
|--:|-------|--------|----------|------:|------|
| 236 | [[BUG] Memory Leak in CameraDisturbanceDetectorBank - Missing Cleanup Methods](https://github.com/aegissystems/actuate-libraries/issues/236) | `bug` | — | 3 | 5mo |
| 305 | [Share internal executor pools across observers per camera](https://github.com/aegissystems/actuate-libraries/issues/305) | `enhancement` | — | 2 | 3mo |
| 290 | [Switch version bump tagging from commit messages to PR labels](https://github.com/aegissystems/actuate-libraries/issues/290) | — | — | 2 | 3mo |
| 243 | [CleanupStep: Remove unnecessary 10-frame floor when pre_alarm is set](https://github.com/aegissystems/actuate-libraries/issues/243) | — | — | 2 | 5mo |
| 242 | [Add defensive checks and logging for cache misses in pipeline steps](https://github.com/aegissystems/actuate-libraries/issues/242) | — | — | 2 | 5mo |
| 233 | [S3 Frame Upload Batching - Connector Implementation](https://github.com/aegissystems/actuate-libraries/issues/233) | `enhancement` | — | 2 | 5mo |
| 256 | [Line Crossing: Trajectory linking causes chaotic drawings in crowded scenes](https://github.com/aegissystems/actuate-libraries/issues/256) | — | — | 1 | 4mo |
| 234 | [Create actuate-onvif Library](https://github.com/aegissystems/actuate-libraries/issues/234) | — | — | 1 | 5mo |

### 🧹 Low-hanging fruit (top 10 by score)

| # | Title | Labels | Assignee | Score | Idle |
|--:|-------|--------|----------|------:|------|
| 244 | [Reduce verbosity of 'after filters' log lines without losing context](https://github.com/aegissystems/actuate-libraries/issues/244) | — | — | 5 | 5mo |
| 234 | [Create actuate-onvif Library](https://github.com/aegissystems/actuate-libraries/issues/234) | — | — | 5 | 5mo |
| 233 | [S3 Frame Upload Batching - Connector Implementation](https://github.com/aegissystems/actuate-libraries/issues/233) | `enhancement` | — | 5 | 5mo |
| 327 | [Blacklist groups accumulate without bound on static scenes](https://github.com/aegissystems/actuate-libraries/issues/327) | — | — | 3 | 2mo |
| 305 | [Share internal executor pools across observers per camera](https://github.com/aegissystems/actuate-libraries/issues/305) | `enhancement` | — | 3 | 3mo |
| 297 | [Blacklist Filter: Storm & Weather Noise Mitigation](https://github.com/aegissystems/actuate-libraries/issues/297) | `enhancement` | — | 3 | 3mo |
| 290 | [Switch version bump tagging from commit messages to PR labels](https://github.com/aegissystems/actuate-libraries/issues/290) | — | — | 3 | 3mo |
| 285 | [FDMD: Consider EMA background blending for smoother adaptation](https://github.com/aegissystems/actuate-libraries/issues/285) | — | — | 3 | 3mo |
| 280 | [Milestone alarm sender retry logic is broken](https://github.com/aegissystems/actuate-libraries/issues/280) | — | — | 3 | 4mo |
| 266 | [Release actuate-suddenscenechange v1.2.0 from 1.x line](https://github.com/aegissystems/actuate-libraries/issues/266) | — | — | 3 | 4mo |

### 🔍 Codebase-scan follow-up candidates (idle >180d)

*These are **not** bulk-close candidates — each needs case-by-case review. Many may already be addressed by later work; some deserve a bump. Walk the codebase for context before commenting.*

_(none)_

### 📊 Labels

| Label | Count |
|-------|------:|
| `enhancement` | 4 |
| `bug` | 1 |

### 🗃️ Full open inventory

<details><summary>All 34 open issues (click to expand — sorted newest first)</summary>

| # | Title | Labels | Assignee | Age | Idle |
|--:|-------|--------|----------|-----|------|
| 348 | [actuate-movement: preallocate cv2 output buffers in frame-diff pipeline (~40% a…](https://github.com/aegissystems/actuate-libraries/issues/348) | — | actuateMark | 1mo | 1mo |
| 337 | [[Enhancement] actuate-pullers: Expose stream diagnostics metadata from AvUrlFra…](https://github.com/aegissystems/actuate-libraries/issues/337) | — | — | 2mo | 2mo |
| 327 | [Blacklist groups accumulate without bound on static scenes](https://github.com/aegissystems/actuate-libraries/issues/327) | — | — | 2mo | 2mo |
| 305 | [Share internal executor pools across observers per camera](https://github.com/aegissystems/actuate-libraries/issues/305) | `enhancement` | — | 3mo | 3mo |
| 297 | [Blacklist Filter: Storm & Weather Noise Mitigation](https://github.com/aegissystems/actuate-libraries/issues/297) | `enhancement` | — | 3mo | 3mo |
| 290 | [Switch version bump tagging from commit messages to PR labels](https://github.com/aegissystems/actuate-libraries/issues/290) | — | — | 3mo | 3mo |
| 285 | [FDMD: Consider EMA background blending for smoother adaptation](https://github.com/aegissystems/actuate-libraries/issues/285) | — | — | 3mo | 3mo |
| 283 | [BaseDynamoDAO.batch_get silently drops items when DynamoDB returns UnprocessedK…](https://github.com/aegissystems/actuate-libraries/issues/283) | — | — | 4mo | 4mo |
| 280 | [Milestone alarm sender retry logic is broken](https://github.com/aegissystems/actuate-libraries/issues/280) | — | — | 4mo | 4mo |
| 266 | [Release actuate-suddenscenechange v1.2.0 from 1.x line](https://github.com/aegissystems/actuate-libraries/issues/266) | — | — | 4mo | 4mo |
| 257 | [Add retry logic for create-detection-window 503 responses](https://github.com/aegissystems/actuate-libraries/issues/257) | — | — | 4mo | 4mo |
| 256 | [Line Crossing: Trajectory linking causes chaotic drawings in crowded scenes](https://github.com/aegissystems/actuate-libraries/issues/256) | — | — | 4mo | 4mo |
| 252 | [Line Crossing: Verify direction interpretation matches UI](https://github.com/aegissystems/actuate-libraries/issues/252) | — | — | 5mo | 5mo |
| 251 | [Improve RawModelFilterStep logging to clarify label filtering vs ignore zones](https://github.com/aegissystems/actuate-libraries/issues/251) | — | — | 5mo | 5mo |
| 248 | [Create new version of all branch libraries on merge](https://github.com/aegissystems/actuate-libraries/issues/248) | — | — | 5mo | 5mo |
| 247 | [Frame queue overflow: discard oldest frames instead of clearing entire queue](https://github.com/aegissystems/actuate-libraries/issues/247) | — | — | 5mo | 5mo |
| 245 | [VideoQueuePuller: AttributeError when frame is None in check_frame_motion_and_p…](https://github.com/aegissystems/actuate-libraries/issues/245) | — | — | 5mo | 5mo |
| 244 | [Reduce verbosity of 'after filters' log lines without losing context](https://github.com/aegissystems/actuate-libraries/issues/244) | — | — | 5mo | 5mo |
| 243 | [CleanupStep: Remove unnecessary 10-frame floor when pre_alarm is set](https://github.com/aegissystems/actuate-libraries/issues/243) | — | — | 5mo | 5mo |
| 242 | [Add defensive checks and logging for cache misses in pipeline steps](https://github.com/aegissystems/actuate-libraries/issues/242) | — | — | 5mo | 5mo |
| 241 | [Optimize previous_frame_ids buffer when pre_alarm is not used](https://github.com/aegissystems/actuate-libraries/issues/241) | — | — | 5mo | 5mo |
| 240 | [Add FFmpeg flags for improved RTSP stream tolerance (jittery/spotty connections)](https://github.com/aegissystems/actuate-libraries/issues/240) | — | — | 5mo | 5mo |
| 239 | [Add CI check for inter-package dependency version constraints](https://github.com/aegissystems/actuate-libraries/issues/239) | — | — | 5mo | 5mo |
| 238 | [Add bandwidth tracking (DynamoDB + New Relic) to all pullers](https://github.com/aegissystems/actuate-libraries/issues/238) | — | — | 5mo | 5mo |
| 237 | [EU Support: Make actuate_base_url a required parameter for AdminDAO/AdminApi](https://github.com/aegissystems/actuate-libraries/issues/237) | — | — | 5mo | 5mo |
| 236 | [[BUG] Memory Leak in CameraDisturbanceDetectorBank - Missing Cleanup Methods](https://github.com/aegissystems/actuate-libraries/issues/236) | `bug` | — | 5mo | 5mo |
| 234 | [Create actuate-onvif Library](https://github.com/aegissystems/actuate-libraries/issues/234) | — | — | 5mo | 5mo |
| 233 | [S3 Frame Upload Batching - Connector Implementation](https://github.com/aegissystems/actuate-libraries/issues/233) | `enhancement` | — | 5mo | 5mo |
| 232 | [Review and enable disabled test files](https://github.com/aegissystems/actuate-libraries/issues/232) | — | — | 5mo | 5mo |
| 231 | [Add tests for pipeline steps](https://github.com/aegissystems/actuate-libraries/issues/231) | — | — | 5mo | 5mo |
| 230 | [Add tests for sudden scene change detection](https://github.com/aegissystems/actuate-libraries/issues/230) | — | — | 5mo | 5mo |
| 229 | [Add tests for alert senders](https://github.com/aegissystems/actuate-libraries/issues/229) | — | — | 5mo | 5mo |
| 228 | [Add tests for video pullers](https://github.com/aegissystems/actuate-libraries/issues/228) | — | — | 5mo | 5mo |
| 51 | [Optimization of IOU Calculation Function](https://github.com/aegissystems/actuate-libraries/issues/51) | `enhancement` | actuateMark | 1y | 5mo |

</details>

<!-- END-AUTO-REFRESH repo-scan -->

## Related

- [[repo-backlog/_summary|repo-backlog topic]]
- Latest scan: [[2026-06-18_scan]]
- GitHub: [aegissystems/actuate-libraries/issues](https://github.com/aegissystems/actuate-libraries/issues)
