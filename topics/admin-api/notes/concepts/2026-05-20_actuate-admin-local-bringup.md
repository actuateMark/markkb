---
title: "actuate_admin local bring-up — command-line runbook"
type: concept
topic: admin-api
tags: [actuate-admin, local-dev, runbook, postgres, django, uv, codeartifact, personal-laptop]
created: 2026-05-20
updated: 2026-05-20
author: kb-bot
outgoing:
  - topics/admin-api/notes/entities/actuate-admin-rds.md
  - topics/admin-api/notes/syntheses/2026-05-20_deploy-branch-full-scope.md
  - topics/personal-laptop/notes/entities/local-service-ports.md
incoming:
  - home/offboarding/2026-06-23_local-repo-audit.md
  - home/operations/2026-06-24_secrets-refresh-runbook.md
  - topics/admin-api/notes/concepts/2026-05-21_deploy-branch-e2e-cycle-verified.md
  - topics/admin-api/notes/entities/actuate-admin-safe-test-sites.md
  - topics/admin-api/notes/syntheses/2026-05-20_deploy-branch-full-scope.md
  - topics/personal-laptop/notes/entities/local-service-ports.md
  - topics/personal-notes/notes/daily/2026-05-21.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-25
---

# actuate_admin local bring-up — command-line runbook

> **Audience:** future-self / sibling sessions. Goal — go from "Postgres running, repo cloned" to "Django runserver responding on a chosen port with all migrations applied" in a single readable session, with the gotchas pre-marked. Verified working 2026-05-20 on this laptop.
> **Relationship to the README:** the `actuate_admin/Readme.md` documents the steps; this note codifies the working **sequence**, the **port-allocation convention** vs. other local services, and the **warnings to ignore vs. address**.

## Prereqs (one-time host setup)

| Component | Verify | If missing |
|---|---|---|
| Postgres 16 running on `127.0.0.1:5432` | `pg_isready` | Install via package manager, ensure default cluster running |
| Postgres roles `rdsadmin` + `actuateadmin` (superuser) | `psql -U postgres -c "\du"` | See [[actuate-admin-rds]] for role creation |
| `actuateadmin` database restored | `PGPASSWORD=actuateadmin psql -h 127.0.0.1 -U actuateadmin -d actuateadmin -c "SELECT count(*) FROM inframap_customer"` should return ~22k | Use `actuate_admin_rds` repo's `restore.sh` pipeline ([[actuate-admin-rds]]) |
| `actuate_admin_rds` repo cloned | `ls /home/mork/work/actuate_admin_rds/restore.sh` | `gh repo clone aegissystems/actuate_admin_rds` |
| `uv` ≥ 0.8 | `uv --version` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| AWS SSO active on `prod` profile | `AWS_PROFILE=prod aws sts get-caller-identity` | `aws sso login --profile prod` |
| `.env` at repo root `/home/mork/work/actuate_admin/.env` populated | (see below) | Copy from `actuate_admin/actuate_admin/.env.example` and fill values |

## `.env` shape — known-working values

```bash
# local
DB_NAME=actuateadmin
DB_USER=actuateadmin
DB_PASS=actuateadmin            # matches the role password from the restore step
DEBUG=True
STAGE=local                     # MUST be 'local' — selects local DB config branch in Django settings
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME_TEST=test_actuateadmin
DB_NAME_DJANGO_Q=django_q       # this DB may not exist locally — warning is harmless (see below)
DB_USER_DJANGO_Q=actuateadmin
DB_PASS_DJANGO_Q=actuateadmin
DB_HOST_DJANGO_Q=127.0.0.1
DB_PORT_DJANGO_Q=5432
DEBUG_TOOLBAR=False
AWS_REGION=us-west-2
SECRET_KEY=123456789            # local-only; any non-empty string fine
```

`.env` lives at the **repo root**, not at `actuate_admin/actuate_admin/.env` (despite the README pointing to the example file in that subdirectory). The handoff `set -a; source .env; set +a` approach reads from the root location.

## Bring-up sequence (canonical)

Run from `/home/mork/work/actuate_admin/`.

