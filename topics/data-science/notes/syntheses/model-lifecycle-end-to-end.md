---
title: "Model Lifecycle End-to-End"
type: synthesis
topic: data-science
tags: [synthesis, cross-topic, model-lifecycle, training, evaluation, deployment, shadow-testing, monitoring, retirement]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Model Lifecycle End-to-End

## Overview

This synthesis traces the complete lifecycle of a YOLO model at Actuate, from the moment production data is sampled for labeling through training, multi-tier evaluation, deployment to Kubernetes, production monitoring, and eventual retirement. Each phase has dedicated tooling, repos, and human owners. The lifecycle is designed around a core principle: **no model reaches production without passing every evaluation gate**, and **full provenance links every deployed model back to its exact training data, hyperparameters, and evaluation results**.

The v8 intruder rollout (AI-180) and weapon v8 deployment (PROD-98) serve as concrete examples throughout.

## Phase 1: Data Collection

The lifecycle begins with production data. [[training-data-sampler]] queries the production Postgres database to extract frames (images) or windows (video clips) matching desired criteria -- scene diversity, geographic spread, failure-case targeting, or specific alert types. Data is structured into **Batches** (smallest unit), grouped into **Data Packs** (thematic collections), and assembled into **Data Decks** (the complete training corpus).

Sampled media is uploaded to the `actuate-training-data-new` S3 bucket for labeling.

**Key repo:** `aegissystems/training_data_sampler`
**Owner:** DS team

## Phase 2: Labeling

Two labeling platforms serve different needs:

- **[[actuate-labeling-tool]]** (Spektar) -- Self-hosted Label Studio with custom RBAC, audit logging, and GDPR compliance. Used for internal bounding-box annotation by the DS team.
- **Encord** -- External labeling platform for larger-scale or outsourced annotation. [[training-data-sampler]] has native Encord integration (project creation, media upload, label retrieval via ontology hashes and workflow templates).

For rapid evaluation cycles, **Mladen Lukic's point-based annotation** method uses centroid marking instead of full bounding boxes, dramatically accelerating turnaround. This was critical during the UK/EU bespoke model experiments where multiple iterations needed quick feedback (Confluence: "A High-Speed Framework for Model Evaluation: Point-Based Annotation").

**Key repos:** `aegissystems/actuate-labeling-tool`, Encord (external)
**Key people:** Mladen Lukic (point-based annotation), Alena Prashkovich (UK camera screening)

## Phase 3: Data Versioning

Labeled data flows into [[actuate-data-registry-dvc]], the DVC-backed data registry on S3. The "Coordinator Model" separates compute (curation scripts in `ai-kb-scripts`) from catalog (lightweight `.dvc` pointers and `meta.yaml` in Git) from storage (content-addressable S3). Each incremental batch progresses through three stages:

1. `01_raw/` -- uncurated production data, frozen with `dvc add`
2. `02_pre_encord/` -- curated subset after active learning, ready for labeling
3. `03_post_encord/` -- human-verified labels from Encord

Golden production datasets live under `{model_name}/base_training_sets/`. The `datasets/dataset_manifest.yaml` in [[ds-training-pipeline]] is the canonical S3 reference for all products.

**Key repo:** `aegissystems/actuate-data-registry-dvc`

## Phase 4: Training

[[ds-training-pipeline]] executes training on AWS SageMaker, supporting the full Ultralytics ecosystem (YOLOv5u through YOLO26, YOLOE, YOLO World, RT-DETR) and Roboflow's RF-DETR. See [[training-pipeline-architecture]] for architecture details.

Key configuration levers:
- **Training presets** (`baseline`, `quick_test`, `small_object_v1`--`v4_balanced`) control resolution (640--1280px) and loss weights
- **Custom fitness functions** (`recall_map50`, `f1_balanced`, etc.) determine checkpoint selection
- **SSL pretraining** (DINOv2, SimCLR, BYOL) bootstraps fine-tuning on smaller labeled datasets
- **NeuronX compilation** transforms trained PyTorch models for Inferentia2 deployment

All experiments tracked in Weights & Biases.

**Key repo:** `aegissystems/ds-training-pipeline`
**Key people:** Carlos Torres (weapon model), Otzar Jaffe (PPF, model merging)

## Phase 5: Evaluation

The [[evaluation-tiers|6-tier evaluation framework]] gates every model before deployment:

| Tier | Method | Tool | What It Catches |
|------|--------|------|-----------------|
| 1 | Frame-level mAP@0.5 | [[actuate-eval]] | Raw detection accuracy regression |
| 2 | Point-based annotation | Centroid matching | Rapid screening (optional) |
| 3 | Genesis FP stress | Curated hard scenes | FP resilience regression |
| 4 | Confidence threshold sweep | [[actuate-eval]] + sweep scripts | Poor calibration, threshold instability |
| 5 | Shadow testing (McNemar) | [[shadow-test-pipeline]] | Alert-level regression on live traffic |
| 6 | Cumulative misses | Regression dataset | Re-introduction of known failures |

