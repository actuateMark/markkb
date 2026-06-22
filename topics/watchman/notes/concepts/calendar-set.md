---
title: Calendar Set (entity)
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: watchman
type: concept
tags: [watchman, calendar-set, scheduling]
related:
  - "[[topics/watchman/_summary]]"
  - "[[watch-entity]]"
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-28_watchman-scheduling-brainstorm-correlation]]"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/watchman/_summary.md
  - topics/watchman/notes/concepts/watch-entity.md
incoming_updated: 2026-05-30
---

# Calendar Set (entity)

## Definition

A **Calendar Set** is a first-class, tenant-scoped, named collection of `calendar_event` rows that can be subscribed to by many [[watch-entity|Watches]]. Editing a single event row propagates to every subscribed [[watch-entity|Watch]] without touching the [[watch-entity|Watch]] table.

Schema (per [[watchman-repo|Watchman]] scheduling brainstorm, PM/601686018):

```
CalendarSet(
  id,
  name: str,
  kind: 'base' | 'suppress',
  tenant_id,
)

CalendarEvent(
  id,
  calendar_set_id,
  cron: str,          # AWS cron(...) or at(...), wall-clock only
  type: 'arm' | 'disarm',   # Option A
  # OR
  arm_cron, disarm_cron,    # Option B (one row = one contiguous armed window)
)

WatchSubscription(           # M:N: a Watch can subscribe to many CalendarSets
  watch_id,
  calendar_set_id,
  priority: int,             # stacking order for multiple suppress sets
)
```

## Kinds

- **`kind='base'`** — the recurring armed pattern. A set of one or more arm/disarm event pairs defining when subscribed Watches should be armed. A multi-window day produces multiple event pairs inside the same set.
- **`kind='suppress'`** — a set whose events, when in-window, **veto any base-set arm** for all subscribed Watches. A single suppress set can be applied to many Watches without duplicating override logic per [[watch-entity|Watch]]. Suppression lifted to set level — holidays, force-close windows, etc.

A [[watch-entity|Watch]] subscribes to:
- Exactly one `base` set (at minimum)
- Zero or more `suppress` sets (stacked by `priority`)

## Composition (armed-state evaluation)

Armed-state is derived, not stored. Pure-function semantics:

```
armed(watch, now) =
    (∃ subscribed base CalendarEvent in window for watch
       OR ∃ active ManualOverride(kind='arm') for watch)
    AND NOT ∃ subscribed suppress CalendarEvent in window for watch
    AND NOT ∃ active ManualOverride(kind='suppress') for watch
```

This is the testable seam — pure function of `(now, watch, calendar_sets, overrides) -> bool`. Lends itself directly to property-based testing; see [[2026-05-29_ait-watch-manager-integration]] property #1.

## Window decomposition rules

Two rules that map customer intent onto cron rows. Apply in the UI/API layer before persisting; the resolver never guesses intent.

**Rule A — multiple non-contiguous windows on one day become multiple rows.**

"Monday armed 00:00–06:00 and 18:00–24:00" → two rows in the same set:
- arm: `cron(0 0 ? * MON *)`, disarm: `cron(0 6 ? * MON *)`
- arm: `cron(0 18 ? * MON *)`, disarm: `cron(0 0 ? * TUE *)`

**Rule B — a single contiguous window crossing midnight is one row, with disarm DOW shifted +1.**

"Monday 18:00 to 06:00" must be interpreted as Mon 18:00 → Tue 06:00 (one contiguous overnight window), NOT Mon 06:00 → Mon 18:00. Encode:
- arm: `cron(0 18 ? * MON *)`, disarm: `cron(0 6 ? * TUE *)`

For weekday ranges ("Mon-Fri 18:00 to 06:00"), the disarm cron's DOW shifts +1: arm on `MON-FRI`, disarm on `TUE-SAT`.

The UI must do this conversion. Storing the customer's literal text without interpretation arms at the wrong end of the window.

## DST behavior

Timezone lives on the [[watch-entity|Watch]], not on `CalendarEvent`. Two observable rules:

- **Spring-forward (missing hour):** any transition whose wall-clock falls in the skipped hour does not fire that day. `02:30` arm in `America/Los_Angeles` will not trigger on the DST Sunday. Document in customer-facing help text.
- **Fall-back (doubled hour):** the [[watch-entity|Watch]] does not transition twice. State updated exactly once regardless of how many times the wall clock passes the hour.

Both options A and B converge on these semantics — Option A delegates to EventBridge's DST policy; Option B's runner tick recomputes per pass and gives the same result.

## Status

**Not yet implemented.** As of 2026-05-29 there's no `CalendarSet` class anywhere in code. Today's `Calendar` model in `actuate_admin` is a different concept — holidays inflate into `ScheduleV2(is_override=True)` rows; they don't run anything themselves. The [[watchman-repo|Watchman]] `CalendarSet` is a clean replacement that the manager-service work would introduce.

## Cross-references

- [[watch-entity]] — what subscribes to a CalendarSet
- [[2026-05-28_watch-management-service-design]] — manager owns CalendarSet lifecycle
- [[2026-05-28_watchman-scheduling-brainstorm-correlation]] — Option A vs. Option B implementation
- [[2026-05-29_ait-watch-manager-integration]] — property-based testing of composition
