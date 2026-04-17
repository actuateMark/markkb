---
title: "actuate-labeling-tool"
type: entity
topic: data-science
tags: [repo, label-studio, annotation, docker, terraform, aws, rbac, gdpr]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-labeling-tool

Self-hosted data annotation platform built on Label Studio, with a custom RBAC and security overlay, Dockerised deployment, and Terraform-managed AWS infrastructure.

**Repo:** `aegissystems/actuate-labeling-tool` (private, updated 2026-04-08)

## Purpose

Provides a centralised labeling tool for the data science team to annotate training data (images, video frames, detections) for models used in the Actuate surveillance pipeline. Built on the open-source Label Studio platform with an in-house security layer on top.

## Architecture

The stack consists of:

- **Label Studio** -- the core annotation UI, running in Docker.
- **`actuate_ls` package** -- a custom Django overlay that adds RBAC middleware, audit logging, role-seeding management commands, and GDPR data-handling commands (`export_gdpr`, `erase_gdpr`).
- **PostgreSQL** -- backing database (RDS in production, Docker Compose locally).
- **Nginx** -- TLS termination (self-signed certs for dev, ALB for production).
- **Terraform modules** -- IaC for networking, compute, RDS, S3, ALB, and secrets in `us-west-2`.

## Local Development

1. Generate dev TLS certificates via `scripts/generate-dev-certs.sh`.
2. Copy `.env.example` to `.env` and configure `POSTGRES_PASSWORD` and `LABEL_STUDIO_SECRET_KEY`.
3. Run `docker compose -f docker/docker-compose.yml up --build` (first run takes approximately 5 minutes).
4. Access at `https://localhost` with the admin credentials from `.env`.

## Production Deployment

Infrastructure is managed by Terraform under `terraform/environments/us-west-2/`. CI/CD is handled by GitHub Actions: pushes to `main` build the Docker image, push to ECR, and deploy via SSM. Secrets (DB password, secret key, allowed hosts) are stored in AWS Secrets Manager.

## Security and Compliance

- **RBAC**: Custom middleware enforces role-based access; roles are seeded via a Django management command.
- **GDPR**: Dedicated runbook and management commands for data export and erasure requests.
- **Audit logging**: All annotation actions are logged through the middleware layer.
- **RBAC matrix**: Documented in `docs/rbac-matrix.md`.

## Tech Stack

Python 3.10+, Django 4.2+, boto3, Docker, Terraform (HCL), Shell scripts. Languages by size: Python (primary), HCL (Terraform), Shell, Dockerfile.

## Related

- [[person-classifier]] -- one of the models whose training data is labeled here
