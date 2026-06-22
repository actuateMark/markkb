---
type: concept
topic: personal-notes
tags: [dashboard, signals, operational, offboarding, monitoring]
created: 2026-06-22
updated: 2026-06-22
author: kb-bot
---

# Dashboard Signals Catalog + How-To

Operating and extending the `/dashboard-check` operational dashboard after Mark's
offboarding (last day 2026-06-26). This is the **silent-regression detection** surface
for the Actuate fleet: a static-HTML dashboard rebuilt on a firebat cron timer,
classifying each signal green / yellow / red against thresholds and a small set of
regression rules.

Authoritative config: `~/.claude/skills/dashboard-check/config/signals.json`.
Design background + coverage matrix: [[2026-05-05_operational-dashboard-context]].
Offboarding/persistence handoff: [[2026-06-22_offboarding-plan]] (Workstream A re-homes
the firebat identities that back the AWS/NR/GH-sourced signals).

> **Load-bearing principle:** `Errors=0` / `200 OK` / `Invocations>0` are NOT health
> signals. **Activity-marker log lines + downstream side effects are.** Most of the
> catalog is built around proving that real work happened, not that nothing errored.

---

## 1. Where to view it

- **Live API (current values/statuses):** `curl -fsS http://mork-firebat/app/api/observations`
  — JSON: `summary` (n_signals, n_green/yellow/red/error/informational, overall) + per-signal `signals{}`.
- **Web dashboard:** `http://mork-firebat/app/` (and `http://mork-firebat/dashboard/` Caddy alias).
- **On-disk snapshots:** `~/Documents/worklog/dashboard/<YYYY-MM-DD>/index.html`, with a
  `latest` symlink. Components, `regressions.html`, and a machine-readable `data.json` per snapshot.
- **Append-only sink:** `~/Documents/worklog/dashboard/sink/observations.jsonl` (history; see §3).

Live state at catalog time (2026-06-22): **129 signals evaluated** — 86 green, 8 yellow,
7 red, 3 error, 25 informational; overall = red (driven by a `new_pattern` OOM offender).
The 129 is the rendered total including per-facet rows and prior-run sink fallbacks; the
JSON `signals.json` catalog itself defines the source signal set below.

---

## 2. The signal catalog (grouped by component)

Each row: real signal `id` from `signals.json` · what it measures · severity threshold
or regression basis · source. `source` legend: `cw_log`/`cw_metric`/`cw_sqs`/`cw_lambda` =
AWS CloudWatch CLI under `AWS_PROFILE=prod`; `nr_log`/`nr_k8s_*`/`nr_transaction`/`nr_issues` =
New Relic NRQL via MCP; `ce_daily` = AWS Cost Explorer (cached aggregate); `git_local` =
local git/lint tooling over `~/work/<repo>`; `tls_cert` = Python TLS probe; `minipc_local` =
local shell on firebat/minipc; `external` = written by a separate firebat timer into the sink.
`(off)` = `enabled: false` in the catalog (defined but not executed).

### autopatrol_onboarder
| id | measures | threshold / basis | source |
|---|---|---|---|
| `onboarder_activity_us` | `get_sites HTTP` activity-marker lines, US onboarder Lambda | yellow<30, red<5 /h; silent_drop + activity_marker_antipattern | cw_log |
| `onboarder_lambda_invocations_us` | US onboarder invocation count (pair anchor) | yellow<8, red<2 /h | cw_metric |
| `onboarder_activity_eu` *(off)* | EU onboarder activity marker (`Fetched`) | yellow<5, red<1 /h | cw_log |
| `onboarder_lambda_invocations_eu` *(off)* | EU onboarder invocations | yellow<8, red<2 /h | cw_metric |
| `onboarder_healthcheck_hotfix_in_effect` | boolean: 2026-04-23 healthcheck-warning hotfix still present | red<1 (fires on revert) | git_local |

