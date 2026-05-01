---
title: Training Pipeline Architecture
type: concept
topic: data-science
tags: [training, sagemaker, ultralytics, neuronx, inferentia, labeling, spektar, encord, dvc, deployment]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Training Pipeline Architecture

## Overview

The training pipeline takes raw production data through a structured sequence of stages -- sampling, labeling, versioning, training, compilation, and deployment -- before a model can serve inference in [[ds-server-container]]. Each stage has dedicated tooling, and full provenance (tracing a production model back to its exact training data, hyperparameters, and code commit) is a core design principle.

## Stage 1: Data Sampling

The pipeline begins with [[training-data-sampler]], which queries the production Postgres database to extract frames (images) or windows (video clips) that meet specific criteria -- geographic spread, scene diversity, camera type, or failure-case targeting. The sampler organises data into **Batches**, the smallest atomic unit. Batches are grouped into **Data Packs** (thematic collections, e.g., construction sites at night) and ultimately into **Data Decks** (the full training corpus for a model version).

Sampled media is uploaded to the `actuate-training-data-new` S3 bucket, ready for labeling.

## Stage 2: Labeling

Labeling happens through two platforms, depending on the project:

- **[[actuate-labeling-tool]]** (internally branded as [[spektar|Spektar]]) -- a self-hosted Label Studio deployment with custom RBAC, audit logging, and GDPR compliance. Used for internal annotation of bounding boxes on sampled frames.
- **Encord** -- an external labeling platform used for larger-scale or outsourced annotation. The [[training-data-sampler]] has native Encord integration: it creates Encord projects, uploads media, and retrieves completed labels. Encord uses ontology hashes (defaulting to a 7-class + cover ontology) and configurable labeling workflows.

**Point-based annotation** (developed by Mladen Lukic) offers a lighter-weight alternative where annotators mark object centroids rather than full bounding boxes. This dramatically accelerates labeling for evaluation purposes, though full bounding box labels remain necessary for training. See [[model-evaluation-framework]] for details on point-based evaluation.

## Stage 3: Data Versioning

Labeled data flows into [[actuate-data-registry-dvc]], the DVC-backed (Data Version Control) data registry. The registry follows a strict folder convention with three stages per incremental batch:

1. **`01_raw/`** -- uncurated data from production, immediately frozen with `dvc add`
2. **`02_pre_encord/`** -- curated subset after active learning or framing scripts, ready for labeling
3. **`03_post_encord/`** -- human-verified labels returned from Encord

Every curated folder requires a `meta.yaml` linking to the source code repo, commit hash, script path, curator name, and creation date. Golden production datasets live under `{model_name}/base_training_sets/`. DVC's content-addressable S3 storage deduplicates images shared across models or pipeline stages.

## Stage 4: Training on SageMaker

[[ds-training-pipeline]] is the primary training repository, replacing the older `ds-sagemaker-yolov5`. It supports the full Ultralytics model ecosystem:

- **YOLO family**: YOLOv5u through YOLO26 (latest, 43% faster CPU, NMS-free), in sizes nano through xlarge
- **YOLOE**: open-vocabulary detection/segmentation with text or visual prompts
- **YOLO World**: open-vocabulary detection (v1 and v2)
- **RT-DETR**: Ultralytics real-time transformer (no NMS)
- **RF-DETR**: Roboflow's SOTA detection transformer (60.1 AP on COCO with 2xlarge)

Training runs execute on AWS SageMaker with configurations specified via named **presets** (`baseline`, `quick_test`, `small_object_v1` through `v4_balanced`) that control resolution (640--1280px) and box loss weights. **Custom fitness functions** (`recall_map50`, `recall_priority`, `f1_balanced`, and others) determine checkpoint selection strategy. For example, the [[weapon-v8-model]] used `recall_map50` because missing a weapon is far more costly than a false positive.

**Self-supervised learning (SSL) pretraining** is available via Lightly/Lightly Train on unlabeled data. Supported methods include DINOv2 (recommended), SimCLR, BYOL, MoCo v2, and SwAV. Pretrained backbones bootstrap the YOLO fine-tuning step, improving convergence on smaller labeled datasets.

All experiments are tracked in **Weights & Biases (W&B)** for reproducibility and comparison.

The canonical dataset reference is `datasets/dataset_manifest.yaml` in the training pipeline repo, which lists S3 ARN-style locations for every Actuate product (backbone, weapon, intruder, euromodel, fire, pets, etc.).

## Stage 5: NeuronX Compilation

Trained PyTorch models must be compiled for AWS Inferentia2 hardware before production deployment. The `compile_neuronx.py` script in [[ds-training-pipeline]] handles this transformation using the AWS Neuron SDK, producing optimised artifacts that exploit NeuronCores for parallel inference.

Compilation targets are configured per model -- input resolution, batch size, and NeuronCore allocation must match the deployment topology in [[ds-server-container]].

## Stage 6: Deployment to ds-server-container

The compiled model is packaged into a Docker image via [[ds-server-container]]'s layered build system. Model-specific images layer on top of a base inference server image (`ctr-build-and-push-all-model-images`). Two binaries serve different roles:

- **inference_server** (x86_64) -- runs YOLO on Inferentia2 `inf2.*` instances for native-resolution images
- **slicing_server** (aarch64) -- runs on Graviton4 for SAHI-style tiling of high-resolution frames, dispatching tiles to the inference server

Images are pushed to ECR and deployed to the `ds-model-prod` Kubernetes namespace via [[argocd|ArgoCD]] from the `kubernetes-deployments` repo. Each model gets a K8s Service at `http://{model}-svc.ds-model-prod.svc.cluster.local:8080/infer`.

## Concrete Example: Weapon v8

1. **Data**: [[carlos-torres|Carlos Torres]] assembled weapon training data via [[training-data-sampler]] and [[actuate-data-registry-dvc]]
2. **Training**: YOLOv8 XL at 736px resolution using `recall_map50` fitness on SageMaker
3. **Evaluation**: Passed [[model-evaluation-framework]] -- frame-level mAP via [[actuate-eval]], FP stress testing on Genesis sets, confidence threshold sweep yielding HIGH=0.65/MED=0.60/LOW=0.55
4. **Compilation**: NeuronX compilation for Inferentia2
5. **Deployment**: [[ds-server-container]] image to `ds-model-prod` under PROD-98

## Related Notes

- [[ds-training-pipeline]] -- training repo details
- [[actuate-data-registry-dvc]] -- data versioning
- [[training-data-sampler]] -- production data sampling
- [[actuate-labeling-tool]] -- [[spektar|Spektar]] labeling platform
- [[ds-server-container]] -- inference serving layer
- [[model-evaluation-framework]] -- evaluation gates between training and deployment
- [[model-lifecycle-end-to-end]] -- full lifecycle synthesis
