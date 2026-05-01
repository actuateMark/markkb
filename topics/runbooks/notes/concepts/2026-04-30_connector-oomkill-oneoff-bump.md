---
title: "Runbook: Connector pod OOMKill — one-off limit bump"
type: concept
topic: runbooks
tags: [runbook, vms-connector, oomkill, kubernetes, vpa, memory, fleet]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
---

# Connector pod OOMKill — one-off limit bump

## When this applies

A specific `connector-<site_id>` pod is appearing in the dashboard's `fleet_new_oom_offender` top-15 and OOMKilling repeatedly (≥10/24h). You need it back online today. The fleet-wide fix (restoring the VPA min-memory floor) is tracked in mark-todos §18 — this runbook is the per-incident triage you run while §18 is in flight.

Real precedents: connector-20628 (2026-04-23, bumped 384 MB → 1.6 GB), connector-14170 (2026-04-29 ongoing), connector-45999 (2026-04-29 ongoing).

## Symptoms

- Container appears in `fleet_new_oom_offender` dashboard signal with sustained count ≥ 10 per 24h.
- `kubectl get pod connector-<id>-<x> -o json | jq .status.containerStatuses[].lastState.terminated.reason` returns `OOMKilled`.
- Customer reports gaps in alert delivery / clip processing for that site.
- Pod's working set (live memory usage) is within 10–30% of the `limits.memory` ceiling — confirmable from a `kubectl top pod` snapshot or VPA recommendation.

## Diagnose

**1. Confirm OOMKill pattern and current limit:**

```bash
SITE=14170  # the offending site_id

kubectl -n connector-<env> get pod -l site=$SITE -o json \
  | jq -r '.items[].status.containerStatuses[]
      | "\(.name)\tlastReason=\(.lastState.terminated.reason // "-")\trestartCount=\(.restartCount)"'

kubectl -n connector-<env> get pod -l site=$SITE -o json \
  | jq -r '.items[].spec.containers[]
      | "\(.name)\trequests=\(.resources.requests.memory)\tlimits=\(.resources.limits.memory)"'
```

**2. Snapshot working set + VPA recommendation:**

```bash
kubectl -n connector-<env> top pod -l site=$SITE --no-headers
kubectl -n connector-<env> get vpa -l site=$SITE -o json \
  | jq -r '.items[].status.recommendation.containerRecommendations[]
      | "\(.containerName) target=\(.target.memory) upper=\(.upperBound.memory)"'
```

If `working_set / limits.memory > 0.7` sustained, the pod genuinely needs more memory. If working set is far below the limit but OOMs are still happening, suspect a leak in a sub-container (motion, autopatrol cronjob) — this runbook's "raise the limit" recipe won't fix that case.

## Fix

**The validated recipe (from connector-20628 / 2026-04-23):**

Raise `limits.memory` in the connector_deployer YAML for that specific site. The proven jump for connector-class workloads is 384 MB → 1.6 GB; pick a value that gives ~30% headroom over the working-set peak from the prior 7 days. Don't go below 1.0 GB for a connector pod even if working set is small — VPA will keep nudging the floor down otherwise.

```bash
# In connector_deployer repo, find the site's deployment YAML
cd ~/work/connector_deployer
grep -rn "site_id: $SITE" src/yaml/ 2>/dev/null | head -3

# Edit the matching deployment.yaml (or templated source)
# Bump: limits.memory: 384Mi → 1600Mi
# requests.memory should follow the same fraction — typical 50–60% of limit
```

Open a small PR titled `connector-<site_id>: bump memory limit (one-off triage; §18 fleet-wide fix in flight)`. Don't bundle multiple sites in the same PR — keeps the rollback surface clean.

## Verify

After the deploy lands:

```bash
# 1. Confirm the new spec is live
kubectl -n connector-<env> get pod -l site=$SITE -o jsonpath='{.items[*].spec.containers[*].resources.limits.memory}'

# 2. Watch OOMKill count drop. Expect 0/12h within ~1h of the deploy
~/bin/observations-snapshot --json | python3 -c "
import json, sys
d = json.load(sys.stdin)
v = d['signals']['fleet_new_oom_offender']['value']
print({k: v[k] for k in v if 'connector-$SITE' in k} or 'OK: not in top-15')
"

# 3. Spot-check working-set vs new limit at 24h, 7d
kubectl -n connector-<env> top pod -l site=$SITE
```

Acceptance: 0 OOMKills for the bumped pod for 24h, AND working set < 70% of new limit.

## Prevent

- **Fleet-wide:** mark-todos §18 — restore VPA min-memory floor in `connector_deployer` (Feb 9 commit `a5de5db` removed it; 73 days of drift left ~1,956 pods in the CRITICAL 384–426 MB tier). One-off bumps don't scale; this is the durable fix.
- **Detection:** dashboard signal `fleet_new_oom_offender` already catches this same-day. Keep its red threshold at the current setting (≥10 per pod per 24h).
- **PR template:** when one-off bumps land in `connector_deployer`, the PR description should reference this runbook + §18 so the per-pod work doesn't accumulate as drift in its own right.
- Consider promoting `connector_pod_headroom_over_70pct` to a tracked signal (currently in §9 Phase 1b backlog) — would catch pods *approaching* OOM before they cross the threshold.

## Cross-refs

- [[2026-04-23_oom-surge-connector-limit-drift]] — root-cause analysis (Feb-9 floor removal commit, fleet-wide tier breakdown)
- mark-todos §18 — fleet memory-limit drift (the durable fix)
- `~/.claude/skills/dashboard-check/config/signals.json` — `fleet_new_oom_offender` + `fleet_oomkills_24h` signal definitions
- [[runbooks/_summary|Runbooks]]
