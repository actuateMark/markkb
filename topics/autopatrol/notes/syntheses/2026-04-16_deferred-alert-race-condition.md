---
title: "Investigation: Deferred Alert Race Condition at Patrol Exit"
type: synthesis
topic: autopatrol
tags: [autopatrol, alert-lifecycle, race-condition, deferred-alerts, investigation, vms-connector, immix]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - topics/autopatrol/_summary.md
  - topics/autopatrol/notes/concepts/autopatrol-alert-lifecycle.md
  - topics/autopatrol/notes/entities/todo-list.md
  - topics/infrastructure/notes/syntheses/2026-04-16_cronjob-image-rotation-lag.md
  - topics/personal-notes/notes/daily/2026-04-20.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-05-01
---

# Deferred Alert Race Condition at Patrol Exit

## Summary

Patrol `5c46ac66` on site 35832 detected both "person" and "bike" on IP Camera 02. The patrol summary and DynamoDB detection windows show both. Only the bike alert appeared in the Immix patrol timeline and internal patrol timeline data. The person alert was silently lost.

**Root cause:** Both alerts were deferred (tag zones active) and fired via `flush_deferred_alerts()` at the very end of the patrol run. The alerts were submitted to nested thread pool executors, but the CronJob process exited ~278ms after the person alert's Immix API call was initiated. No executor drain (`shutdown(wait=True)`) exists in the exit path, so daemon threads were killed mid-flight.

## Evidence Trail

### What the NR logs show

1. **Both deferred alerts fired** from `flush_deferred_alerts` at patrol end:
   - Person: `flush_deferred_alerts: firing pending alert for person window_id=...threatperson... frame_source=s3` (ts: 412072)
   - Bike: `flush_deferred_alerts: firing pending alert for bike window_id=...threatbike... frame_source=s3` (ts: 412166)

2. **Both `trigger_alert()` calls ran** (in `send_executor` threads):
   - Person: `alert url is .../alert_label=intruder` (ts: 412072)
   - Bike: `alert url is .../alert_label=bike` (ts: 412166)
   - `put_detection_window()` succeeded for both (both visible in DynamoDB)

3. **Person's `alert_sender.send()` ran** (in `MultiAlertSender.executor` thread):
   - `Sending AutoPatrol Alert for camera IP Camera 02 alert_type PERSON` (ts: 412306)
   - `Raising patrol alert: {"detectionCode": "PERSON", "tier": 3, ...}` (ts: 412307)

4. **Bike's `alert_sender.send()` — NO logs visible**

5. **Process exited at ts: 412585** — "All camera threads have ended, exiting site manager."

### Timing analysis

| Event | Timestamp (ms suffix) | Delta from person raise |
|-------|----------------------|------------------------|
| Person flush fired | 412072 | -235ms |
| Bike flush fired | 412166 | -141ms |
| Person `send()` reached | 412306 | 0 |
| Person HTTP payload logged | 412307 | +1ms |
| Process exit | 412585 | +278ms |
| Person HTTP response (est.) | 412507+ | +200ms+ |

The Immix API call for person was initiated at 412307. With typical network latency (200-300ms), the response would arrive at ~412507-412607. The process exits at 412585. If the HTTP call takes >278ms, it's interrupted. The DynamoDB save (`save_autopatrol_alert`) that follows the HTTP call would never execute.

### Why bike may have appeared despite missing logs

Several possibilities:
- Bike's `send()` ran in parallel (inner executor has its own thread pool) and completed before exit, but the log was lost in container teardown
- A previous patrol on the same schedule successfully sent the bike alert, and the timeline shows it from that run
- The bike timeline entry could come from a different data source

## Architecture: The Three-Layer Executor Chain

```
flush_deferred_alerts()
  └─ send_executor.submit(trigger_alert, ...)        [2 workers, prefix "send"]
       ├─ put_detection_window()  ← DynamoDB write (synchronous in this thread)
       └─ MultiAlertSender.executor.submit(send, ...) [prefix "as"]
            ├─ _build_annotated_image_url()  ← DDB + S3 + annotate + S3 upload
            ├─ send_autopatrol_alert()       ← HTTP call to Immix
            └─ save_autopatrol_alert()       ← DDB write (autopatrol alerts table)
```