### autopatrol_cleanup
| id | measures | threshold / basis | source |
|---|---|---|---|
| `cleanup_lambda_dlq_depth` | cleanup-Lambda SQS dead-letter depth (should be 0) | yellow>0, red>5 | cw_sqs |
| `cleanup_lambda_errors` | ERROR log count, cleanup Lambda | yellow>3, red>10 /h | cw_log |
| `cleanup_lambda_would_patch_rate` | `would PATCH` dark-mode lines (should be ~0 post-flip) | yellow>5, red>15 /h; new_pattern | cw_log |
| `cleanup_lambda_actual_disable_rate` | `disabled admin schedule` real PATCH fires (audit metric) | yellow>10, red>30 /h; new_pattern | cw_log |
| `cleanup_lambda_anomaly_reset_rate` | schedules at threshold but not disabled (safety-net firing) | yellow>10, red>30 /h; new_pattern | cw_log |
| `cleanup_lambda_anomaly_repeat_offenders_7d` *(off)* | distinct schedule_ids anomaly-resetting 2+ times / 7d | yellow>1, red>5; new_pattern | cw_log |
| `cleanup_lambda_main_queue_depth` | cleanup-Lambda SQS main-queue depth | yellow>100, red>500 | cw_sqs |
| `cleanup_lambda_event_source_mapping_state` | SQS event-source mapping Enabled (1/0) | red<1 | cw_lambda |
| `cleanup_chm_emit_24h` *(off)* | upstream `emit_no_patrols_signal` count | yellow<10, red<1 /24h; silent_drop | nr_log |
| `patrol_exit_emit_rate` *(off)* | fleet-wide `patrol_exit ... no_patrols` | yellow<50, red<5 /24h; silent_drop | nr_log |

