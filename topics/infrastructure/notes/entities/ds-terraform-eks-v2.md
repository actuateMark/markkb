---
title: "ds-terraform-eks-v2"
type: entity
topic: infrastructure
tags: [terraform, terragrunt, iac, aws, eks]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# ds-terraform-eks-v2

The primary Infrastructure as Code (IaC) repository for Actuate's AWS infrastructure. Built with **Terraform** and orchestrated by **Terragrunt** to support multi-environment (`dev`, `prod`) and multi-region (`eu-west-1`, `us-west-2`) deployments.

## Modules

The `modules/` directory contains 30+ reusable Terraform modules covering the full stack:

- **Networking & DNS**: `shared-infrastructure` (VPC, subnets, AZs), `route53`, `fck-nat-vpn`, `fck-nat-optional-vpn`, `actuate-fck-nat`.
- **Compute -- EKS**: `eks-infrastructure` (EKS control plane, node groups, IAM, networking), `eks-irsa` (IAM Roles for Service Accounts -- Thanos S3 access), `eks-services`, `eks-cicd`.
- **Compute -- ECS**: `ecs`, `ecs-services` (signal receiver HTTP/TCP, job scheduler), `ec2-service`.
- **Serverless**: `core-lambdas` (inference auth, SNS-to-Slack, detection window, token refresh, immix onboarding, csupdates, blur metric, admin status/camera), `lambdas`, `lambda-layers`, `lambda-secrets-manager`.
- **Storage**: `s3-buckets` (clips, clips_sync, ai_link, sentinel, settings, analytics_ui, admin_temp, admin_onboarding), `s3-ui` (camera-ui, [[alert-ui]] via CloudFront).
- **Data**: `dynamodb` (~20 tables including AuthorizationV2, CameraStatus, Heartbeat, EnrichedFrameV2, WindowIdsV2, scene change tables), `rds` (Aurora), `redis`.
- **Messaging**: `sqs_queue` (14 queues: analytics, eagle_eye, healthcheck, immix_alarm, sentinel_alarm, webhook, etc.), `sns_topics` (customer-warnings).
- **Auth & Security**: `cognito` (user pools, app clients), `iam`, `ses`, `acm`.
- **CI/CD & Container**: `ecr`, `ecr-pull-through-cache` (Docker Hub caching), `api_gateway`.
- **Monitoring**: `monitoring_api` (ECS-based monitoring API + camera admin).

## Stages and State Management

Environment configs live under `stages/{env}/{region}/`:

- **dev/eu-west-1** -- 17 stacks (shared-infrastructure, dynamodb, eks-infrastructure, ecs-services, core-lambdas, s3-buckets, s3-ui, cognito, sqs_queue, sns_topics, eks-irsa, eks-cicd, eks-services, monitoring_api, ec2_service, ecr-pull-through-cache, snowflake-integration).
- **prod/eu-west-1** -- full production stack with additional modules (acm, api_gateway, ecr, iam, lambdas, rds, redis, route53, ses).
- **prod/us-west-2** -- multi-region production.

Each region has a `root.hcl` that defines shared locals (account ID, VPC IDs, subnets, CIDR blocks, cert ARNs) and configures the Terragrunt remote state backend. State is stored in S3 buckets named `actuate-terragrunt-state-{region}-{stage}`, with per-module state keys and encryption enabled. Lock files are used instead of DynamoDB locking.

## Prerequisites and Workflow

Requires AWS CLI, Terraform, Terragrunt, and pre-commit. The `shared-infrastructure` and `s3-buckets` modules must be applied first as foundational dependencies; all other modules can be applied in any order after that. Pre-commit hooks enforce Terraform formatting and validation.
