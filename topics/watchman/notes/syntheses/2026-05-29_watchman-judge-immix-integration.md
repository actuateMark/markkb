---
title: Watchman Judge ⇔ Immix Integration — Captured as a Separate Concern
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: watchman
type: synthesis
tags: [watchman, immix, partner-integration, judge-agent, decoupling]
related:
  - "[[topics/watchman/_summary]]"
  - "[[2026-05-29_watchman-judge-backend-io-contract]]"
  - "[[2026-05-29_watchman-prds-summary]]"
  - "[[2026-05-28_watchman-scheduling-brainstorm-correlation]]"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/watchman/_summary.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-judge-backend-io-contract.md
incoming_updated: 2026-05-30
---

# Watchman Judge ⇔ Immix Integration — Captured as a Separate Concern

## Why this note exists

The `WATCHMAN_BACKEND_IO_CONTRACT.md` source doc lists three consumers in its SNS fan-out: **Django, Immix, audit log**. Reviewing the doc against the PRD framing, we factored **Immix out as a separate integration concern** rather than treating it as a peer of Django.

This note captures the reasoning, the open questions, and the boundaries — so the [[2026-05-29_watchman-judge-backend-io-contract|judge contract]] can stay focused on its core path (judge → operator) while Immix gets its own design.

## Why Immix is separate, not peer

The [[watchman-repo|Watchman]] PRD (PM/478019585) §17 and the Escalation Agent spec (PM/482344961, PROD-172/178/183) describe escalation as **direct-to-operator**: push notifications, SMS, phone calls, email. The [[watchman-repo|Watchman]] product positioning is **the operator's app is the primary surface**, not Immix.

Immix today is the alarm console for our existing partner integrations (Patriot, Alarmwatch, StarFM, Crosbies). Those integrations remain compatible during [[watchman-repo|Watchman]] rollout but **shift role from primary to secondary**:

- **Before [[watchman-repo|Watchman]]:** Connector → alert senders → Immix/Patriot/Alarmwatch → operator at customer alarm console.
- **With [[watchman-repo|Watchman]]:** Connector → judge → Django → operator's mobile/desktop app (primary). Immix becomes one of several secondary delivery channels for customers who want it.

Treating Immix as a peer of Django in the contract:
- Locks in an Immix-shaped output schema that doesn't carry [[watchman-repo|Watchman]]'s `descriptor` / disposition vocabulary cleanly.
- Couples the judge's release cadence to Immix integration testing.
- Misrepresents the product direction.

Treating Immix as a downstream of Django (or a separate sender entirely):
- Lets Django decide whether to forward to Immix per-customer.
- Keeps the judge's SNS contract simple — operator app + audit only.
- Aligns with partner-integration secondary status from [[2026-05-28_watchman-scheduling-brainstorm-correlation]].

## Recommended integration shape

Two viable models. Pick based on operational appetite:

### Model A — Django proxies to Immix

```
Judge → SNS → Django → operator (primary)
                    └─→ Immix gateway (per-customer config)
```

Django reads each disposition and, for customers with `immix_enabled=true`, forwards a translated message to Immix's API (or to the existing Immix SQS queue used today by `actuate-alarm-senders`).

**Pros:** Single judge contract, clean primary path. Per-customer Immix routing lives in Django config.
**Cons:** Django becomes a translation layer — needs Immix schema knowledge.

### Model B — Separate Immix consumer on the same SNS topic

```
Judge → SNS ─┬─→ Django → operator
             ├─→ Immix bridge service (consumes SQS, translates, posts to Immix)
             └─→ Audit log
```

Stand up a dedicated Immix bridge service that consumes the judge's SNS fan-out independently. Translates [[watchman-repo|Watchman]] disposition vocabulary to Immix's alarm/clear vocabulary.

**Pros:** Decouples Django from Immix. Bridge owns translation. Independent release cadence.
**Cons:** Net-new service to operate. SNS subscription cost.

**Recommendation: Model B**, because:
- Django shouldn't carry partner-specific translation logic.
- Existing `actuate-alarm-senders` patterns (Patriot, Alarmwatch, etc.) are already separate per-partner; a bridge service mirrors that pattern.
- Easier to retire Immix per-customer without touching Django.

## Schema translation rough sketch

[[watchman-repo|Watchman]] dispositions → Immix events:

| [[watchman-repo|Watchman]] disposition | Immix equivalent |
|---|---|
| `escalate_immediate` | Alarm raised, priority HIGH |
| `escalate_review` | Alarm raised, priority MEDIUM (review queue) |
| `auto_clear_normal` | No Immix event (or "informational" if customer wants logging) |
| `auto_clear_fp` | No Immix event |
| `suppress_low_value` | No Immix event |

The bridge would filter aggressively — Immix gets only `escalate_*` dispositions. The other three resolve into the operator app or audit log without bothering the alarm console.

## Open questions

1. **Which existing partners care about this?** Today's Patriot/Alarmwatch/StarFM/Crosbies integrations live in `actuate-alarm-senders`. Does the Immix bridge replace those, or do they coexist as parallel channels with different dispositions?
2. **Per-customer routing config.** Where does `immix_enabled` (and equivalent per-partner flags) live? Customer model in admin, or a Watchman-side registry?
3. **Reverse direction.** Today Immix can issue arm/disarm commands back to us (Alarmwatch/Crosbies path — ENG-125/34). Does that path continue under [[watchman-repo|Watchman]], or is it migrated to a new Watchman-side arm/disarm API? Cross-references [[2026-05-28_watch-management-service-design]] (manual override entity).
4. **Reconciliation with existing [[actuate-alarm-senders]].** If the bridge service publishes to Immix, do the existing per-partner senders shut down, or do they continue for non-judge alerts? Risk of double-fire.
5. **Translation rules per disposition.** The table above is a sketch; needs partner sign-off.
6. **Audit boundary.** Does the Immix bridge write to audit log too, or is audit a separate SNS consumer that captures the raw judge disposition only?

## Status

**Design-stage.** No code yet for the bridge service. The existing Immix integration via `actuate-alarm-senders` continues to function with today's alert path (post-window confirmed alerts going through Patriot dispatch, Alarmwatch dispatch, etc.).

## Cross-references

- [[2026-05-29_watchman-judge-backend-io-contract]] — the parent contract that lists Immix as a fan-out consumer (this note factors that out)
- [[2026-05-29_watchman-prds-summary]] — PRD escalation framing (direct-to-operator primary)
- [[2026-05-28_watchman-scheduling-brainstorm-correlation]] — partner-integration-impact framing
- [[topics/external-api/notes/entities/alarmwatch-customer]] — existing partner-integration prior art
- `actuate-alarm-senders/` — existing per-partner sender library
