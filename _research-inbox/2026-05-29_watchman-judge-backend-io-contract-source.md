# Watchman ↔ Backend I/O Contract

**For:** backend developers building the plumbing around Watchman.
**Status:** draft for review.

Watchman is the AI stage between the motion+YOLO pipeline and the operator. It takes one alert at a time, looks at the footage, and returns a decision: `escalate_immediate`, `escalate_review`, `auto_clear_normal`, `auto_clear_fp`, or `suppress_low_value`.

This doc covers only the two connections around it: how alerts get **in**, and how decisions get **out**. (The POC currently fakes these with a CSV file in and stdout out — same logic, stubbed edges.)

```
 pipeline ──[SQS queue]──▶ WATCHMAN ──[SNS]──▶ Django ──[WebSocket]──▶ operator app
                                          ├──▶ Immix
                                          └──▶ audit log
```

---

## 1. Input — sending an alert to Watchman

**One YOLO firing = one message** (same fields as a CSV row). The pipeline drops it into an **SQS queue**; Watchman pulls from the queue at its own pace.

```python
# pipeline side — fire and forget, no open connection:
sqs.send_message(QueueUrl=INGEST_QUEUE, MessageBody=json.dumps(alert))
```

Message shape (metadata only — **no image bytes**; frames stay in S3, Watchman fetches them):

```json
{
  "alert_id": "connector-29371-1778110058160871",
  "site_id": "connector-29371",
  "camera_id": "Cam5",
  "alert_ts": "2026-05-26T02:47:00.000Z",
  "yolo_class": "vehicle",
  "yolo_confidence": 0.80,
  "bbox": { "x": 28, "y": 22, "w": 14, "h": 45 },
  "s3_prefix": "s3://bucket/prefix/.../1778110058.160871",
  "schema_version": 1
}
```

- `alert_id` must be **globally unique and stable** — it's how we ignore accidental duplicates. Reuse the pipeline's own event ID if it has one.
- `s3_prefix` points at the folder with `metadata.json` + frames.
- Use an **SQS standard queue** (not FIFO): we don't need strict ordering, and Watchman already de-duplicates.

**Why a queue, not a direct call:** Watchman takes a few seconds per alert (it calls an AI model). A queue lets the pipeline keep running at full speed and absorbs bursts without dropping anything.

---

## 2. Output — receiving Watchman's decision

Watchman **publishes each decision once to SNS**. SNS copies it into one SQS queue per listener, and each listener pulls from its own queue independently:

- **Django** — turns the decision into the operator-app event and pushes it to phones/desktops over WebSocket (per the existing WS strawman).
- **Immix** — the alarm console.
- **Audit log** — records everything.

```python
# Watchman side:
sns.publish(TopicArn=DECISION_TOPIC, Message=json.dumps(decision))
# each consumer (Django/Immix/audit) pulls from its own SQS queue.
```

Decision shape:

```json
{
  "alert_id": "connector-29371-1778110058160871",
  "sequence_id": "seq-connector-29371-20260526T0247",
  "site_id": "connector-29371",
  "camera_id": "Cam5",
  "disposition": "escalate_review",
  "confidence": 0.82,
  "summary": "Vehicle stationary at dock outside operating hours...",
  "descriptor": { "...": "entity descriptor, proposal §4.1.2" },
  "s3_prefix": "s3://bucket/prefix/.../1778110058.160871",
  "decided_at": "2026-05-26T02:47:09.000Z",
  "schema_version": 1
}
```

**Why SNS fan-out:** there are three listeners that shouldn't depend on each other. One announcement reaches all three; if Django is mid-deploy, Immix and audit still get it. If it turns out **Django is the only consumer**, simplify this to a single HTTPS POST from Watchman to a Django endpoint.

End-to-end latency for an escalation: ~6–12 s, which is inside budget.

---

## 3. Where WebSocket fits (and where it doesn't)

| Hop | Mechanism | Why |
|---|---|---|
| pipeline → Watchman | SQS queue | reliable handoff between services; never drop an alert |
| Watchman → Django / Immix / audit | SNS → SQS | one decision, several listeners, never drop |
| **Django → operator's screen** | **WebSocket** | a live UI needs instant push the moment something changes |

Rule of thumb: **queues between machines** (reliability), **WebSocket to the human's screen** (liveness). A dropped WebSocket loses messages — fine for a UI that just re-syncs, not for alerts you must never lose.

---

## 4. Two things every consumer must do

1. **Be idempotent.** Messages can arrive twice. Upsert on `alert_id` / `sequence_id` so a duplicate is a no-op. (We prefer a rare duplicate over ever losing an alert.)
2. **Use a dead-letter queue.** A malformed message should move aside after a few failed tries, not block the queue.

---

## 5. Open questions for the backend team

1. **What messaging infra already exists at Actuate?** This doc assumes AWS-native SQS/SNS (matches the current stack). If you already run Kafka/Kinesis, we use that instead — the message shapes above don't change, only the transport.
2. **How many output consumers?** Django only → single HTTPS POST. Django + Immix + audit → SNS fan-out as above.
3. **`alert_id` source.** Does the pipeline already mint a stable unique ID we can reuse as the dedupe key?
4. **Frame URLs for the UI.** Who turns `s3_prefix` into the short-lived image/stream URLs the operator app shows — Django at display time? (Recommended.)
5. **Latency SLO.** Is ~6–12 s acceptable for the escalate path, or is there a tighter target?

---
