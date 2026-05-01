---
title: "VCH and CHM are Not AutoPatrol — Container Names Are Misleading"
type: concept
topic: camera-health-monitoring
tags: [vch, chm, autopatrol, integration-types, naming-confusion, operational-debugging]
jira: "AUTO-566, AUTO-567"
created: 2026-04-28
updated: 2026-04-28
author: kb-bot
---

# VCH and CHM Do Not Run ML Models

vms-connector runs three patrol-style integrations as K8s CronJobs. Two of them — VCH (Visual Camera Health) and CHM (Camera Health Monitor) — **do not run ML inference**. They share a container naming suffix (`-chm-cronjob`) with AutoPatrol, creating the false impression they are variants of the same workload. They are not.

## Key Distinction

| Feature | VCH / CHM | AutoPatrol |
|---|---|---|
| Runs YOLO inference? | **No** | **Yes** |
| Has models array in settings? | Empty (intentional) | Populated (required) |
| Container name | `connector-<site>-chm-cronjob` | `connector-<site>-autopatrol-<N>-chm-cronjob` |
| Detects tampering / blur / FPS? | **Yes** | No |
| Sends detections to Immix? | No | **Yes** |

## Why This Matters for Observability

Empty `models` arrays in VCH/CHM are **not a bug**. They are by design. When building monitoring queries that check for ML configuration issues, filter explicitly to AutoPatrol containers only:

```sql
-- WRONG: Returns VCH/CHM false positives
SELECT count(*) FROM Log
WHERE message LIKE '%No models configured%'

-- CORRECT: AutoPatrol only
SELECT count(*) FROM Log
WHERE container_name LIKE '%-autopatrol-%'
  AND message LIKE '%No models configured%'
```

During AUTO-566, an unfiltered query returned 30 "misconfigured" sites. The actual count: **2 production + 1 staging**, all AutoPatrol. The other 27 were VCH/CHM, where the empty array is expected.

## Related Notes

- [[2026-04-28_integration-types-naming-confusion]] (AutoPatrol topic) — full architectural breakdown of all three types
- [[camera-health-monitoring/_summary|CHM Topic Summary]] — VCH/CHM workstreams and capabilities
