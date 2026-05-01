---
title: "Dashboard signal cookbook — adding a new signal to /dashboard-check"
type: concept
topic: operational-health
tags: [dashboard-check, signals, cookbook, runbook, observability, monitoring, new-relic]
created: 2026-04-27
updated: 2026-04-28
author: kb-bot
incoming:
  - topics/personal-laptop/notes/concepts/2026-04-27_handoff-repos-architectural-dashboard.md
  - topics/personal-laptop/notes/concepts/2026-04-28_handoff-repos-dashboard-phase-2-code-health.md
  - topics/personal-laptop/notes/concepts/2026-04-29_minipc-api-surface.md
  - topics/personal-laptop/notes/concepts/2026-04-29_repos-dashboard-followups.md
  - topics/personal-laptop/notes/syntheses/2026-04-27_minipc-tooling-improvements.md
  - topics/personal-notes/notes/daily/2026-04-27.md
incoming_updated: 2026-05-01
---

# Dashboard signal cookbook

How to add a new signal to `/dashboard-check`'s catalog — broken down by **where the data comes from**, because each source has its own NRQL/API shape, threshold-calibration approach, and gotchas. Use this whenever you want the dashboard (and the morning routine that reads from it) to start tracking something new.

## Decision tree — pick your source

```
I want to monitor X, where does X live?

├── In NR (logs, k8s metrics, transactions, etc.) ─────► nr_log / nr_k8s_*
│       ├── Log lines (errors, fingerprints, volume)         → nr_log
│       ├── Container metrics (OOM, CPU, memory, restarts)   → nr_k8s_container_sample
│       └── Node-level (cluster CPU/mem, node count, ready)  → nr_k8s_node_sample
│
├── In AWS — Lambda log line counts ──────────────────► cw_log
├── In AWS — CloudWatch metrics ──────────────────────► cw_metric
│       (Lambda Invocations, SQS depth, RDS, etc.)
├── In AWS — Cost Explorer (daily spend) ─────────────► ce_daily
│
├── In GitHub (PRs, CI checks, SSL checks) ──────────► gh_*  (Phase 2 — not yet wired)
├── On-host systemd / journalctl (minipc only) ──────► minipc_local
├── Per-repo working tree (TODO/FIXME, version pins,
│   radon CC, ruff F401, …) — minipc only ────────────► git_local
└── Custom HTTP / file artifact ──────────────────────► extend collect.py with a new source type
```

Choosing the right source matters: NR is the path of least resistance for anything already streamed to NR (no extra IAM); CW direct is required for things NR doesn't ingest (e.g. specific Lambda log fingerprints + their invocation counts as separate signals); CE is the only path for spend.

## Common workflow (applies to every source type)

Every signal goes through the same six steps. The source-specific deltas come in steps 2–4.

### 1. Define the value the signal represents

Write down in one sentence what the **scalar or dict** for this signal means:
- "Count of OOMKilled events in the last 24h, fleet-wide" → scalar int
- "Top-10 facets by count_per_12h, FACET container_name" → dict {container: count}
- "Yesterday's S3 spend in USD" → scalar float

Render.py expects either a scalar or a dict (FACET). If you find yourself wanting to encode multiple values for one signal id, that's two signals.

### 2. Write the query

