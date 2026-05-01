---
title: "AutoPatrol Alert Lifecycle"
type: concept
topic: autopatrol
tags: [autopatrol, alert-lifecycle, immix, vms-connector, alarm-senders, deferred-alerts, dynamodb]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# AutoPatrol Alert Lifecycle

End-to-end flow of how a detection becomes a timeline entry in the Immix Connect portal and in our internal DynamoDB alert data.

## Two Independent Alert Paths

AutoPatrol has two separate mechanisms for reporting detections to Immix. They run independently and write to different data stores.

### Path 1: Connector Real-Time Alerts

**Source:** vms-connector CronJob (camera pipeline)
**Destination:** Immix Connect API (`PUT /Patrols/{id}/raise`) + AutoPatrol alerts DynamoDB table

```
YOLO inference → check_confirmation_step → sliding_window_step → send_alerts()
  → flush_deferred_alerts() (if tag zones defer the alert)
    → send_executor.submit(trigger_alert)
      → put_detection_window() [WindowIdsV2 DynamoDB]
      → MultiAlertSender.executor.submit(AutoPatrolAlertSender.send)
        → get_autopatrol_alert_type() [label → detection code mapping]
        → _build_annotated_image_url() [DDB + S3 annotate + presign]
        → raise_patrol_alert() [HTTP to Immix]
        → save_autopatrol_alert() [AutoPatrol alerts DynamoDB]
```

**Creates:** Individual per-detection timeline entries (PERSON, BIKE, VEHICLE, etc.)
**Detection code:** Mapped from converted label via `get_autopatrol_alert_type()` in `autopatrol_sender.py`

### Path 2: Autopatrol-Server Summary Alert

**Source:** autopatrol-server (SQS consumer)
**Destination:** Immix Connect API (`PUT /Patrols/{id}/raise`) + S3 patrol JSON

```
SQS message (patrol data with clips) → AutoPatrolHandler.run()
  → Object tracking (SORT) + Activity analysis per clip
  → PatrolSummarizer aggregates results
  → raise_patrol_alert(detection_code="PATROL_SUMMARY", description=text_summary)
  → end_patrol()
```

**Creates:** One PATROL_SUMMARY entry per patrol with aggregated text description
**Does NOT create:** Individual per-detection timeline entries

### Data Stores Written

| Store | Path 1 (Connector) | Path 2 (Server) |
|-------|-------------------|-----------------|
| WindowIdsV2 DynamoDB | `put_detection_window()` in trigger_alert | Not written |
| AutoPatrol alerts DynamoDB | `save_autopatrol_alert()` in sender | Not written |
| S3 patrol JSON | Not written | `save_patrol_to_s3()` |
| Immix timeline | Per-detection raise | Single PATROL_SUMMARY raise |

## Label Flow Through the Pipeline

The label undergoes several transformations:

1. **Model output:** Raw YOLO label (e.g., `"person"`, `"bicycle"`)
2. **check_confirmation_step:** Matched against `raw_metrics` keys. Vehicle labels converted via `merge_vehicles` + label_converter (e.g., `"bicycle"` → `"bike"`). Non-vehicle labels pass through raw.
3. **sliding_window_step:** Window created with the label from step 2. Window ID includes raw label.
4. **trigger_alert → get_alert_url_components:** `label_converter.convert_label(raw_label)` applied. E.g., `"person"` → `"intruder"`.
5. **AutoPatrolAlertSender.send → get_autopatrol_alert_type:** Maps converted label to Immix detection code. `"intruder"` → `PERSON`, `"bike"` → `BIKE`.

If a label doesn't have a converter mapping AND isn't in the `get_autopatrol_alert_type` mapping, a `ValueError` is raised — currently caught by `ActuateThreadPoolExecutor._callback` and logged as a warning, but the alert is lost.

## Deferred Alert Path (Tag Zones)

When a product has tag zones configured, the alert is deferred:
- `threshhold_reached()` sets `alert_pending = True` instead of `send_alert = True`
- The alert waits for the window to close (accumulate tag zone hits)
- At patrol end, `flush_deferred_alerts()` fires any still-pending alerts
- Frame data may have expired from the LRU cache → [[s3-frame-fallback|S3 frame fallback]] activates (see [[s3-frame-fallback]])

**Known issue:** `flush_deferred_alerts()` submits to the executor but does not wait for completion. The patrol CronJob can exit before the executor threads finish the Immix API call and DynamoDB save. See [[2026-04-16_deferred-alert-race-condition]].

## Key Code Locations

