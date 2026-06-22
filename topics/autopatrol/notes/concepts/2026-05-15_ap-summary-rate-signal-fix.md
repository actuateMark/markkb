---
title: "AP summary-rate signal config-noise fix (2026-05-15)"
type: concept
topic: autopatrol
tags: [autopatrol, dashboard-check, signal-config, false-positive, fix, triage]
created: 2026-05-15
updated: 2026-05-15
author: kb-bot
- No backlinks found.
incoming:
  - topics/personal-notes/notes/daily/2026-05-15.md
  - topics/personal-notes/notes/daily/2026-05-18.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-19
---

# AP summary-rate signal config-noise fix (2026-05-15)

## Verdict

**Signal-config noise, not a silent break.** The `autopatrol_server_patrol_summary_rate` signal had a typo in its `container_name` filter — it queried `container_name='autopatrol-server'` (exact match) but the active container is named `autopatrol-server-dev`. Result: the signal returned 0 for at least 7 days straight, manifesting as a chronic RED on the dashboard.

The summarizer pipeline itself is **healthy** — `autopatrol-server-dev` emits ~20 "Generating patrol summary" lines per hour, ~480/day, ~14,800 in the last 24h.

Fixed by widening the filter to `container_name LIKE 'autopatrol-server%'` so it catches both the active `-dev` container AND the legacy/secondary `autopatrol-server` (which has ~58 logs/24h, well below the active one but still real).

## What triggered the triage

`autopatrol_server_patrol_summary_rate=0` showed RED on the morning dashboard fan-out 2026-05-13, 14, and 15. Originally flagged as "potentially real silent break" (the autopatrol equivalent of the 2026-04-23 onboarder incident) in the Friday-wrap fan-out + carry-forward chain. Today's Friday-scope picked it up as a deferred triage item.

## Evidence chain

### 1. Signal NRQL didn't match anything

Running the signal's exact query:

```sql
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name='autopatrol-server'
  AND message LIKE '%Generating patrol summary%'
SINCE 7 days ago
TIMESERIES 1 day
```

→ all 7 daily buckets returned **0**. Not just last hour. Never-firing pattern.

### 2. Container-existence check showed the right one is named `*-dev`

```sql
SELECT uniques(container_name, 30) FROM Log
WHERE container_name LIKE '%autopatrol%'
SINCE 1 hour ago
```

→ surfaced `autopatrol-server-dev` (no `autopatrol-server` exact match in last hour). Plus a long tail of `connector-XXXXX-autopatrol-NNN-chm-cronjob` containers (the per-patrol cronjobs).

### 3. Confirming the summarizer IS running, just under the `-dev` name

```sql
SELECT count(*) FROM Log
WHERE message LIKE '%Generating patrol summary%'
SINCE 24 hours ago
FACET container_name
```

→ 471 matches in 24h, **all from `autopatrol-server-dev`** (none from the bare `autopatrol-server`).

Re-checking with a wildcard at the 24h window:

```sql
SELECT count(*) FROM Log
WHERE container_name LIKE 'autopatrol-server%'
SINCE 24 hours ago FACET container_name
```

→ `autopatrol-server-dev`: 14,831 logs total. `autopatrol-server`: 58 logs total. Both exist; the active one has the `-dev` suffix.

### 4. Healthy rate timeseries

Same query but TIMESERIES on 4-hour buckets:

| 4-hour window | "Generating patrol summary" count |
|---|---|
| -24h to -20h | 82 |
| -20h to -16h | 80 |
| -16h to -12h | 78 |
| -12h to -8h | 70 |
| -8h to -4h | 81 |
| -4h to now | 80 |

Steady ~20/hour, ~80/4-hour window. Well above the signal's `red_below=1` and `yellow_below=2` thresholds. The pipeline has been healthy the entire time.

## The fix

Edit at `~/.claude/skills/dashboard-check/config/signals.json` — change exact-match to prefix-match:

```diff
- "nrql": "SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND message LIKE '%Generating patrol summary%' SINCE 1 hour ago",
+ "nrql": "SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND container_name LIKE 'autopatrol-server%' AND message LIKE '%Generating patrol summary%' SINCE 1 hour ago",
```

Plus extended the description to document the gotcha + the original-vs-current container naming.

Validation: corrected NRQL returns **20 lines in the last hour** at fix time. Above red AND yellow thresholds. Signal will flip RED → GREEN on next minipc `/dashboard-check` cron pass.

## Why this matters (the meta-lesson)

This signal was specifically designed to be the autopatrol equivalent of the [[2026-04-23_postmortem-onboarder-healthcheck|2026-04-23 onboarder incident]] — a silent-break detector. The signal's design was correct (count summary emits, alarm on zero). But the implementation had a one-word typo (`autopatrol-server` vs `autopatrol-server-dev`) that caused it to **always return zero**, making the signal **permanently RED**.

Two failure modes compound here:

1. **Permanent-RED normalization.** A signal that's been RED for weeks gets implicitly classified as "known noise" in morning fan-outs and stops being investigated. The signal was supposed to be a tripwire for the next silent break — instead it became a tripwire we'd learned to ignore.

2. **No value-validation at signal-creation time.** The signal was added without a one-time test that "in a known-healthy state, this returns >0." If that check had run, the typo would have been caught immediately.

### Discipline rule worth adding (suggest in §9)

Every NEW signal added to `signals.json` must go through a one-time validation pass at creation time:

- Run the exact NRQL once
- Confirm the result is non-zero AND above the `yellow_below` threshold in a known-healthy state
- If zero / below threshold: the NRQL is wrong, or thresholds are wrong, or the underlying metric isn't being emitted. Don't enable the signal until that's resolved.

Without this, "silent break detectors" can themselves be silently broken at birth.

## Cross-references

- §9 in [[mark-todos]] — operational dashboard work; add the value-validation rule there
- [[2026-04-23_postmortem-onboarder-healthcheck]] — the original silent-break incident this signal was designed to catch the next instance of
- Signal config: `~/.claude/skills/dashboard-check/config/signals.json` (lines around 1776)
- Dashboard observation: `morning_ap_summary_rate_signal_fix` (logged today)
