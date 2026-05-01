---
title: "Dashboard Phase 1b — Pickup Guide for Next Session"
type: concept
topic: operational-health
tags: [dashboard, phase-1b, pickup, runbook, regression-prevention, new-relic]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
status: ready-to-pick-up
---

# Dashboard Phase 1b — Pickup Guide

**Purpose of this note:** everything a fresh session needs to execute §9 Phase 1b tomorrow morning with no prior context. Author ran Phase 1a end-to-end on 2026-04-23 (2026-04-23 afternoon) and wrote this before clearing context. Read this first; it contains paths, exact commands, pitfalls already learned, and the execution order.

## State as of end-of-day 2026-04-23

Phase 1a shipped. Full mechanics:
- Skill at `/home/mork/.claude/skills/dashboard-check/` — SKILL.md, run.sh, render.py, sink.py, Jinja2 templates, CSS, config/signals.json (~60-entry catalog), config/baselines.json, tests/test_signal_classification.py
- Output at `/home/mork/Documents/worklog/dashboard/` — per-day snapshot dirs, `latest/` symlink, `index.html` redirect shim, `sink/observations.jsonl` (schema: `/home/mork/Documents/worklog/dashboard/sink/.schema.md`)
- HTTP server at `http://localhost:8765/` — systemd user service `dashboard-server.service` (enabled, auto-starts at login)
- 10/10 pytests pass including the canonical acceptance test `test_onboarder_silent_earlyreturn_is_red`
- One signal pair enabled (`onboarder_activity_us` × `onboarder_lambda_invocations_us`), catalog contains ~20 primary signals disabled + ~40 placeholders

**Do this first tomorrow:** open `http://localhost:8765/` in a browser. Confirm the service survived overnight + the dashboard renders. If it doesn't, the first 1b task is re-running `/dashboard-check` to regenerate the snapshot for today's date.

## Key references

- Plan file (authoritative file-level detail): `/home/mork/.claude/plans/clever-tickling-swing.md`
- Design sketch: `/home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/2026-04-23_dashboard-sketch.md`
- Post-mortem that triggered the initiative: `topics/autopatrol/notes/syntheses/2026-04-23_postmortem-onboarder-healthcheck.md`
- Signal catalog: `~/.claude/skills/dashboard-check/config/signals.json`
- Current baselines: `~/.claude/skills/dashboard-check/config/baselines.json`
- Mark-todos §9 (cross-repo workstream): `topics/personal-notes/notes/entities/mark-todos.md`

## Phase 1b deliverables (from the approved plan)

