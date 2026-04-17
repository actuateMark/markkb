---
title: "Model Lifecycle: Research to Production to Retirement"
type: synthesis
topic: data-science
tags: [synthesis, cross-topic, model-lifecycle, training, evaluation, deployment, shadow-testing, sagemaker]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Model Lifecycle: Research to Production to Retirement

The journey of a YOLO model from initial research through production deployment and ongoing monitoring spans five distinct phases, each with dedicated tooling, repos, and evaluation gates. This synthesis traces the full lifecycle using the v8 intruder rollout (AI-180) and weapon v8 deployment (PROD-98) as concrete examples.

## Phase 1: Data Collection and Labeling

### Tools
- **Spektar** -- Actuate's labeling platform where annotators mark bounding boxes on sampled frames.
- **[[training-data-sampler]]** -- Generates batches (the smallest unit of training data) from production frames. Batches are grouped into Data Packs (thematic collections, e.g., construction sites) and Data Decks (logical collections of packs).
- **[[actuate-data-registry-dvc]]** -- DVC-based data registry for versioning and tracking datasets on S3.

### Data Hierarchy
```
Data Deck (e.g., "intruder-v8-training-deck")
  -> Data Pack (e.g., "construction-sites-pack")
    -> Batch (e.g., "batch-2026-03-15-site-42")
      -> Individual labeled frames
```

The `datasets/dataset_manifest.yaml` in [[ds-training-pipeline]] is the canonical reference for S3 dataset locations across all products (backbone, weapon, intruder, euromodel, fire, pets, etc.). Full provenance -- mapping training runs to compiled data decks -- is a core principle.

## Phase 2: Training

### Infrastructure
- **[[ds-training-pipeline]]** -- The primary training repo, supporting the full Ultralytics ecosystem: YOLOv5u through YOLO26, YOLOE (open-vocabulary), YOLO World (text prompts), RT-DETR, and Roboflow's RF-DETR transformer. Replaces the older `ds-sagemaker-yolov5` repo.
- **AWS SageMaker** -- Training execution environment. Pipeline definitions specify architecture, augmentation, and hyperparameters.
- **Weights & Biases (W&B)** -- Experiment tracking for training runs.

### Training Configuration
Named presets control resolution and loss weights: `baseline`, `quick_test`, `small_object_v1` through `v4_balanced` (640-1280px resolution range). Custom fitness functions (`recall_map50`, `recall_priority`, `f1_balanced`) determine checkpoint selection strategy -- for example, the weapon model uses `recall_map50` because missing a weapon is more costly than a false positive.

### Advanced Techniques
- **SSL pretraining** via Lightly/Lightly Train on unlabeled data (DINOv2 recommended, also SimCLR, BYOL, MoCo v2, SwAV). Pretrained backbones feed into the YOLO fine-tuning step.
- **NeuronX compilation** -- Compiles trained models for AWS Inferentia2/Trainium via `compile_neuronx.py` for production deployment.

### Example: Weapon v8
Carlos Torres trained `weapon-v8-XL-736` using YOLOv8 XL architecture at 736px resolution. The model showed "improvement by many orders of magnitude" over v5, with new confidence thresholds: HIGH=0.65, MED=0.60, LOW=0.55.

## Phase 3: Evaluation

Actuate uses a rigorous multi-level evaluation framework with multiple statistical gates before any model reaches production.

### Level 1: Frame-Level Metrics
- **Tool:** [[actuate-eval]] (`actuate-eval map`)
- **Metrics:** mAP@0.5, mAP@0.5:0.95, per-class AP, precision, recall, F1
- **Dataset:** 28,828+ labeled images in ground truth sets
- **Method:** Predictions from detection CSV/Parquet compared against YOLO TXT ground truth. PR curves exported at 1000 points per class.

### Level 2: Statistical Model Comparison
- **Tool:** [[actuate-eval]] (`actuate-eval compare`)
- **Method:** McNemar's paired statistical test for alert-level comparison between two models. Also supports Wilcoxon signed-rank tests. Sweeps across configurable confidence thresholds and reports statistical significance.
- **Repo:** `shadow-testing-stats` for deeper statistical analysis.

### Level 3: Stress Testing
- **Genesis image sets** -- curated collections of hard real-world conditions (rain, fog, low light, reflective surfaces, cluttered scenes). Models must not regress on these.
- **Cumulative misses validation set** -- production misses accumulated over time to prevent regression on known failure modes.

