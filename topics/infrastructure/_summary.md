---
title: Infrastructure & Security
type: summary
topic: infrastructure
tags: [aws, eks, terraform, wireguard, security, cognito, secrets]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/PM/pages/488079361"
created: 2026-04-13
updated: 2026-04-14
author: kb-bot
---

# Infrastructure & Security

## AWS Account & Regions

- **Account:** 388576304176
- **Primary:** us-west-2
- **EU:** eu-west-1 (GDPR)
- **Orchestration:** EKS clusters (managed via ArgoCD GitOps from aegissystems)

## Key Services

| Service | AWS Resource | Purpose |
|---------|-------------|---------|
| VMS Connector | EKS (rearchitecture namespace) | Frame processing pipeline |
| Model Servers | EKS (ds-model-prod/dev) | YOLO inference |
| Admin API | ECS (Docker + Nginx + Gunicorn) | Config & management |
| Inference API | Lambda (container image) | External detection API |
| Authorizer | Lambda (Rust) | API key validation |
| Alert Delivery | SQS FIFO queues | Per-integration alert routing |
| Data | DynamoDB, S3, PostgreSQL (RDS) | Storage |
| Caching | ElastiCache | Performance |
| DNS | Route 53 | Domain management |
| Certs | ACM + cert-manager | TLS |
| VPN | WireGuard | Customer camera connectivity |
| Monitoring | New Relic, CloudWatch, Datadog | Observability |

## Security

### Encryption
- TLS 1.2+ for platform traffic
- AES-256 at rest (S3, RDS, DynamoDB, ElastiCache)
- Istio mTLS (progressive rollout)

### Authentication
- **Customer-facing:** AWS Cognito (social login prod, local dev)
- **API:** API keys via DynamoDB + Rust Lambda authorizers
- **Internal:** VPC private subnets, Security Groups

### Critical Security Gaps (Internal, April 2026)

| Gap | Risk | Remediation |
|-----|------|-------------|
| **Secrets in Git** | API keys, Snowflake creds, DB strings in `cluster-values.yaml` | Deploy External Secrets Operator, migrate to AWS Secrets Manager |
| **Cognito single client** | 19+ apps share one client; destructive update API | Automate per-app client provisioning |
| **WireGuard coverage** | Not universal for camera connections | Extend coverage |

## WireGuard VPN

Customer camera connectivity via encrypted tunnels. Teltonika RUT241 routers or Actuate Secure App.

**Active work:**
- **ENG-117** (Aziz, In Progress) -- Phase 5A: server metrics and observability
- **PROD-31/35** (QA/QC) -- Site-level WireGuard tunnel views
- **PROD-265/266** -- Exponential backoff retry + reconnection telemetry

## EKS Upgrade Needed

**ENG-79 (Highest, Unassigned):** Upgrade EKS 1.32 -> 1.35. In-place pod resize (GA in 1.35) would eliminate VPA eviction restarts. Related to ENG-78 (VPA over-provisioning).

## ECR Image Build Pipeline

Docker images for [[vms-connector]] are built and pushed to ECR via GitHub Actions:

| Workflow | Trigger | Image Tag |
|----------|---------|-----------|
| `Deploy to ECR Rearchitecture Stage` | Push to `stage` | `:stage` |
| `Deploy to ECR Rearchitecture Custom` | Push to any non-protected branch | `:<sanitized-branch-name>` |
| Production build | Push to `rearchitecture` | `:latest` |

Each workflow runs parallel **ARM64** and **x86** build jobs. ARM64 uses a self-hosted runner; x86 uses `ubuntu-latest`. Both authenticate to ECR via OIDC role assumption, fetch a CodeArtifact token for internal Python dependencies, and build with `docker/build-push-action@v6`.

**ECR repositories:** `arm_connector_rearch` (ARM64), `connectors_rearch` (x86) — account `388576304176` / `us-west-2`.

**Caching:** Dual-layer — local buildx cache on runner (`/tmp/.buildx-cache-*`) + registry-level cache image (`:buildcache-arm`, `:buildcache-x86`) in ECR. Slack notifications post to `#dev` on success/failure.

**Branch-to-tag mapping** is deterministic: branch name sanitized (non-alphanumeric stripped, capped at 128 chars). This enables per-branch ECR images for staging individual features on real hardware without touching the `stage` image.

See [[connector-library-deployment-lifecycle]] for the full deployment process and [[connector-fleet-monitoring]] for NRQL query patterns used during release monitoring.

## IaC Repos

- `ds-terraform-eks-v2` -- EKS cluster, API Gateway, Terraform modules
- `kubernetes-deployments` -- Helm charts, ArgoCD configs
- `actuate-inference-api/terraform/` -- Lambda, API Gateway, DynamoDB, multi-region
