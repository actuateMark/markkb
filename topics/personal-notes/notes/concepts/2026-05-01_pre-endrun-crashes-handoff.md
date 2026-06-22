---
title: "Handoff — Investigate pre-endrun crashes in autopatrol/VCH connector pods"
type: concept
topic: personal-notes
tags: [handoff, autopatrol, vms-connector, pre-endrun, crashes, NameError, KeyError, TypeError, fleet-silence]
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
outgoing:
  - topics/personal-notes/notes/daily/2026-05-01.md
  - topics/personal-notes/notes/daily/2026-05-04.md
incoming:
  - topics/autopatrol/notes/syntheses/2026-05-01_pre-endrun-crashes-resolution.md
  - topics/personal-notes/notes/daily/2026-05-04.md
incoming_updated: 2026-05-27
---

# Handoff — Investigate pre-endrun crashes in autopatrol/VCH connector pods

**Status: CLOSED** — see [[2026-05-01_pre-endrun-crashes-resolution]] for outcome.

> **Purpose:** kick off a focused investigation in a new conversation. The 2026-05-01 fleet-silence diagnosis (see [[2026-05-01_silent-cameras-diagnosis]]) found that ~9k traceback events over 7 days come from 4 distinct pre-endrun crash modes affecting **37 sites**. The endrun-fix shipped today covers only **2 sites**. The other 35+ sites need targeted investigation per exception type.

## TL;DR

- Of 39 chm-cronjob sites with `Traceback` events in the last 7 days, **only 2 hit endrun failures** (cid=34158 active, cid=30792 resolved). Those are now covered by the user's endrun fix shipped 2026-05-01 (verified end-to-end on cid=35832).
- The other **37 sites have pre-endrun crashes** — pods that fail BEFORE reaching the endrun call, so the endrun fix doesn't help. These pods are 100% dark for their cameras: no Snowflake row, no Immix alert, no S3 frame.
- **Four distinct exception types**, each likely a different root cause:
  - `NameError: name 'cache_multiplier' is not defined` (autopatrol_camera.py:51) — 1 site, 2,145 events
  - `KeyError: Model 'EKS to EKS dev YAM Slicing Microservice Intruder + vehicle' not found` — 4 sites, 4,964 events
  - `TypeError: integration doesn't exist` — 1 site, 719 events
  - `AttributeError: 'NoneType' object has no attribute 'lower'` — multiple sites, 1,009 events
- **Each one needs a code investigation + targeted fix.** None are blocked by data or infra; they're code/config bugs in the connector.

## Affected sites by crash type

### 1. NameError: `cache_multiplier` not defined

- **Affected sites:** cid=35830 (Alibi Witness), 2 cronjob variants (`-autopatrol-308-` and `-autopatrol-309-`)
- **Event volume:** 2,145 / 7d (~12.7/hr — every single run failing completely)
- **Code location:** `vms-connector/camera/autopatrol/autopatrol_camera.py:51`
- **Working hypothesis:** code references a variable `cache_multiplier` that's not in scope. Likely a regression from a recent refactor that removed the variable's definition (or moved it to a different scope) without updating the reference. **First place to look: git blame on autopatrol_camera.py around line 51.**
- **Why it might be cid=35830-specific:** the cronjob image for cid=35830 is tagged `arm_connector_rearch:s3alerts` (custom tag from `Customer.deployment_phase=CUSTOM` + `cv_tag='s3alerts'`). If `s3alerts` is an old image branch where the variable was differently scoped, that explains why only this customer hits it. **Check whether `:s3alerts` ECR tag's code is stale.**
- **Possible fix paths:**
  1. If the `:s3alerts` image is unintentional drift, switch cid=35830 to `deployment_phase=PROD` (default → `:rearch` image)
  2. If `:s3alerts` is intentional (e.g., for an experimental code path), update the image to current main
  3. If the bug exists in current main too (just exposed by `:s3alerts` config), fix the variable scope

### 2. KeyError: Model `'EKS to EKS dev YAM Slicing Microservice Intruder + vehicle'` not found

- **Affected sites:** cid=44565, 41516, 27652, 40722 (4 distinct sites)
- **Event volume:** 4,964 / 7d — the **biggest single contributor** to the silent fleet
- **Code location:** model lookup path inside the connector — likely in the patrol detection routing where the connector resolves which inference model to call. The model name has internal spaces and a `+` and `dev` in it, which suggests it's a non-prod or dev-only routing target that prod cameras shouldn't be hitting.
- **Working hypothesis:** these 4 customers have somehow been configured to use a dev/staging-only AI model that doesn't exist in the prod model registry. The connector tries to look it up, fails with KeyError, crashes the pod. This is a **data-routing bug** — the customer's config in admin probably points at a wrong model.
- **Where to look:**
  - `vms-connector/connector_factories/` for the model resolution code (probably calls into a model registry / cache)
  - `actuate_admin` Customer model — check what AI model field is set for cid 44565/41516/27652/40722 (likely `ai_model_id` or `default_ai_model` or similar)
  - Compare to a known-working autopatrol customer's AI model setting — what's the difference?
- **Possible fix paths:**
  1. Update the 4 customers' AI model field to a real prod model
  2. Add a defensive fallback in the connector — if model not found, log + skip rather than crash
  3. Audit all autopatrol/VCH customers for "dev"/"staging" AI model references in admin

### 3. TypeError: `integration doesn't exist`

- **Affected sites:** cid=7493 (1 site)
- **Event volume:** 719 / 7d
- **Code location:** Integration lookup in connector. Probably `Customer.integration` is None at the call site, and code tries to call a method on it that fails because the underlying Integration row got deleted or detached.
- **Working hypothesis:** customer 7493 had its integration FK cleared or the integration row was hard-deleted. The connector still has it cached / configured, so it tries to use it on every run.
- **Where to look:**
  - Admin DB query: `SELECT integration_type_id, integration_id FROM inframap_customer WHERE id = 7493;` — what's null or stale?
  - vms-connector code for the "integration doesn't exist" string — find the exact raise site