### Level 4: Shadow Testing
- **Tool:** [[shadow-test-pipeline]]
- **Method:** Run DEV model alongside PROD on real traffic. The pipeline queries AWS Athena for alert data, classifies alerts as prod/dev based on model identifiers, matches them using sliding-window + greedy algorithm (25s time delta, 0.3 IoU threshold), and identifies alerts unique to each model.
- **Labeling:** Manual TP/FP labeling via OpenCV tools, Streamlit interface, or Encord integration.
- **Output:** Statistical comparison of false positive and false negative rates between models.

### Level 5: Confidence Threshold Sweep
- Systematic sweep from 0.10 to 0.80 with various sliding window configurations to find optimal operating points per sensitivity level (HIGH/MED/LOW).

### Level 6: Point-Based Annotation
- Mladen Lukic's method: fast evaluation via centroid matching rather than full bounding box IoU. Accelerates labeling for rapid iteration.

### Example: v8 Intruder
The v8 model (`int07-actuate003-v8`) passed frame-level evaluation and was "approved for rollout," but the rollout epic (AI-180) has 13 sub-tasks still To Do: deploy endpoint, build container, register model, create v8-calibrated sensitivity settings, pilot site selection, model-aware sensitivity, bulk model swap tooling, decouple raw metrics, and model change audit trail.

## Phase 4: Deployment

### Container Build
Trained and Neuron-compiled models are packaged into [[ds-server-container]] Docker images. The Rust-based inference server runs on AWS Inferentia2 instances (NeuronCores). Model-specific images layer on top of a base inference server image. The companion `slicing_server` runs on Graviton4 for SAHI-style tiling.

### Kubernetes Deployment
Models deploy to the `ds-model-prod` namespace (or `ds-model-dev` for testing). Each model gets a K8s Service with a URL pattern: `http://{model}-svc.ds-model-{env}.svc.cluster.local:8080/infer`. ArgoCD manages GitOps deployments from the `kubernetes-deployments` repo.

### Client Configuration
The [[vms-connector]] reaches models through [[actuate-inference-client]] or [[actuate-classic-inference-client]] using `KubernetesModelUri`. The model endpoint is specified in the site's `settings.json` via [[actuate-config]]. Changing which model a site uses requires updating the settings and restarting the connector.

### VLM Deployment
Vision Language Models (Qwen3-VL-8B, etc.) for the VLM FP reduction filter deploy on K8s with vLLM backend on EC2 g5.2xlarge instances (~$1.21/hr). Communication is via SQS queues and DynamoDB polling through [[actuate-vlm]].

## Phase 5: Monitoring and Retirement

### Production Monitoring
- **Shadow testing (ongoing):** Even after deployment, shadow testing can continue to compare the production model against experimental successors.
- **New Relic / CloudWatch / Datadog:** [[actuate-monitoring]] reports inference latency, error rates, and throughput.
- **[[actuate-event-listener]]:** Analytics events track per-model, per-camera detection rates for anomaly detection.

### YAM Re-evaluation
After code changes that affect the inference path (e.g., commit `788bed7` changing chip generation from processed_frame to original frame resolution), **all model endpoints need re-evaluation** for updated mAP/recall/F1. This is the YAM re-evaluation initiative (AI-211, Highest Priority), currently being run by Vlad (Uladzimir Sapeshka).

### Model Retirement
When a successor model is validated (e.g., v8 replacing v5 for intruder), the old model's K8s resources are removed from `ds-model-prod`, and sites are migrated via the bulk model swap tooling (part of AI-180). The old model's evaluation data is retained for historical comparison.

### Example: v5 -> v8 Transition
`intruder-384h-512w-svc` (YOLOv5) is the current production model. `int07-actuate003-v8` (YOLOv8) is approved but not yet rolled out. The transition requires: new K8s deployment, v8-calibrated sensitivity settings (different optimal confidence thresholds), pilot site testing, gradual rollout with shadow testing at each stage, and eventually decommissioning the v5 endpoint. The UK/EU bespoke model (`euromodel-int01-actuate004-v8`) was parked after it failed to outperform the generalist v8 -- an example of a model that reached Phase 3 evaluation but was retired before Phase 4 deployment.

## Key People Across the Lifecycle

| Phase | People |
|---|---|
| Data & Labeling | Mladen Lukic (point-based annotation), Alena Prashkovich (UK camera screening) |
| Training | Carlos Torres (weapon), Otzar Jaffe (PPF, model merging), DS team |
| Evaluation | Uladzimir Sapeshka / Vlad (YAM, shadow testing), Zack Schmidt (decisions) |
| Deployment | Engineering team, [[connector-deployer]], ArgoCD |
| Monitoring | Platform engineering, New Relic dashboards |
