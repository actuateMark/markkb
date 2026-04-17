---
title: "Source: New Relic CHM Operational Data (April 8-15, 2026)"
type: source
topic: camera-health-monitoring
tags: [newrelic, operational-data, chm, metrics, diagnostics]
ingested: 2026-04-15
author: kb-bot
---

# New Relic CHM Operational Data

Queried 2026-04-15, covering the 7-day window April 8-15.

## Volume

- **~900K healthcheck log entries per day** (ranging 879K-1.07M)
- **~21K connectivity checks/day**, ~20.7K stream quality, ~19.8K motion status, ~19.8K recording, **~14.7K scene change** (fewer -- scene_change_check defaults to False)
- **~6K verified scene change detections/day** (SAC bank notifications), trending upward (5K -> 6.3K over the week)

## Active CHM Sites

VCH CronJobs observed: `connector-40499-vch-261-chm-cronjob`, `connector-40507-vch-269-chm-cronjob`, `connector-40800-vch-288-chm-cronjob`, etc. (~10 active VCH sites).

One non-VCH site (`connector-12749`) generating 9.3K "unable to connect" warnings in 7 days -- chronic connectivity issue.

## Recurring Errors (7 days)

| Error | Count | Integration | Root Cause |
|-------|-------|-------------|------------|
| `error in digital watchdog healthcheck 'NoneType' object has no attribute 'lower'` | 184 | DW | NoneType in DW API response parsing |
| `error in hikcentral healthcheck: 'NoneType' object is not subscriptable` | 167 | HikCentral | NoneType in HikCentral API response |
| `error in exacq healthcheck: 'Cameras'` | 163 | Exacq | KeyError in camera list parsing |
| `error in rtsp diagnostics ('Connection aborted.', BadStatusLine('RTSP/1.0 400 Bad Request'))` | 102 | RTSP | **RTSP responding to HTTP GET with RTSP status line** -- confirms the HTTP GET probe is wrong |

**Key finding:** The RTSP diagnostic error `BadStatusLine('RTSP/1.0 400 Bad Request')` directly confirms the problem described in Phase 1 -- the diagnostic sends an HTTP GET to an RTSP port, and the camera responds with an RTSP status line that Python's HTTP library can't parse.

## Skipped Cameras (7 days)

| Pattern | Count |
|---------|-------|
| `Healthcheck is disabled, exiting` | 3,838 |
| `empty healthcheck data, returning` | 3,792 |
| `Skipping healthcheck for camera X. No runner available` | ~18,000+ (across many cameras) |

**"No runner available"** affects thousands of camera-runs per week. These are cameras where the healthcheck type isn't supported for their integration -- exactly the gap that Phase 4 (GenericDiagnostics) would address.

## Incident Patterns

Connectivity incidents dominate. Example: camera `AXISP3265V` has been in continuous `ongoing` incident state for 264+ consecutive runs (likely weeks). The incident_analysis logs show `valid=False, has_previous_incident=True, previous_incident_ended=False` -- stuck in a failure loop with no deeper diagnosis.

## Implications for Phase Proposals

1. **Phase 1 (NetworkProbe):** The `RTSP/1.0 400 Bad Request` error proves the HTTP GET probe is wrong. A real RTSP DESCRIBE or TCP probe would eliminate this class of errors entirely.
2. **Phase 3 (Correlation):** The `connector-12749` site with 9.3K "unable to connect" events likely has an NVR or tunnel issue, not individual camera problems. Correlation would collapse this to 1 alert.
3. **Phase 4 (GenericDiagnostics):** 18K+ "No runner available" skips per week represent cameras getting zero diagnostic value. GenericDiagnostics would cover all of these.
4. **Phase 7 (Trending):** The `AXISP3265V` camera stuck in ongoing incident for 264+ runs shows the need for escalation -- if an incident isn't resolving after N runs, the alert severity should increase.
5. **Existing bugs:** DW (NoneType), HikCentral (NoneType), Exacq (KeyError) each have ~160-180 errors/week -- these are defensive coding gaps, not architectural issues. Quick fixes.
