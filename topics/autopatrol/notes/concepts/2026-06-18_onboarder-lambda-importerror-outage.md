---
title: "Onboarder Lambda ImportError Outage (2026-06-18)"
type: concept
topic: autopatrol
tags: [incident, autopatrol, lambda, deploy, ci, onboarder, postmortem]
jira: ""
created: 2026-06-18
updated: 2026-06-18
author: kb-bot
incoming:
  - topics/autopatrol/notes/entities/autopatrol-onboarder.md
  - topics/personal-notes/notes/daily/2026-06-17.md
incoming_updated: 2026-06-19
---

## Incident: Lambda Deployment Divergence

**Timeline:** Merge 2026-06-17 21:38 UTC → deploy 21:41 UTC → crash 21:41-2026-06-18 15:00 UTC → fix 2026-06-18 15:XX UTC.

**Impact:** Complete onboarder silence in **both US and EU regions** for ~8 hours. Zero tenant enable/disable cascades; customers whose status changed in the ~8h window were not synced to Actuate. Dashboard signal `onboarder_activity_us` dropped from baseline ~150/hr to 0/hr.

**Every Lambda invocation crashed immediately:**
```
Runtime.ImportModuleError: No module named 'deploy_verification'
```

## Root Cause: Split Deployment Paths

The [[autopatrol-onboarder]] repository has **two independent deployment packaging mechanisms** that bundled **different file sets**:

1. **Manual deploy scripts** (`deploy_prod.sh`, `deploy_prod_eu.sh`): used a hardcoded `cp` list including:
   - `lambda_function.py`, `cleanup_lambda.py`, `reenable_lambda.py`, `admin_api_handler.py`, `cleanup_dao.py`, `newrelic_helper.py`
   - **Plus `deploy_verification.py`** (added May 2026)

2. **CI auto-deploy** (`.github/workflows/deploy.yml`): packaged a different list:
   - `lambda_function.py`, `cleanup_lambda.py`, `reenable_lambda.py`, `admin_api_handler.py`, `cleanup_dao.py`, `newrelic_helper.py`
   - **Omitted `deploy_verification.py`**

### Why the bug was latent

PR #16 added an import of `deploy_verification` in `lambda_function.py` (2026-05-22). Since #16 had only ever been deployed via manual `deploy_prod.sh` (which bundled the file), the missing import path never surfaced. The CI path remained broken.

Merging PRs #14, #15, #16 to `master` triggered the auto-deploy for the first time with the new import → immediate crash. AWS Lambda status reported "State=Active, LastUpdateStatus=Successful" — the deploy itself succeeded, but the runtime failed silently on every invocation until someone checked the logs.

## The Trap: Divergent Packaging

**Core lesson:** When a service has both manual and CI deployment paths, any divergence in their bundled file sets is a **latent production break**. Manual deployment can mask missing files (the operator's environment has them). CI deployment, by contrast, is a clean workspace — only the packaged files exist, and there is no environment fallback. The first CI deploy after adding a new dependency will fail unless the packaging step was also updated.

This applies to any Lambda, container, or built artifact with multiple deployment mechanisms. 

## Detection Lag

~8 hours elapsed before the outage was noticed (dashboard signal `onboarder_activity_us` reading 0/hr vs baseline ~150/hr). For a synchronization service, that is excessive. The metric exists and was correct — the gap is in alerting coverage.

## Remediation

**Immediate (same day):**
1. Ran `deploy_prod.sh` (US region) → recovered within ~1 min (verified: ImportModuleError gone, activity resumed ~139/hr).
2. Ran `deploy_prod_eu.sh` (EU region) → recovered within ~1 min (activity resumed ~42/hr US, ~16/15 invocations in NR logs).
3. Root-cause fix pushed to `master` (commit 73fd270): added `deploy_verification.py` to the CI cp list in `.github/workflows/deploy.yml`.
4. The fix commit auto-deployed via the same broken workflow, but the updated packaging now included the file → corrected auto-deploy succeeded.

**Verification steps run post-remediation:**
- No `ImportModuleError` in Lambda logs (CloudWatch + NR).
- `get_sites` activity resumed at expected hourly cadence.
- Immix sync endpoints responding; contract fetches succeeding.

## Standing Fixes + Follow-ups

### 1. Unify deployment packaging (high priority)

Replace split manual + CI packaging with **a single source of truth**:

- **Option A:** Generate the file list from `pyproject.toml` or a manifest, use it in both `.deploy_prod.sh` and `.github/workflows/deploy.yml`.
- **Option B:** Parameterize the deployment path, call the same Python script from both manual and CI workflows.
- **Option C:** Smoke-test post-package: after bundling, attempt to import the handler module from the built zip — this would catch missing dependencies before deploying.

### 2. Paged alert on onboarder activity flatline (medium priority)

- **Condition:** `onboarder_activity_us` OR `onboarder_activity_eu` = 0 for >5 min.
- **Action:** Page on-call (or thread to Slack channel) with severity high.
- **Rationale:** onboarder is a critical path service; 8-hour detection is too slow for a prod sync Lambda.

### 3. Document in [[branch-conventions]] (low, informational)

The [[autopatrol_onboarder]] row already notes:
> **Push to `master` AUTO-DEPLOYS the prod Lambda** via `.github/workflows/deploy.yml` (`on: push: branches: [master]`) — every merge to master is a prod deploy.

Reinforce that contributors must test locally with the CI packaging path (not just manual `deploy_prod.sh`) before merging.

### 4. Code review checklist for new onboarder imports

When adding a new import to `lambda_function.py` or other handler-level modules, the PR reviewer should check:
- Does `.github/workflows/deploy.yml` bundle the new module in its cp list?
- Has the PR been tested by running the CI workflow (or manually packaging with CI's file list)?

## Preventive Measure: Branch Convention Enforcement

Updated [[branch-conventions]] row for `autopatrol_onboarder` to explicitly document:
> Lambda repo. **Push to `master` AUTO-DEPLOYS the prod Lambda** via `.github/workflows/deploy.yml` (`on: push: branches: [master]`) — every merge to master is a prod deploy.

This is now in the team's centralized reference. For future work:
- Before merging to `master`, verify that all imports and dependencies are in the CI packaging list.
- Use [[2026-06-15_onboarder-lambda-importerror-outage|this incident note]] as a reference for the trap of split deployment paths.

---

## Summary

A single-file omission in one of two deployment pipelines caused an 8-hour prod outage in both regions. The root cause was **packaging path divergence** — manual and CI pipelines bundled different file sets. The latency in detection (8 hours) and remediation was the secondary lesson: ensure paged alerts for critical service flatlines.

The fix is immediate (add the file to the CI list) and straightforward. The meta-lesson is durable: **any service with multiple deployment paths must either unify their packaging or maintain perfect parity** — any divergence is a landmine waiting for the next merge.
