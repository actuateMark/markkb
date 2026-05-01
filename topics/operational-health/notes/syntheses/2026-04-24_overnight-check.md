---
title: "Overnight Health Check 2026-04-24"
type: synthesis
topic: operational-health
tags: [overnight-check, nr, autopatrol, vms-connector, oom]
created: 2026-04-24
updated: 2026-04-24
author: kb-bot
status: yellow
---

# Overnight Health Check — 2026-04-24

**Verdict:** YELLOW. Platform-level signals clean; two site-specific anomalies need action. OOM counts are in a recovering-from-spike band, not a new escalation.

> Supersedes earlier same-day stub written by the headless cron run when NR MCP was detached. That stub surfaced a separate tooling-gap (cron session had no NR MCP allowlist) — tracked as a §9 follow-up.

## OOMKills (24h)

- **Total:** 725 (vs. yesterday's 423; vs. 7d-trailing 16,557 skewed by a 9,106-kill day ~48h ago).
- **Read:** 725/day is within the ~800–900 pre-spike baseline band, not a new escalation. The 2026-04-23 figure of 423 was a trough, not a baseline.
- **Top 5 containers:**
  - `connector-14170` — 132 (reversed from "improving" yesterday)
  - `connector-23422` — 116 (NEW entrant)
  - `connector-23730` — 109 (reversed from "improving" yesterday)
  - `connector-20628` — 103 (was 87 yesterday — still chronic, not settling)
  - `connector-45010` — 99 (NEW entrant)

## NoneType (12h)

- `smtp-frame-receiver` dropped out of top-10 (was 3.8K/12h yesterday — material improvement).
- `create-detection-window` now sole dominant source at 3,016/12h.
- New entrants: CHM cronjobs — `connector-40261-chm-cronjob` (96), `connector-17322-chm-cronjob` (24). Worth watching.

## `streamId Guid` on `:stage`

- **0 occurrences / 24h** — GREEN.

## §2b deferred-alert canaries

- All INFO-level, no ERROR-level events for `send_executor.shutdown(wait=True)`, `drain_alert_executors`, or silent-drop guard.
- No regression post-2026-04-20 merge. GREEN.

## New anomalies (2)

1. **`connector-11202` — 23,454 ERRORs/24h**
   - Pattern: `Exception when retrieving authorization string for camera ... Expecting value: line 1 column 1 (char 0)` — JSON parse on empty/non-JSON camera-auth responses.
   - Site-level VMS integration failure (DW VMS returning empty), affecting multiple cameras (~684 each).
   - Action: open a site-scoped integration GH issue (vms-connector) if none exists; not a platform regression.

2. **`connector-deploy` — 18,147 ERRORs/24h**
   - Pattern: `Self reboot connector-14170: error: failed to create patch ... if restart has already been triggered within the past second` — deploy controller thrash-looping on `connector-14170` restart attempts.
   - Likely coupled to the OOM loop: connector-14170 OOMs → reboot triggered → deploy controller rate-limits → thrash.
   - Action: investigate connector-14170 memory limit + whether VPA is correctly sizing it. Cross-ref [[2026-04-23_oom-surge-connector-limit-drift]] config-drift signal.

## Action items

- `connector-14170` is both a top-5 OOMer AND the target of the deploy-controller reboot loop. Treat as single incident. Memory pressure → OOM → self-reboot triggered twice/sec → deploy controller refuses → 18K errors/day. Needs a memory-limit bump or VPA review.
- `connector-11202` DW camera-auth: site-scoped, not platform; open GH issue if none exists.
- Cron session NR MCP gap: the scheduled overnight run wrote an empty stub this morning because the `newrelic` MCP server isn't in its allowlist. Follow-up: extend the systemd overnight-check service's Claude Code MCP config.

## Cross-refs

- [[2026-04-23_overnight-check]] — yesterday's baseline
- [[2026-04-23_oom-surge-connector-limit-drift]] — config-drift signal context
- [[2026-04-23_dashboard-sketch]] — where connector-limit-drift signals should eventually land
- [[automation-overnight-check]] — cron wrapper that needs MCP allowlist fix
