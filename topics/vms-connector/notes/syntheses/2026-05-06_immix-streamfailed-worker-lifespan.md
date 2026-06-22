---
title: "Immix DeviceWorker lifespan expiry mislabeled as 'streamfailed'"
type: synthesis
topic: vms-connector
tags: [autopatrol, vch, immix, patrol-api, alert-dispatch, worker-lifecycle]
jira: ""
created: 2026-05-06
updated: 2026-05-06
author: kb-bot
outgoing:
  - topics/personal-notes/notes/daily/2026-05-06.md
  - topics/vms-connector/notes/concepts/2026-05-06_bugfix-stream-id-history-iteration.md
  - topics/autopatrol/notes/syntheses/2026-05-07_consumer-side-websocket-close-feasibility.md
incoming:
  - topics/autopatrol/notes/concepts/2026-05-14_autopatrol-tier-api-cross-reference.md
  - topics/autopatrol/notes/data/2026-05-06_immix-streamfinished-inquiry.md
  - topics/autopatrol/notes/entities/immix-vendor-api.md
  - topics/autopatrol/notes/syntheses/2026-05-07_consumer-side-websocket-close-feasibility.md
  - topics/autopatrol/notes/syntheses/2026-05-14_autopatrol-tier-model-and-detection-types.md
  - topics/billing/notes/syntheses/2026-05-12_week-in-review-non-technical.md
  - topics/camera-health-monitoring/notes/concepts/2026-05-14_chm-multi-frame-quality-sampling-followup.md
  - topics/integrations/vch/notes/syntheses/2026-05-18_libav-decoder-warmup-frame-fix.md
  - topics/personal-notes/notes/daily/2026-05-06.md
  - topics/personal-notes/notes/daily/2026-05-07.md
incoming_updated: 2026-05-27
---

# Immix DeviceWorker lifespan expiry mislabeled as 'streamfailed'

**TL;DR:** Every no-detection patrol shows `streamfailed` in Immix's UI. Root cause is not a connector failure—it's Immix's DeviceWorker intentionally terminating after consuming the video duration we requested via API. The Worker's exit cause is being mislabeled as "stream failure" when it should be labeled "normal completion" or "lifespan expiry."

## The Pattern

Every AutoPatrol and VCH patrol that completes without detections shows:
- `patrolStatus: Finished` (HTTP 200, correct termination)
- `streamfailed` label in Immix UI (incorrect labeling)
- Connector logs show zero errors; frames successfully decoded; no websocket reconnects

This affects **100% of no-detection patrols** examined to date.

## Triggering Evidence

Patrol `A188AC1E-89C9-4B58-5FCD-08DEA10F17AF` on 2026-05-06 at 14:15:01 UTC:

**Connector side** (internal NR logs — container `connector-46560-autopatrol-1066-chm-cronjob`):
```
14:15:01 → Obtained stream URL from Immix (success)
14:15:01 → Stream ID: 6535afa3-ff43-47aa-a6d3-42edddb71f06
14:15:01 → Websocket connected on attempt 1 (no retries)
14:15:01 → Frame resolution 720x1280 confirmed
14:15:11 → Frame Count: 39, Time elapsed: 10.181s
14:15:11 → has_motion: False, motion_frame_count: 0
14:15:11 → POST /Patrols/{id}/raise → HTTP 200
14:15:11 → GET /Patrols/{id} → patrolStatus: Finished (HTTP 200)
         → Zero ERROR logs in container for entire run
```

