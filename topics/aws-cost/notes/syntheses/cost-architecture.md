---
title: "Cost Architecture"
type: synthesis
topic: aws-cost
tags: [synthesis, cross-topic, cost, infrastructure, eks, gpu, dynamodb, sharding, watchman]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Cost Architecture

The Actuate platform's cost structure is a layered composition of EKS compute, GPU inference, managed data services, and delivery infrastructure. Understanding per-site economics is essential as the platform operates two concurrent business models: the existing B2B2B partner channel and the emerging [[watchman/_summary|Actuate Watchman]] B2B direct play targeting many small sites. This synthesis maps the major cost components and identifies where [[watchman/_summary|Actuate Watchman]]'s multiplier effect amplifies or compresses each layer.

## EKS Compute: The Connector Layer

The [[vms-connector]] runs as one Kubernetes Deployment per site in the `rearchitecture` namespace on EKS (account 388576304176, primary region us-west-2, EU in eu-west-1). Memory is budgeted at `cameras * 32MB + 500MB base`, with steady-state RSS around 270 MB per camera. The [[connector-deployer]] provisions each deployment with a paired VerticalPodAutoscaler (VPA) and PodDisruptionBudget.

[[sharding|Camera sharding]] is the dominant compute cost lever. When a site exceeds the shard size (default 24 cameras), `ChunkedSiteManager` forks into multiple OS processes. Empirical testing found that crossing a shard boundary incurs a CPU increase of at least 50-80% -- the single most expensive operation in the connector. Keeping even one additional camera on the same process saves 0.5-2 CPU, enough to offset cost increases across 10 other sites. The default shard size was raised to 24 specifically to reduce unnecessary forking.

VPA itself is a cost problem. ENG-78 (Highest priority, unassigned) documents VPA over-provisioning: resource requests are 3-5x CPU and 2x memory versus actual utilization. This waste compounds across hundreds of active deployments. The EKS upgrade to 1.35 (ENG-79, also unassigned) would enable in-place pod resize, eliminating VPA eviction restarts that cause both service disruption and transient over-allocation.

Docker images are built in four variants (x86 CPU, x86 GPU, ARM CPU, ARM GPU) and pushed to ECR repositories (`arm_connector_rearch`, `connectors_rearch`). ARM instances (Graviton) offer roughly 20% cost savings over equivalent x86 for CPU-bound connector workloads -- an important multiplier as site count grows.

## GPU Inference: YOLO vs VLM

Model inference runs in the `ds-model-prod` / `ds-model-dev` K8s namespaces. The cost profile diverges sharply between YOLO and VLM workloads:

