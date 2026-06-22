---
title: "Dashboard Phase 1b — Continuation Pickup (2026-04-24 handoff)"
type: concept
topic: operational-health
tags: [dashboard, phase-1b, pickup, runbook, handoff]
created: 2026-04-24
updated: 2026-04-24
author: kb-bot
status: ready-to-pick-up
supersedes: "[[2026-04-23_dashboard-phase-1b-pickup]]"
incoming:
  - topics/operational-health/notes/concepts/2026-04-27_dashboard-signal-cookbook.md
  - topics/operational-health/notes/syntheses/2026-05-05_operational-dashboard-context.md
  - topics/personal-notes/notes/daily/2026-04-24.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-27
---

# Dashboard Phase 1b — Continuation Pickup

**This supersedes [[2026-04-23_dashboard-phase-1b-pickup]]** as the authoritative runbook for the next session. Read this first.

## State as of 2026-04-24 EOD handoff

- Dashboard live: `http://localhost:8765/latest/` (systemd `dashboard-server.service` enabled, auto-starts at login)
- Today's snapshot: `~/Documents/worklog/dashboard/2026-04-24/` — overall **GREEN** (exit 0), 18 green + 3 informational, 0 yellow / 0 red
- Catalog: **21 signals enabled** (up from 6), 49 total in catalog, 28 still disabled
- Sink: 227 observations (208 end-of-2026-04-23 → 227 after today's writes)

### Signals enabled today

| Component | Signals |
|---|---|
| `vms-connector` (7) | `fleet_oomkills_24h` `fleet_new_oom_offender` `fleet_error_top15` `streamid_guid_rejection_stage` `nonetype_unpack_top_facet` `deployment_cpu_pct_vms` `deployment_memory_pct_vms` |
| `alert-pipeline` (7) | `queue_evalink_errors_12h` `queue_evalink_volume_12h` `queue_eagle_eye_volume_12h` `frontel_puller_volume_12h` `clips_smtp_worker_volume_12h` `smtp_frame_receiver_volume_12h` `clips_prod_volume_12h` |
| `autopatrol_onboarder` (2) | `onboarder_activity_us` `onboarder_lambda_invocations_us` |
| `k8s-cluster` (2) | `cluster_cpu_pct_avg` `cluster_memory_pct_avg` |
| `inference-api` (2) | `deployment_cpu_pct_inference` `deployment_memory_pct_inference` |
| `cost` (1) | `cost_s3_daily_total` |

### Code / config changes landed today

- `signals.json` — 15 signal changes: enabled + recalibrated 9 existing; added 6 new alert-pipeline volume signals. All baselines derived from 7d trailing NRQL data.
- `baselines.json` — 7 new baseline values for silent-drop / baseline-drift regression rules.
- `render.py` — `apply_regression_rules` new_pattern guard: requires BOTH today and prior values to be dicts (prevents false-positive "every facet is new" on first run).
- `daily-scope/SKILL.md` — Step 2bb preflight now includes dashboard-sink-writable check; Step 2c makes `/dashboard-check` a standing mandatory exec item + prescribes sink writes for every fan-out result.
- `mark-todos.md` — §9 Phase 1b deliverables #6 + #7 ticked; §11d (push-based minipc ingest) + §11e (cronify-friendly refactor) added.

## Calibration lessons (DO NOT REDO)

1. **`cpuUsedCoresVsLimitPercent` / `memoryUsedVsLimitPercent` are null on this cluster** — K8sContainerSample doesn't populate the "% of limit" fields (likely because limits aren't consistently set). Use:
   - Node-level: `allocatableCpuCoresUtilization`, `allocatableMemoryUtilization` (on `K8sNodeSample`)
   - Container-level: `requestedCpuCoresUtilization`, `memoryWorkingSetUtilization` (on `K8sContainerSample`)
   - Semantic note: `requestedCpuCoresUtilization` is % of **request** not % of limit. Can exceed 100% legitimately when limits > requests. Today's connector avg is ~70%; yellow/red thresholds set at 120/200.

2. **Inference containers aren't named `%inference%`** — the actual container names are `inference-server` and `model-server`. `actuate-external-api` is the user-facing v5 API surface (not currently in catalog).

3. **Alert-pipeline services log only at `level='info'`** — `smtp-frame-receiver`, `clips-prod`, `clips-smtp-worker`, `frontel-puller` do NOT produce ERROR-level logs. `queue-evalink-consumer` and `queue-eagle-eye-consumer` use uppercase ERROR. For the info-only services, the right health signal is **log-volume drop** (silent_drop rule) not error-count. This is why 6 of today's new signals are `*_volume_12h` not `*_errors_12h`.

4. **Static thresholds need real-data calibration before enabling** — `queue_evalink_errors_12h` had yellow=20 / red=100 in the catalog stub; 7d real data showed 142–1178/12h with median ~650. The stub was 6× too low. Lesson: always `SINCE 7 days ago TIMESERIES 12 hours` a signal before enabling, derive p75/p95 for yellow/red.

