---
title: "New Relic Log Level Strategy"
type: concept
topic: new-relic
author: kb-bot
created: 2026-04-16
updated: 2026-04-16
tags: [nrql, logging, log-levels, triage, new-relic, connector]
---

# New Relic Log Level Strategy

This note defines what each log level means in the Actuate [[vms-connector]] fleet and how to triage findings. Understanding log levels is essential for writing efficient queries (see [[nrql-efficient-query-patterns]]) -- querying the wrong level wastes tokens on noise, while ignoring the right level misses real issues.

## Log Level Distribution (24h snapshot)

| Level | Volume | Proportion |
|---|---|---|
| `INFO` | ~1.85 billion | 98.5% |
| `WARNING` | ~26.5 million | 1.4% |
| `ERROR` | ~187 thousand | 0.01% |
| `DEBUG` | 72 | Negligible |

Note: Most connector logs use uppercase levels (`INFO`, `WARNING`, `ERROR`). Some platform services (Lambda, infrastructure) use lowercase (`info`, `error`, `warn`). When querying across all sources, use `level IN ('ERROR', 'error')` to catch both. For connector-scoped queries, uppercase is sufficient.

## ERROR -- Always Investigate

Every ERROR-level log deserves at least a count check. However, not all ERRORs indicate code bugs -- many are infrastructure/camera connectivity issues.

### Signal (code or infrastructure problems)

| Pattern | Meaning | Action |
|---|---|---|
| `NoneType object` / `cannot unpack non-iterable NoneType` | Inference returned None -- the ML model server did not respond or returned invalid data | Check model server health (`K8sContainerSample WHERE containerName = 'model-server'`). Usually transient under load, but sustained means overload or crash. |
| `pipeline run aborted` | A camera processing pipeline was killed mid-run | Usually recovers next cycle. Persistent across multiple cycles means a puller bug or stream instability. |
| `MemoryError` / `OOMKilled` | Container exhausted its memory allocation | Check `K8sContainerSample` for `restartCount` increases. May need resource limit adjustment. |

### Noise (not actionable from code side)

| Pattern | Meaning | Action |
|---|---|---|
| `Max retries exceeded` / `Connection refused` | Camera VMS server is unreachable -- network issue, server offline, or firewall | Not a connector code issue. Log for site ops team. These dominate the ERROR count (~50%+ of all errors). |
| `Failed to get session ID` (Exacq) | Exacq VMS login failed -- server offline or credentials changed | Site-level issue. Not actionable from connector code. |
| `error in genetec camera launch` | Genetec VMS API unreachable | Same as above -- site infrastructure. |

### Efficient Error Triage Query

```sql
-- Step 1: Get error counts by pattern (not by full message)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'connector-%'
  AND level = 'ERROR'
  AND message NOT LIKE '%Max retries exceeded%'
  AND message NOT LIKE '%Failed to get session ID%'
  AND message NOT LIKE '%Connection refused%'
SINCE 1 hour ago
FACET message LIMIT 10
```

This filters out the known connectivity noise and surfaces only potentially actionable errors.

## WARNING -- Usually Transient

WARNING-level logs indicate issues that the connector is handling gracefully -- retries, fallbacks, and recoverable failures. They are high-volume (~26M/day) and rarely require immediate action.

### Common WARNING Patterns

| Pattern | Meaning | Action |
|---|---|---|
| `yolo call failed with status code 500. updating ip` | Model server returned 500; connector will retry with an updated IP | Transient. Only investigate if sustained for >15 minutes -- indicates model server instability. |
| `unable to connect, sleeping 60s before retry` | Camera stream connection failed; connector is backing off | Normal for cameras that go offline periodically. Not actionable unless the site should be live. |
| `broken stream, restarting` | [[rtsp-deep-dive|RTSP]] stream dropped; connector is reconnecting | Expected behaviour for unreliable camera streams. |
| `frame skip` / `frame drop` | Processing fell behind the stream rate | Usually transient under load. Sustained drops may indicate undersized containers. |

### When to Query WARNINGs

Only query WARNING level when:
1. You already checked ERRORs and found nothing, but the site is misbehaving
2. You are investigating inference latency (`yolo call failed` count is a proxy for model server health)
3. You are checking camera connectivity patterns (`unable to connect` frequency by camera)

```sql
-- WARNING query scoped to inference issues
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-{site_id}'
  AND level = 'WARNING'
  AND message LIKE '%yolo call failed%'
SINCE 30 minutes ago
TIMESERIES 5 minutes
```

## INFO -- Normal Operation Markers

INFO logs are the bulk of volume (~1.85B/day) and should almost never be queried with raw row fetches. Use them for:

- **Counting activity:** `SELECT count(*) FROM Log WHERE ... AND level = 'INFO' SINCE 30 min ago` confirms the container is alive.
- **Milestone markers:** `message LIKE '%task results%'` or `message LIKE '%patrol%complet%'` for AutoPatrol completion.
- **Processing throughput:** Count INFO messages per time bucket as a proxy for frame processing rate.

```sql
-- Is the connector actively processing? (tiny response)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-{site_id}'
  AND level = 'INFO'
SINCE 15 minutes ago
```

**Healthy:** Thousands of INFO lines in 15 minutes. **Dead:** Zero.

## DEBUG -- Rarely Available

DEBUG logging is almost never enabled in production (72 events in 24 hours across the entire fleet). It may be temporarily enabled for specific troubleshooting. If you need DEBUG data, it likely requires a pod restart with updated log level configuration.

## Querying Multiple Levels Efficiently

When you need a full picture of a site's health, query all levels in a single aggregation:

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-{site_id}'
SINCE 30 minutes ago
FACET level
```

This returns one row per level -- typically 4 or fewer rows. Far more efficient than running separate queries per level.

## Related

- [[nrql-efficient-query-patterns]] -- how to structure these queries for minimal token usage
- [[nr-connector-query-cookbook]] -- pre-built queries that apply these triage patterns
- [[actuate-nr-data-model]] -- the `level` attribute and its variants
- [[connector-fleet-monitoring]] -- how log levels are used during deployment monitoring