Source-specific (see sections below). Test it interactively first:
- NR: in [`one.newrelic.com → Query your data`](https://one.newrelic.com/data-exploration/query-builder)
- AWS CW: `AWS_PROFILE=dashboard-check aws logs filter-log-events ...` from the laptop or minipc
- AWS CE: `aws ce get-cost-and-usage ...`

**For NR**, watch out for query-cost limits (`NRDB:1107005` server error). FACETs over high-volume tables (`Log` over 12h+) hit this. Mitigate by tightening the time window, the `WHERE`, or the `LIMIT`.

### 3. Add the entry to `config/signals.json`

Required fields (see [`signals.json`](file:///home/mork/.claude/skills/dashboard-check/config/signals.json) examples):

```json
{
  "id": "<short_snake_case_id>",
  "component": "<one of: vms-connector, alert-pipeline, autopatrol_onboarder, k8s-cluster, inference-api, cost>",
  "source": "<nr_log | nr_k8s_container_sample | nr_k8s_node_sample | cw_log | cw_metric | ce_daily>",
  "nrql": "<full NRQL>",                       // for nr_* sources only
  "query": "<aws CLI invocation as text>",     // for cw_*/ce_* sources — documentation only, see step 4
  "unit": "<count_per_24h | percent | usd_per_day | facet_count | …>",
  "description": "<what it measures + why it matters in 1-2 sentences>",
  "regression_rules": ["silent_drop", "new_pattern", "baseline_drift", "activity_marker_antipattern"],
  "thresholds": { "yellow_above": 200, "red_above": 350 },
  "window_hours": 24,
  "enabled": true,
  "would_have_caught": "<incident date + slug — required for sanity>"
}
```

Optional fields used by render:
- `pair_with` — for activity-marker anti-patterns (paired invocations + activity markers)
- `freshness_threshold_hours` — how stale a sink-rendered observation can be before it falls back to "stale"
- `critical: true` — escalates `new_pattern` from yellow to red
- `region` — informational; for AWS signals matches the boto3 region

### 4. Wire collect.py to fetch it

**For NR signals (nr_log, nr_k8s_*):** Nothing to change. `collect.py::collect_nr_signals()` reads the `nrql` field, runs it via nerdgraph, and parses the result via `parse_nr_results()`. Just having `enabled: true` + a valid `nrql` is enough.

**For AWS signals (cw_log, cw_metric, ce_daily):** Add a per-signal Python function in `collect.py` and register it in `AWS_DISPATCH`. Each function takes `profile: str` and returns the scalar/dict value:

```python
def cw_log_my_new_signal(profile: str) -> int:
    s = _boto_session(profile)
    client = s.client("logs", region_name="us-west-2")
    paginator = client.get_paginator("filter_log_events")
    pages = paginator.paginate(
        logGroupName="/aws/lambda/my-fn",
        startTime=...,
        endTime=...,
        filterPattern="my-fingerprint",
    )
    return sum(len(p.get("events", [])) for p in pages)

AWS_DISPATCH["my_new_signal_id"] = cw_log_my_new_signal
```

If you need a new IAM permission for the call, add it to the `dashboard-check-readonly` IAM policy in AWS — see [[2026-04-27_iam-rolesanywhere-minipc]] §"IAM permission policy + role" for the pattern.

### 5. Calibrate thresholds against 7-day trailing data

Don't guess. Pull the actual distribution:

For NR signals, run the same NRQL as `TIMESERIES 1 hour SINCE 7 days ago` and look at p50, p75, p95, max. Set:
- `yellow` between p75 and p95 (you want a yellow ~once or twice a week, not every day)
- `red` at or above p95 (real anomaly, not normal variance)

For below-thresholds (silent_drop checks), invert: `yellow_below = p25`, `red_below = p5`.

If you don't have enough history yet (new infrastructure), set conservative thresholds and note `# TODO recalibrate after 14d` in the description.

### 6. Add a test fixture

Add a replay test to `~/.claude/skills/dashboard-check/tests/test_signal_classification.py` that anchors the signal to a real historical incident (the `would_have_caught` field). This is what guarantees the signal stays useful — if a future refactor breaks the classification logic, the test catches it. Pattern:

```python
def test_my_new_signal_red_on_incident_date():
    sig = load_signal("my_new_signal_id")
    obs = {"my_new_signal_id": <value observed during the incident>}
    eval_ = classify(sig, obs["my_new_signal_id"], baseline=None)
    assert eval_ == "red", f"expected red on incident-day value, got {eval_}"
```

## Per-source recipes

### nr_log — NR Log table queries

**When to use:** error counts, fingerprint counts, volume-drop detection, FACET-by-container-or-service for "who's noisy."

**NRQL shape:**
```sql
SELECT count(*)
FROM Log
WHERE cluster_name='Connector-EKS'
  AND level='ERROR'
  AND <fingerprint>
[FACET <field>]
SINCE <window>
[LIMIT <N>]
```

**Best-practice clauses:**
- Always scope: `cluster_name='Connector-EKS'` (or `'Connector-EKS:stage'`) — NR ingests multiple clusters; without scope you'll get cross-cluster noise.
- Always include `level='ERROR'` (or specific level) to stay in your query budget.
- For FACET, pick a `LIMIT` between 10 and 20 — bigger means longer query + costs more budget.
- For volume-drop signals (`silent_drop` rule), use `count(*)` not a metric — drops show up as zero.

**Time window guidance:**
- 1h windows are cheap and react fast; good for "is the pipeline alive?" signals.
- 12h windows are expensive on `Log` table; use only when you genuinely need the longer baseline (error trending, fan-out volume).
- 24h windows on `Log` may exceed query budget — prefer 12h with adjusted thresholds.

**Examples in catalog:**
- `streamid_guid_rejection_stage` (scalar count, narrow filter, 1h window)
- `fleet_error_top15` (FACET, broad filter, 12h, LIMIT 15 — note this one is flaky due to query cost; calibrate carefully)
- `nonetype_unpack_top_facet` (FACET on specific error pattern)

**Gotchas:**
- NRDB:1107005 SERVER_ERROR = query exceeded backend cost budget. Tighten WHERE or window. There's no warning before this hits — you discover it when the signal goes intermittent.
- `FACET <field>` causes nerdgraph to echo the facet column back as a same-named field in each row. Our `parse_nr_results()` handles this, but if you're inspecting raw responses don't be confused by `{"facet": "x", "container_name": "x", "count": 10}`.
- `count(*)` returns 0 if no matching events; the signal evaluates as scalar 0 (not None). To distinguish "0 events" from "query failed," check the sink JSONL.

### nr_k8s_container_sample — per-container metrics

**When to use:** OOM kills, container CPU/memory utilization, restart counts, per-container fingerprinting.

**NRQL shape:**
```sql
SELECT count(*)
FROM K8sContainerSample
WHERE clusterName='Connector-EKS' AND <condition>
[FACET containerName]
SINCE <window>
```

**Useful fields** (verify in NR's data explorer — schema drifts):
- `reason='OOMKilled'` for OOM events
- `containerName`, `podName`, `deploymentName`, `namespaceName`
- `requestedCpuCoresUtilization` (% of request) and `memoryWorkingSetUtilization` (% of working set)
- `containerRestartCount` (cumulative; use `latest()` not `count()`)

**Threshold calibration tip:** OOMKills baseline is fleet-and-cluster-specific. Connector-EKS baseline as of 2026-04 is ~100/24h; spike to 700+ would have caught the [[2026-04-23_oom-surge-connector-limit-drift]] incident. Re-pull the 7d distribution every quarter or after major fleet changes.

**Examples in catalog:**
- `fleet_oomkills_24h` (scalar, 24h window — the canonical fleet-health signal)
- `fleet_new_oom_offender` (FACET — top OOM-ing containers, paired with `new_pattern` rule)
- `deployment_cpu_pct_vms` (scalar percent, paired with deployment filter)

**Gotchas:**
- Cluster-CPU/memory utilization fields changed naming late-2025 — old field names like `cpuUsedCoresVsLimitPercent` return null. Use `requestedCpuCoresUtilization` / `memoryWorkingSetUtilization` instead. Fixed during Phase 1b ([[2026-04-24_dashboard-1b-continuation]]).
- `K8sContainerSample` updates every ~30s but NR can lag a minute or two; don't set windows < 5min.

### nr_k8s_node_sample — node-level metrics

**When to use:** cluster-wide CPU/mem averages, node count, NotReady detection, capacity tracking.

**NRQL shape:**
```sql
SELECT average(allocatableCpuCoresUtilization)
FROM K8sNodeSample
WHERE clusterName='Connector-EKS'
SINCE 1 hour ago
```

**Useful fields:**
- `allocatableCpuCoresUtilization`, `allocatableMemoryUtilization` — % of allocatable used (cluster-wide, average works well)
- `nodeName` (FACET for per-node breakouts)
- `condition`, `status` — for NotReady detection (combination of `condition='Ready' AND status='True'`)
- `uniqueCount(nodeName)` — node count for fleet-size drift

**Examples in catalog:**
- `cluster_cpu_pct_avg`
- `cluster_memory_pct_avg`

### cw_log — CloudWatch Logs (Lambda log fingerprints)

**When to use:** counting specific log-line fingerprints in a Lambda log group when (a) you don't have NR ingesting the same logs, or (b) you want the canonical AWS-side count for release-gate purposes.

**boto3 shape:**
```python
client = boto3.Session(profile_name=profile).client("logs", region_name="us-west-2")
paginator = client.get_paginator("filter_log_events")
pages = paginator.paginate(
    logGroupName="/aws/lambda/<fn-name>",
    startTime=<ms_since_epoch>,
    endTime=<ms_since_epoch>,
    filterPattern="<fingerprint>",
)
count = sum(len(p.get("events", [])) for p in pages)
```

**IAM permission needed** (add to the `dashboard-check-readonly` policy):
```json
{
  "Sid": "ReadCWLogsForMyNewSignal",
  "Effect": "Allow",
  "Action": "logs:FilterLogEvents",
  "Resource": "arn:aws:logs:us-west-2:388576304176:log-group:/aws/lambda/<fn-name>:*"
}
```

**Always resource-scope** to the specific log group. Do not add `logs:DescribeLogGroups` on `*` unless you actually need it — that's a list-action and dramatically widens blast radius.

**Filter-pattern syntax:**
- Plain text matches anywhere in the message: `"get_sites HTTP"`
- JSON field match: `'{ $.level = "ERROR" }'`
- Regex: not supported by `filter-log-events` (use `start_query` + Logs Insights for regex)

**Calibration tip:** the postmortem fingerprint isn't always the runtime fingerprint. Verify your filter pattern matches real log lines by running a `--max-items 5` query against the live log group before committing. Lesson from 2026-04-23: the postmortem said "Fetched N contracts"; real logs said "get_sites HTTP."

**Examples in catalog:**
- `onboarder_activity_us` (count of "get_sites HTTP" in 1h — the canonical activity-marker signal)

### cw_metric — CloudWatch Metrics

**When to use:** Lambda Invocations / Errors / Duration, SQS queue depth, RDS connections, ELB request count — anything published as a CW metric.

**boto3 shape:**
```python
resp = client.get_metric_statistics(
    Namespace="AWS/Lambda",
    MetricName="Invocations",
    Dimensions=[{"Name": "FunctionName", "Value": "<fn-name>"}],
    StartTime=<datetime utc>,
    EndTime=<datetime utc>,
    Period=3600,             # seconds; align to your window
    Statistics=["Sum"],      # or Average / Maximum / Minimum / SampleCount
)
value = resp["Datapoints"][0]["Sum"] if resp["Datapoints"] else 0.0
```

**IAM:** the `dashboard-check-readonly` policy already covers CW metrics (`cloudwatch:GetMetricStatistics` on `*`). No policy edit needed for new metric signals.

**Window+Period mapping:**
- 1h window → Period=3600 (one datapoint)
- 24h window → Period=86400 (one datapoint), or Period=3600 (24 datapoints, sum if you want total)

**Pair with cw_log** for activity-marker anti-pattern detection: a Lambda with non-zero Invocations but zero log activity = silent early return (the [[2026-04-23_postmortem-onboarder-healthcheck]] fingerprint). Set `pair_with: "<cw_metric_signal_id>"` on the cw_log signal and add `activity_marker_antipattern` to its `regression_rules`.

**Examples in catalog:**
- `onboarder_lambda_invocations_us` (paired with `onboarder_activity_us`)

### git_local — Per-repo working-tree metrics (minipc only)

**When to use:** any code-health metric computed by walking a checked-out working tree on the minipc — TODO/FIXME counts, lint findings, complexity hotspots, version pins parsed from `pyproject.toml`. The repos to iterate over come from `~/.config/minipc-repo-cron/repos.json` (the same file `git-fetch-major-repos.sh` consumes; phase-13 deploys it). The hourly `collect-repos.timer` keeps the working trees fresh.

**Shape:** every `git_local` signal emits a FACET dict `{repo_name: value}`. `repo_todo_fixme_count` is the canonical example.

**Adding one:**
1. Write a metric function in `collect.py` taking `repo_path: Path`, returning a scalar:
   ```python
   def repo_my_metric(repo_path: Path) -> int | float:
       # Read the working tree at `repo_path`. Use subprocess for tools like rg / ruff / radon.
       ...
   ```
2. Register it in `GIT_LOCAL_DISPATCH[<signal_id>] = repo_my_metric`.
3. Add the signal entry with `source: "git_local"`, optional `repos: ["all"]` (default) or `repos: ["vms-connector", "actuate-libraries"]` to scope.
4. The collector handles iteration, missing-tree skip, and FACET assembly.

**Gotchas:**
- **Partial clones** (`--filter=blob:none`). Tools that read files lazily (rg, ruff, radon) work transparently — the first read triggers a blob fetch, then it caches. Tools that walk full history (`git log -p` for blame-based metrics) may force per-blob downloads — slow on first run.
- **Don't mutate the canonical clones.** The `git-fetch-major-repos.sh` timer owns `~/work/<repo>/`. If a metric needs to install deps or run pre-commit, do it in `/tmp/<repo>-analysis/` or with `git worktree add`.
- **Laptop dev runs.** `repos.json` doesn't exist on the laptop; `collect_git_local_signals` skips with a warning. Signals run only on the minipc.
- **Tooling installs.** Stuff that isn't in the base image (`ruff`/`radon`/`vulture`) needs to be added to `phase-06-base-tooling.sh` *before* the signal lands, otherwise the metric function fails with `FileNotFoundError`.

**Examples in catalog:**
- `repo_todo_fixme_count` (FACET dict — TODO + FIXME counts per repo via ripgrep)
- `repo_actuate_{frames,filters,pullers}_pin` (FACET dict — per-repo pin specs; parser handles pyproject.toml + requirements.txt; informational because version-string FACETs can't be thresholded; relies on the `new_pattern` regression rule to flag drift)

**FACET-of-strings & None handling:** the `git_local` collector treats a per-repo `None` return as "metric N/A for this repo" and drops the entry from the FACET dict (e.g. unpinned packages don't show as `null` rows). FACET values can be strings — they render as plain text in the drilldown table; `classify` returns `informational` when no thresholds are set.

### ce_daily — Cost Explorer

**When to use:** spend tracking by service / dimension. Daily total, week-over-week delta, top-N services by spend.

**boto3 shape:**
```python
client = boto3.Session(profile_name=profile).client("ce", region_name="us-east-1")  # CE only lives here
resp = client.get_cost_and_usage(
    TimePeriod={"Start": "<YYYY-MM-DD>", "End": "<YYYY-MM-DD>"},
    Granularity="DAILY",
    Metrics=["UnblendedCost"],
    Filter={"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Simple Storage Service"]}},
)
amount = float(resp["ResultsByTime"][0]["Total"]["UnblendedCost"]["Amount"])
```

**IAM:** `dashboard-check-readonly` already has `ce:GetCostAndUsage` on `*`.

**Quirks:**
- CE region is **always us-east-1** regardless of where your data lives. Setting region_name elsewhere doesn't fail but is silently re-routed.
- "Yesterday" in CE means the most recently *closed* day — today's spend is incomplete and reported as `Estimated: true`. For daily-total signals use yesterday-to-today (closed) or accept the estimate flag.
- CE has its own latency: figures stabilize ~24h after the day closes. Don't compare today's CE number to yesterday's NR number and expect them to match within 1%.

**Examples in catalog:**
- `cost_s3_daily_total`

## Promoting a stub to enabled

The catalog has 49 signals total but only 21 enabled today. To promote a `enabled: false` stub:

1. **Run the underlying query manually** and confirm it returns sane data (catalog stubs are sometimes drafted against assumed schemas that drift).
2. **Recalibrate thresholds** with current 7d distribution — historical thresholds drift fast.
3. **Flip `enabled: true`**.
4. **Trigger a manual run** to verify the new signal renders without error: `~/bin/run-dashboard-check.sh` on the minipc, or `./run.sh collect+render` locally.
5. **Add a replay test** if there's an incident in `would_have_caught` that should anchor the signal.

## Calibration cookbook (cross-cutting)

Threshold calibration is the part most often skipped, then bites. Three patterns:

| Signal type | Calibration approach |
|---|---|
| **Above-thresholds** (errors, OOM, queue-depth) | Pull 7d TIMESERIES, set `yellow_above = p75`, `red_above = p95`. Skew higher if pre-existing seasonality (cron jobs, batch windows) is real. |
| **Below-thresholds** (activity, invocations, frame-rate) | Same data, invert: `yellow_below = p25`, `red_below = p5`. The `silent_drop` regression rule is a *separate* check on top of these. |
| **Cluster utilization** (% used) | Static thresholds — yellow at 60%, red at 80% — UNLESS the workload is steady-state high (e.g. inference). For steady-state, baseline at p50 + 2σ. |

After landing a new signal, watch its sink for 7 days. If it never goes yellow/red, thresholds are too loose — tighten. If it goes yellow daily, thresholds are too tight — loosen. Recalibrate quarterly or after major workload changes.

## Skill reference

`/dashboard-check` and the underlying scripts:

- `~/.claude/skills/dashboard-check/SKILL.md` — high-level skill description (read for the dashboard's mental model)
- `~/.claude/skills/dashboard-check/config/signals.json` — the catalog (this is what you edit to add a signal)
- `~/.claude/skills/dashboard-check/collect.py` — fetch step (NR + AWS)
- `~/.claude/skills/dashboard-check/render.py` — classify + html step
- `~/.claude/skills/dashboard-check/run.sh` — entry wrapper for collect / render / sink
- `~/bin/run-dashboard-check.sh` (on minipc) — cron entry point — calls run.sh collect + render
- IAM auth setup for the AWS side: [[2026-04-27_iam-rolesanywhere-minipc]]

## Future enhancements (not blocking signal adds)

- **Drill-down detail pages** ([[mark-todos]] §12i task #60) — the main dashboard summarizes (e.g. "15 items"); detail pages should expose every facet, regression annotation, sparkline, prior-day comparison.
- **gh_* signal source** — currently catalog-only stubs for SSL cert expiry + CI health. Activating requires a `gh` token on the minipc + a dispatcher in collect.py.
- **`/add-signal` skill** — interactive wizard that walks through the 6-step common workflow, scaffolds the signals.json entry + the test fixture. Worth building once the catalog crosses ~50 signals and the manual workflow becomes friction.
- **Sink-aware threshold derivation** — auto-suggest yellow/red thresholds from the sink's historical observations after 14d of data. Replaces manual TIMESERIES calibration.

## Related

- [[2026-04-27_iam-rolesanywhere-minipc]] — AWS auth setup that powers the cw_*/ce_* paths
- [[2026-04-23_dashboard-sketch]] — original design rationale for /dashboard-check
- [[2026-04-24_dashboard-1b-continuation]] — Phase 1b pickup with deeper notes on per-signal calibration
- [[2026-04-23_postmortem-onboarder-healthcheck]] — the incident that motivated the activity-marker / invocation pairing pattern
- [[2026-04-23_release-acceptance-criteria]] — process rule extension that codifies "track config-surface drift over time"
- [[skill-dashboard-check]] — the skill SKILL.md