### autopatrol_server
| id | measures | threshold / basis | source |
|---|---|---|---|
| `autopatrol_server_patrol_summary_rate` | `Generating patrol summary` lines (silent-break detector) | yellow<2, red<1 /h; silent_drop | nr_log |
| `autopatrol_server_error_rate` | ERROR lines (structured + text-format) | yellow>5, red>20 /h | nr_log |
| `autopatrol_server_cnctnfail_rate` | camera connection-failure summary path (PR #26) | yellow>3, red>10 /h | nr_log |

### vms-connector
| id | measures | threshold / basis | source |
|---|---|---|---|
| `fleet_oomkills_24h` | fleet-total OOMKills/day (baseline ~100) | yellow>200, red>350; baseline_drift | nr_k8s_container_sample |
| `fleet_new_oom_offender` | top-15 OOMKill containers (new entrant) | new_pattern (critical → red) | nr_k8s_container_sample |
| `fleet_error_top15` | top-15 containers by ERROR count | new_pattern + baseline_drift (critical) | nr_log |
| `streamid_guid_rejection_stage` | streamId/Guid rejection on :stage (AP/VCH bug; should be 0) | yellow>0, red>5 /12h | nr_log |
| `connector_dummy_model_fallback_24h` | distinct autopatrol containers logging dummy-model fallback | yellow>0, red>5 /24h; silent_drop_inverse (critical) | nr_log |
| `connector_no_patrols_to_run_24h` | distinct containers logging empty patrol queue | yellow>0, red>3 /24h; silent_drop_inverse | nr_log |
| `nonetype_unpack_top_facet` | `cannot unpack non-iterable NoneType` FACET (locus shift) | new_pattern | nr_log |
| `connector_deploy_error_rate` *(off)* | connector-deploy ERROR rate | yellow>100, red>1000 /12h; baseline_drift | nr_log |
| `deployment_cpu_pct_vms` | vms-connector avg CPU (% of request) | yellow>120, red>200; baseline_drift | nr_k8s_container_sample |
| `deployment_memory_pct_vms` | vms-connector avg memory (% of limit WSS) | yellow>75, red>90; baseline_drift | nr_k8s_container_sample |
| `vch_billing_emit_6h` | VCH `site_product_ended` events (SIGTERM-loss class, PR #1667) | yellow<50, red<10 /6h; silent_drop_inverse (critical) | nr_log |
| `chm_billing_emit_6h` | CHM billing events (highest-volume class) | yellow<8000, red<2000 /6h; silent_drop_inverse (critical) | nr_log |
| `autopatrol_billing_emit_6h` | AutoPatrol (non-VCH) billing events (PR #1663) | yellow<50, red<1 /6h; silent_drop_inverse | nr_log |
| `analytics_billing_emit_6h` | Analytics site-manager billing events (largest pod count) | yellow<30000, red<8000 /6h; silent_drop_inverse (critical) | nr_log |
| `fleet_billing_emit_6h` | fleet-wide `site_product_ended` top-level sanity | yellow<50000, red<15000 /6h; silent_drop_inverse (critical) | nr_log |
| `ap_empty_metrics_warn_6h` | AP/VCH empty plain_metrics warns (connector-side) | yellow>0, red>50 /6h | nr_log |

### actuate-admin
| id | measures | threshold / basis | source |
|---|---|---|---|
| `ap_metrics_admin_fallback_24h` | admin `ap_metrics_fallback_all` (upstream pair to ap_empty_metrics) | yellow>0, red>50 /24h | nr_log |
| `deployment_cpu_pct_admin` *(off)* | actuate-admin avg CPU | yellow>75, red>90; baseline_drift | nr_k8s_container_sample |
| `deployment_memory_pct_admin` *(off)* | actuate-admin avg memory | yellow>75, red>90; baseline_drift | nr_k8s_container_sample |

### alert-pipeline
| id | measures | threshold / basis | source |
|---|---|---|---|
| `queue_evalink_errors_12h` | Evalink consumer ERROR rate (recalibrated 2026-04-24) | yellow>1200, red>1800 /12h | nr_log |
| `queue_eagle_eye_errors_12h` *(off)* | Eagle Eye consumer ERROR rate | yellow>20, red>100 /12h | nr_log |
| `smtp_frame_receiver_errors_12h` *(off)* | smtp-frame-receiver ERROR rate | yellow>50, red>500 /12h; baseline_drift | nr_log |
| `queue_eagle_eye_volume_12h` | Eagle Eye total log volume (silent-stop) | yellow<500, red<50 /12h; silent_drop | nr_log |
| `queue_evalink_volume_12h` | Evalink total log volume | yellow<500, red<50 /12h; silent_drop | nr_log |
| `frontel_puller_volume_12h` | frontel-puller log volume | yellow<50, red<5 /12h; silent_drop | nr_log |
| `clips_smtp_worker_volume_12h` | clips-smtp-worker log volume (low-volume) | yellow<5, red<0 /12h | nr_log |
| `smtp_frame_receiver_volume_12h` | smtp-frame-receiver volume (high-throughput) | yellow<5M, red<100K /12h; silent_drop + baseline_drift | nr_log |
| `clips_prod_volume_12h` | clips-prod volume (bimodal) | yellow<3M, red<500K /12h; silent_drop + baseline_drift | nr_log |
| `deployment_cpu_pct_alert_pipeline` *(off)* | alert-pipeline avg CPU | yellow>75, red>90; baseline_drift | nr_k8s_container_sample |
| `deployment_memory_pct_alert_pipeline` *(off)* | alert-pipeline avg memory | yellow>75, red>90; baseline_drift | nr_k8s_container_sample |

### inference-api
| id | measures | threshold / basis | source |
|---|---|---|---|
| `deployment_cpu_pct_inference` | inference-api avg CPU (% request) | yellow>120, red>200; baseline_drift | nr_k8s_container_sample |
| `deployment_memory_pct_inference` | inference-api avg memory (% limit WSS) | yellow>75, red>90; baseline_drift | nr_k8s_container_sample |
| `inferenceapi_prod_errors_us_west_2` | InferenceAPI-prod Lambda Errors, us-west-2 | yellow>0, red>50 /h; silent_drop_inverse | cw_metric |
| `inferenceapi_prod_errors_eu_west_1` | InferenceAPI-prod Lambda Errors, eu-west-1 | yellow>0, red>50 /h; silent_drop_inverse | cw_metric |
| `nr_apm_apdex_inference` *(off)* | Apdex (t:0.5) | yellow<0.9, red<0.75; baseline_drift | nr_transaction |
| `nr_apm_error_rate_inference` *(off)* | APM error rate | yellow>2, red>5 % | nr_transaction |
| `nr_apm_throughput_inference` *(off)* | requests/min | silent_drop + baseline_drift | nr_transaction |
| `nr_apm_p95_latency_inference` *(off)* | p95 latency | baseline_drift | nr_transaction |
| `nr_apm_p99_latency_inference` *(off)* | p99 latency | baseline_drift | nr_transaction |

> **Note:** the 3 inference-api E2M billing signals (`inferenceApi.billing.requests`,
> `inferenceApi.billing.frames`, `inferenceApi.inference.slices`) from
> [[2026-05-14_inference-api-e2m-rules]] are still on the §9 to-wire list — they are NOT
> yet in `signals.json`. Wiring them is the open Phase-1b item; the standing discipline in §4
> applies to all future E2M rules.

### ecr-lifecycle
| id | measures | threshold / basis | source |
|---|---|---|---|
| `ecr_pruning_risk_count` | image-backed Lambdas whose live digest would be pruned (should be 0) | yellow>0, red>0; critical | external (`~/bin/ecr-lifecycle-audit`) |
| `ecr_dangerous_policies` | ECR repos with overly-broad expire rules | yellow>0, red>0; new_pattern | external (`~/bin/ecr-lifecycle-audit`) |

### k8s-cluster
| id | measures | threshold / basis | source |
|---|---|---|---|
| `cluster_cpu_pct_avg` | cluster-wide avg CPU (% allocatable) | yellow>60, red>80; baseline_drift | nr_k8s_node_sample |
| `cluster_memory_pct_avg` | cluster-wide avg memory | yellow>60, red>80; baseline_drift | nr_k8s_node_sample |
| `cluster_pending_pods` | pods stuck Pending | yellow>60, red>100; baseline_drift | nr_k8s_pod_sample |
| `cluster_node_count` | total node count (baseline ~110) | yellow<80/red<50/yellow>200; baseline_drift | nr_k8s_node_sample |
| `cluster_node_not_ready` | nodes Ready != True | yellow>0, red>2 | nr_k8s_node_sample |
| `cluster_deployment_unavailable` | sum(desired − available) replicas | yellow>5, red>15; baseline_drift | nr_k8s_deployment_sample |
| `cluster_pod_restarts_5m` *(off)* | restart-count delta /5m | yellow>5, red>15; baseline_drift | nr_k8s_container_sample |
| `k8s_hpa_saturation` *(off)* | HPAs at max replicas | new_pattern | nr_k8s_hpa_sample |
| `argocd_out_of_sync_count` *(off)* | ArgoCD apps out-of-sync | yellow>0, red>3 | cw_log |

### cross-cutting
| id | measures | threshold / basis | source |
|---|---|---|---|
| `iam_access_denied_cluster_wide` | AccessDenied / not-authorized lines, faceted by container | yellow>1, red>10 /12h; new_pattern (critical) | nr_log |
| `nr_issues_12h_count` *(off)* | NR Issues opened /12h | yellow>40, red>80; baseline_drift | nr_issues |
| `nr_issues_critical_12h` *(off)* | CRITICAL NR Issues /12h | yellow>10, red>30 | nr_issues |

### infra-health
| id | measures | threshold / basis | source |
|---|---|---|---|
| `ssl_cert_days_until_expiry` | TLS days-to-expiry per customer-facing host (FACET) | yellow<21, red<7 days; silent_drop | tls_cert |

### minipc-host
| id | measures | threshold / basis | source |
|---|---|---|---|
| `minipc_failed_user_units` | failed `--user` systemd units (FACET) | yellow>0, red>2; new_pattern | minipc_local |
| `minipc_failed_system_units` | failed system-wide units (FACET) | yellow>1, red>3; new_pattern | minipc_local |
| `minipc_unit_starts_24h` | tracked-timer fire count /24h | yellow<200, red<100; silent_drop | minipc_local |

### billing
| id | measures | threshold / basis | source |
|---|---|---|---|
| `billing_production_unbilled_cams` | production cams running billable products not in usage_monthly | yellow>500, red>1500 | minipc_local |
| `billing_reconcile_residual` | cams not landing in exactly one pipeline bucket | yellow>0, red>10 | minipc_local |
| `billing_reconcile_freshness` | reconciliation JSON sinks written /24h (expect 1) | yellow<1, red<1 | minipc_local |

### cost
| id | measures | threshold / basis | source |
|---|---|---|---|
| `cost_total_daily` | total prod-account daily spend (~$7,788 baseline) | yellow>9750, red>11700; baseline_drift | ce_daily |
| `cost_top_services_daily` | top-15 AWS services by spend (FACET) | new_pattern + baseline_drift | ce_daily |
| `cost_ec2_compute_daily` | EC2 Compute (largest line, ~$4663) | yellow>5800, red>7500; baseline_drift | ce_daily |
| `cost_ec2_other_daily` | EC2-Other (NAT/EBS/transfer, ~$445) | yellow>700, red>1200; baseline_drift | ce_daily |
| `cost_dynamodb_daily` | DynamoDB (~$573) | yellow>750, red>1100; baseline_drift | ce_daily |
| `cost_ecs_daily` | ECS Fargate (~$181) | yellow>280, red>500; baseline_drift | ce_daily |
| `cost_rds_daily` | RDS (~$152) | yellow>230, red>400; baseline_drift | ce_daily |
| `cost_vpc_daily` | VPC / NAT-GW (~$144) | yellow>220, red>350; baseline_drift | ce_daily |
| `cost_aws_config_daily` | AWS Config (~$129) | yellow>200, red>400; baseline_drift | ce_daily |
| `cost_cloudwatch_daily` | CloudWatch (~$93) | yellow>150, red>250; baseline_drift | ce_daily |
| `cost_elb_daily` | ELB/ALB/NLB (~$71) | yellow>110, red>180; baseline_drift | ce_daily |
| `cost_glue_daily` | Glue (~$51) | yellow>100, red>250; baseline_drift | ce_daily |
| `cost_sqs_daily` | SQS (~$44) | yellow>80, red>150; baseline_drift | ce_daily |
| `cost_lambda_daily` | Lambda (~$24) | yellow>60, red>150; baseline_drift | ce_daily |
| `cost_s3_daily_total` | total S3 daily (~$1106) | yellow>1500, red>2500; baseline_drift | ce_daily |
| `cost_s3_breakdown_daily` | S3 by USAGE_TYPE (FACET: tier1/storage/tier3/tier2/transfer) | new_pattern + baseline_drift | ce_daily |
| `cost_s3_tier1_daily` | S3 Tier1 PUT/COPY/LIST (~$496) | yellow>700, red>1000; baseline_drift | ce_daily |
| `cost_s3_storage_daily` | S3 storage GB-month (~$399) | yellow>500, red>700; baseline_drift | ce_daily |
| `cost_s3_tier3_daily` | S3 Tier3 replication/lifecycle (~$130; the $44k/yr line) | yellow>200, red>400; baseline_drift | ce_daily |

### code-health
| id | measures | threshold / basis | source |
|---|---|---|---|
| `repo_todo_fixme_count` | TODO+FIXME per repo (FACET) | yellow>25; baseline_drift | git_local |
| `repo_actuate_frames_pin` | per-repo `actuate-frames` pin (FACET; drift detector) | new_pattern | git_local |
| `repo_actuate_filters_pin` | per-repo `actuate-filters` pin | new_pattern | git_local |
| `repo_actuate_pullers_pin` | per-repo `actuate-pullers` pin (adoption tracker) | new_pattern | git_local |
| `repo_radon_cc_hotspots` | cyclomatic-complexity hotspots (grade C+, CCN≥11) per repo | yellow>80; baseline_drift | git_local |
| `repo_ruff_unused_imports` | F401 unused-import count per repo | yellow>85; baseline_drift | git_local |
| `repo_stale_branches_count` | remote branches >60d stale per repo | yellow>65; baseline_drift | git_local |
| `repo_ci_failure_rate_pct` | CI failure % (last 50 runs) per repo | yellow>15, red>30; baseline_drift | git_local (gh) |
| `repo_open_prs_p50_age_days` | median open-PR age per repo | yellow>15, red>60; baseline_drift | git_local (gh) |
| `repo_mtm_days_p50` | median time-to-merge (last 50 PRs) per repo | yellow>1, red>3; baseline_drift | git_local (gh) |
| `repo_vulture_dead_code` | likely-dead code (vulture conf≥80) per repo | yellow>20; baseline_drift | git_local |

**Catalog totals:** ~89 signal definitions across 15 components. Components covered:
autopatrol_onboarder, autopatrol_cleanup, autopatrol_server, vms-connector, actuate-admin,
alert-pipeline, inference-api, ecr-lifecycle, k8s-cluster, cross-cutting, infra-health,
minipc-host, billing, cost, code-health. The live `/api/observations` reports **129** because
FACET signals expand and prior-run sink rows are included.

---

## 3. The sink (`observations.jsonl`)

Append-only JSONL at `~/Documents/worklog/dashboard/sink/observations.jsonl`. Helper lives
at `~/.claude/skills/dashboard-check/sink.py`. Schema doc: `sink/.schema.md` alongside the data.

**Record schema** (one JSON object per line; written by `write_observation()`):

| field | required | notes |
|---|---|---|
| `timestamp` | yes | UTC ISO-8601, `%Y-%m-%dT%H:%M:%SZ` |
| `source_skill` | yes | who wrote it — convention below |
| `component` | yes | matches the signal's `component` |
| `signal_id` | yes | the catalog id |
| `value` | yes | scalar or FACET dict |
| `status` | yes | one of `green` / `yellow` / `red` / `informational` / `error` |
| `unit` | opt | e.g. `count_per_hour`, `usd_per_day`, `facet_count` |
| `baseline` | opt | numeric baseline for the signal |
| `notes` | opt | e.g. regression detail `new_pattern:connector-47879`, or `stale (from sink…)` |
| `extras` | opt | dict; dashboard stores the signal `description` here |

**`source_skill` convention:** `/dashboard-check` writes every signal with
`source_skill="dashboard-check"`. **Other skills write their own observations with their own
identifier** (e.g. `daily-scope.fan-out`, `autopatrol-overnight-check`). The renderer's trailing
window *excludes* `source_skill == "dashboard-check"` rows when computing sparklines (to avoid
self-tailing) but *includes* them for graceful-failure fallback and trend charts. Non-dashboard
rows are what the planned Morning-summary aggregation surfaces.

**`write_observation()`** (validates, never raises; returns bool): rejects invalid status or
missing component/signal_id/source_skill, else appends one line. There's a CLI shim:
`python3 sink.py write '<json>'` and `python3 sink.py recent <hours>`. `read_recent(since_hours,
component=, signal_id=, source_skill=)` and `read_all()` are the read helpers.

---

## 4. How to ADD a new signal

Edit `~/.claude/skills/dashboard-check/config/signals.json` and append an object to the
`signals` array. Full cookbook with per-source recipes + threshold calibration:
[[2026-04-27_dashboard-signal-cookbook]].

**Required fields:** `id` (unique snake_case), `component`, `source` (one of the legend
values), `unit`, `description`, `regression_rules` (list, may be empty), `window_hours`,
`enabled` (bool).

**Per-source query field:**
- NR signals (`nr_*`): `nrql` — the NRQL string. Always scope `cluster_name='Connector-EKS'`
  (logs) / `clusterName='Connector-EKS'` (k8s samples) and FACET by `container_name`; tight
  windows; small LIMIT. (See global NR query rules.)
- CW signals (`cw_*`): `query` — the `aws` CLI invocation (run under `AWS_PROFILE=prod`).
- `ce_daily`: `query` — describes the cached Cost Explorer aggregate / classification key.
- `git_local`: `repos` (list; `["all"]` = every tracked repo) + `command`.
- `tls_cert`: `hosts` list. `minipc_local`: `command`. `external`: `writer` (the firebat timer).

**Optional fields:** `thresholds` (`yellow_above`/`red_above`/`yellow_below`/`red_below` — any
subset); `critical: true` (escalates a `new_pattern` hit from yellow → red); `pair_with` (for
the activity-marker anti-pattern); `region`; `freshness_threshold_hours` (how stale a sink value
may be before it's flagged — defaults to `window_hours × 2`); `would_have_caught` (the incident
the signal anchors to — every new signal should name one).

**Standing discipline (permanent, does not close):** *every new inference-api E2M rule ships
with a matching dashboard signal.* When you add a rule to `EventsToMetricRules.graphql` (or via
the NR UI), update `signals.json` in the **same change** — don't let a metric series exist
without a regression-aware view. Tracked at [[mark-todos]] §9; design surface
[[2026-05-14_v5-tracking-fields-e2m-design]]. (Resolve the NR account-ID question first:
graphql targets `7081731`, KB-documented primary is `3421145`.)

---

## 5. Regression rules (static threshold vs. drift)

Classification has two layers: **static thresholds** (§2 columns) via `classify()`, then
**regression rules** via `apply_regression_rules()` which can *elevate* the status. For FACET
dict values, the worst per-key classification wins.

**Implemented** (in `render.py::apply_regression_rules`):
- **`silent_drop`** — scalar today < 10% of prior-day, and prior-day > 1 → **RED**. Catches a
  normally-nonzero value falling to zero (the onboarder silent-early-return class).
- **`activity_marker_antipattern`** — paired (`pair_with`) signal where invocations > 10/h AND
  activity < 10% of invocations → **RED**. The canonical 2026-04-23 acceptance test.
- **`new_pattern`** — FACET signal where a key appears today that wasn't in the prior window →
  **YELLOW** (or **RED** if `critical: true`). Both today and prior must be dicts (avoids
  first-render false positives). Note recorded as `new_pattern:<keys>`.

**Declared in catalog but NOT yet implemented** (treated as no-ops by the rule engine; the
signal still classifies on its static thresholds):
- **`baseline_drift`** — intended 2σ-from-baseline drift detection. This is the Phase-1b
  "Regression rules 3" deliverable; many cost / resource / code-health signals declare it but
  currently rely only on their static thresholds.
- **`silent_drop_inverse`** — declared on the billing-emit and inference-error signals as the
  intended primary relative-drop detector once 7d of history accumulates; not in the rule
  function today, so those signals fire on their absolute floor thresholds.
- Chronic-offender promotion (Rules 4) — also Phase-1b, not implemented.

So today: **static thresholds + silent_drop + activity_marker_antipattern + new_pattern are
live**; baseline_drift / silent_drop_inverse / chronic-offender are catalog intent awaiting
implementation. See [[mark-todos]] §9 "Regression rules 3 + 4".

**Data-freshness handling:** if a signal can't be collected live, the renderer falls back to the
last good sink value — `sink_recent` if within `freshness_threshold_hours`, else `sink_stale`
(downgraded to informational with a `stale (...)` note); no value at all → `error`.

---

## 6. How it renders + rebuilds

- **Engine:** `~/.claude/skills/dashboard-check/render.py` + Jinja2 templates in `render/`
  (`index.html.j2`, `component.html.j2`, `macros.j2`, `regressions.html.j2`, `trends.html.j2`).
  Driven by `run.sh render --tempdir … --output-root ~/Documents/worklog/dashboard --snapshot-date …`.
- **Cron rebuild (firebat, Tier-1):** the `run-dashboard-check` systemd `--user` timer on
  `mork-firebat` (script `~/bin/run-dashboard-check.sh`) runs the collector + renderer on a
  schedule, writes the dated snapshot, updates `latest`, and appends sink rows. AWS-sourced
  signals authenticate via **IAM Roles Anywhere** (host-bound cert → role
  `dashboard-check-rolesanywhere`, account `388576304176`) — a machine identity that survives
  Mark's departure (see [[2026-06-22_offboarding-plan]] Workstream A; NR + GH credentials are the
  re-home targets there).
- **Exit codes (release-gate contract):** `0` all green · `1` ≥1 yellow · `2` ≥1 red. Release
  skills should run `/dashboard-check --gate <commit>` and BLOCK on exit 2.
- **Serving:** Caddy on firebat serves the snapshots + the `/app/` API at
  `http://mork-firebat/app/` and `http://mork-firebat/dashboard/`.

To run by hand: `/dashboard-check` (optionally `--component <name>`, `--gate <commit>`,
`--diff <date>`, `--open`).

---

## Related
- [[2026-05-05_operational-dashboard-context]] — scope, principles, coverage matrix, phasing
- [[2026-06-22_offboarding-plan]] — firebat identity re-home (backs the cron + AWS/NR/GH signals)
- [[2026-04-27_dashboard-signal-cookbook]] — full add-a-signal cookbook + per-source recipes
- [[2026-04-23_postmortem-onboarder-healthcheck]] — the incident that motivated the dashboard
- [[2026-05-14_inference-api-e2m-rules]] — the E2M signals still to wire (§4 discipline)
- [[mark-todos]] §9 — live workstream tracker (Phase 1b open items)
- Config: `~/.claude/skills/dashboard-check/config/signals.json` · Skill: `~/.claude/skills/dashboard-check/SKILL.md`
