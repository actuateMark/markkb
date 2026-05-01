---
title: Operational Health
type: summary
topic: operational-health
tags: [operational-health, monitoring, automation, reports]
created: 2026-04-16
updated: 2026-04-17
author: kb-bot
---

# Operational Health

Snapshots, reports, and running observations about the **current operational state** of the Actuate platform. This topic is the landing zone for automated daily checks and ad-hoc operational investigations.

Distinct from sibling topics:
- [[new-relic/_summary|New Relic]] — telemetry platform itself (accounts, query patterns, deep links)
- [[fleet-architecture/_summary|Fleet Architecture]] — the architectural redesign effort
- [[knowledgebase/topics/autopatrol/_summary|AutoPatrol]] — product workstreams + people
- [[infrastructure/_summary|Infrastructure]] — AWS resources, IaC

Operational-health is "how is it running right now / last night / last week" — the *running-state* view.

## What Lives Here

### `notes/syntheses/`

Dated operational reports. Naming convention: `{YYYY-MM-DD}_{job-slug}.md`.

Automated reports currently landing here:

| Job | Cadence | Produced by |
|-----|---------|-------------|
| `overnight-check` | Daily 08:03 `America/New_York` | [[automation-overnight-check]] |
| `overnight-check-followup` | Ad-hoc (same day, ~11:00 EDT) | Manual KB update after verification |

Recent incidents with follow-ups:
- [[2026-04-17_overnight-check-followup|2026-04-17 Follow-Up]] — Evalink deviceId validation, EKS CPU pressure, VMS relay recovery

### `notes/concepts/`

Recurring patterns discovered from the reports — e.g., "CNCTNFAIL trends weekly before Immix redeploys", "container X has a memory-leak cycle every 9 days". Reserved for human synthesis across multiple reports.

### `notes/entities/`

Named operational artifacts (a specific dashboard, a standing incident, an ongoing workstream). Reserved.

## Reading Cadence

- **Daily:** Scan the most recent synthesis during the morning KB scan. `FAILED:`-titled notes mean the overnight automation itself broke — prioritize above all other KB content.
- **Weekly:** Skim the week's syntheses for trends worth lifting into `notes/concepts/`.
- **Ad-hoc:** When investigating an incident, grep `notes/syntheses/` for the affected container / site / integration.

## Related

- [[automation-overnight-check]] — the primary automated producer
- [[agents-catalog]] — agents used by the automation
- [[nr-connector-query-cookbook]] — NRQL templates the automation builds on
- [[actuate-platform/_summary|Actuate Platform Overview]] — overall architecture context
