---
title: Core Repository Suite
type: entity
topic: actuate-platform
tags: [repos, github, development, reference]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Core Repository Suite

Canonical list of repositories and their local clone status. Repos in the "clone on need" list should be cloned to `/home/mork/work/` when they become active sources for a task.

**Rule:** When a task requires reading or modifying a remote-only repo, clone it first: `cd /home/mork/work && gh repo clone aegissystems/{repo}`

## Local (20 repos in /home/mork/work/)

| Repo | Category | Primary Use |
|------|----------|-------------|
| actuate-inference-api | API | External detection API (v1-v5) |
| actuate-libraries | Libraries | 41-package UV monorepo |
| actuate_admin | API | Django admin/config backbone |
| vms-connector | Core | Frame processing pipeline |
| autopatrol-server | Product | AutoPatrol scheduling backend |
| autopatrol_onboarder | Product | Lambda sync from Immix Connect |
| connector_deployer | Infra | K8s connector lifecycle management |
| queue_consumer | Infra | SQS alert delivery (16 consumer types) |
| kubernetes-deployments | IaC | ArgoCD Helm charts, app-of-apps |
| ds-terraform-eks-v2 | IaC | Terraform modules (30+) |
| camera-ui | Frontend | React SPA for camera management |
| alertviewer | Frontend | Alert video viewer |
| health_report | Lambda | CHM email report generation |
| actuate_admin_rds | Tooling | DB backup/restore scripts |
| dev-environment | Tooling | Developer onboarding |
| settings-files | Config | 207 VMS connector JSON configs |
| layers | Lambda | Lambda layer (requests lib) |
| adpro_puller | Integration | Rust Adpro XO puller |
| actuate-claude-agents | Tooling | Claude Code agents/skills |
| actuate-cursor-rules | Tooling | Cursor/Claude Code rules |

## Clone on Need (High Priority)

These are actively developed, frequently referenced in the KB, and likely needed soon:

| Repo | Category | Why You'd Need It |
|------|----------|-------------------|
| **Watchman** | Product | Greenfield Watchman agentic AI -- active development target |
| **actuate-external-api** | API | Partner API proxy -- ENG-122 workstreams |
| **alert-ui** | Frontend | Vue 3 alert dashboard -- UI changes |
| **actuate_monitoring_api** | API | Django monitoring API -- read-only dashboards |
| **actuate_ailink** | Integration | WebSocket server for AILink/Sentinel/Frontel/Yousix |
| **ds-server-container** | ML | Rust YOLO inference server -- model deployment |
| **ds-training-pipeline** | ML | SageMaker training -- model development |
| **connector-tools** | Tooling | Camera management CLI utils (K8s jobs) |

## Clone on Need (DS/ML)

| Repo | Category | Why You'd Need It |
|------|----------|-------------------|
| **actuate-eval** | Evaluation | mAP/McNemar/Wilcoxon toolkit -- model validation |
| **shadow-test-pipeline** | Evaluation | Prod vs dev model comparison infra |
| **vlm-inference** | ML | VLM inference workers (SQS + vLLM + KEDA) |
| **ppf** | ML | Pixels-per-foot depth estimation |
| **actuate-labeling-tool** | Data | Self-hosted Label Studio |
| **ds-smart-alert-supervisor** | ML | VLM alert verification system |
| **actuate-data-registry-dvc** | Data | DVC data hub for CV datasets |
| **training_data_sampler** | Data | Production data sampling for labeling |

## Clone on Need (Infrastructure)

| Repo | Category | Why You'd Need It |
|------|----------|-------------------|
| **reusable-github-actions** | CI/CD | Shared workflows + Docker base images |
| **network-configuration** | VPN | AWS VPN management tool |
| **actuate-cost-analysis** | Ops | EKS cost analysis |
| **actuate-watchman** | Product | On-prem line crossing pipeline |
| **actuate-watchman-internal** | Product | Internal watchman variant |

## Low Priority / Reference Only

These are older, less active, or highly specialized -- don't clone unless specifically needed:

- classifyr, wireguard-route-manager, shadow-testing-stats, qwen3vl-aws
- frame_fetcher_v3, frame_receiver_smtp_v2, create_detection_window
- remote-access-proxy, sns_to_slack, lambda_admin_status
- admin-auto-onboarding, actuate-automation-test, design-demos-repo
- architecture-decision-records, ai-kb-scripts, actuate_bi, sales-dashboard