**Immix side** (DeviceWorker log for the same run — timestamps mixed UTC/local):
```
2026-05-06T09:15:02 12588 Worker : Started. Arguments: HanwhaWaveMeta\DevNetworkOptix.dll DevNetworkOptix.Device 98.116.129.133
2026-05-06T09:15:02 12588 Worker : DeviceHost shared
2026-05-06T09:15:02 12588 Worker : Worker has a hard life-span and is therefore not reusable. Life span limit set to 10 seconds
2026-05-06T09:15:02 12588 Worker : Worker heartbeat started
2026-05-06T09:15:02 12588 Worker : Worker running
2026-05-06T09:15:02 12588 Worker : Starting host heartbeat loop.
2026-05-06T09:15:02 12588 DeviceHost: Heartbeating worker. Source - ObjectHostContainer constructor.
2026-05-06T09:15:02 12588 DeviceHost: Host ID Set - aae3e77b-14c0-4b62-8610-80a232065b8f
2026-05-06T09:15:02 12588 DeviceHost: Loading. File=C:\Program Files (x86)\Immix Cloud\Devices\HanwhaWaveMeta\DevNetworkOptix.dll,Type=DevNetworkOptix.Device
2026-05-06T09:15:02 12588 DeviceHost: Action 'new()' calling
2026-05-06 14:15:02.435:{Th:3} - Assembly : DeviceWorker - 2.2601.27.1
2026-05-06T09:15:02 12588 DeviceHost: Action 'Server={Host=98.116.129.133,Port=7001,User=ssginc,Password=Yde2320100,Extra=}' calling
2026-05-06T09:15:02 12588 DeviceHost: Heartbeating worker. Source - Starting video.
2026-05-06T09:15:02 12588 DeviceHost: Action 'UsePassthrough=False' calling
2026-05-06T09:15:02 12588 DeviceHost: Action 'CameraExtraValue=1158e582-37c7-39d8-503b-91938f9de081' calling
2026-05-06T09:15:02 12588 DeviceHost: Action 'CameraNumber=18' calling
2026-05-06T09:15:02 12588 DeviceHost: Action 'CameraQuality=Medium' calling
2026-05-06T09:15:02 12588 DeviceHost: Action 'CameraAdditionalID=0' calling
2026-05-06T09:15:02 12588 DeviceHost: Action 'DeviceConnect()' calling
2026-05-06T09:15:02 12588 DeviceHost: Action 'CameraStartLive()' calling
06/05/2026 09:15:03: Immix.Media - Setting default AVOption: rtsp_transport=tcp
06/05/2026 09:15:03: Immix.Media - Setting default AVOption: probesize=8192
06/05/2026 09:15:03: Immix.Media - Setting AVOption: probesize=50000
06/05/2026 09:15:03: Immix.Media - [rtsp @ 040267c0] Stream #0: not enough frames to estimate rate; consider increasing probesize
2026-05-06T09:15:03 12588 DeviceHost: Heartbeating worker. Source - Finished starting video.
2026-05-06T09:15:04 12588 DeviceHost: Camera muxer set up: encoding
2026-05-06T09:15:04 12588 Worker : Encoder initialized event detected. Starting life span limit now. Worker will end in 10 seconds
2026-05-06T09:15:08 12588 DeviceHost: Heartbeating worker. Source - Stream heartbeat.
2026-05-06T09:15:14 12588 DeviceHost: Heartbeating worker. Source - Stream heartbeat.
2026-05-06T09:15:14 12588 Worker : Worker life span limit hit. Signaling the worker to close
2026-05-06T09:15:14 12588 Worker : Force closing worker due to life-span expiry
2026-05-06T09:15:14 12588 Worker : Delayed end, killing the process after a short delay
```

The smoking gun: `Worker life span limit hit. Signaling the worker to close` → `Force closing worker due to life-span expiry`. The Worker executed its intended termination logic (the 10-second timeout we requested), but exited in a way Immix's labeling layer categorizes as "streamfailed."

## How It Works

1. **Connector API call:** `GET /Patrols/{id}/Device/{device}/videostream?Duration=10`
   - The `Duration=10` parameter is set from `autopatrol_config.duration` in `actuate-pullers/socket/autopatrol_websocket_stream_puller.py:78`
   - AutoPatrol default: 10 seconds
   - VCH default: 2 seconds

