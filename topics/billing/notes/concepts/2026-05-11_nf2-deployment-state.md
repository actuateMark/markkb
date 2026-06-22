---
title: "NF2 deployment state — billing-reconciliation Tier-1 wrapper (2026-05-11)"
type: concept
topic: billing
tags: [billing, nf2, deployment-state, dashboard-check, tier-1, postgres-whitelist, signals-json, systemd-timer]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
incoming:
  - topics/billing/_todos.md
  - topics/fleet-architecture/notes/syntheses/2026-05-11_rubric-monitoring-billing-dimensions.md
  - topics/personal-notes/notes/concepts/2026-05-11_next-session-handoff.md
  - topics/personal-notes/notes/daily/2026-05-11.md
incoming_updated: 2026-05-27
---

# NF2 deployment state — billing-reconciliation Tier-1 wrapper

Snapshot of where NF2 stands as of 2026-05-11. **Wrapper + systemd units shipped; FIRST REAL END-TO-END RUN SUCCEEDED** at 13:20 ET; signals.json wiring drafted but not yet committed.

## Historical replay (NF9) — Feb → May 2026 trend

Run 2026-05-11 against `--month 2026-04` and `--month 2026-03` on Firebat (Snowflake `site_product_run_day_last_year` retains 1 year, so all months reachable). **Validates the "would have caught Cohort F" claim** ([[_todos]] NF9): Cohort F was discovered 2026-05-04 via manual audit; a live signal would have fired RED 2 months earlier on the Feb→Mar transition.

| Month | Production missing subscription | Hours | Connector billed % | Signal at red≥1500 |
|---|---:|---:|---:|---|
| Feb 2026 (CLAUDE.md baseline) | 803 | (n/a) | ~88% | 🟡 YELLOW |
| Mar 2026 (live replay) | **2,353** | 15.9M | 89.7% | 🔴 **RED** |
| Apr 2026 (live replay) | **3,152** | 13.5M | 93.9% | 🔴 RED |
| May 2026 (current, partial 11d) | 2,024 | 4.0M | 95.9% | 🔴 RED |

**Findings:**

1. **The unbilled-camera class has roughly 4×'d since Feb 2026** (peaking at 3,152 in April). May's lower number reflects the partial month — usage_monthly's 3-hour threshold under-counts cameras until late month.
2. **Connector-side emit reliability improved monotonically** (88% → 89.7% → 93.9% → 95.9%) — confirms the PR-#1675→#1688 connector-side fixes landed and held. The remaining production-unbilled class is **NOT a connector emit gap** anymore; it's **purely a Snowflake-side missing-Ordway-subscription class** (the silent `INNER JOIN raw.ordway.subscription` drop documented in [[snowflake-billing-tables]]).
3. **The signal would have fired RED on March's data**, roughly 2 months before Cohort F's manual discovery on 2026-05-04. Replay confirms the `would_have_caught` claim in `billing_production_unbilled_cams`'s signal definition.

