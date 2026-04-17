---
title: "Source: Immix Queue Consumer Operational Notes"
type: source
topic: alerts-improvements
tags: [worklog, immix, queue-consumer, reliability, pagerduty, datadog]
ingested: 2026-04-14
author: kb-bot
---

# Immix Queue Consumer Operational Notes

After-action worklog notes from operational issues with the Immix alert queue consumer. These are remediation items and hardening measures.

## Action Items

1. **Create redundant tasks for all consumers** -- eliminate single points of failure in alert delivery.
2. **Set up Immix low alert to PagerDuty** -- ensure low-priority Immix alerts still reach on-call if they indicate systemic issues.
3. **Investigate AWS task kills** -- look into whether tasks were being killed randomly by AWS (ECS task recycling or OOM).
4. **Use separate channel for testing** -- stop using the real warnings channel for things like Datadog testing to avoid noise pollution.
5. **Add healthcheck to the queue consumer** -- the consumer itself needs a liveness check so failures are detected, not just the alerts it processes.
6. **Kill and restart consumer periodically** -- restart every few days to prevent memory leaks or stale state from accumulating.
7. **Enable execute command on tasks at start of run** -- allow shell access into running tasks for debugging.
8. **Wrap queue listener in try/catch** -- allow recovery from transient errors instead of crashing the entire consumer.

## Significance

These notes reveal that the queue consumer was fragile -- no healthcheck on itself, no automatic recovery from exceptions, no redundancy. The after-action items represent a hardening checklist that moves the consumer toward production-grade reliability.

## See Also

- [[data-flow-architecture]] -- where the queue consumer fits in the pipeline (Stage 9-10)