1. **Execute remaining ~19 primary signals end-to-end** — flip `enabled: false` → `true` in signals.json + add matching collector commands in SKILL.md. The catalog already has the NRQL / AWS CLI queries; just enable + query + populate tempdir.
2. **CPU/memory per deployment subset** — wire at minimum `cluster_cpu_pct_avg`, `cluster_memory_pct_avg`, `deployment_cpu_pct_vms`, `deployment_memory_pct_vms`, `deployment_cpu_pct_inference`, `deployment_memory_pct_inference`. User directive: catch release-induced resource regressions.
3. **Full drill-down per-component HTML** — `component.html.j2` already supports it structurally; add SVG sparklines (inline, no JS) + collapsed raw-log samples.
4. **Regression rules 3 + 4** — baseline drift 2σ, chronic offender promotion. Extend `render.py::apply_regression_rules()`.
5. **Morning-summary aggregation in index** — already stubbed in `index.html.j2`; render from `sink.read_recent(24)` filtered to `source_skill != 'dashboard-check'`.
6. **`/daily-scope` Step 2c integration** — edit `~/.claude/skills/daily-scope/SKILL.md` to run `/dashboard-check` as the standing NR exec item + append one sink observation per fan-out check via `sink.py::write_observation()`. This is the single most valuable 1b task because it turns the sink into a growing dataset.
7. **`/daily-scope` Step 2bb preflight extension** — verify the sink dir exists + is writable.
8. **Replay tests for the 7 historical incidents** — extend `tests/test_signal_classification.py` with fixtures derived from: 2026-04-23 onboarder silent-failure (already have it — canonical acceptance), 2026-04-23 OOM surge 4x baseline, 2026-04-23 NoneType platform-services shift, 2026-04-20 streamId-null bug, 2026-04-20 SSL cert-verify cert-verify failure, 2026-04-17 connector-deploy 11K-error outlier, 2026-04-20 evalink 540-error breach.
9. **Baseline calibration pass** — after 24h of real sink data, re-read baselines.json values and adjust per signal. Some will be noisy false-positives in Phase 1a; downgrade those to `informational` temporarily.
10. **Config-surface drift signals (added 2026-04-23 mid-day, post-OOM-surge triage).** These are a new signal class — they track the delta between a **declared** config value (in source) and the **running** value (observed in cluster). Motivated by today's finding that connector memory limits drifted from the 6 GiB template down to 384 MB via VPA over 73 days, triggered by a single Feb 9 2026 commit (`a5de5db` in `connector_deployer`). Signals to add in Phase 1b:
    - **`connector_pods_under_1gb_limit`** — `FROM K8sContainerSample SELECT uniqueCount(podName) WHERE clusterName='Connector-EKS' AND containerName LIKE 'connector-%' AND memoryLimitBytes < 1073741824 SINCE 1 hour ago`. Threshold: yellow>500, red>1500. **Would have caught:** 2026-04-23 OOM surge (fleet had ~2,000 pods at 384-426 MB).
    - **`connector_pod_headroom_over_70pct`** — `FROM K8sContainerSample SELECT uniqueCount(podName) WHERE clusterName='Connector-EKS' AND containerName LIKE 'connector-%' AND (memoryWorkingSetBytes / memoryLimitBytes) > 0.7 SINCE 15 minutes ago`. Pre-OOM early-warning.
    - **`vpa_updatemode_drift`** — compare `kubectl get vpa -A -o json` mode field vs. expected-Auto baseline in repo. Catches the "VPA silently disabled" case.
    - **`s3_lifecycle_rules_disabled`** — flags buckets like `aegis-all-frames-v2-sts` (disabled lifecycle rule + accumulating data) surfaced by 2026-04-23 Tier-3 investigation.
    - Case study for this class: [[2026-04-23_oom-surge-connector-limit-drift]]. Process rule: [[2026-04-23_release-acceptance-criteria]] §5.

## Execution order (recommended)

**Most valuable-first** — don't just flip enabled-flags without wiring the collectors, and don't wire collectors without exercising them:

1. **Calibration sanity** — view `http://localhost:8765/` today's snapshot. Is `onboarder_activity_us` still GREEN? If it's RED or error, fix the signal before adding more.
2. **`/daily-scope` integration (Step 2c + 2bb)** — this is the integration that makes the whole thing grow. Edit daily-scope SKILL.md to add `/dashboard-check` as the standing NR exec item + sink writes. Re-run `/daily-scope` morning flow manually and confirm sink gains records.
3. **Enable + collect the 5-6 NR signals most likely to surface today's open questions:** `fleet_oomkills_24h` (today's 4x surge), `fleet_new_oom_offender` (connector-20628), `nonetype_unpack_top_facet` (smtp-frame-receiver shift), `queue_evalink_errors_12h`, `streamid_guid_rejection_stage`. These 5 signals alone would have caught multiple 2026-04 incidents.
4. **Enable + collect CPU/memory per deployment** — user-priority. 4 signals minimum: cluster CPU/memory avg + vms + inference.
5. **Add regression rules 3 + 4** to render.py — baseline drift 2σ, chronic-offender promotion.
6. **Extend tests** with 7-incident replay fixtures.
7. **Morning-summary rendering** from sink.
8. **Drill-down SVG sparklines + collapsed raw logs** (visual polish).

## Pitfalls already learned (DO NOT redo)

1. **Log fingerprint calibration is required per signal.** The postmortem said `"Fetched N contracts"` was the onboarder activity marker. Real logs emit `"get_sites HTTP"` per tenant. Always `aws logs filter-log-events` with a broad filter first + sample the real messages before locking in the fingerprint in signals.json.

2. **`aws logs --query 'events | length(@)'` paginates.** It returns one count per response page (up to 3 stacked). Use this instead:
   ```bash
   aws logs filter-log-events ... --output json \
     | python3 -c "import json, sys; print(len(json.load(sys.stdin)['events']))"
   ```
   or `--output text --query 'events[].message' | wc -l`.

3. **CodeArtifact + UV_INDEX will expire and block fresh installs.** The skill's `run.sh` handles this: if system python3 has jinja2 (Ubuntu 24 does by default), use it directly; else uv/pip install with `env -u UV_INDEX -u PIP_INDEX_URL PIP_CONFIG_FILE=/dev/null` + `--default-index https://pypi.org/simple/`. If adding new deps, re-verify this path works.

