---
title: "ds-training-pipeline"
type: entity
topic: data-science
tags: [training, yolo, ultralytics, sagemaker, wandb, rf-detr, ssl, neuronx, inferentia]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# ds-training-pipeline

Multi-architecture object detection training pipeline for AWS SageMaker. Supports the full Ultralytics model ecosystem (YOLOv5u, v8, v9, v10, v11, v26, YOLOE, YOLO World, RT-DETR) and Roboflow's RF-DETR transformer. Replaces the older `ds-sagemaker-yolov5` repository.

## Supported Model Families

- **YOLO family** -- YOLOv5u through YOLO26, in sizes nano through xlarge. YOLO26 is the latest, optimized for edge/CPU (43% faster). YOLOv10 and YOLO26 are NMS-free.
- **YOLOE** -- Open-vocabulary detection and segmentation using text/visual prompts (YOLOE-26, YOLOE-26-seg).
- **YOLO World** -- Open-vocabulary detection with text prompts (v1 and v2).
- **RT-DETR** -- Ultralytics real-time transformer, no NMS required (v1 and v2).
- **RF-DETR** -- Roboflow's SOTA detection transformer (ICLR 2026), achieving 60.1 AP on COCO with the 2xlarge variant. Uses a DINOv2 backbone and is designed for fine-tuning.

## Key Features

- **Training presets** -- Named configurations for different scenarios: `baseline`, `quick_test`, `small_object_v1` through `v4_balanced`, varying resolution (640--1280px) and box loss weights.
- **Custom fitness functions** -- Configurable weighting of precision, recall, mAP50, and mAP50-95 for checkpoint selection. Presets include `recall_map50` (recommended for weapons), `recall_priority`, `f1_balanced`, and others.
- **SSL pretraining** -- Self-supervised learning with Lightly/Lightly Train on unlabeled data. Supports DINOv2 (recommended), SimCLR, BYOL, MoCo v2, and SwAV methods. Pretrained backbones feed into the YOLO fine-tuning step.
- **NeuronX compilation** -- Compiles trained models for AWS Inferentia/Inferentia2/Trainium deployment via `compile_neuronx.py`. Outputs are deployed to SageMaker endpoints.
- **W&B integration** -- Experiment tracking with Weights & Biases.

## Project Layout

Training scripts live under `src/training/` (`train.py` for Ultralytics, `train_rfdetr.py` for RF-DETR). Additional modules cover pretraining (`src/pretraining/`), compilation (`src/compilation/`), evaluation (`src/evaluation/`), inference servers (`src/inference/`), and preprocessing (`src/preprocessing/`). Training configs are organized by product (weapon, intruder) under `training_config/`. The `datasets/dataset_manifest.yaml` file is the canonical reference for S3 dataset locations across Actuate products (backbone, weapon, intruder, euromodel, fire, pets, etc.).

## Deployment Flow

1. Train a model locally or on SageMaker using `train.py` or `train_rfdetr.py`.
2. Optionally compile for Inferentia2 with `compile_neuronx.py`.
3. Deploy to a SageMaker endpoint using the included inference server scripts, or export for deployment to [[ds-server-container]].

## Requirements

Python 3.10+, PyTorch 2.0+, Ultralytics 8.3+, RF-DETR 1.4+, Lightly 1.5+, AWS Neuron SDK (for compilation), AWS SageMaker SDK.