**Wrapper-design follow-up surfaced by replay:** `--month X` runs all clobber `reconciliation-$(date +%F).json` (the sink filename is keyed by *today's* date, not by the month being analyzed). Historical replays should write to `reconciliation-YYYY-MM_replay-on-$(date +%F).json` or similar to avoid overwriting the current-month sink that `/dashboard-check` reads. Tracked in [[_todos]] as a follow-up.

## First real run — May 2026 snapshot (2026-05-11 13:20 ET)

| Metric | Value | Note |
|---|---:|---|
| `exit_status` | `"ok"` | Wrapper completed cleanly |
| `reconciliation.balanced` | `true` (residual=0) | Every Postgres camera accounted for in exactly one pipeline |
| `_parse_meta.missing_keys` | `[]` | 25/25 fields parsed |
| Total active Postgres cams | 108,760 | (Feb baseline: 104,640 — +4%) |
| Connector cams billed % | 95.9% | (Feb baseline: ~88% — **+7.9pp**, PR-#1675→#1688 fixes confirmed working) |
| Connector cams w/ no SPRD events | 240 | (Feb: 257) |
| Clip cams matched | 50.0% | (Feb: 46% — same band) |
| VCH cams | 1,429 | (Feb: 2,406 — **-41%**, cleanup activity) |
| **Production unbilled (missing subscription)** | **2,024 cams / 4,018,433 hours** | **(Feb: 803 cams) — +150%, regression worth surfacing** |
| Trial/Pilot unbilled | 299 cams / 80,246 hrs | (Feb: 1,169 — -74%, many trials converted) |
| Internal/Demo | 515 cams / 118,345 hrs | (Feb: 485 — within noise) |

**Headline takeaway: connector-side billing-emit reliability *improved* between Feb and May (PR-#1675→#1688 fixes landed). But Ordway-subscription coverage *regressed* — 2.5x more production cams without a subscription now than 3 months ago.** This is the value-add demo NF3 is meant to surface; the *current* number is meaningfully worse than the baseline you'd been working from. See [[_todos]] NF3 (reframed to use the current snapshot, not Feb).

## What's done

| Step | Status | Artifact |
|---|---|---|
| Wrapper script | ✓ Shipped | `/home/mork/work/local_network_scripts/files/billing-reconcile-check.py` |
| systemd service unit | ✓ Drafted | `/home/mork/work/local_network_scripts/files/billing-reconcile-check.service` |
| systemd timer unit | ✓ Drafted | `/home/mork/work/local_network_scripts/files/billing-reconcile-check.timer` (daily 04:00 PT) |
| [[sales-dashboard|Sales-dashboard]] venv | ✓ Synced | `~/work/sales-dashboard/.venv` (Python 3.13, uv-managed, pypi-only resolve to bypass CodeArtifact auth) |
| [[sales-dashboard|Sales-dashboard]] `.env` | ✓ Bootstrapped | From AWS Secrets Manager `prod/actuate/sales-dashboard`; contains `SNOWFLAKE_PASSWORD` + ordway_* + anthropic_api_key |
| Snowflake auth validated | ✓ Confirmed | First real reconcile run got past `connect_snowflake()` cleanly — proves `reports@actuate.ai` credentials work end-to-end. No lockout risk: only 1 attempt used. |
| Parser self-test | ✓ 25/25 fields | Synthetic fixture mirroring `reconcile_cameras.py` SUMMARY + FULL RECONCILIATION blocks; tested both `Residual: 0 ✓` and `Residual: <negative>` cases |
| JSON sink path | ✓ Working | `~/.local/state/minipc-tasks/billing/reconciliation-YYYY-MM-DD.json` |

## Postgres IP whitelist — RESOLVED 2026-05-11

`67.80.57.32` (laptop + Firebat NAT) whitelisted in the admin Postgres security group. First real end-to-end run succeeded immediately after — see snapshot above.

## Proposed signals.json entries

Three signals to add to `~/.claude/skills/dashboard-check/config/signals.json`. Drafted here so they can be reviewed before committing. All three use `source: minipc_local` since the JSON sink lives on Firebat.

```jsonc
{
  "id": "billing_production_unbilled_cams",
  "component": "billing",
  "source": "minipc_local",
  "command": "jq -r '.unbilled.production_missing_subscription.cameras // 0' ~/.local/state/minipc-tasks/billing/reconciliation-$(date +%F).json 2>/dev/null || echo 0",
  "unit": "count_per_24h",
  "description": "Production cameras (not trial/internal) running billable products but NOT in usage_monthly — i.e. missing Ordway subscription. Headline NF2 value-add signal. May 2026 actual: 2,024 cams (Feb 2026 was 803 — regression). Updated daily 04:00 PT post-SPRD-swap. Stale-file alarm covered by billing_reconcile_freshness.",
  "regression_rules": [],
  "thresholds": {
    "yellow_above": 500,
    "red_above": 1500
  },
  "window_hours": 24,
  "enabled": false,
  "would_have_caught": "Cohort F (June 2024-Apr 2026 — 642 cams, ~400 of which match the missing-subscription class)"
},
{
  "id": "billing_reconcile_residual",
  "component": "billing",
  "source": "minipc_local",
  "command": "jq -r '.reconciliation.residual // 999' ~/.local/state/minipc-tasks/billing/reconciliation-$(date +%F).json 2>/dev/null || echo 999",
  "unit": "count_per_24h",
  "description": "Reconciliation residual — every Postgres-active camera should land in exactly one pipeline bucket (Connector / Clip / VCH). Non-zero indicates a counting bug, schema drift, or an unhandled integration type. Default 999 if JSON missing (covers stale-file case via the threshold).",
  "regression_rules": [],
  "thresholds": {
    "yellow_above": 0,
    "red_above": 10
  },
  "window_hours": 24,
  "enabled": false,
  "would_have_caught": "Counting drift in reconcile_cameras.py (e.g. new integration type added in admin without updating the script's bucket-set)"
},
{
  "id": "billing_reconcile_freshness",
  "component": "billing",
  "source": "minipc_local",
  "command": "find ~/.local/state/minipc-tasks/billing -name 'reconciliation-*.json' -mtime -1 -print | wc -l",
  "unit": "facet_count",
  "description": "Count of reconciliation JSON sinks written in the last 24h. Expected: 1. Zero means the systemd timer didn't fire or the wrapper exited before writing. Catches missing daily runs that would otherwise leave the other two billing signals reading stale numbers.",
  "regression_rules": [],
  "thresholds": {
    "yellow_below": 1,
    "red_below": 1
  },
  "window_hours": 24,
  "enabled": false,
  "would_have_caught": "Timer wedge / wrapper regression / sink-dir permission loss"
}
```

`enabled: false` until the Postgres whitelist lands. Flip after first successful real run.

**Calibration note on `billing_production_unbilled_cams` thresholds:** the May 2026 actual is 2,024 cams — well above any threshold we'd want to alarm on permanently. Initial yellow=500/red=1500 means the signal goes **RED out of the gate**, which correctly surfaces the state. Once NF3 follow-ups close real accounts and the steady-state drops, ratchet thresholds down. Same ramp pattern as [[2026-05-11_billing-reconciliation-dashboard-design|R1 design]] §"Alert thresholds."

## Deploy steps (post-whitelist)

```bash
# 1. Copy systemd units to the systemd user dir on whichever host (laptop or
#    Firebat) — for Tier-1 deployment, Firebat is the right home per
#    three-tier pattern.

# Laptop test first:
cp /home/mork/work/local_network_scripts/files/billing-reconcile-check.{service,timer} \
   ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now billing-reconcile-check.timer

# Verify
systemctl --user list-timers | grep billing-reconcile

# Manual fire to validate:
systemctl --user start billing-reconcile-check.service
journalctl --user -u billing-reconcile-check.service --since "5 min ago"

# 2. Once laptop validation passes, promote to Firebat via the
#    local_network_scripts deploy pattern (same flow as morning-prep, etc.).
#    Firebat is where Tier-1 lives per the three-tier-routine-check-pattern.

# 3. Append the three signals.json entries (from §"Proposed signals.json
#    entries" above) into ~/.claude/skills/dashboard-check/config/signals.json.
#    Flip `enabled` to true after the first sink file is on disk.

# 4. Run /dashboard-check and confirm the three new signals render.
```

## Verification checklist

After deploy completes:

- [ ] `~/.local/state/minipc-tasks/billing/reconciliation-YYYY-MM-DD.json` exists and is <24h old
- [ ] `jq '.exit_status'` returns `"ok"`
- [ ] `jq '.reconciliation.balanced'` returns `true` (or `false` with a documented residual reason)
- [ ] `jq '.unbilled.production_missing_subscription.cameras'` returns a sensible number (>0 currently expected; if 0 with non-zero baseline, suspect data-pipeline issue)
- [ ] `/dashboard-check` shows the three new signals — yellow at minimum on `billing_production_unbilled_cams` (until NF3 closes accounts) and green on the other two
- [ ] Replay test: run with `--month 2026-05` (Cohort F window) and confirm the signal goes red. *(Skipped for now — current month's data is the more important first signal.)*

## Cross-references

- [[_todos]] NF2 — the parent item
- [[sales-dashboard-repo]] — repo the wrapper invokes
- [[2026-05-11_billing-reconciliation-dashboard-design|R1 design]] — design spec NF2 implements
- [[three-tier-routine-check-pattern]] — deployment pattern
- [[mark-todos]] §28 — workstream tracker
- `/home/mork/work/local_network_scripts/files/billing-reconcile-check.py` — wrapper
- `/home/mork/work/local_network_scripts/files/billing-reconcile-check.{service,timer}` — systemd units
- `~/.claude/skills/dashboard-check/config/signals.json` — destination for the three new entries (not yet appended)