5. **`sink.py::write_observation` with `source_skill="dashboard-check"` is filtered out from `_latest_sink_observation`** — the renderer excludes its own writes so it doesn't read stale values from prior runs. Workaround: for backfill / manual writes, use `source_skill="backfill"` or `daily-scope.fan-out`. For live-run values, write them to `$TEMPDIR/*_results.json` so the renderer treats them as `data_source="live"`.

## Remaining Phase 1b deliverables

In recommended execution order (most value first). Each is scoped so a fresh session can pick up one at a time.

### 1. (PRIMARY) Replay tests for 7 historical incidents — **deliverable #8** *(STARTED 2026-04-24 EOD; verification pending)*

**Status update 2026-04-24 EOD:** 6 new replay tests authored in `~/.claude/skills/dashboard-check/tests/test_signal_classification.py` (the file went from 9 tests → 15). **Not yet run** — no pytest venv was set up at handoff. **First task on resume: `pytest -v` to verify all pass.** If any fail, the most likely causes are:
- a baseline parameter mismatch (`render.classify` may not accept `baseline=` as kwarg — check signature)
- a regression-rule guard mismatch (the `new_pattern` rule was edited mid-session to require `isinstance(prior_value, dict)` — verify that didn't break the existing `test_new_pattern_facet_rule`)
- the 2026-04-20 SSL test is a placeholder using `fleet_error_top15` as proxy; consider whether the assertion shape is right

The 7-incident replay scope below stays accurate; what's already in the file:

- 2026-04-23 onboarder silent-failure — *already have it; canonical acceptance test*
- 2026-04-23 OOM surge (4x baseline) — fixture needs `fleet_oomkills_24h=423` + `fleet_new_oom_offender={'connector-20628': 87, ...}` → asserts status=yellow/red
- 2026-04-23 NoneType platform-services shift — `nonetype_unpack_top_facet={'smtp-frame-receiver': 3800, 'create-detection-window': 2200}` vs prior `{'connector-*': ...}` → asserts new_pattern fires
- 2026-04-20 streamId-null bug — `streamid_guid_rejection_stage=5` vs threshold → asserts yellow
- 2026-04-20 SSL cert-verify failure — needs a new signal first; punt or use `fleet_error_top15` proxy
- 2026-04-17 connector-deploy 11K-error outlier — `fleet_error_top15` dict with connector-deploy spike
- 2026-04-20 evalink 540-error breach — `queue_evalink_errors_12h=540` vs new 1800 threshold (WON'T trigger with today's recalibration — update the threshold rationale)

Each test = one assertion pair: (input observations + prior_observations) → (expected status + expected regressions). Pattern: look at existing `test_onboarder_silent_earlyreturn_is_red` for shape.

### 2. Regression rules 3 + 4 — **deliverable #4**

Extend `render.py::apply_regression_rules`:

- **Rule 3 — baseline_drift**: today's value drifts >2σ from `baselines[signal_id]`. Data source: `sink.read_recent(since_hours=24*7)` computes σ from the 7d trailing. Flags yellow at 2σ, red at 3σ. Only fires for signals whose `regression_rules` list contains `"baseline_drift"`. Signals ready for this rule: `fleet_oomkills_24h`, `queue_evalink_errors_12h`, `cluster_cpu_pct_avg`, `cluster_memory_pct_avg`, `deployment_cpu_pct_vms`, `deployment_memory_pct_vms`, `deployment_cpu_pct_inference`, `deployment_memory_pct_inference`, `cost_s3_daily_total`, `smtp_frame_receiver_volume_12h`, `clips_prod_volume_12h`.
- **Rule 4 — chronic_offender_promotion**: FACET signal where the SAME top facet has appeared in top-N on ≥3 of the last 7 days. Graduates from informational → yellow. Catches e.g. "connector-11202 has been the top error source every day this week — not a transient".

Both rules need access to 7d sink history. Extend `Evaluation` with a `history_stats: {mean, stddev, count}` field populated at eval time from sink.

### 3. Morning-summary section aggregation — **deliverable #5**

`index.html.j2` already stubs a "Morning summary" section; `render.py` needs to populate it from `sink.read_recent(since_hours=24, source_skill !=` `"dashboard-check"`). Group by `source_skill` (e.g. `daily-scope.fan-out`, `autopatrol-cleanup-lambda-check`, `autopatrol-overnight-check`). Each group shows the per-signal verdict + one-line note. This becomes the single place to see cross-skill observations.

Prereq: `/daily-scope` now writes sink rows (Step 2c change shipped today) — will populate organically after next morning run. To test before then, call `sink.write_observation(..., source_skill="daily-scope.fan-out")` manually from a REPL with ~5 fake entries.

### 4. Sparklines (Tier 1 charts) — **deliverable #13 tier 1**