2. **Immix DeviceWorker:** Translates the `Duration` parameter into a hard lifespan limit
   - Line: `Worker has a hard life-span and is therefore not reusable. Life span limit set to 10 seconds`
   - The Worker will forcibly terminate after that time, regardless of websocket state

3. **Connector consumes stream:** Successfully receives frames for the full requested duration (10.2 seconds in this run)

4. **Worker timer fires:** At the 10-second boundary, the Worker's lifespan expires
   - `Worker life span limit hit. Signaling the worker to close` → `Force closing worker due to life-span expiry`
   - **This forced-kill exit is what Immix labels `streamfailed` in the UI**

5. **Outcome:** Patrol completes successfully (HTTP 200, `patrolStatus: Finished`), but carries the misleading label

## Why This Is NOT the stale-stream_id bug

This pattern is unrelated to [[2026-04-20_streamid-null-patrol-alert-bug|the streamId-null bug we fixed on 2026-04-20]]. The stale stream_id bug only triggers when `consume_stream` enters its retry loop (i.e., websocket fails mid-run and the puller re-fetches a fresh stream URL).

In this patrol:
- Zero websocket reconnects
- Zero retries of `get_patrol_stream`
- Connector received video successfully for the full duration
- Single successful connect attempt

The `streamfailed` label is purely driven by the Worker's lifespan timer firing as designed.

## Open Questions for Immix

- What exit-cause codes does the DeviceWorker distinguish, and which ones map to `streamfailed`?
- Is there a graceful-close path we can trigger from the websocket client side (e.g., explicit `close()` frame before the lifespan timer fires)?
- Why do some log lines timestamp in local time (`09:15:02`) and others in UTC with millisecond precision (`14:15:02.435`)? Inconsistency complicates correlation.

## Proposed Fixes

**Primary (Immix-side):** Don't label "Worker hit configured lifespan limit" as `streamfailed`. The lifespan limit is the duration **we explicitly requested via the API**—terminating at that boundary is normal completion, not failure. This likely requires distinguishing the exit cause in the Worker's shutdown path before it reaches Immix's labeling layer.

**Secondary (connector-side experiment, optional):** Request `duration=12` seconds from the API but close the websocket and exit `consume_stream` at 10 seconds. If Immix's Worker observes the client-initiated close before its own lifespan timer fires, it may exit with a different label. Single patrol trial would be cheap before committing to a connector behavior change.

> **Update 2026-05-07:** evaluated in detail and deferred — see [[2026-05-07_consumer-side-websocket-close-feasibility]]. The change is mechanically simple but carries a ~15–20% inference-frame-coverage cost to actually win the close race against Immix's hard-lifespan timer. Held pending Immix's response on [[2026-05-06_immix-streamfinished-inquiry]] and broader discussion.

**Tertiary (acceptance, only if 1 & 2 both fail):** Treat the label as cosmetic. The signals that matter are `HTTP 200` on the raise call and `patrolStatus: Finished` on the status check—both are present and correct.

---

**Internal-only context (strip if forwarding externally):**

- NR query window: container `connector-46560-autopatrol-1066-chm-cronjob`, 2026-05-06 14:15:01–14:15:19 UTC
- Correlation key: `motion_run_timestamp: 1778076901` from autopatrol-server S3 payload matches `Obtained stream URL` at 1778076901.6 in connector logs (unambiguous match)
- Stream ID used at raise time: `6535afa3-ff43-47aa-a6d3-42edddb71f06` (matches patrol ack'd by Immix)
- Affected patrols: confirmed on every no-detection run audited; no example of a patrol completing without this label found to date
- Related: [[2026-04-20_streamid-null-patrol-alert-bug]] (distinct issue: stream_id validation on alert dispatch); [[2026-05-06_immix-websocket-consumer-retry-fix]] (distinct fix: stale stream_id on reconnect)