| Component | File | Key Lines |
|-----------|------|-----------|
| Confirmation step | `actuate-pipeline/.../check_confirmation_step.py` | 26-47 |
| Sliding window | `actuate-pipeline/.../sliding_window_step.py` | 71-182 |
| send_alerts dispatch | `vms-connector/camera/shared/base_stream_camera.py` | 878-970 |
| flush_deferred_alerts | `vms-connector/camera/shared/base_stream_camera.py` | 1009-1106 |
| AutoPatrolCamera.send_alerts | `vms-connector/camera/autopatrol/autopatrol_camera.py` | 175-177 |
| patrol_send_alerts (clip collection) | `vms-connector/camera/patrol/patrol_camera_mixin.py` | 162-193 |
| trigger_alert + AlertData | `actuate-alarm-senders/.../multi_alert_sender.py` | 114-265 |
| AutoPatrolAlertSender.send | `actuate-alarm-senders/.../autopatrol_sender.py` | 135-161 |
| Label → detection code mapping | `actuate-alarm-senders/.../autopatrol_sender.py` | 27-68 |
| autopatrol-server raise | `autopatrol-server/server/autopatrol_queue.py` | 97-105 |
| AutoPatrolAPI.raise_patrol_alert | `actuate-integration-calls/.../autopatrol_api.py` | 361-397 |

## Monitoring & Regression Detection

After the deferred alert race condition fix (see [[2026-04-16_deferred-alert-race-condition]]), the pipeline now emits enough log signals to detect alert drops in production.

### Key NR Queries

**Detect alert drops** — compare flush firing count vs delivery count per patrol:

```sql
-- Alerts fired vs delivered for a specific patrol
SELECT count(*)
FROM Log
WHERE cluster_name = 'TARGET_CLUSTER' AND container_name LIKE 'vms-connector%'
  AND (message LIKE '%flush_deferred_alerts: firing%' OR message LIKE '%AutoPatrol alert delivered%')
FACET CASES(
  WHERE message LIKE '%flush_deferred_alerts: firing%' AS 'fired',
  WHERE message LIKE '%AutoPatrol alert delivered%' AS 'delivered'
)
SINCE 1 hour ago
```

If `fired` > `delivered`, alerts are being lost.

**Drain timeout warnings:**

```sql
SELECT count(*)
FROM Log
WHERE cluster_name = 'TARGET_CLUSTER' AND container_name LIKE 'vms-connector%'
  AND message LIKE '%executor drain%'
SINCE 24 hours ago
```

Any results here mean the executor did not finish within the drain timeout — alerts may have been lost.

**HTTP status errors from Immix:**

```sql
SELECT count(*)
FROM Log
WHERE cluster_name = 'TARGET_CLUSTER' AND container_name LIKE 'vms-connector%'
  AND message LIKE '%raise_patrol_alert failed: status=%'
SINCE 24 hours ago
```

### Healthy Patrol Log Sequence

A healthy patrol with deferred alerts should produce this sequence for EACH detection:

1. `flush_deferred_alerts: firing pending alert for {label}` — alert submitted to executor
2. `drain_alert_executors: completed in {N}s` — executor drained successfully (once per patrol, not per alert)
3. `AutoPatrol alert delivered for {camera} alert_type {TYPE}` — Immix accepted the alert and DDB was written

### Alert Conditions to Set Up

| Condition | Meaning | Severity |
|-----------|---------|----------|
| `flush_deferred_alerts: firing` without matching `AutoPatrol alert delivered` within 30s | Lost alert — fired but never confirmed delivered | Critical |
| `drain_alert_executors: completed` timing approaching 30s | Executor is saturated, alerts at risk of timeout | Warning |
| `raise_patrol_alert failed: status=` present | Immix API rejecting alerts | Critical |
| `executor drain` warning present | Drain timed out, alerts likely lost | Critical |

### Operational Notes

- The drain timeout is the hard boundary. If `drain_alert_executors: completed in Xs` shows X approaching the timeout (30s), the executor thread pool is saturated — likely too many concurrent alerts or slow Immix API responses.
- The `flush_deferred_alerts` summary counts (fired/skipped) provide a quick per-patrol health signal without needing to count individual log lines.

## Related Notes

- [[s3-frame-fallback]] — frame cache eviction fix for deferred alerts
- [[sliding-window-mechanics]] — window lifecycle and threshold gating
- [[actuate-alarm-senders]] — sender implementations
- [[autopatrol-server]] — summary analysis and PATROL_SUMMARY raise
- [[2026-04-16_deferred-alert-race-condition]] — investigation of lost person alert