Inline SVG, 60×20 px, 24h window, one per signal in the grid. Data source: `Evaluation.history` (already populated via `_latest_sink_observation` trailing_window). Add a `render/charts.py` helper taking `(points, width, height, baseline)` → SVG string. No JS, no framework.

Sink has enough data (227 rows, growing daily) to make sparklines meaningful starting today. Start with high-volume signals: `fleet_oomkills_24h`, `queue_evalink_volume_12h`, `cost_s3_daily_total`.

### 5. Hero carousel — **deliverable #12**

`index.html.j2` top section: 3 view-cards users flip via `< / >` or dropdown.
1. **Heat-grid** — GitHub-contribution-grid layout, one chip per signal × 7d history
2. **Top regressions today** — signals with biggest deviation from baseline (depends on rule 3)
3. **Recent launches gated** — `/dashboard-check --gate <commit>` history (depends on gate mode being exercised)

CSS `:target` + anchor-based carousel; no JS framework.

### 6. Compact grid + inline expand — **deliverable #11**

Drop the `Description` column; add `<details><summary>` inline expand per row (status, id, value, sparkline, baseline, regressions in the collapsed row; description/query/thresholds/last-N sink rows in the drawer). Target ~28px row height, 20 rows visible in a viewport.

### 7. Data hooks — **deliverable #14**

- Extend `data.json` so agents can answer "what did X look like at time T?" without re-querying
- `sink.py::query(signal_id, window_hours)` helper for any skill
- Embedded NRQL / CLI query in the expanded drawer (copy button)
- `kb_link` field in signals.json → rendered as "Why this signal exists: [[...]]" in the drawer

### 8. Catalog coverage enrichment — **deliverable #15**

Add signals for:

- **actuate-admin** (currently 2 in catalog): schedule-activation rate, tenant-create success rate, RBAC denial patterns, admin-API 4xx/5xx breakdown
- **inference-api** (currently 2, both K8s): per-model detection throughput, per-partner-API-key activity, per-endpoint 4xx/5xx
- **autopatrol-server** (not in catalog): patrol-completion rate, CNCTNFAIL per site
- **actuate-libraries** (not in catalog): version-drift alert, consumer-side import-check
- **Config-drift signals** (deliverable #10): `connector_pods_under_1gb_limit`, `connector_pod_headroom_over_70pct`, `vpa_updatemode_drift`, `s3_lifecycle_rules_disabled`

Follow today's calibration pattern: query 7d TIMESERIES before enabling, set thresholds at p75/p95 of real data, always populate `would_have_caught`.

### 9. Baseline recalibration pass — **deliverable #9**

After ~1 week of sink accumulation (target: next 2026-05-01+ session), walk every `baselines[signal_id]` and re-compute from 7d sink data. Some will shift materially once day/night patterns, weekend cycles, etc. bake in.

## After Phase 1b: §11e cronify → §11d push-based minipc arch

Once Phase 1b is calibrated, the **next workstream is §11e** (cronify-friendly headless collector) so the dashboard auto-updates every 15–30 min on the minipc (§11a scaffold). Then §11d (push API endpoints on minipc, laptop store-and-forward outbox). Both are documented in `mark-todos.md` §11.

Phase 2 (launch-gate wiring into `/stage-release`, `/post-deploy-monitor`, `/validate-release`) comes after that — don't start until the dashboard isn't producing any false-positive yellows/reds.

## Quick-start commands for the continuation session

```bash
# Verify dashboard is live
curl -sS http://localhost:8765/latest/ -o /dev/null -w "HTTP %{http_code}\n"
systemctl --user status dashboard-server.service

# Inventory enabled signals
python3 -c "
import json
with open('/home/mork/.claude/skills/dashboard-check/config/signals.json') as f:
    d = json.load(f)
for s in d['signals']:
    if s.get('enabled'):
        print(f'  {s[\"id\"]:40s} {s[\"component\"]:24s} {s[\"source\"]}')"

# Count sink rows
wc -l ~/Documents/worklog/dashboard/sink/observations.jsonl

# Re-render on demand (uses cached tempdir from prior run if still present)
ls /tmp/tmp.* 2>/dev/null | head -3  # find a tempdir with *_results.json
bash ~/.claude/skills/dashboard-check/run.sh render \
  --tempdir <tempdir> \
  --output-root ~/Documents/worklog/dashboard \
  --snapshot-date $(date -u +%Y-%m-%d)
```

## Cross-refs

- [[2026-04-23_dashboard-phase-1b-pickup]] — **superseded by this note**; keep for archaeology
- [[2026-04-23_dashboard-sketch]] — authoritative design
- [[2026-04-23_postmortem-onboarder-healthcheck]] — origin incident
- [[2026-04-23_release-acceptance-criteria]] — the rule this skill operationalizes
- [[mark-todos]] §9 — workstream tracker; §11d / §11e — follow-on work
- [[feedback_acceptance_criteria_every_merge]], [[feedback_fail_fast_guards]] — hard rules
- Skill: `/dashboard-check` (live); integration: `/daily-scope` Step 2c (shipped today)