**Key problem:** `flush_deferred_alerts()` submits fire-and-forget to `send_executor`. Neither the camera thread, the main thread, nor the site manager waits for the executor to drain. When `endrun()` returns and the site manager exits, daemon threads are killed.

## Structural Issues Identified

1. **No executor drain at patrol exit** — `flush_deferred_alerts()` submits tasks but nobody calls `send_executor.shutdown(wait=True)` or waits for futures
2. **Deferred alerts fire at the last possible moment** — by the time flush runs, the patrol is already collecting task results and preparing to exit
3. **Nested async dispatch** — send_executor → trigger_alert → MultiAlertSender.executor → send() adds latency layers, each with its own queue
4. **Autopatrol-server only sends PATROL_SUMMARY** — the `autopatrol_queue.py` calls `raise_patrol_alert` once with `detection_code="PATROL_SUMMARY"`, not per-detection. Individual detection timeline entries depend entirely on the connector's real-time raises.
5. **Silent loss path** — if the process exits before the `_callback` on `ActuateThreadPoolExecutor` fires, the exception (or success) is never logged

## Impact

Any site with tag zones enabled will defer alerts to `flush_deferred_alerts`. On patrol-type integrations (AutoPatrol, GenericPatrol), the process exits immediately after flush. This means **every deferred alert on every patrol is at risk of being lost**, depending on the HTTP latency to the Immix API.

Continuous monitoring sites are less affected because the process runs indefinitely, giving executors ample time.

## Observability Lessons

This investigation was harder to diagnose than it needed to be. The alert pipeline has significant logging gaps that made it difficult to confirm whether the person alert was actually delivered or silently dropped.

### Gaps Found

1. **HTTP response status buried at DEBUG** — `autopatrol_api.py` line 393 logs the Immix API response status at DEBUG level. A 400 or 500 from Immix would be completely invisible in normal (INFO-level) production logs.

2. **No success confirmation after `send_autopatrol_alert` completes** — only failures are logged. If the Immix HTTP call succeeds, there is no INFO-level log proving it happened.

3. **No success confirmation after `save_autopatrol_alert` (DDB save)** — the DynamoDB write is silent on success. We can only infer it worked by querying DDB after the fact.

4. **Three layers of fire-and-forget executors** — `send_executor` → `trigger_alert` → `MultiAlertSender.executor` → `send()`. Each layer submits work and moves on. No per-stage completion logging exists, so there is no way to tell from logs how far a given alert progressed.

5. **`ActuateThreadPoolExecutor._callback` only logs exceptions** — successful task completions are not logged. If a task finishes normally, the callback produces no output.

6. **No count/summary log in `flush_deferred_alerts`** — the function fires individual alerts but never logs a summary (e.g., "flushed 2 deferred alerts, skipped 0"). You have to grep for individual "firing" lines and count them manually.

7. **No drain timing or completion log** — there was no executor drain at all (the root cause), but even after adding one, the completion time and outcome need to be logged or it is still invisible.

8. **No end-to-end correlation ID** — a single alert passes through flush → trigger_alert → send → raise_patrol_alert → save_autopatrol_alert with no shared identifier in the logs. Correlating log lines requires matching on label + camera name + approximate timestamp.

### Fix Adds

The fix for the race condition also addresses several observability gaps:
- **Drain completion logging** — `drain_alert_executors: completed in {elapsed}s` at INFO level
- **`raise_patrol_alert` response status at INFO level** — HTTP status from Immix is now visible in production logs
- **`send()` completion confirmation** — `AutoPatrol alert delivered for {camera} alert_type {type}` at INFO level after successful send
- **`flush_deferred_alerts` summary counts** — logs how many alerts were fired and how many were skipped

## Related Notes

- [[s3-frame-fallback]] — previous fix for frame cache eviction in deferred alerts (same flush path)
- [[sliding-window-mechanics]] — window lifecycle and deferred alert gating
- [[knowledgebase/topics/autopatrol/notes/entities/autopatrol-server]] — only sends PATROL_SUMMARY, not per-detection alerts
- [[actuate-alarm-senders]] — AutoPatrolAlertSender implementation