Shadow testing (Tier 5) is the most production-representative: the candidate runs in `ds-model-dev` alongside production in `ds-model-prod`, processing identical live feeds. McNemar's paired test on the 2x2 discordant-pair contingency table provides statistical significance. See [[shadow-testing-methodology]] for the statistical details.

The February 2026 shadow test (Confluence: "DEV vs PROD Shadow Test Evaluation") compared `int07-actuate003-v8` vs `intruder-384h-512w-svc` at the alert-sequence level, leading to v8 approval. [[confidence-threshold-calibration]] determines per-model, per-label operating points from the Tier 4 sweep.

**Key repos:** `aegissystems/actuate-eval`, `aegissystems/shadow-test-pipeline`, `aegissystems/shadow-testing-stats`
**Key people:** Uladzimir Sapeshka / Vlad (evaluation, shadow testing), Zack Schmidt (model decisions)

## Phase 6: Deployment

Trained and NeuronX-compiled models are packaged into [[ds-server-container]] Docker images -- a Rust-based inference platform with two binaries:

- **inference_server** (x86_64, Inferentia2) -- core YOLO inference
- **slicing_server** (aarch64, Graviton4) -- SAHI-style tiling proxy for high-resolution frames

Model-specific images layer on top of a base inference server image, are pushed to ECR, and deployed to the `ds-model-prod` Kubernetes namespace via ArgoCD from the `kubernetes-deployments` repo. Each model gets a Service at `http://{model}-svc.ds-model-prod.svc.cluster.local:8080/infer`.

VLM models ([[vlm-pipeline-architecture]]) follow a separate deployment path: Docker images with vLLM backend, deployed to K8s with KEDA autoscaling from SQS queue depth, writing results to DynamoDB.

**Key repos:** `aegissystems/ds-server-container`, `aegissystems/vlm-inference`, `aegissystems/kubernetes-deployments`

## Phase 7: Production Monitoring

After deployment, the model enters ongoing monitoring:

- **Shadow testing (ongoing):** The same [[shadow-test-pipeline]] infrastructure can run continuous comparison against experimental successors
- **YAM re-evaluation (AI-211):** When code changes affect the inference path (e.g., commit `788bed7` changing chip generation to original-frame resolution), all endpoints need re-evaluation -- currently the highest-priority initiative
- **Observability:** New Relic, CloudWatch, and Datadog track inference latency, error rates, and throughput via [[actuate-monitoring]]
- **Analytics:** [[actuate-event-listener]] tracks per-model, per-camera detection rates for anomaly detection
- **[[ds-analysis-microservice]]:** Enables controlled single-variable experiments on pipeline components (FDMD, filters, slicing, loiterer) against production baselines

## Phase 8: Retirement

When a successor passes all evaluation gates, the old model transitions out:

1. **Pilot rollout:** New model deployed to selected pilot sites with shadow testing at each stage
2. **Fleet migration:** Bulk model swap tooling (AI-180 sub-task) updates `settings.json` across the fleet
3. **K8s cleanup:** Old model's Service and Deployment are removed from `ds-model-prod`
4. **Data retention:** Evaluation data, training artifacts, and DVC-tracked datasets are retained for historical comparison

**Example:** [[intruder-v5-model]] (`intruder-384h-512w-svc`) is currently awaiting replacement by [[intruder-v8-model]] (`int07-actuate003-v8`). The euromodel (`euromodel-int01-actuate004-v8`) was retired before deployment after evaluation showed it did not outperform the generalist v8 (Confluence: "UK/EU Model Evaluation: euromodel vs intruder vs int07").

## Cross-Cutting Concerns

### Provenance

Every deployed model traces back to: exact training data (DVC commit in [[actuate-data-registry-dvc]]), training configuration (W&B run ID), evaluation results (mAP JSON, shadow test reports), and deployment manifest (ArgoCD sync).

### Model-Aware Sensitivity

The v8 rollout requires the platform to know which model serves each camera, because [[confidence-threshold-calibration|v8 thresholds are approximately 10% lower than v5]]. AI-180 includes sub-tasks for model-aware sensitivity and v8-calibrated settings.

### VLM Integration

[[vlm-pipeline-architecture|VLMs]] operate as a post-alert layer. They do not replace the YOLO pipeline but augment it with scene-level understanding for FP reduction (AutoPatrol) and structured assessment (Watchman). Their lifecycle is parallel but simpler: HuggingFace model selection, vLLM deployment, evaluation via [[vlm-eval-visualizer]] and [[ds-smart-alert-supervisor]].

## Related Notes

- [[training-pipeline-architecture]] -- Phase 4 in depth
- [[evaluation-tiers]] -- Phase 5 in depth
- [[shadow-testing-methodology]] -- McNemar's test details
- [[confidence-threshold-calibration]] -- threshold determination
- [[vlm-pipeline-architecture]] -- VLM deployment and use cases
- [[detection-pipeline]] -- the runtime pipeline models serve within
- [[ds-server-container]] -- Rust inference server
- [[ds-training-pipeline]] -- training repo
- [[actuate-eval]] -- evaluation toolkit
- [[shadow-test-pipeline]] -- shadow testing infrastructure
