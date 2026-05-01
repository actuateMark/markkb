---
title: "Operational Dashboard — Local Static HTML Sketch"
type: synthesis
topic: operational-health
tags: [dashboard, monitoring, regression-prevention, release-gate, sketch, design, autopatrol]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
status: sketch
incoming:
  - topics/engineering-process/_summary.md
  - topics/engineering-process/notes/concepts/2026-04-23_release-acceptance-criteria.md
  - topics/engineering-process/notes/syntheses/2026-04-14_feature-development-lifecycle.md
  - topics/operational-health/notes/concepts/2026-04-23_dashboard-phase-1b-pickup.md
  - topics/operational-health/notes/concepts/2026-04-24_dashboard-1b-continuation.md
  - topics/operational-health/notes/concepts/2026-04-27_dashboard-signal-cookbook.md
  - topics/operational-health/notes/syntheses/2026-04-24_overnight-check.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-01
---

# Operational Dashboard — Local Static HTML Sketch

**Status:** Phase 1a SHIPPED 2026-04-23 (skill live at `/dashboard-check`, HTTP server at http://localhost:8765/, 10 tests pass, one signal pair wired end-to-end against live prod). Phase 1b pickup guide: [[2026-04-23_dashboard-phase-1b-pickup]].

**Trigger:** 2026-04-23 user directive after the onboarder post-mortem: *"I want to sketch out the dashboard in question. If possible I would like it to generate a local, static website. It can be as simple as an index html with a daily report of the alarms and metrics and log patterns. We need this, and we need to check and verify against it for EVERY launch. Above all else our priority with every launch is to avoid regressions and to catch them as soon as possible when they do occur."*

## The load-bearing principle

**Regression prevention + fastest-possible detection is the #1 operational priority for every launch.** Everything below serves that principle. See [[engineering-process/_summary|engineering-process]] — this is now reflected in the top of the Key Principles list.

The onboarder incident ([[2026-04-23_postmortem-onboarder-healthcheck]]) is the reference case: 47 hours of customer-facing silent failure because CI was green, `Errors=0`, and no one had a daily checkable signal. We are not allowed to let that happen again. The dashboard is the forcing function.

## Form — local static HTML

- Output root: `/home/mork/Documents/worklog/dashboard/`
- Everything lives on disk as files; no server required
- Viewable via `file://` in a browser, or `python -m http.server` for local serving if preferred
- Daily snapshot directory + `latest/` symlink for the most-recent run
- Per-component drill-down pages linked from the index
- Regression page highlights deltas vs prior day + 7-day trailing baseline

Directory layout:

```
~/Documents/worklog/dashboard/
├── index.html                # symlink → latest/index.html (open this)
├── latest/                   # symlink → YYYY-MM-DD/ (most recent run)
├── 2026-04-23/               # dated snapshot (one dir per run)
│   ├── index.html            # the main dashboard
│   ├── data.json             # raw query results (machine-readable)
│   ├── regressions.html      # deltas vs prior day + trailing 7-day avg
│   ├── components/
│   │   ├── vms-connector.html
│   │   ├── autopatrol.html
│   │   ├── inference-api.html
│   │   ├── actuate-admin.html
│   │   ├── actuate-libraries.html
│   │   └── alert-pipeline.html
│   └── assets/
│       ├── dashboard.css     # tiny, inlined into index.html on write
│       └── dashboard.js      # optional — collapse/expand drill-down sections
└── config/
    ├── signals.json          # signal definitions + baselines + thresholds
    └── templates/            # Jinja2 or plain-string templates
```

Design constraints:
1. **No hosted infrastructure.** Just files in the worklog directory. Backed up by whatever backs up the worklog. Version-controllable if we choose (can commit the whole `dashboard/` dir to a git repo later).
2. **Human-readable at every layer.** `data.json` is inspectable; HTML is self-contained; signal definitions are one JSON file.
3. **Works offline.** Dashboard works without a live internet connection IF the query data was already collected. Generation needs connectivity; viewing doesn't.
4. **Cheap to regenerate.** Every `/dashboard-check` invocation produces a new snapshot. Old snapshots are kept indefinitely (cheap disk cost for audit trail).

## Content — what goes on the index page

### Header

```
┌────────────────────────────────────────────────────────┐
│ Actuate Operational Dashboard                         │
│ Snapshot: 2026-04-23T14:30:00Z                        │
│ Overall status: 🟡 YELLOW (2 yellow, 0 red, 6 green)  │
│ Comparison: vs 2026-04-22 | 7d trailing avg           │
└────────────────────────────────────────────────────────┘
```

### Per-component summary grid

One row per component, two most-important signals each. Red/yellow/green indicator + current value + baseline.

```
┌──────────────────────┬─────────────────┬─────────────────┬────┐
│ Component            │ Signal 1        │ Signal 2        │ ?  │
├──────────────────────┼─────────────────┼─────────────────┼────┤
│ vms-connector        │ 🟡 OOMKills 423 │ 🟢 patrols 3502 │ →  │
│ autopatrol_onboarder │ 🟢 288/h each   │ 🟢 errors 0     │ →  │
│ inference-api        │ 🟢 v5 98.5% OK  │ 🟢 models 7/7   │ →  │
│ actuate-libraries    │ 🟢 drift 1 day  │ 🟢 published ok │ →  │
│ actuate-admin        │ 🟢 schedules OK │ 🟢 RBAC clean   │ →  │
│ autopatrol-server    │ 🟢 completion   │ 🟢 CNCTNFAIL    │ →  │
│ alert-pipeline       │ 🟡 NoneType 3x  │ 🟢 delivery     │ →  │
│ cleanup-lambda       │ 🟢 invokes 30   │ 🟢 DLQ 0        │ →  │
└──────────────────────┴─────────────────┴─────────────────┴────┘
```

Click any row → per-component drill-down HTML.

### Regressions section (top of page when present)

```
🚨 Regressions detected since 2026-04-22:
  - vms-connector: OOMKills 103 → 423 (+4x)
    NEW TOP OFFENDER: connector-20628 (87 events; was 0 yesterday)
  - alert-pipeline: NoneType errors shifted from connector pods
    to smtp-frame-receiver (3.8K/12h) + create-detection-window (2.2K/12h)

⚠ Drifts (watch):
  - none
```

### Launch record (mandatory gate)

A collapsed section that expands to show recent launches + whether their acceptance criteria passed on the dashboard. If a launch is pending verification, it's prominent at the top.

```
Recent launches (last 24h):
  ✓ 2026-04-22T14:53 vms-connector#1654 (deferred-alert fix) — §2b canaries clean
  ⏳ 2026-04-22T18:04 cleanup-Lambda stage (§3 Step D) — bake in progress
```

## Content — per-component drill-down

Each `components/<name>.html` has:

1. Signal definitions (what we're measuring and why)
2. Current values + baseline bands
3. 7-day trend sparkline (inline SVG, no JS lib)
4. Raw log samples (top N lines from the most-relevant NR query) — collapsed by default
5. Last time acceptance criteria were evaluated against this component + result
6. Link to the repo's `CLAUDE.md` "Release Acceptance Criteria" section

## Signal set (starting inventory — phase 0)

Full signal set lives in `config/signals.json`. Initial version below. Each signal has: `query_source`, `query`, `baseline`, `thresholds`, `weight`.

### vms-connector

| Signal | Source | Baseline (subject to per-run recalibration) | Red threshold |
|---|---|---|---|
| OOMKills per 24h fleet-total | NR `K8sContainerSample` `reason='OOMKilled'` | ~100 | >2x baseline for 2 consecutive days |
| Patrol-exit emit count per 24h | NR Log fingerprint `emit_no_patrols_signal` | ~3500 | <50% of baseline for 6h |
| New chronic OOM offender | Delta today's top-10 OOM facet vs 7-day | n/a | any new container with >50 kills/day that wasn't in top-10 prior |
| `streamId Guid` rejection on `:stage` | NR Log | 0 | any |
| Connector-container ERROR facet | NR Log `level='ERROR'` FACET container_name | baseline per-container | any container >3x its 7d baseline |

### autopatrol_onboarder (per region: US + EU)

Per [[2026-04-23_alarm-dashboard-sketch]]. Primary signals:

| Signal | Source | Baseline | Red threshold |
|---|---|---|---|
| Contracts fetched per hour | CW Log `Fetched N contracts` | ≥10 per hour | 0 for 2 consecutive hours |
| Schedules activated per 24h | CW Log `activating schedule` | fleet-specific | 0 for 24h streak |
| Lambda invocations with real work | CW Log activity-marker count | >10/h | near 0 while invocations non-zero (silent-early-return fingerprint) |

### autopatrol cleanup Lambda + reenable Lambda

Per [[2026-04-23_alarm-dashboard-sketch]] §2. Specifically:

| Signal | Source | Baseline | Red threshold |
|---|---|---|---|
| DLQ depth (stage + prod) | CW SQS | 0 | >0 |
| Would-PATCH rate (`CLEANUP_ENABLED=false`) | CW Log | 0-few/day | >10/h spike |
| Anomaly reset rate | CW Log | <5/day | >10/h spike |

### actuate-inference-api

| Signal | Source | Baseline | Red threshold |
|---|---|---|---|
| v5 detect endpoint success rate | NR Log or metric | >99% | <95% for 15min |
| Per-model invocation count | NR FACET model_name | baseline per-model | any model at 0 when it was non-zero 7d prior |
| 4xx rate | NR | <5% | >10% |
| 5xx rate | NR | 0 | any sustained |

### actuate-libraries

| Signal | Source | Baseline | Red threshold |
|---|---|---|---|
| Days between latest dev-pin and latest stable publish | local `gh release list` + compare | 0-3 days | >7 days |
| Last successful "Publish Stable" workflow run | GH Actions | daily-ish | >72h stale |
| Developer-build-from-main works | local `uv sync` in connector on latest pin | clean | dependency resolution fails |

### actuate_admin

| Signal | Source | Baseline | Red threshold |
|---|---|---|---|
| Schedule activation rate (AutoPatrol → admin) | Admin API access log | baseline per-region | sustained 0 rate while upstream active |
| RBAC denial spike | Admin log `403` | baseline | >10x spike (may indicate regression in auth) |
| Django migrations last applied | deployed commit vs schema | current | migration lag >24h (stuck deploy) |

### alert-pipeline (queue-consumer + smtp-frame-receiver + clips-smtp-worker + evalink/eagle-eye consumers)

| Signal | Source | Baseline | Red threshold |
|---|---|---|---|
| Delivery rate per integration | NR FACET container_name | baseline per-integration | 0 for 30 min |
| Queue depth per integration | CW SQS | bounded | >baseline × 3 for 30 min |
| NoneType / unpack errors | NR Log fingerprint | baseline per-container | shift to new top offender |

### autopatrol-server

| Signal | Source | Baseline | Red threshold |
|---|---|---|---|
| Patrol completion rate | NR Log | baseline per-day | <50% for 6h |
| CNCTNFAIL per site | NR Log | baseline per-site | new site with >5 CNCTNFAIL/h |

## The skill — `/dashboard-check`

### Invocation modes

```bash
/dashboard-check                      # full scan, all components
/dashboard-check --component vms-connector   # narrowed
/dashboard-check --gate <pr-or-commit>       # narrows to the component that just deployed; blocks until verified or timeout
/dashboard-check --diff 2026-04-22           # regenerates comparing against a specific prior snapshot
/dashboard-check --open                       # open the generated index.html in default browser after write
```

### Behavior

1. **Preflight** (reuses the `/daily-scope` Step 2bb pattern) — verify AWS prod SSO + NR MCP + GH CLI + any other credential that today's signal set requires. Pause and ask for remediation on failure.
2. **Parallel query execution** — all NR queries in parallel via nrql-investigator sub-agent; all CW queries in parallel via bash; all GH queries in parallel via gh. Collect into a structured dict.
3. **Baseline load** — read `config/signals.json` for baseline values + thresholds. If signal has no baseline, run in "informational" mode (no red/yellow classification).
4. **Classification** — per signal: compute status (green/yellow/red) against threshold; compute delta vs yesterday + 7d trailing avg.
5. **Regression detection** — explicit pass comparing today vs yesterday + 7d:
   - New log fingerprint in top-10 that wasn't there yesterday → RED REGRESSION
   - Metric crossed from non-zero to zero when expected non-zero → RED REGRESSION
   - Metric outside ± 2σ of 7d trailing avg → YELLOW DRIFT
6. **Write artifacts** — `data.json`, `index.html`, per-component `components/*.html`, `regressions.html`. Update `latest/` symlink.
7. **Print summary to console** — 3-5 line PASS/FAIL summary + path to `index.html`.
8. **Exit code**: 0 if all green, 1 if any yellow, 2 if any red. Lets the skill be used as a release gate (CI can gate on exit code).

### Skill file structure

```
~/.claude/skills/dashboard-check/
├── SKILL.md                 # the skill definition
├── run.sh                   # top-level wrapper (python → run.sh)
├── check.py                 # orchestrator
├── signals/
│   ├── vms_connector.py     # per-component query + classify
│   ├── autopatrol.py
│   ├── inference_api.py
│   ├── actuate_admin.py
│   ├── actuate_libraries.py
│   └── alert_pipeline.py
├── render/
│   ├── index.j2             # Jinja2 templates
│   ├── component.j2
│   └── regressions.j2
├── css/
│   └── dashboard.css        # inlined at render time
└── config/
    └── signals.json         # signal thresholds + baselines (version-controlled)
```

### Failure modes + graceful degradation

- If NR MCP is unreachable: render dashboard with NR sections marked "unavailable" + clear failure message; skill exits non-zero.
- If a single signal query fails: skip that signal, render its row as "error"; other signals unaffected.
- If baselines aren't set for a signal: render in informational mode, no classification. Prompt user to calibrate after 7 days of data.

## Launch-gate contract (this is the load-bearing rule)

Every release-path skill runs `/dashboard-check --gate <commit>` as the final step BEFORE declaring success:

| Skill | When | Gate behavior |
|---|---|---|
| `/stage-release` | After dev deploy verified | Run dashboard scoped to the deployed component; wait at least one cron cycle / one real-traffic window. Block declaring success until GREEN. |
| `/post-deploy-monitor` | Post-merge-to-prod watch | Continuous polling every 5min for first 30min, then every 15min for 2h. Any RED triggers rollback dialogue. |
| `/validate-release` | Pre-merge sanity | Run dashboard on prod BEFORE the merge as the baseline; compare post-deploy against this baseline, not yesterday's, to catch deploy-induced drift. |
| `/daily-scope` | Every morning | Run dashboard as part of Step 2c fan-out; any RED is surfaced in the interview. |
| Direct user invocation | Ad-hoc | Any time. |

**Hard rule:** a release is NOT verified until the dashboard has gone through at least one full cron cycle / real-traffic window GREEN against the deployed component. CI-green is necessary but never sufficient.

## Regression detection — the specific logic

This is the piece that prevents the onboarder-incident class of failure. Explicit rules:

1. **Silent-drop alarm.** Any signal that is normally non-zero going to zero (or near-zero) triggers RED. Configurable per signal — some are allowed to be zero (e.g., reenable Lambda invocations are often 0); most aren't.
2. **New-pattern alarm.** Any log fingerprint appearing in top-10 FACET today that wasn't in top-10 7-day trailing → YELLOW. If it's in a "critical" container (connector, inference, alert-delivery) → RED.
3. **Baseline drift alarm.** Any signal outside ± 2σ of trailing 7d avg for 2 consecutive days → YELLOW. Crossing 3σ → RED.
4. **Chronic-offender promotion.** If a "new top OOMKill offender" appears and sustains for 2 consecutive days → RED (this is the `connector-20628` pattern from 2026-04-23).
5. **Activity-marker anti-pattern.** If a component's Lambda `Invocations > 0` but activity-marker count near 0 → RED (this is the exact onboarder 2026-04-21 silent-failure fingerprint).

Every rule is expressed in `signals.json` + `check.py`. Every rule has a named test case in `tests/` (when the skill is implemented) so we don't drift.

## Rollout plan

### Phase 0 — Signal inventory (current workstream)

- [ ] Draft `config/signals.json` for autopatrol + vms-connector + inference-api (3 starter components)
- [ ] Confirm each repo's `CLAUDE.md` has "Release Acceptance Criteria" section populated
- [ ] Lock the per-component signal list through an interview round with user
- [ ] Commit the signal catalog to the KB at `topics/operational-health/notes/concepts/dashboard-signal-catalog.md` (live doc)

### Phase 1 — MVP skill (split 2026-04-23 into Phase 1a + 1b)

The full Phase 1 plan is at `/home/mork/.claude/plans/clever-tickling-swing.md` (approved 2026-04-23). Summary below; plan file is authoritative for file-level detail.

#### Phase 1a (this session — 2026-04-23)

- [ ] Full signal catalog (~60 signals) committed as `config/signals.json`; most `enabled: false` for 1a
- [ ] Catalog includes: the 44 historical signals from overnight-check inventory + NEW categories: **CPU + memory per deployment type** (user-priority; catches release-induced resource regressions), AWS Budgets + cost anomalies, NR APM golden metrics (Apdex/error rate/throughput/latency), K8s HPA saturation + [[argocd|ArgoCD]] out-of-sync
- [ ] Static `config/baselines.json` with values hand-picked from historical notes
- [ ] Shared sink: schema at `sink/.schema.md` + empty `sink/observations.jsonl` + `sink.py` helper (`write_observation()` + `read_recent()`)
- [ ] Skill scaffold: `SKILL.md`, `run.sh`, `requirements.txt` (jinja2==3.1.*), `README.md`
- [ ] Python orchestrator `render.py` with regression rules 1/2/5
- [ ] Jinja2 templates: `index.html.j2`, `component.html.j2`, `regressions.html.j2`, `macros.j2`
- [ ] Self-contained CSS at `css/dashboard.css` (inlined at render time)
- [ ] Minimal collectors: `collect_aws.sh`, `collect_gh.sh`
- [ ] Tests: onboarder anti-pattern fixture → expect RED; sink round-trip test; both pass under `pytest`
- [ ] **One end-to-end signal wired**: `onboarder_activity_us` paired with `onboarder_lambda_invocations_us` — canonical acceptance test
- [ ] Smoke run: viewable `~/Documents/worklog/dashboard/2026-04-23/index.html` with real data for the onboarder row

#### Phase 1b (next session)

- [ ] Execute remaining ~19 primary signals end-to-end (the 20-signal list in § "Signal set" minus the 1 from 1a)
- [ ] CPU/memory per deployment subset wired: `cluster_cpu_pct_avg`, `cluster_memory_pct_avg`, `deployment_cpu_pct_vms`, `deployment_memory_pct_vms`, `deployment_cpu_pct_inference`, `deployment_memory_pct_inference`
- [ ] Full drill-down pages (per-component HTML with SVG sparklines, collapsed raw-log samples)
- [ ] Regression-rules page with full deltas-vs-prior-day + 7-day-trailing; add rules 3 (baseline drift 2σ) + 4 (chronic offender promotion)
- [ ] Morning-summary section aggregating sink entries from last 24h grouped by `source_skill`
- [ ] Wire into `/daily-scope` Step 2c: add standing `/dashboard-check` exec item + fan-out writes to sink via `sink.py`
- [ ] Extend `/daily-scope` Step 2bb preflight to verify sink dir + write-access
- [ ] One additional component (likely inference-api for NR APM payoff)
- [ ] Replay tests for all 7 historical incidents (onboarder silent-failure, OOM surge, NoneType shift, streamId null, cert-verify, 2026-04-17 error spike, 2026-04-20 evalink breach)
- [ ] Baseline calibration pass against 7 days of real data

### Phase 2 — Launch gate

- [ ] Wire into `/stage-release` + `/post-deploy-monitor` + `/validate-release`
- [ ] Exit-code contract: 0/1/2 formalized
- [ ] Release-gate documentation in each repo's `CLAUDE.md`

### Phase 3 — Full component coverage

- [ ] Add actuate-admin, actuate-libraries, alert-pipeline, autopatrol-server
- [ ] Full regression-rule set (rules 1-5)
- [ ] 7-day baseline calibration automation

### Phase 4 — Continuous improvement loop

- [ ] Every incident → which missing signal would have caught it? Add. Document in the signal-catalog with a "derived from" pointer to the incident post-mortem.
- [ ] Automated KB note generation: when a RED fires, the dashboard writes a fresh concept note to `topics/operational-health/notes/concepts/YYYY-MM-DD_<component>-red.md` summarizing the signal + likely cause + last-known-good run.

## Open decisions

1. **HTML vs static-site generator?** MVP uses raw string templating or Jinja2 for speed. If the dashboard grows past ~10 components or needs more sophisticated visuals, move to MkDocs or similar.
2. **Signal baselines: static or learned?** Phase 0/1 use static (human-calibrated) baselines. Phase 3+ can shift to rolling-window baselines if coverage is broad enough.
3. **Cross-region handling.** Most signals are single-region-obvious ([[autopatrol-onboarder|autopatrol onboarder]] is per-region). Do we render two separate per-region sections or unify? Sketch assumes unified per-component, region column in the table. Revisit.
4. **Data retention.** Do we keep every daily snapshot forever, or prune after 90 days? Disk usage is minimal (~1MB/day); retain forever for audit purposes.
5. **Notification integration.** MVP: printed to console + HTML file. Phase 2+ could post to Slack on any RED. Defer.

## Relationship to existing work

- **Subsumes** `/autopatrol-overnight-check`, `/autopatrol-cleanup-lambda-check`, and the ad-hoc NR queries in `/daily-scope` Step 2c fan-out. Those skills continue to exist as drill-down tools; `/dashboard-check` is the aggregator.
- **Complements** (not replaces) the `code-health` dashboard initiative in [[2026-04-16_code-health-dashboard]]. Operational-health (this sketch) is runtime/behavioral; code-health is static-analysis/structural. Both can share the same HTML rendering infrastructure but the data pipelines are distinct.
- **Enforces** the rules in [[2026-04-23_release-acceptance-criteria]] at the tool level. The rule says "verify every launch"; the skill is the verification.
- **Per-repo signal inventory lives in each repo's `CLAUDE.md`**, synced to `topics/operational-health/notes/concepts/dashboard-signal-catalog.md` as the single source of truth.

## Next step

Implementation PR for Phase 0 + Phase 1 — scaffold the skill, draft `signals.json`, get one end-to-end run producing real HTML for the autopatrol + vms-connector + inference-api subset. Tracked in [[mark-todos]] §9.

## Cross-refs

- [[mark-todos]] §9 — parent workstream
- [[2026-04-23_postmortem-onboarder-healthcheck]] — the trigger incident
- [[2026-04-23_alarm-dashboard-sketch]] — AutoPatrol-scoped precursor (this sketch generalizes it)
- [[2026-04-23_release-acceptance-criteria]] — the rule this operationalizes
- [[feedback_fail_fast_guards]], [[feedback_acceptance_criteria_every_merge]] — origin memories
- [[engineering-process/_summary]] — where the principle lives
- [[2026-04-16_code-health-dashboard]] — adjacent (static code-health counterpart)
- [[2026-04-14_connector-fleet-monitoring]] — existing monitoring synthesis (partial overlap; should be re-integrated once the skill lands)
