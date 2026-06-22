---
title: "Investigation: 3.5-hour stale-code rotation after stage deploy"
type: synthesis
topic: infrastructure
tags: [connector_deployer, cronjob, kubernetes, autopatrol, image-pull-policy, rollout]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# 3.5-Hour Stale-Code Rotation After Stage Deploy

## Summary

Stage deploy of `vms-connector` commit 17bbc1b4 published to ECR at 13:10 EDT.  Pods on stage continued running the *previous* commit (101ef2c4, the sentinel-drain version) until ~16:41 EDT — **~3.5 hours of mixed old/new code**, during which deferred autopatrol alerts were silently lost.  Expected rotation window for a ~15-min-cadence CronJob is closer to 15-30 min.

## Evidence

- ECR `arm_connector_rearch:stage` updated at 13:09 EDT (confirmed via `aws ecr describe-images`). New digest, correct push.
- NR `container_image LIKE '%stage%'` pods emitted the sentinel-only log `"executor drain: all tasks completed"` until 16:41 EDT (last instance from pod `4lrcq`).  That log is unique to the pre-17bbc1b4 code path (`ActuateThreadPoolExecutor.drain()` — removed in 17bbc1b4).
- **Site-level impact:** site 35832 / IP Camera 02 showed ~50% deferred-alert delivery rate from 13:10 → 16:16 EDT (6/12 flushed alerts had no matching "AutoPatrol alert delivered" log).  Rate flipped to 100% after 16:41 EDT.

## Why this happened (hypotheses, ordered by likelihood)

**1. CronJob specs aren't upserted by the deployer.** `connector_deployer/src/command.py:167-178` `create_batch()` only calls `create_namespaced_cron_job` — it does not catch `AlreadyExists` and patch.  Compare with `reboot_deployment` (line 153) which correctly replaces and falls back to create.  Consequence: once a site's CronJob is created, any subsequent change to `cronjob.py` template (imagePullPolicy, resource limits, annotations, etc.) never reaches it until the site is manually re-deployed.

**2. `imagePullPolicy: Always` may not actually be set on long-lived CronJobs.** The template at `connector_deployer/src/yaml/cronjob.py:48` has `imagePullPolicy: Always` and has since Jan 2024.  But per (1), CronJobs created before Jan 2024 or patched out-of-band might have `IfNotPresent`.  Would need `kubectl get cronjob -n rearchitecture <site> -o yaml` to confirm.

**3. Node-local image digest cache + tag reuse.** Even with `imagePullPolicy: Always`, pods only re-pull if the remote digest changed.  If Karpenter node-provisioning or spegel-image-warmer serves a stale digest for `:stage`, pods on that node keep running old code.  `spegel-image-warmer` is in the cluster (`deployments/applications/spegel-image-warmer/`) — worth checking if it's pre-warming stale tags.

## Observations consistent across all three hypotheses

- `create_namespaced_cron_job` returns `AlreadyExists` silently (no logging).  Any ongoing template drift would be invisible.
- `create_chm_cronjob` in `methods.py:208` uses delete-then-create pattern, which *does* force a fresh CronJob — but only when the deployer is *triggered* for that site (e.g., via `actuate_admin` site config update).  A code-only deploy on `vms-connector` does not trigger deployer re-runs.
- AutoPatrol runs are short-lived pods (~2-5 min).  Once CronJob spec is refreshed, rotation should be within one cadence cycle.  The 3.5-hour lag is not explained by pod runtime.

## Operational impact

- **Silent alert loss during deploy window.**  For the autopatrol deferred-alert path specifically, 6 real person-detection alerts on site 35832 were dropped over ~3 hours without any error log (see `[[2026-04-16_deferred-alert-race-condition]]`).  Other sites with tag-zone configs likely saw proportional loss.
- **Unpredictable rollout timing.**  Any fix that depends on a code change takes effect on an unknown schedule — can't say "fix is live after X minutes" with confidence.
- **Invisible config drift.**  If only new CronJobs get template updates, the fleet silently diverges over time.  Changes to resource limits, tolerations, or security policies intended for "all connector CronJobs" only cover the subset created/recreated since the change.

## Recommended Actions (for a ticket on `connector_deployer`)

1. **Make `create_batch` an upsert.**  Catch `AlreadyExists` (409 Conflict) and fall back to `replace_namespaced_cron_job` — mirror the pattern in `reboot_deployment`.  Single-line-of-defense fix.
2. **Add a reconcile job.**  Nightly (or on-demand) task that iterates every connector CronJob in `rearchitecture` / `connector` namespaces, regenerates from current template + config, and patches if drift is detected.  Surfaces drift to observability.
3. **Post-deploy validation step.**  After a vms-connector image push, a CI check that queries ECR for the new digest + compares against the digest actually pulled by stage pods (e.g., via NR `container_image_id` attribute).  Fail the deploy if not reconciled within N minutes.
4. **Investigate spegel-image-warmer behavior with mutable tags** (`:stage`, `:latest`).  Confirm it invalidates its cache when the underlying digest changes.

## Severity

**Medium-to-high.**  Silent alert loss is already a known-hazardous failure mode — we have a dedicated investigation for it in the autopatrol topic.  This issue multiplies any such hazard by the length of the rotation window.  Worth cutting a ticket but not a P0 — the workaround (wait out the rotation + [[watch-entity|watch]] NR) is viable short-term.

## Related Notes

- [[2026-04-16_deferred-alert-race-condition]] — the investigation that uncovered this
- [[core-repo-suite]] — `connector_deployer` listed as locally cloned
