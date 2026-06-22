---
title: "Connector Deployer"
type: entity
topic: vms-connector
tags: [connector, deployer, kubernetes, fastapi, eks, infrastructure]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
outgoing:
  - topics/actuate-platform/notes/syntheses/camera-onboarding-end-to-end.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/actuate-platform/notes/syntheses/integration-landscape.md
  - topics/actuate-platform/notes/syntheses/watchman-vs-current-platform.md
  - topics/aws-cost/notes/syntheses/cost-architecture.md
  - topics/data-science/notes/syntheses/model-lifecycle.md
  - topics/personal-notes/notes/concepts/2026-04-29_cleanup-handoff.md
  - topics/product-roadmap/notes/syntheses/b2b2b-vs-b2b-go-to-market.md
  - topics/video-processing/notes/concepts/eks-prod-node-pool-gpu-availability.md
  - topics/vms-connector/notes/entities/connector-tools.md
incoming:
  - topics/actuate-platform/notes/syntheses/camera-onboarding-end-to-end.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/actuate-platform/notes/syntheses/integration-landscape.md
  - topics/actuate-platform/notes/syntheses/watchman-vs-current-platform.md
  - topics/autopatrol/notes/concepts/2026-04-28_tenant-status-sync-gap.md
  - topics/autopatrol/notes/syntheses/2026-05-01_silent-cameras-diagnosis.md
  - topics/aws-cost/notes/syntheses/cost-architecture.md
  - topics/data-science/notes/syntheses/model-lifecycle.md
  - topics/personal-notes/notes/concepts/2026-04-29_cleanup-handoff.md
  - topics/product-roadmap/notes/syntheses/b2b2b-vs-b2b-go-to-market.md
incoming_updated: 2026-05-27
---

## Overview

The **Connector Deployer** is an internal platform service that manages the lifecycle of [[vms-connector|VMS connector]] deployments on Kubernetes (EKS). It exposes a FastAPI HTTP API that the Admin backend calls to start, stop, reboot, and delete connector pods, create Camera Health Monitoring (CHM) cronjobs, run one-off tasks, and launch connector-tools jobs. It is the control plane that translates Admin API deployment requests into Kubernetes resources.

**Repository:** `aegissystems/connector_deployer`

## Tech Stack

- **Language:** Python 3.11+ (managed with `uv`)
- **Web Framework:** FastAPI with uvicorn
- **Kubernetes Client:** `kubernetes-asyncio` (async K8s API operations)
- **HTTP Client:** `httpx` (Slack notifications, integration patches)
- **YAML Generation:** `pyyaml` + in-house YAML template/patch system
- **Other:** `asyncache`/`cachetools` for caching, Pydantic for request validation

## Deployment Model

The service runs on EKS in the `connector` namespace. Production runs 4 replicas plus 1 canary replica (separate Deployment using a `develop` image tag). The pod uses a `serviceAccountName: internal-kubectl` for RBAC-scoped Kubernetes API access. The container image is built for `linux/arm64` and pushed to ECR repository `connector_deploy`.

CI/CD (`.github/workflows/main.yml`) triggers on push to `main` or `develop`. The `main` branch builds a `prod_<sha>` tagged image, pushes to ECR, and then triggers a Kubernetes deployment via a reusable `k8s-deploy.yml` workflow (application: `deployerPrd`). The `develop` branch builds a `dev_<sha>` tagged image for the canary.

The Dockerfile uses Amazon Linux as the base, installs Python 3.11, pip, and kubectl, then runs `uvicorn --host 0.0.0.0 --timeout-keep-alive=65 deployer:app`.

## Key Files and Entry Points

- **`deployer.py`** -- FastAPI app definition with all HTTP endpoints: `/health`, `/start`, `/reboot`, `/stop`, `/delete`, `/self_reboot/{hostname_id}`, `/task`, `/chm`, `/connector-tools`
- **`src/methods.py`** -- Core business logic: `start_internal`, `reboot_internal`, `delete_internal`, `self_reboot`, `start_task`, `create_chm_cronjob`, `delete_chm_cronjob`, `create_connector_tools`. Handles YAML generation, K8s API calls, VPA management, and Slack error notifications
- **`src/command.py`** -- `K8sApi` class wrapping `kubernetes-asyncio` for create/delete/reboot of Deployments, VPAs, CronJobs, and Jobs; also includes `async_subprocess` for kubectl commands
- **`src/enums.py`** -- Pydantic models for API requests: `DeploymentRequest`, `StopDeploymentRequest`, `CronjobRequest`, `ConnectorToolsRequest`; enums for `Arch` (arm/x86), `NAT`, `PatrolType`, `ConnectorToolsScript`
- **`src/generate_yaml.py`** -- YAML template loading and patching functions for Deployments, VPAs, CronJobs, Tasks, PDBs, and connector-tools Jobs
- **`src/yaml/`** -- YAML template definitions: `deployment.py`, `cronjob.py`, `vpa.py`, `vpa_cronjob.py`, `task.py`, `pdb.py`, `connector_tools_job.py`
- **`src/config.py`** -- App configuration: `preserve_vpa` flag (default true, controlled by `APP_PRESERVE_VPA` env var)
- **`manifests/prod/`** -- Production Kubernetes manifests: Deployment (4 replicas + canary), Service, Ingress, PDB, ConfigMap, CronJob, access RBAC

## Configuration

The deployer itself has minimal configuration -- primarily the `APP_PRESERVE_VPA` environment variable (defaults to `true`). All deployment parameters (stage, architecture, NAT, wireguard, image tag, lead, etc.) come via the API request payloads.

Image selection logic maps stages to ECR repositories: `prod` -> `arm_connector`/`connectors`, `rearch` -> `arm_connector_rearch`/`connectors_rearch`, etc. The namespace is determined by stage: `prod`/`dev` -> `connector`, everything else -> `rearchitecture`.

## Dependencies on Other Actuate Services

- **Admin API** -- the primary caller; triggers connector deployments via HTTP
- **Slack** -- receives error/warning notifications via webhook
- **EKS Cluster** -- the deployer operates directly on the Kubernetes API to manage connector pods, VPAs, cronjobs, and jobs
- **ECR** -- connector images are pulled from various ECR repositories based on stage and architecture

## Architecture Patterns

- **Async-first**: All K8s operations and HTTP calls are async, leveraging `kubernetes-asyncio` and `httpx`
- **YAML template patching**: Rather than generating YAML from scratch, the deployer loads base templates and applies patches/overrides for each deployment's specific configuration
- **VPA co-management**: Each connector deployment gets a paired VerticalPodAutoscaler; VPA recommendations from CHM cronjob VPAs are read to size task jobs
- **Cron schedule randomization**: CHM cronjob schedules are randomized (random minute, distributed hours) to spread load across the cluster
- **Canary deployment**: Production runs a separate canary Deployment with 1 replica using the `develop` image tag alongside the 4-replica production Deployment
- **Hostname ID normalization**: Deployment IDs are sanitized (lowercase, hyphens, 63-char Kubernetes name limit) to produce valid K8s resource names