- **Possible fix paths:**
  1. Restore the customer's integration FK if it was accidentally cleared
  2. Add defensive fallback: if integration is None, log + skip the patrol cycle rather than crash
  3. If customer 7493 should be deactivated entirely, run §16 cascade

### 4. AttributeError: `'NoneType' object has no attribute 'lower'`

- **Affected sites:** multiple (count not yet broken down)
- **Event volume:** 1,009 / 7d
- **Code location:** unknown — common pattern is `some_variable.lower()` where `some_variable` is `None`. Could be many places (camera_name, integration_name, schedule_status, etc).
- **Working hypothesis:** a config field that should always be populated is null for some customers, and a downstream `.lower()` call hits None.
- **Where to look:**
  - Get the full traceback (NRQL query for messages with `AttributeError` AND `'lower'`) to find the exact source line
  - Once line known, identify which field is None and which customers have it null
- **This one needs a traceback dump first** to know what to look for.

## Suggested investigation order

1. **Start with #4 (`AttributeError: NoneType.lower`)** — it's the cheapest to scope. Pull full traceback from NR, identify the source line, find the null field, count affected customers. Tells you whether it's 1 site or 30. ~30 min.

2. **Then #2 (`KeyError: YAM Slicing Microservice`)** — biggest event volume (4,964/7d, ~50% of pre-endrun crashes). 4 known customers. Run an admin DB query to see what AI model is set for cids 44565/41516/27652/40722 vs a known-working customer. Probably a one-line config fix per customer. ~1 hour.

3. **Then #1 (`NameError: cache_multiplier`)** — 1 customer, but the customer is on a custom image (`:s3alerts`). Two-axis fix: either flip the customer to `:rearch` (if the custom image isn't doing anything special) or fix the missing variable in the `:s3alerts` branch. Code archaeology required. ~1-2 hours.

4. **Then #3 (`TypeError: integration doesn't exist`)** — 1 customer. Quick admin DB check, then either restore the FK or run §16 cascade. ~30 min.

## Diagnostic NRQL queries to start with

For each exception, get the full traceback context + customer pk distribution:

```
SELECT count(*), latest(message) FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%chm-cronjob%'
  AND container_name NOT LIKE 'staging-%'
  AND message LIKE "%NameError: name 'cache_multiplier'%"
SINCE 7 days ago
FACET capture(container_name, r'connector-(?P<site_id>\d+)-')
LIMIT 50
```

Repeat with the other three exception strings. The `latest(message)` gives you the most recent traceback for each FACET so you can see the full Python stack.

For #4 specifically (the AttributeError that needs full context):

```
SELECT message FROM Log
WHERE cluster_name='Connector-EKS'
  AND container_name LIKE '%chm-cronjob%'
  AND message LIKE "%AttributeError: 'NoneType' object has no attribute 'lower'%"
SINCE 24 hours ago
LIMIT 5
```

— grab the full multi-line traceback to find the source line.

## What this session DID NOT do

- Did NOT investigate any of the 4 crash types beyond identifying their existence + scope
- Did NOT pull full tracebacks (only the one-line `latest(message)` summaries via the dashboard-signal query)
- Did NOT run admin DB queries to see how cid=44565/41516/27652/40722 differ from working customers
- Did NOT check git blame on `autopatrol_camera.py:51` for the `cache_multiplier` history
- Did NOT validate that `:s3alerts` is the right image for cid=35830 — that's part of the broader stage-field cleanup ([[2026-05-01_silent-cameras-diagnosis]] §"Stage-field data integrity")

## Cross-references

- [[2026-05-01_silent-cameras-diagnosis]] — full fleet-silence investigation that surfaced these crash modes
- [[2026-04-30_data-model-cascade-semantics]] — admin model cascade semantics (relevant for #3 TypeError)
- [[2026-04-30_autopatrol-state-audit]] — the audit synthesis with the cohort definitions
- [autopatrol-server PR #23](https://github.com/aegissystems/autopatrol-server/pull/23) — the fix the user shipped today (cid=35832, endrun-call). Different category from the 4 above; covered separately.
- Dashboard signals: `autopatrol_pre_endrun_crashes_7d` (critical=true) — fires on any of the 4 exception types
- GH issue [connector_deployer #164](https://github.com/aegissystems/connector_deployer/issues/164) — full diagnostic thread including the corrections; safe to close once these crashes have their own ticket(s)

## Suggested order for the next session

1. Read this handoff (10 min)
2. Run the 4 diagnostic NRQL queries — capture full tracebacks for each exception (15 min)
3. Pick #4 (AttributeError) first since it needs the traceback to know what to investigate (30 min)
4. Then #2 (KeyError) — admin DB drilldown on the 4 affected customers (60 min)
5. By that point you have enough data to file a focused Jira ticket per crash type (or one umbrella ticket with sub-tasks). The umbrella probably belongs in AUTO project alongside the silent-cameras ticket; sub-tasks can be in vms-connector or [[actuate_admin]] depending on where the fix lives.

## Bootstrap

```bash
# Read order:
cat ~/Documents/worklog/knowledgebase/topics/personal-notes/notes/concepts/2026-05-01_pre-endrun-crashes-handoff.md  # this doc
cat ~/Documents/worklog/knowledgebase/topics/autopatrol/notes/syntheses/2026-05-01_silent-cameras-diagnosis.md  # full context

# Then run the diagnostic NRQLs above, starting with #4.
```
