---
title: "Runbook: RDS & Aurora PostgreSQL Extended-Support Upgrade (2026-06)"
type: concept
topic: runbooks
tags: [runbook, rds, aurora, postgres, aws-cost, extended-support, database, upgrade]
jira: "cost-optimization"
created: 2026-06-02
updated: 2026-06-02
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-06-03.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/runbooks/_summary.md
incoming_updated: 2026-06-19
---

# RDS & Aurora PostgreSQL Extended-Support Upgrade

## Status (2026-06-17)

- **supportwiki (BACK-625): ✅ UPGRADED to PG16.11 2026-06-17 ~20:30 UTC.** Pre-flight clean, snapshot `actuateadminsupportwiki-pre-pg16-20260617` taken, **dress-rehearsed** (restored snapshot → temp instance → upgraded to 16.11 → confirmed schema md5 + per-table rowcount parity for both `cms` and `kbcms` vs live → deleted temp), then real upgrade via `aws rds modify-db-instance --apply-immediately` (Multi-AZ roll, ~10 min). Post-verify all pass: 16.11/`default.postgres16`, schema+data parity (cms 102/9751, kbcms 37/5481), VACUUM ANALYZE both DBs, error log clean, sites `kb`/`support.actuateui.net` 302→login→200. **Lesson: the instance hosts TWO DBs (`cms`=support wiki, `kbcms`=KB) — fingerprint both.** Remaining: human logged-in spot-check, surcharge→$0 confirm (~48h), delete snapshot after ~30d.
- **Module bug fixed (commit `f86c599`, branch `integration/rds-pg16-extended-support`).** PR #99 set `allow_major_version_upgrade=true` on the standalone *instance* entries, but the flag was only wired through the Aurora *cluster* module path — the `instances` object type, the `module "instance"` call, and the `aws_db_instance` resource all lacked it, so the value was silently dropped and the major-upgrade apply failed with `AllowMajorVersionUpgrade flag must be present`. Now plumbed end-to-end. **This was the latent blocker that kept the upgrade from ever applying — and it also gated the jobschedulerdjangoq (standalone) half of BACK-673.**
- **Important: the upgrade code (PR #99/#100) lives only on `integration/rds-pg16-extended-support`, NOT `main`.** `origin/main` still shows `engine_version="12.22"`. Applies for this work are run from the integration branch.

## When this applies

Three Actuate databases are running end-of-life PostgreSQL major versions under AWS RDS **Extended Support** — a paid-per-vCPU surcharge applied after a major version exits standard support. Upgrading them to PostgreSQL 16 will zero out the extended-support surcharge (~$613/mo total).

**Extended Support is distinct from EKS version extended support** — they're separate AWS programs. This runbook targets the RDS database engine lifecycle.

## Current Situation

| DB | Engine | Account / Region | Config | Ext-support Since | Monthly Surcharge |
|---|---|---|---|---|---|
| actuateadminsupportwiki | RDS PG 12.22 | prod 388576304176 / us-west-2 | db.t3.micro, Multi-AZ | Mar 1 2025 | $297.60 |
| jobschedulerdjangoq | RDS PG 13.20 | prod 388576304176 / us-west-2 | db.t3.micro, single-AZ | Mar 1 2026 | $148.80 |
| actuate-dev-eu-west-1-aurora-writter | Aurora PG 12.22 | dev 558106312574 / eu-west-1 | db.r6g.large writer | Mar 1 2025 | $166.66 |

**Deadline:** PG12 databases entered Extended Support Year 1 on Mar 1 2025. Year 3 (starting ~Mar 1 2027) **doubles the rate** — supportwiki → $595/mo, dev Aurora → $333/mo. The PG12 pair is time-boxed.

**Target Version:** PostgreSQL 16 (16.11 to match the existing prod Aurora fleet — `actuateadminprodcluster`, `develop`, `customer-capture` all run 16.11). Verified via `describe-db-engine-versions`: **12.22 → 16.11 and 13.20 → 16.11 are valid single-step major upgrades.** Avoid PG14 (standard EOL ~Nov 2026) and PG13/15 as end targets.

## Execution path — via IaC (`ds-terraform-eks-v2`), NOT raw CLI

**All three DBs are Terraform/Terragrunt-managed.** Upgrading with `aws rds modify-db-instance` directly causes drift: code still says PG12/13 while live is PG16, so the next `terragrunt apply` tries to *downgrade* (RDS refuses → failed/perpetual-drift apply). Do the upgrade **in the repo.**

Repo: `ds-terraform-eks-v2` (`git@github.com:aegissystems/ds-terraform-eks-v2.git`). The `modules/rds` module already exposes `allow_major_version_upgrade` (optional, default `false`). Applies are **manual `terragrunt apply`** per stage dir (no Atlantis/Spacelift); PRs run `claude_review` + `qa` checks only.

**Exact edits:**
- `stages/prod/us-west-2/rds/terragrunt.hcl`
  - block `support_wiki`: `engine_version "12.22"→"16.11"`; add `allow_major_version_upgrade = true`; `parameter_group_name "default.postgres12"→"default.postgres16"`
  - block `jobscheduler_django_q`: `engine_version "13.20"→"16.11"`; add `allow_major_version_upgrade = true`; `parameter_group_name "default.postgres13"→"default.postgres16"`
- `stages/dev/eu-west-1/monitoring_api/terragrunt.hcl`
  - `engine_version "12.22"→"16.11"`; add `allow_major_version_upgrade = true`; `db_cluster_parameter_group_name "default.aurora-postgresql12"→"default.aurora-postgresql16"`

**Workflow per stage:** branch → edit hcl → PR → review the `terragrunt plan` → in a maintenance window take the manual pre-upgrade snapshot → `terragrunt apply` → `ANALYZE` → smoke test → confirm ExtendedSupport → $0. The raw `aws rds modify-*` commands in Phase 2 are a **manual/emergency fallback only**; if ever used, immediately mirror `engine_version` back into the hcl to kill drift.

## Phase 0 — Decommission Gate (jobschedulerdjangoq ONLY)

> **✅ RESOLVED 2026-06-03 — RESULT: LIVE, upgrade (do NOT delete).** The gate ran and the DB is in active use, NOT redundant with the Aurora clusters:
> - **30d CloudWatch:** DatabaseConnections 3–5 sustained (avg 3.33), CPU ~7.6% steady, **WriteIOPS ~12/day (active writes)**, ReadIOPS ~5.5 — an idle DB would show ~0 writes.
> - **Code/IaC refs:** backs the standalone `job_scheduler` ECS service (3-container task def + `job_scheduler_ui` daphne ASGI + `job_scheduler` / `job_scheduler_healthcheck` ECR repos) and the [[actuate_admin]] `inframap` db_router → `job_scheduler` connection (`job_scheduler_jobfailure/jobormq/jobschedule/jobsuccess/jobtask` tables). Distinct system from the Aurora `djangoqcluster` (autopatrol Django Q). IaC-managed in `ds-terraform-eks-v2/stages/prod/us-west-2/rds`.
> - **Created** 2022-03-04; single-AZ db.t3.micro; endpoint `jobschedulerdjangoq.c6tcmklzkcgl.us-west-2.rds.amazonaws.com:5432`.
> - **→ Proceed to the PG13→16.11 upgrade.** Single-AZ means a brief downtime window — schedule low-activity and coordinate with the `job_scheduler` service.

Before upgrading the standalone `jobschedulerdjangoq` RDS instance, confirm it's actually in use. Alternative Aurora clusters already exist:
- `djangoqcluster` (PG 15.15)
- `actuate-eu-django-q-prod-cluster` (PG 16.11)

If `jobschedulerdjangoq` is idle or superseded, snapshot and delete it instead of upgrading (saves $148.80/mo outright).

**Diagnosis steps:**

```bash
# 1. CloudWatch connections — max value over 30d
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=jobschedulerdjangoq \
  --start-time 2026-05-03T00:00:00Z \
  --end-time 2026-06-02T00:00:00Z \
  --period 86400 \
  --statistics Maximum \
  --region us-west-2

# 2. Live sessions — connect and check
psql -h <jobschedulerdjangoq endpoint> -U postgres -d postgres -c \
  "SELECT count(*), application_name FROM pg_stat_activity GROUP BY application_name;"

# 3. Grep terraform & k8s manifests for the endpoint hostname
grep -r "jobschedulerdjangoq" /home/mork/work/
```

**Decision:**
- Max connections = 0 or nil, no live sessions, no code references → **snapshot + delete** (Phase 0 complete, skip to Phase 1 for the other two DBs).
- In active use → proceed to Phase 1.

## Phase 1 — Pre-flight (per DB)

**1. Confirm upgrade path:**

```bash
# RDS standalone (supportwiki, jobschedulerdjangoq)
aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version 12.22 \
  --query 'DBEngineVersions[0].ValidUpgradeTarget[?IsMajorVersionUpgrade].EngineVersion' \
  --region us-west-2

# Aurora cluster (dev eu-west-1)
aws rds describe-db-engine-versions \
  --engine aurora-postgresql \
  --engine-version 12.22 \
  --query 'DBEngineVersions[0].ValidUpgradeTarget[?IsMajorVersionUpgrade].EngineVersion' \
  --region eu-west-1 \
  --profile dev
```

Expect both to include `16.11` in the list.

**2. Parameter group:**

All three DBs use the **DEFAULT family group** (`default.postgres12`, `default.postgres13`, or default aurora-postgresql12 cluster group). Major upgrades automatically migrate to the corresponding `default.postgres16` / `default aurora-postgresql16` group — no manual pre-creation needed.

(Custom parameter groups would require pre-creating the postgres16-family equivalent before upgrade; none apply here.)

**3. Extension compatibility:**

Connect to each database and verify extensions are supported on PG16:

```bash
psql -h <endpoint> -U postgres -d <db> -c \
  "SELECT extname, extversion FROM pg_extension;"
```

Common supported extensions: `pg_stat_statements`, `pgcrypto`, `plpgsql`, `uuid-ossp`. If an unusual extension appears, check the [[infrastructure/_summary|RDS extension matrix]] in Confluence.

**4. Pre-upgrade blockers:**

RDS runs `pg_upgrade` preflight checks; major upgrades abort without mutating the DB if issues exist. Common blockers RDS rejects:
- Unknown or `reg*` data types
- Logical-replication slots (must be dropped)
- Prepared transactions (must be rolled back)

```bash
# Quick check for logical slots (if applicable)
psql -h <endpoint> -U postgres -d postgres -c \
  "SELECT * FROM pg_replication_slots;"
```

**5. App compatibility:**

Confirm the consuming application supports PG16. Almost always yes for mature apps; spot-check the release notes of:
- Support Wiki app (Django or Rails version)
- Django Q (last release supports PG16)

**6. Take a manual pre-upgrade snapshot:**

```bash
# RDS standalone
aws rds create-db-snapshot \
  --db-instance-identifier <actuateadminsupportwiki|jobschedulerdjangoq> \
  --db-snapshot-identifier <id>-pre-pg16-20260602 \
  --region us-west-2

# Aurora cluster
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier actuate-dev-eu-west-1-aurora-cluster \
  --db-cluster-snapshot-identifier actuate-dev-eu-west-1-aurora-pre-pg16-20260602 \
  --region eu-west-1 \
  --profile dev
```

This snapshot is your **rollback baseline**. Major upgrades are not reversible in place.

**7. Notify & window:**

- **supportwiki** = internal users → coordinate with team.
- **jobschedulerdjangoq** = job pipeline → notify job-dependent services (if any).
- **dev Aurora** = [[dev-environment|dev environment]] → low risk, but notify dev users.

Pick a maintenance window outside peak usage.

## Phase 2 — Execute (RDS Standalone)

### For supportwiki (actuateadminsupportwiki)

```bash
aws rds modify-db-instance \
  --db-instance-identifier actuateadminsupportwiki \
  --engine-version 16.11 \
  --allow-major-version-upgrade \
  --apply-immediately \
  --region us-west-2
```

Multi-AZ setup (supportwiki is Multi-AZ): RDS upgrades the standby first, initiates a failover to the newly-upgraded standby, then upgrades the old primary. Brief failover blip (~1–2 min); app connections may briefly hang.

Monitor with:

```bash
aws rds describe-db-instances \
  --db-instance-identifier actuateadminsupportwiki \
  --query 'DBInstances[0].{status:DBInstanceStatus,ver:EngineVersion,port:DBPortNumber}' \
  --region us-west-2
```

[[watch-entity|Watch]] for `status: available` and `ver: 16.11`.

### For jobschedulerdjangoq (if still in use)

```bash
aws rds modify-db-instance \
  --db-instance-identifier jobschedulerdjangoq \
  --engine-version 16.11 \
  --allow-major-version-upgrade \
  --apply-immediately \
  --region us-west-2
```

Single-AZ: **full downtime** for upgrade duration (~10–15 min on a t3.micro). No failover. Monitor the same way.

## Phase 2b — Execute (Aurora Cluster)

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier actuate-dev-eu-west-1-aurora-cluster \
  --engine-version 16.11 \
  --allow-major-version-upgrade \
  --apply-immediately \
  --region eu-west-1 \
  --profile dev
```

Aurora performs the major upgrade with a brief outage (writer + readers roll sequentially). Verify the writer and any readers come back on 16.x:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier actuate-dev-eu-west-1-aurora-cluster \
  --query 'DBClusters[0].{status:Status,ver:EngineVersion}' \
  --region eu-west-1 \
  --profile dev
```

## Phase 3 — Post-upgrade Verification (CRITICAL — don't skip)

**1. Confirm upgrade:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier <id> \
  --query 'DBInstances[0].{status:DBInstanceStatus,ver:EngineVersion,param_group:DBParameterGroups[0].DBParameterGroupName}' \
  --region <region>
```

Expect: `status: available`, `ver: 16.11`, `param_group: default.postgres16`.

**2. Vacuum & analyze — MOST-MISSED STEP:**

`pg_upgrade` does NOT carry optimizer statistics forward. Without `VACUUM ANALYZE`, queries are slow until autovacuum catches up (~24h on small DBs, longer on large ones).

```bash
# Connect and run (this may take a few minutes on each DB)
psql -h <endpoint> -U postgres -d <db> -c "VACUUM ANALYZE;"

# For the public schema; if there are multiple schemas, repeat per schema
psql -h <endpoint> -U postgres -d <db> -c "ANALYZE;"
```

**3. Smoke test the application:**

- **Support Wiki:** Log in to the admin dashboard, verify page load / search works.
- **Django Q:** Enqueue a test job, verify it dequeues and completes successfully.
- **Dev Aurora:** Run a simple query from the app layer.

**4. Monitor error logs:**

```bash
# RDS log group: /aws/rds/instance/<id>/error
aws logs tail /aws/rds/instance/actuateadminsupportwiki/error --follow --region us-west-2
```

[[watch-entity|Watch]] for `ERROR` lines in the first 10 min post-upgrade. Expected: none (or innocuous startup messages).

**5. Verify the surcharge dropped:**

AWS Cost Explorer updates with a 1–2 day lag. After ~48h, check:

```bash
# Verify via AWS console: Cost Explorer → Blended Cost → Filter by:
# - Usage type: USW2-ExtendedSupport:Yr1-Yr2:PostgreSQL12 (or PostgreSQL13, or AuroraPostgreSQL12)
# Result should be $0
```

Or use the `/cost-check` skill for a programmatic query.

**6. Soak for 24h:**

Monitor [[infrastructure/_summary|connection counts]], error rates, query latency over a full day. [[watch-entity|Watch]] especially:
- `DatabaseConnections` metric stays flat.
- `DatabaseLatency` didn't spike.
- Autovacuum is working normally (check `log_autovacuum_min_duration` in CloudWatch Logs).

**7. Snapshot retention:**

Retain the pre-upgrade snapshot for ~30 days (per company retention policy). Delete after confirmation that the upgrade is stable.

## Rollback

**In-place rollback is impossible.** To revert:

1. Restore the pre-upgrade snapshot to a **new** RDS instance or Aurora cluster (different identifier).
2. Test connectivity and app functionality against the restored instance.
3. Repoint the application connection string to the restored instance.
4. Delete the 16.x instance.

This is why Phase 1 step 6 (manual snapshot) is mandatory.

## Recommended Sequence

1. **actuateadminsupportwiki** (PG12 → 16.11, $297.60/mo, Multi-AZ low-downtime) — biggest cost impact; good pipe-cleaner.
2. **actuate-dev-eu-west-1-aurora-writer** (PG12 → 16.11, $166.66/mo, dev low-risk) — also consider right-sizing the `r6g.large` (heavy for dev) or evaluating whether the dev EU Aurora is needed at all.
3. **jobschedulerdjangoq** (PG13 → 16.11, $148.80/mo) — **run Phase 0 decommission gate first**; upgrade only if genuinely in use.

## Pre-flight state captured (read-only, 2026-06-03)

Full non-disruptive pre-flight ran clean. Tickets: [BACK-625](https://actuate-team.atlassian.net/browse/BACK-625) (supportwiki) · [BACK-673](https://actuate-team.atlassian.net/browse/BACK-673) (other two).

| DB | param group | Multi-AZ | backup retention | maint window | del-protection | pending mods |
|---|---|---|---|---|---|---|
| actuateadminsupportwiki | default.postgres12 (in-sync) | **yes** | 30d | Wed 11:59–12:29 UTC | on | none |
| jobschedulerdjangoq | default.postgres13 (in-sync) | no | 7d | Wed 07:56–08:26 UTC | on | none |
| actuate-dev-eu-west-1-aurora-cluster | default.aurora-postgresql12 | no (single writer) | **1d** | Thu 03:00–03:30 UTC | on | none |

Findings / implications:
- **All on default param groups** → upgrade auto-adopts the postgres16 family; no custom param-group migration. Confirmed.
- **Deletion-protection on (all three)** — does NOT block version upgrades; fine.
- **None of the three target DBs have AWS-side pending major-upgrade actions** → we fully control timing. (Note: the *admin* prod/develop Aurora clusters DO have pending "Upgrade to Aurora PG 16.11.3" + OS patches queued — separate from this work, worth a look.)
- **dev Aurora backup retention = 1 day** — thin rollback margin; bump retention or rely on the mandatory pre-upgrade manual snapshot.
- **jobschedulerdjangoq has NO diurnal quiet window** — WriteIOPS is flat ~3.5/hr 24/7 (Django Q heartbeat/polling). Single-AZ downtime impact is uniform across hours → pick the existing Wed maint window or any agreed pause; don't chase a "low-traffic" hour.
- **Extension / pg_upgrade blocker scan — DONE 2026-06-17 for supportwiki, CLEAN.** Connected directly (the instance has `publicly_accessible=true`; creds in Secrets Manager `prod/actuate/wiki`, `*-support` keys, db `cms`). Results: only `plpgsql` extension; 0 logical replication slots; 0 prepared transactions; 0 reg*/unknown-type columns in user schemas (36 found, all in `pg_catalog` — expected, not blockers); DB 23 MB / 102 public tables. No pg_upgrade blockers. (jobschedulerdjangoq + dev Aurora scans still pending their own runs.)

## Cross-refs

- [[infrastructure/_summary]] — RDS service baseline, EKS, ECR pipeline
- [[aws-cost/_summary]] — cost research and optimization [[strategies]]; see active right-sizing threads table
- [[2026-04-28_s3-cost-reduction-action-plan]] — broader cost optimization context; database upgrades are one vector among S3, EKS, GPU
- [[skill-cost-check]] — `/cost-check` skill for Cost Explorer queries to verify surcharge drop post-upgrade
- [[runbooks/_summary|Runbooks]] — parent runbook index
