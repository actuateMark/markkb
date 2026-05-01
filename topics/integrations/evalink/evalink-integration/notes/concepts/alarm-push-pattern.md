---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [evalink, integration, alarms, sqs, architecture]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/Integratio/pages/232325125"
incoming:
  - topics/actuate-platform/notes/concepts/data-flow-architecture.md
  - topics/team-structure/notes/entities/laura-reno.md
incoming_updated: 2026-05-01
---

# Alarm Push Pattern (Evalink)

The [[integrations/evalink/_summary|Evalink]] uses an **outbound REST push** pattern to deliver Actuate alerts to [[evalink-components|Evalink]]'s alarm management console. This is one of 25+ alarm sender types implemented in the `actuate-alarm-senders` codebase and serves as a representative example of how Actuate delivers alerts to external monitoring center platforms.

## Pattern Overview

The alarm push pattern follows this flow:

```
Detection confirmed (sliding window)
    |
    v
Alert record written to DynamoDB (DetectedV2, EnrichedFrame)
    |
    v
SQS FIFO queue (per-customer ordering guaranteed)
    |
    v
queue_consumer (K8s pod)
    |
    v
EvalinkAlertConfig alarm sender
    |
    v
Outbound REST POST to Evalink API
```

The key design decisions in this pattern are:

### SQS FIFO Delivery

Alerts are delivered through an **SQS FIFO (First-In-First-Out) queue** rather than a standard SQS queue. FIFO guarantees:

- **Ordered delivery** -- Alerts arrive at the alarm sender in the order they were generated. This matters for monitoring centers where alert sequence affects operator response (e.g., a perimeter alert followed by an interior alert tells a different story than the reverse).
- **Exactly-once processing** -- FIFO queues with deduplication prevent duplicate alert deliveries, which would confuse monitoring operators and erode trust in the system.
- **Per-customer message grouping** -- FIFO message group IDs ensure that alerts for one customer don't block delivery to another customer if one customer's endpoint is slow or down.

### Site-Level Configuration

[[evalink-components|Evalink]] configuration is managed at the **site level** in the [[actuate-admin-api|Actuate Admin API]], with three key fields:

| Field | Purpose |
|-------|---------|
| **Server URL** | The [[evalink-components|Evalink]] API endpoint for this customer's alarm management instance |
| **API token** | Authentication credential for the [[evalink-components|Evalink]] REST API |
| **Device ID** | [[evalink-components|Evalink]]'s identifier for the alarm source device, mapped to the Actuate site |

Additionally, an **[[evalink-components|Evalink]] company ID** is stored to map the Actuate customer/site to the correct [[evalink-components|Evalink]] tenant. The configuration is moving from camera-level to site-level granularity (tracked in UI-204 and UI-202), which simplifies setup -- operators configure [[evalink-components|Evalink]] once per site rather than per camera.

### The EvalinkAlertConfig Alarm Sender

The `EvalinkAlertConfig` class in `actuate-alarm-senders` handles the specifics of formatting Actuate alerts into [[evalink-components|Evalink]]'s expected payload format and making the outbound REST POST. It follows the same sender interface as Immix, [[sentinel-components|Sentinel]], Milestone, webhook, and the other 20+ sender types.

## Current Status

The [[evalink-components|Evalink]] integration is **near-production / shipped** -- the oldest integration doc dates to December 2025. The initial customer is **Protectas**, a Swiss security company. Adam Kawczynski is handling support for the [[evalink-components|Evalink]] trial (BT-902, BACK-630), and there are integration failures in the support queue flagged as a risk (see [[active-risks]]).

## Generalizability

While this note focuses on [[evalink-components|Evalink]], the SQS FIFO -> queue_consumer -> alarm sender pattern is the **standard delivery mechanism** for all of Actuate's alert integrations. The same architecture delivers alerts to Immix (~$800K revenue channel), [[sentinel-components|Sentinel]], Milestone, webhooks, and others. Understanding the [[evalink-components|Evalink]] instance is understanding the general pattern.

## See Also

- [[integrations/evalink/_summary|Evalink]] -- the parent integration topic
- [[data-flow-architecture]] -- the full end-to-end data flow
- [[active-risks]] -- integration failure risks
- [[revenue-drivers]] -- Immix uses the same pattern for the primary revenue stream