```bash
# 1. Refresh AWS SSO if not already active
AWS_PROFILE=prod aws sts get-caller-identity >/dev/null || aws sso login --profile prod

# 2. Source the .env so DB creds + STAGE are on the environment
set -a && source .env && set +a

# 3. Fetch CodeArtifact token and configure uv index
export UV_INDEX_PRIVATE_REGISTRY_USERNAME=aws
export UV_INDEX_PRIVATE_REGISTRY_PASSWORD=$(AWS_PROFILE=prod aws codeartifact get-authorization-token \
    --domain actuate --domain-owner 388576304176 \
    --query authorizationToken --output text)

# 4. Sync dependencies (no-op if already in sync)
uv sync

# 5. Apply pending migrations
uv run python manage.py migrate inframap   # add other apps if needed

# 6. Start runserver on a NON-DEFAULT port (see "Port convention" below)
uv run python manage.py runserver localhost:8001
```

Verify:

```bash
curl -fsS -o /dev/null -w "%{http_code}\n" http://localhost:8001/
# expect 302 (redirect to login) — that means Django booted, middleware ran, URL conf resolved
```

## Port convention (personal-laptop)

Multiple Actuate services run locally during a working session. Standardize:

| Port | Service | Notes |
|---|---|---|
| 5432 | Postgres | shared by all Django + inference-api workloads |
| 6379 | Redis | [[actuate_admin]] uses db=3, others vary |
| 8000 | **actuate-inference-api dev server** | this is the v5/v4 inference API uvicorn process — default per its README |
| 8001 | **[[actuate_admin]] runserver** | preferred local port for admin (this note's bring-up) |
| 8002 | reserved for future Django/FastAPI workload | |
| 8554 | rtsp_camera_simulator (Docker) | UDP+TCP, see `docker ps` |

**Rule:** if you start `actuate_admin` with the README's default `runserver localhost:8000`, you'll collide with the inference-api dev server (very commonly running in another session). Always pass `localhost:8001` for admin to avoid the collision.

Cross-link: [[local-service-ports]] for the canonical laptop port-allocation table.

## Warnings to expect and ignore on first run

`manage.py makemigrations` and `migrate` will emit RuntimeWarnings about extra database connections that don't exist locally. These are **harmless** as long as the primary `default` connection works:

| Warning | Cause | Action |
|---|---|---|
| `password authentication failed for user "actuateadmin"` on connection `'closeinfo'` | `.env` has `DB_PASS_CLOSE=123` (placeholder for a separate close-info DB that mirrors prod schema) | Only fix if you need close-info features. Otherwise leave. |
| `database "django_q" does not exist` on connections `'django_q'` / `'job_scheduler'` | Job-scheduler DB not part of the `actuateadmin.backup` dump | Only needed for Django-Q task execution; not for endpoint testing. Create empty DB if needed: `createdb -U postgres django_q && psql -U postgres -c "GRANT ALL ON DATABASE django_q TO actuateadmin"`. |
| `password authentication failed for user "mork"` on `'sqlexplorer'` | SQL-explorer uses host-user default | Set `SQLEXPLORER_*` env vars if you need the explorer; otherwise ignore. |

If `manage.py migrate inframap` itself succeeds, the primary DB connection is working. The warnings don't gate anything.

## Migration head — sanity check before/after sync

```bash
PGPASSWORD=actuateadmin psql -h 127.0.0.1 -U actuateadmin -d actuateadmin \
  -c "SELECT name FROM django_migrations WHERE app='inframap' ORDER BY id DESC LIMIT 5"
```

When the DB was restored from production (mid-cycle staging refresh) it may be 5-10 migrations behind the current branch's head. The branch's head is whatever's listed in `inframap/migrations/` — count the files vs. the DB's max applied. Pending migrations apply cleanly via `migrate inframap` unless a hand-curated migration conflicts with an auto-generated one upstream.

## `makemigrations` gotcha — timezone-choice alters

If you run `manage.py makemigrations inframap` on a branch that adds new model fields, Django often **bundles unrelated `timezone` choice alters** on `Customer`, `Group`, `HistoricalCustomer`, `HistoricalGroup`, `HistoricalServer`, `Location`, `Server`. These are noise from a Django/zoneinfo upgrade that's pending elsewhere — do **not** include them in your PR. Hand-curate the generated migration file:

1. Run `makemigrations inframap` once to see what gets proposed.
2. Edit the generated file in `inframap/migrations/` to keep ONLY the operations relevant to your feature.
3. Re-run `migrate inframap` to apply.

Migration `0546` (deploy-branch Customer fields) was hand-curated this way 2026-05-15. Migration `0547_custombranch_branchdeploymentevent` (both `CustomBranch` + `BranchDeploymentEvent` in one file, plus indexes) was hand-curated the same way 2026-05-20 — see [[2026-05-21_deploy-branch-e2e-cycle-verified]] for the verified result.

## `inframap_customer` column drift — manual ALTERs not in any migration

Production has columns on `inframap_customer` that no migration file adds — they were applied by hand. A fresh local restore is missing them. The Customer model expects them, so any SELECT against Customer raises `ProgrammingError`.

Known missing columns (as of 2026-05-21):

```sql
ALTER TABLE inframap_customer ADD COLUMN IF NOT EXISTS endpoint_stage varchar(20) NOT NULL DEFAULT 'prod';
ALTER TABLE inframap_customer ADD COLUMN IF NOT EXISTS queue_stage    varchar(20) NOT NULL DEFAULT 'prod';
```

Symptom: `django.db.utils.ProgrammingError: column inframap_customer.endpoint_stage does not exist`.

Apply both as a one-time fix after the initial `migrate inframap`. **This is a bring-up step, not a one-off.** Every fresh restore will hit it until someone backfills the columns via a proper migration.

If you see ProgrammingError on a column you don't recognize:

```bash
# What does the model declare?
grep -n "^    <col_name>" inframap/sites/customer/customer_model.py

# What does the DB have?
PGPASSWORD=actuateadmin psql -h 127.0.0.1 -U actuateadmin -d actuateadmin \
  -c "\d+ inframap_customer" | grep <col_name>

# What migrations reference it?
grep -rn "<col_name>" inframap/migrations/
```

If the DB doesn't have it but a migration "added" it only on `inframap_historicalcustomer`, you've hit the same pattern — apply the equivalent ALTER on `inframap_customer` manually.

## Safe test sites — DO NOT touch the production fleet

The local `actuateadmin.backup` carries all ~22k production customers. **Any DB-mutating dev work must restrict its blast radius to the Actuate-owned STAGE pool.**

The hard rule: a customer is safe only if BOTH

1. `Customer.deployment_phase == "STAGE"`
2. Group ancestor is the **Actuate root group at `id=641`**

Full convention + safe candidate inventory: [[actuate-admin-safe-test-sites]].

Even though `reboot_connector` short-circuits on local STAGE (so the real deployer never gets called), DB writes are real. The audit log, customer state, and any save-hooks all execute. Restrict to fleet you own.

## Known harmless boot log lines

```
INFO redis_cli    Init redis connection 0.0.0.0, db: 3
INFO botocore.tokens Loading cached SSO token for actuate
Camera Admin stage: local, coverage: False, version: local, region: us-west-2, locale: us
INFO django.utils.autoreload Watching for file changes with StatReloader
```

If you see the autoreload line and no traceback, the server is healthy. The Redis init is the django-cache backend probing — failure here would be an actual blocker, but you should have Redis from the [[actuate-admin-rds]] docker-compose if you ran its `create.sh`. (This laptop has Redis natively on `127.0.0.1:6379`.)

## Tear-down

```bash
# In the runserver terminal: Ctrl-C
# OR if backgrounded:
pkill -f "manage.py runserver localhost:8001"
```

Postgres can stay running — it's shared infrastructure.

## When this runbook fails

If something goes wrong, common debugging vectors in order of likelihood:

1. **AWS SSO expired** during `uv sync` → CodeArtifact 401. Re-run step 1 + step 3.
2. **`.env` not sourced** → `STAGE` undefined, Django picks a non-`local` settings branch. Re-source.
3. **Migration conflict** — a hand-curated migration on your branch collides with a new one on staging after a fast-forward. Check `manage.py migrate --plan` first; if proposed plan looks wrong, resolve manually before applying.
4. **Port 8001 already in use** — `ss -tlnp \| grep :8001` to see what's there; move admin to 8002 or kill the offender.
5. **Postgres role missing** → see [[actuate-admin-rds]] for role creation.

## Cross-references

- [[actuate-admin-rds]] — RDS restore tooling (Postgres prereq for this runbook)
- [[2026-05-20_deploy-branch-full-scope]] — the §29 work this bring-up was written to support
- [[2026-05-21_deploy-branch-e2e-cycle-verified]] — first end-to-end cycle run against this bring-up
- [[actuate-admin-safe-test-sites]] — safety convention for picking customers to mutate
- [[local-service-ports]] — laptop port-allocation table (sibling of this note)
- `actuate_admin/Readme.md` — upstream README (this note's source material)
