---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [aws, infrastructure, deployment, gdpr, regions]
---

# Multi-Region Deployment

Actuate operates a **multi-region AWS deployment** to serve global customers while meeting European data residency requirements. The architecture spans at least two AWS regions and uses a multi-account strategy.

## Primary Region: us-west-2

The **us-west-2 (Oregon)** region hosts the primary Actuate deployment serving North American customers and global operations. This region runs the full [[data-flow-architecture]] pipeline:

- **EKS cluster** with [[argocd|ArgoCD]] GitOps for continuous deployment. The cluster hosts:
  - `rearchitecture` namespace -- [[vms-connector]] pods (one per site)
  - `ds-model-prod` namespace -- Rust-based YOLO model servers for ML inference
  - `queue_consumer` pods for SQS FIFO alert delivery
  - `connector_deployer` for connector lifecycle management
- **ECS** -- Hosts the [[admin-api/_summary|Actuate Admin API]] (Django 6.0 + DRF)
- **Lambda** -- Hosts [[inference-api/_summary|Actuate Inference API]] (FastAPI + Mangum, container-based)
- **DynamoDB** -- Core data tables (WindowIds, DetectedV2, EnrichedFrame, ImageData, CameraStatus, etc.)
- **S3** -- Frame storage, video clips, settings, model artifacts
- **SQS/SNS** -- Alert queuing and notification
- **RDS (Aurora PostgreSQL)** -- Relational data for the Admin API (subject to CPU spike issues, see [[active-risks]])
- **ElastiCache** -- Caching layer
- **Monitoring** -- [[new-relic|New Relic]], CloudWatch, Datadog

The primary AWS account is **388576304176**.

## EU Region: eu-west-1 (GDPR)

The **eu-west-1 (Ireland)** region exists to satisfy **GDPR data residency requirements** for European customers. European camera feeds must be processed and stored within the EU to comply with data protection regulations.

The EU deployment has its own Jira project (**ED -- EU Deployment**) tracking EU-specific work including:

- EBUS integration (European partner, v5 API update pending with [[mark-barbera]])
- Monitex integration
- Action log enhancements (ED-10, [[jessica-bae]])
- [[alert-muting|Alert muting]] (ED-12)
- YoursIx VMS and [[ajax-components|Ajax]]/StarFM support ([[paolo-zilioti|Paolo Zilioti]], ENG-118, ED-2 -- flagged as Highest priority for EU)

EU model development is also active, with a generalist model deployed and bespoke models continuing (Mladen Lukic handling UK/EU labeling and testing, AI-169, AI-160). The [[edge-hardware-track]] for Morphean/VIDEOR also aligns with EU data residency goals by processing video locally.

## Multi-Account Strategy

Actuate uses a **multi-account AWS strategy**, though the full account topology is not fully documented in available sources. The primary account (388576304176) is known; separate accounts likely exist for:

- Production vs. staging/development isolation
- EU region workloads (for clean GDPR compliance boundaries)
- Data science / model training (GPU instances)

The multi-account approach provides blast-radius isolation, independent billing, and IAM boundary enforcement.

## Orchestration: ArgoCD GitOps

Deployments to EKS are managed via **[[argocd|ArgoCD]]**, a GitOps continuous delivery tool. This means:

- Desired cluster state is declared in Git repositories
- [[argocd|ArgoCD]] syncs the cluster to match the Git-declared state
- Changes deploy by merging PRs, not by running kubectl commands

This is relevant to the [[jira-reorg-proposal]]'s GitHub + Jira integration plans -- PR merges that trigger [[argocd|ArgoCD]] syncs can also trigger Jira ticket transitions.

## Infrastructure Risks

Several infrastructure risks are tracked in [[active-risks]]:
- **EKS upgrade** -- unowned Highest-priority ticket
- **VPA (Vertical Pod Autoscaler)** -- unowned Highest-priority ticket
- **Multi-AZ hosting** -- MAH Jira project exists but has low activity
- **Aurora CPU spikes** -- [[database-performance|database performance]] under [[tatiana-hanazaki]]'s remediation

## See Also

- [[data-flow-architecture]] -- what runs in these regions
- [[jacob-weiss]] -- engineering lead overseeing infrastructure
- [[active-risks]] -- infrastructure-level risks
- [[edge-hardware-track]] -- EU-friendly edge processing alternative