4. **`python3-venv` is NOT installed on this machine**. `python3 -m venv` will fail. `run.sh` uses `uv venv` when a venv is needed and falls back to system python otherwise.

5. **Systemd service expectations.** `dashboard-server.service` runs as the user's systemd instance. It's enabled. If the service fails and the dashboard doesn't render at `http://localhost:8765/`, `systemctl --user status dashboard-server` + `journalctl --user -u dashboard-server -n 30`. Don't assume it's restarted automatically — it has `Restart=on-failure` with `RestartSec=5` but won't loop indefinitely.

6. **Don't over-enable signals without baselines.** Phase 1a lesson: enabling a signal without validating its baseline against real data produces noisy false-positives that erode dashboard trust. Every newly-enabled signal should have a baseline value derived from 1h+ of real data before it ships to `enabled: true`.

## Phase 1b — UX + data-richness expansion (added 2026-04-23 mid-day)

User directive 2026-04-23 after reviewing the live dashboard:
> "Leave plenty of meat and hooks in the data so we can draw a lot of useful conclusions out of it, that is the key, both user and agent should be able to hook into this data to see things."

This expands Phase 1b beyond "enable more signals" into a UX + data-layer evolution. Treat the items below as **first-class Phase 1b deliverables**, not Phase 2 nice-to-haves. They address the observation that the current grid is too tall (description column bloats rows) and too shallow (no graphs, no drill-down, limited per-signal history).

### 11. Compact grid + inline expand

Drop the `Description` column from `component.html.j2` → `signal-table`. Replace with `<details><summary>` inline expand on each row:
- Collapsed: `Status | Signal (id) | Value | Sparkline | Baseline | Regressions` (compact 1-line row)
- Expanded (click chevron): description, thresholds, query snippet, last N observations, link to signal detail page

Grid should fit ~20 rows in a single viewport without wrapping. Baseline row height target: 28px.

### 12. Hero carousel (above everything else)

Add a **hero section at the top of the index page** containing 3+ selectable "view cards" users flip through via `<` / `>` buttons and a dropdown:

Initial three cards (extensible):
1. **Current status heat-grid** — GitHub-style contribution-grid layout; one chip per signal; color = current status; 7-day horizontal history under each chip. Zoomed-out fleet health.
2. **Top regressions today** — ranked list of signals with the largest deviation from baseline in the last 24h, with mini-spark + classification.
3. **Recent launches gated** — per-merge launch-gate outcomes (from `/dashboard-check --gate <commit>` runs). Shows which releases were verified GREEN and which stalled.

Future cards: per-component summary graphs, cost-trend hero, cross-region comparison.

Implementation: each card is a self-contained `<section class="hero-card" data-card-id="…">`; JS-free carousel using CSS `:target` + anchor links, or minimal inline script for dropdown. No framework.

### 13. Graphs — four tiers (data-dependent; wait for real history)

