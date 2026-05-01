---
title: "Actuate Admin RDS"
type: entity
topic: admin-api
tags: [postgresql, rds, backup, restore, docker, database, camera-admin]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/admin-api/notes/entities/admin-auto-onboarding.md
incoming_updated: 2026-05-01
---

# Actuate Admin RDS

Tooling repository for backing up and restoring the Camera Admin PostgreSQL database (`actuateadmin`) for local development. Contains shell scripts, environment-specific restore pipelines, and a Docker Compose setup for running PostgreSQL and Redis locally.

Repository: `actuate_admin_rds`

## Restore Workflow (Local Development)

The main `restore.sh` orchestrates a four-step pipeline:

1. **Download** (`steps/1_download.sh`) -- fetches the latest backup from S3 (`s3://actuate-rds/actuateadmin.backup`).
2. **Restore** (`steps/2_restore_admin.sh`) -- restores the backup into a new database named `actuateadmin_new`.
3. **Update** (`steps/3_update_new.sh`) -- patches fields in the restored DB for local development (e.g., endpoint URLs, credentials).
4. **Switch** (`steps/4_switch_db.sh`) -- atomically swaps `actuateadmin_new` to `actuateadmin`.

Prerequisites: two PostgreSQL superusers (`rdsadmin` and `actuateadmin`) must exist locally, and the `PGPASSWORD` environment variable must be exported.

## Dump Scripts

| Script | Source | Target |
|--------|--------|--------|
| `dump.sh` | Production `actuateadmin` DB via RDS proxy | `s3://actuate-rds/actuateadmin.backup` |
| `dump_kb.sh` | Production `kbcms` (knowledge base CMS) DB | `s3://actuate-rds/kbcms.backup` |
| `dump_support.sh` | Support wiki DB | S3 |

Dumps use `pg_dump` in custom format with pre-data, data, and post-data sections. The production dump excludes large tables like `inframap_motioncount`, `inframap_detectioncount`, `genesis*`, and `inframap_historical*` to keep the backup size manageable. Credentials are fetched from AWS Secrets Manager at dump time.

## Environment-Specific Pipelines

Separate `steps_*` directories contain tailored restore pipelines:

| Directory | Environment | Extra Steps |
|-----------|-------------|-------------|
| `steps_prod` | Production RDS | Download, restore, switch (no field patching). |
| `steps_dev` | [[dev-environment|Dev environment]] | Restore, update fields, switch, run migrations, notify Slack. |
| `steps_staging` | Staging environment | Same as dev -- restore, update, switch, migrate, Slack notify. |
| `steps_snapshot` | Snapshot-based | Disconnect sessions, dump snapshot, restore snapshot. |

## Docker Setup

The `docker/` directory provides a containerized local environment:

- **`docker-compose.yaml`** -- spins up PostgreSQL (port 5432) and Redis (port 6379) with named volumes for data persistence.
- Default platform is `linux/arm64` (Apple Silicon); set `DOCKER_PLATFORM=linux/amd64` for x86 machines.
- **`create.sh`** -- creates containers and initializes with data.
- **`remove.sh`** -- tears down containers; supports `--keep-volumes` and `--keep-backup` flags.

Data is persisted in Docker volumes rather than bind mounts to avoid the slow I/O performance of bind mounts on Apple Silicon Macs.
