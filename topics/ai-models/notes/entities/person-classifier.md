---
title: "person-classifier"
type: entity
topic: ai-models
tags: [repo, classifier, dinov2, lora, person-detection, yolo, surveillance, fastapi]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# person-classifier

Binary person / non-person classifier built on DINOv2 ViT-B/14 with LoRA fine-tuning. Acts as a second-stage filter to confirm or reject YOLO detections in security surveillance pipelines, suppressing false positives from shadows, background clutter, and other non-person objects.

**Repo:** `aegissystems/person-classifier` (private, updated 2026-04-03)

## Architecture

- **Backbone**: DINOv2 ViT-B/14 with registers (`dinov2_vitb14_reg`) -- frozen weights.
- **LoRA adapters**: Injected into backbone attention layers (rank=8), approximately 295k trainable parameters.
- **Classification head**: LayerNorm -> Linear(768, 256) -> GELU -> Dropout -> Linear(256, 1).
- **Total trainable**: approximately 494k out of 87M parameters (0.34%).

## Dataset

Training data totals approximately 226k crops from multiple sources:

| Source | Person | Non-person |
|--------|--------|------------|
| Surveillance cameras (intruder dataset) | 26,992 | 146,017 |
| TinyPerson | 21,545 | -- |
| INRIA | 930 | 2,352 |
| COCO / TinyPerson BG | -- | 23,314 |
| Shadow dev crops | -- | 7,535 |

Augmentations simulate surveillance degradation: blur, downscaling, sensor noise, JPEG compression, lighting variation, and random occlusion.

## Performance

On a held-out test set of 22,634 images with the tuned threshold of 0.39:

| Metric | Value |
|--------|-------|
| Precision | 0.982 |
| Recall | 0.979 |
| F1 | 0.980 |
| AUC | 0.9987 |

The optimal threshold (0.39 vs. the default 0.50) is found via `PersonPredictor.find_optimal_threshold()` on a validation set, trading a small amount of precision for significantly better recall.

## Training

Uses focal loss, MixUp/CutMix augmentation, cosine LR schedule with warmup, mixed precision, and early stopping. Run via `python train.py --dataset_dir data/merged --output_dir outputs`.

## Inference and API

- **Python**: `PersonPredictor("outputs/best_model.pt").predict("crop.jpg", threshold=0.39)` returns `{"is_person": True, "confidence": 0.847, "logit": 1.703}`.
- **Batch**: `predict_batch()` for multiple crops.
- **CLI**: `python inference.py /path/to/image_or_dir --checkpoint outputs/best_model.pt`.
- **FastAPI server**: `uvicorn person_api:app` exposes `/predict`, `/predict_base64`, `/predict_batch`, and `/health` endpoints.

## Requirements

Python 3.10+, PyTorch 2.0+ with CUDA. Data preparation scripts are included for extracting crops from INRIA, COCO, TinyPerson, shadow dev, and intruder datasets.

## Related

- [[actuate-labeling-tool]] -- annotation platform where training data is labeled