**DEFERRED from 2026-04-23 session**: the sink currently holds 5 entries (all from today's testing runs). Sparklines and time-series charts render as dots or empty, not curves, until we have real history. Implement AFTER 24+ hours of `/daily-scope` fan-out writes AND after the per-signal collectors run hourly.

Data-source design (must be chosen before implementation):

- **Option A — sink-derived time-series.** `sink.read_recent(since_hours=24, signal_id=X)` returns up-to-24 observations. Plot those. Pro: all signals get sparklines uniformly. Con: resolution is per-`/dashboard-check`-run, not true hourly; gaps show.
- **Option B — native TIMESERIES from source.** For NRQL signals, replace `SELECT count(*) SINCE 1 hour ago` with `SELECT count(*) SINCE 24 hours ago TIMESERIES 1 hour` and store the full array in `data.json`. For CloudWatch, use `get-metric-statistics --period 3600 --start-time <24h> --end-time <now>` and store the array. Pro: dense, accurate, covers pre-skill history. Con: doubles query complexity; not every signal has a natural TIMESERIES form.
- **Option C — hybrid.** Default to Option A; upgrade individual signals to Option B when they need finer resolution (e.g. OOMKill spikes need 15-min buckets, not daily).

Recommend Option C. Start with Option A for all enabled signals (easy to add — just extend `sink.read_recent()` call inside `render.py::render_html` to populate each eval's `history` field); upgrade to Option B signal-by-signal as we learn which need denser data.

Four tiers:

- **Tier 1: Sparkline per signal** (Phase 1b deliverable #3). Inline SVG in the grid, 24h window, 60×20 px. No JS. Data source: Option A initially.
- **Tier 2: Full TIMESERIES chart on signal detail page** — larger SVG line chart (24h or 7d window), overlaid with threshold bands + baseline line + regression events. Shows the dynamic. Data source: Option B required for accuracy.
- **Tier 3: Component-level summary chart** — one chart per component page, overlay of all that component's signals as `% of baseline`, 24h. High-level "is this subsystem healthy?" Data source: Option A (normalized per-signal).
- **Tier 4: Cross-component overview (on index, inside hero card #1)** — heat-grid. One chip per signal × 7 days. Data source: Option A — 7d × per-day sink rollup.

All charts: pure SVG, no JS runtime dependency. The `render/` module grows a `charts.py` helper that takes `(series, width, height, baseline, thresholds)` and returns an SVG string.

**Prerequisite before implementing this section:**
- [ ] `/daily-scope` has been running `/dashboard-check` as a standing exec item for ≥24h (deliverable #6)
- [ ] Sink has ≥50 non-test observations (verify via `wc -l ~/Documents/worklog/dashboard/sink/observations.jsonl` excluding test rows)
- [ ] Baselines.json values have been calibrated against 24h real data (deliverable #9)

Without these, sparklines will look misleading and calibration will be off.

### 14. Data hooks — agent + user readability

The output directory should be a queryable substrate, not just rendered HTML. Extensions:

- **Extend `data.json`** — each signal object includes: current value, status, baseline, thresholds (full dict), unit, query string (raw), regression rules applied, timestamp, last-N observations (at least 24 points for a 24h window at hourly resolution). Goal: an agent reading `data.json` for the latest snapshot can answer "what did signal X look like at time T?" without re-running queries.
- **Sink query helper** — `sink.py` grows a `query(signal_id, window_hours)` method that returns parsed observations sorted by time. Makes retroactive history queries ergonomic from any skill.
- **Embedded query snippets in HTML** — each signal's expanded drawer shows the NRQL / AWS CLI query string (already in `signals.json`) as a copy-button `<pre>`. Agents and users can reproduce any value.
- **KB cross-links** — each signal has an optional `kb_link` field in `signals.json` pointing to the ADR / synthesis / post-mortem that motivated it. Rendered in the expanded drawer: "Why this signal exists: [[2026-04-23_postmortem-onboarder-healthcheck]]". Initially populate with: onboarder signals → onboarder post-mortem; OOM signals → `2026-04-23_oom-surge-connector-limit-drift`; cost signals → S3-tier3 investigation; etc.

### 15-zero. Sink-fallback grid rendering SHIPPED 2026-04-23 mid-day

Before any sparkline / TIMESERIES chart work, the grid itself needed to become sink-aware so backfilled signals show up in their component blocks, not just in the Morning summary pane. That primitive is now live.

**What changed in `render.py`:**
- `Evaluation` gained `data_source`, `last_observed_at`, `freshness_hours`, `history` fields.
- New helper `_latest_sink_observation(signal_id, window_hours)` reads the sink for a signal: returns the latest row (any age) plus trailing-window rows (for sparklines, which will read `ev.history` later).
- `evaluate_signals()` now runs **best-source-at-render-time** per enabled signal:
  1. Live observation in current run's tempdir → `data_source="live"`, status from `classify()`
  2. Else latest sink row within `freshness_threshold_hours` (default `window_hours × 2`) → `data_source="sink_recent"`, status from `classify()`, notes = "from sink (Xh old)"
  3. Else latest sink row beyond threshold → `data_source="sink_stale"`, status forced to `informational`, notes call out the staleness
  4. Else → `data_source="none"`, status = `error`

**Templates (`macros.j2`, `component.html.j2`, `index.html.j2`):**
- `data_source_badge(ev)` macro renders a small badge next to the signal id: `live` (green outline), `hist <N>h` (blue), `stale <N>h` (yellow), `no data` (muted).
- Drawer gained a "Data source" cell showing the badge + `last_observed_at` ISO timestamp + count of sink rows in the trailing 7d window (for future sparkline).
- `signal-item` gets a `src-<type>` class on the outer element; CSS adds a colored left-border stripe so live vs. historical rows are visually sortable at a glance.

**Signal catalog schema additions:**
- `freshness_threshold_hours` (optional) — per-signal override of the default `window_hours × 2` staleness threshold. Populated for two signals so far:
  - `fleet_oomkills_24h`: 48h (matches its 24h window)
  - `cost_s3_daily_total`: 72h (daily signal; allows 3 days of slack before flagging stale)

**Signals enabled by this change (previously catalogued but disabled):**
- `fleet_oomkills_24h` (nr_k8s_container_sample, 24h window)
- `streamid_guid_rejection_stage` (nr_log, 12h window)
- `fleet_error_top15` (nr_log, 1h window)
- `cost_s3_daily_total` (ce_daily, 24h window, new catalog entry)

Combined with the two already-live onboarder signals, the dashboard now renders **6 signals across 3 components** (autopatrol_onboarder, vms-connector, cost). 4 of those read from sink, 2 read live; all classify correctly against thresholds.

**End-to-end verified 2026-04-23 ~13:30Z:**
- `fleet_oomkills_24h` renders latest sink value (30 kills in the final 4h bucket) with `hist 4h` badge
- `cost_s3_daily_total` renders $1151.70 with `hist 32h` badge (latest CE daily)
- `streamid_guid_rejection_stage` renders 0 with `hist 4h` badge (signal working as intended)
- Source badges visible in HTML (4 × `src-live` + 8 × `src-sink-recent` total — 2 per signal × rendered locations)

**What this unblocks:**
- Sparklines (Phase 1b deliverable #13 tier 1) can now read `ev.history` uniformly — no special-casing for sink-only vs. live signals.
- Per-signal collector wiring becomes strictly additive: enabling a collector upgrades a signal from `sink_recent` → `live` without UX change. No coordinated rollout needed.
- Adding a new signal = write the query + backfill it once via `backfill.py` + flip `enabled: true`. It appears in the grid immediately with sink data; collector wiring comes later.

### 15a. Backfill mini-framework SHIPPED 2026-04-23 mid-day (precedes 15b)

Before the full framework below lands tomorrow, a mini version was built and run end-to-end in this afternoon's session. **Status: framework shipped, initial seed data loaded, ready for Phase 1b to extend.**

**Script:** `~/.claude/skills/dashboard-check/backfill.py`

**Source adapters implemented:**
- `nrql` — parses NRDB TIMESERIES result (from `mcp__newrelic__execute_nrql_query`)
- `cw_metric` — parses `aws cloudwatch get-metric-statistics --statistics Sum` output
- `cw_insights` — parses `aws logs get-query-results` from a CloudWatch Insights `stats count() by bin(...)` query
- `ce_daily` — parses `aws ce get-cost-and-usage --granularity DAILY` output

**Usage pattern:**
```bash
# NRQL (via Claude invoking MCP tool, result piped as JSON)
<result.json python3 backfill.py --signal fleet_oomkills_24h --source nrql

# CloudWatch Metrics
aws cloudwatch get-metric-statistics ... | python3 backfill.py --signal onboarder_lambda_invocations_us --source cw_metric

# Cost Explorer
aws ce get-cost-and-usage ... | python3 backfill.py --signal cost_s3_daily_total --source ce_daily
```

Supports `--dry-run`. Idempotent via `(signal_id, minute-precision-timestamp)` dedupe against existing sink. Records are tagged `source_skill="backfill"`, `extras.backfilled=true`, `extras.source="<adapter>"`.

**Initial seed (ran 2026-04-23 ~13:00Z):**

| Signal | Source | Points | Window |
|---|---|---|---|
| `fleet_oomkills_24h` | nrql | 42 | 7d, 4h buckets |
| `streamid_guid_rejection_stage` | nrql | 42 | 7d, 4h buckets |
| `fleet_error_top15` (total variant) | nrql | 42 | 7d, 4h buckets |
| `onboarder_lambda_invocations_us` | cw_metric | 42 | 7d, 4h buckets |
| `cost_s3_daily_total` *(new catalog entry)* | ce_daily | 30 | 30d, daily |
| (existing real-time) | live | 10 | today |
| **Total sink** | — | **208** | — |

**Catalog additions:** `cost_s3_daily_total` signal added to `signals.json` (description, thresholds, `would_have_caught` populated).

**Known gaps (Phase 1b to address):**
- `deployment_memory_pct_vms` + `deployment_memory_pct_admin` returned all `null` for `memoryUsedVsLimitPercent`. Field may not be populated for these containers; needs Phase 1b calibration (try `cpuUsedVsLimitPercent`, or use absolute `memoryWorkingSetBytes`).
- `nr_apm_apdex_inference` — appName filter returned 0 transactions; the actual APM app name doesn't match `%inference%`. Needs discovery + correction.
- `nonetype_unpack_top_facet` — shape mismatch. Signal is a top-N facet; a TIMESERIES of totals doesn't match. Needs either a sibling `_total_count` signal OR adapter extension for FACET payloads.
- No test fixtures yet. Phase 1b should add `tests/test_backfill_<source>.py` per adapter (see 15b below).
- Not a reusable orchestrator — each signal required I manually invoke the MCP / CLI tool and pipe the result. 15b below designs the script-with-orchestrator pattern that can run `--all --days 7` autonomously once AWS / NR auth is in place.

**How tomorrow extends it:**
- Treat `backfill.py` as the normalizer. Add a per-signal registry mapping `signal_id → (source_fetcher, params)` that `backfill.py --run <signal_id>` or `--all` can iterate.
- The AWS / CE / CW callers can live inline (subprocess to `aws`); the NRQL caller needs a parameterized MCP invocation that either the human wraps or we script via a newer MCP binding.
- Add test fixtures for each adapter — canned API response → expected sink records.
- Extend to more signals once the catalog is enriched per #15.

### 15b. Post-creation data backfill (run ONCE after signals are enabled)

User directive 2026-04-23: "Add a post-creation phase … backfill data from various queries after we get the basics done. Ideally done via tool calls and scripts. We want it to be pretty robust out of the gate."

The sink grows organically once `/daily-scope` runs `/dashboard-check` as a standing item, but that takes days/weeks to accumulate useful history. Backfill shortcuts this: **after Phase 1b signal enablement lands, one-shot backfill 7–30 days of per-signal history into the sink so sparklines / heat-grid / component summaries have data to render on day 1.**

#### Deliverables

1. **`backfill.py` script** in `~/.claude/skills/dashboard-check/`:
   ```
   backfill.py --signal <id> [--days 7] [--dry-run]
   backfill.py --component <name> [--days 7]
   backfill.py --all [--days 7]
   ```
   For each target signal, the script:
   - Looks up the signal in `signals.json`
   - Constructs a TIMESERIES-variant of its `query` (e.g. NRQL `SINCE 1 hour ago` → `SINCE 7 days ago TIMESERIES 1 hour`; CloudWatch `get-metric-statistics --period 3600 --start-time <now-1h>` → `--start-time <now-7d>`)
   - Executes the query via the same source the signal uses (NRQL MCP, AWS CLI, CE, GH)
   - Writes one sink record per returned bucket, with `timestamp` set to the bucket's historical time, `source_skill: "backfill"`, and `extras: {"backfilled": true, "backfill_run_ts": "<now>"}`
   - Classifies each historical value via `classify()` so status history is meaningful

2. **Per-source adapters**:
   - NRQL: parse `NRDB.TimeseriesResult` into hourly buckets
   - CloudWatch logs: chunked `filter-log-events` calls per hour (heavy — may need pagination)
   - CloudWatch metrics: `get-metric-statistics` with `--period 3600` returns the array directly
   - Cost Explorer: `get-cost-and-usage` with `Granularity=DAILY` returns daily buckets for 30d at a go
   - GitHub: `/repos/.../issues?state=closed&since=<7d>` → iterate, count per day

3. **Idempotency**: each backfill run tags records with its bucket timestamp. Before writing, check if a sink record for that `(signal_id, timestamp)` pair already exists and skip if so. Re-running the backfill should be a no-op.

4. **Rate-limit awareness**: batching + throttling. Running `--all --days 30` across ~40 signals will hit NR / AWS / CE APIs significantly. Add `--throttle-seconds` flag defaulting to 1s between queries. For CW log-group scans, use `start-query` + polling rather than synchronous `filter-log-events`.

5. **Verify step**: after backfill, re-render `/dashboard-check`; sparklines and heat-grid cards should now show 7d curves, not dots. Commit the sink file if it's in version control (not currently, but noted for future).

#### Robustness posture (per user directive "robust out of the gate")

- **Every backfill adapter has a test fixture** — `tests/test_backfill_<source>.py` with a canned API response. The adapter must parse it into the expected sink-record shape. Prevents production-only parse bugs.
- **Dry-run mode (`--dry-run`) is mandatory** — shows what would be written without touching the sink. Run before any real backfill against production APIs.
- **Failure isolation** — one signal's backfill failure must not abort the batch. Log the error, skip to the next signal, report summary at end.
- **Respect existing data** — backfill should never overwrite a real-time observation. If `(signal_id, timestamp)` already exists in the sink with `source_skill != "backfill"`, skip (real-time wins).

#### Run posture (one-shot-per-signal-addition)

The backfill should run:
- Once, right after Phase 1b enablement (to seed 7–30d of history on all newly-enabled signals)
- Again whenever a new signal is added to the catalog (backfill just that signal)
- Optionally weekly, to catch any gaps (e.g. days when `/daily-scope` didn't run). Low priority; only if gaps become a problem.

### 15. Catalog coverage enrichment

Observed 2026-04-23 mid-day that the catalog has thin coverage for some components. Before Phase 1b flips enable-flags, extend the catalog per §9 scope:

- **actuate-admin** — currently 2 signals (CPU + memory). Add: schedule-activation rate, tenant-create success rate, RBAC denial patterns, history-endpoint access FACET, admin-API 4xx/5xx rates.
- **inference-api** — currently 7 signals (APM-oriented). Add: per-model detection throughput (by `model_name` facet), per-partner-API-key activity (by `api_key_id` or equivalent facet), per-endpoint 4xx/5xx breakdown.
- **autopatrol-server** — not in catalog at all. Add: patrol-completion rate, CNCTNFAIL per site, queue-depth for upstream alert-pipeline consumers.
- **actuate-libraries** — not in catalog at all. Add: version-drift alert (catalog published version vs. consumer pins), consumer-side import-check outcomes.
- **Config-surface drift (from OOM-surge root-cause)** — added in deliverable #10 above.

**Test hook:** every signal added here MUST include a `would_have_caught` field pointing to a specific past incident. If no past incident motivates the signal, add a forward-looking description ("detects the class of regression where X silently drops to zero").

## Verification of "done"

Phase 1b is complete when:
- [ ] All ~20 primary signals have `enabled: true`, populate per-run, render with accurate classifications
- [ ] `/daily-scope` morning run produces one sink record per exec item (visible in `observations.jsonl`)
- [ ] Next `/dashboard-check` render surfaces those sink records in the Morning summary section
- [ ] Replay tests for all 7 historical incidents pass
- [ ] Dashboard is re-calibrated against the first 24h of real sink data (no chronic false-positive YELLOW/REDs on signals known-healthy)
- [ ] CPU/memory per deployment wired for vms + inference at minimum
- [ ] End-to-end smoke: fresh `/dashboard-check` run yields overall GREEN with ~20 signals, exit 0
- [ ] **UX expansion:** compact grid + inline expand (deliverable #11), hero carousel with 3+ cards (#12), four graph tiers (#13), data hooks (#14) — all shipped
- [ ] **Catalog coverage:** actuate-admin, inference-api, autopatrol-server, actuate-libraries signals added per §9 scope; every signal has a `would_have_caught` field (#15)
- [ ] **Config-drift signals:** `connector_pods_under_1gb_limit`, `connector_pod_headroom_over_70pct`, `vpa_updatemode_drift`, `s3_lifecycle_rules_disabled` shipped (deliverable #10)

After verification: update mark-todos §9 Phase 1b checklist to `[x]`, commit the portability repo if §10 has started (otherwise note for later).

## Then: Phase 2

Phase 2 is the launch-gate wiring ([[mark-todos]] §9 "Phase 2+" section). Don't start it until Phase 1b is calibrated — the release skills shouldn't block on a still-noisy dashboard.

## Cross-refs

- [[2026-04-23_dashboard-sketch]] — authoritative design (Phase 1a + 1b + 2+)
- [[2026-04-23_postmortem-onboarder-healthcheck]] — origin incident
- [[2026-04-23_release-acceptance-criteria]] — the rule this skill operationalizes
- [[feedback_acceptance_criteria_every_merge]], [[feedback_fail_fast_guards]] — hard rules
- [[mark-todos]] §9 — workstream tracker
- Skill: `/dashboard-check` (live, ready to extend)