**YOLO inference** (intruder v5/v8, weapon, fire, etc.) runs on the [[ds-server-container]] Rust servers. These are the workhorse -- every frame in the production pipeline passes through YOLO. The existing fleet uses a mix of CPU instances and Inferentia2 accelerators. Inferentia2 (AWS's custom inference chip, available on `inf2` instances) is significantly cheaper than GPU instances for the deterministic, high-throughput inference patterns that YOLO requires. The multi-head inference initiative (AI-204, not yet started) would further reduce per-frame cost by running multiple detection models in a single forward pass.

**[[vlm-inference|VLM inference]]** (Qwen3-VL-8B-Instruct, Qwen2.5-VL-32B-Instruct-AWQ, Gemma-3-12B-IT-FP8) runs via [[vlm-inference]] on g5.2xlarge instances (~$1.21/hr) with 24 GB VRAM. These are GPU instances that cannot run on Inferentia2 because VLM architectures require general-purpose GPU compute with dynamic attention patterns. The [[actuate-vlm]] client decouples the request path via SQS FIFO queues, with KEDA scaling replicas from zero based on queue depth. This scale-to-zero capability is critical -- [[vlm-inference|VLM inference]] is expensive enough that idle GPU time must be eliminated.

The cost gap between these two tiers defines the economic boundary of the [[vlm-fp-reduction]] filter and [[watchman/_summary|Actuate Watchman]]'s two-track routing. Every frame that reaches a VLM costs roughly an order of magnitude more than YOLO inference alone. The layered architecture (YOLO as cheap high-throughput gate, VLM as expensive high-accuracy verifier) exists because running VLM on every frame is economically infeasible at production volumes.

## Data Services: DynamoDB, S3, SQS

The platform operates 20+ DynamoDB tables: WindowIdsV2, EnrichedFrameV2, DetectedV2, ImageData, CameraStatus, PeopleFlow, Healthcheck, SceneChange, Motion, Blacklist, Analysis, ClipsMetadata, Token, and VLM result tables. DynamoDB costs scale with read/write capacity units and storage volume. The WindowIdsV2 table is particularly write-heavy -- every detection window produces multiple writes across window creation, frame enrichment, and VLM verdict storage.

S3 stores frame images, video clips, [[settings-files|settings files]], and cost analysis CSVs. Frame storage is the largest volume -- each detection window persists annotated frames to S3 for alert delivery and later review. The [[s3-frame-fallback]] pattern (ENG-93) adds additional S3 reads when deferred alerts miss the in-memory cache, but the cost is marginal relative to the alternative (dropped alerts).

SQS FIFO queues handle per-integration alert delivery (e.g., `event_queue_immix_alarm.fifo`) and VLM request routing (e.g., `vlm-qwen3-vl-8b-instruct.fifo`). SQS costs are per-request and generally modest, but the FIFO queues' 300 TPS limit can become a bottleneck under the thundering-herd scenario documented in ENG-66.

## Supporting Services

| Service | Purpose | Cost Driver |
|---|---|---|
| **ECS** | [[admin-api/_summary|Actuate Admin API]] (Django + Gunicorn + Nginx) | Fixed -- small fleet |
| **Lambda** | [[inference-api/_summary|Actuate Inference API]] (external partner API) + Rust authorizer | Per-invocation, scales with partner API usage |
| **RDS (PostgreSQL)** | Admin database (`actuateadminprodcluster`) | Fixed instance cost + storage. BT-926 CPU spikes from recursive CTE increase effective cost. |
| **ElastiCache** | Performance caching | Fixed |
| **Route 53 / ACM** | DNS + TLS | Minimal |
| **[[new-relic|New Relic]] / Datadog** | Observability | Per-host/per-event -- grows with connector fleet |

## Cost Visibility

The [[actuate-cost-analysis]] tool runs as a Docker container on EKS, producing per-site cost breakdowns (compute, inference, slicing, storage) as CSVs stored in S3. The [[sales-dashboard]] consumes these CSVs alongside Ordway billing data, HubSpot CRM data, and Snowflake analytics to present a unified view of account profitability. This two-pass matching (Ordway master list + S3 cost-only accounts) enables the business to identify sites where infrastructure cost exceeds revenue -- a critical metric as [[watchman/_summary|Actuate Watchman]] targets smaller sites with tighter margins.

## Watchman's Cost Multiplier

[[watchman/_summary|Actuate Watchman]] targets businesses with 4-30 cameras -- dramatically smaller than many current B2B2B sites. Per-site economics shift:

- **Connector overhead dominates.** A 4-camera site still needs a K8s Deployment, VPA, PDB, and monitoring. The 500 MB base memory is amortized across only 4 cameras instead of 50+. If [[watchman/_summary|Actuate Watchman]] reaches hundreds of small sites, the per-site fixed cost of K8s resource management, [[connector-deployer]] API calls, and monitoring becomes the dominant expense.
- **[[sharding|Sharding]] is rare.** Most [[watchman-repo|Watchman]] sites will be well under the 24-camera shard size, avoiding the 50-80% CPU penalty of multiprocessing. This is favorable.
- **Agent overhead is additive.** The multi-agent orchestration layer (Site Supervisor, Patrol Agent, Assessment Agent, etc.) adds per-site compute beyond the bare connector pipeline. The agent runtime needs its own hosting -- likely a new K8s namespace -- and its own scaling model.
- **VLM cost per site is higher proportionally.** If [[watchman/_summary|Actuate Watchman]]'s two-track routing sends more events to VLM assessment (for the compound severity scoring that differentiates the product), the g5.2xlarge cost is spread across fewer cameras per site.
- **Escalation infrastructure is new cost.** Push notifications, SMS, and automated phone calls (CRITICAL tier auto-escalate after 60s) require new service integrations beyond SES/SNS, each with per-message pricing.

The EKS upgrade (1.35 for in-place pod resize) and VPA fixes become urgent under this model. Over-provisioning by 3-5x CPU on 50 sites is expensive; doing it on 500 sites is untenable. Dynamic, per-site shard sizing (the long-term strategy documented in [[sharding]]) would help -- logging per-site performance to DynamoDB and adjusting resources based on observed utilization rather than worst-case defaults.

## Per-Site Breakeven

The [[sales-dashboard]]'s ability to show compute + inference + slicing + storage cost per site, matched against Ordway revenue, is the key tool for [[watchman-repo|Watchman]] pricing decisions. The question is whether a 4-camera site's infrastructure cost (connector Deployment + monitoring + [[vlm-inference|VLM inference]] + agent compute + escalation messaging) can fit within a price point that undercuts RVM ($50-150+/camera/month) while maintaining margin. If the fully loaded cost for a 10-camera site exceeds $200/month, the market thesis narrows significantly. The [[actuate-cost-analysis]] tool and [[sales-dashboard|sales dashboard]] need to model Watchman-scale sites specifically, not just extrapolate from current large-site economics.
