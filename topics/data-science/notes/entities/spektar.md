---
type: entity
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [labeling, annotation, ground-truth, sagemaker, training-data]
---

# Spektar

Spektar is the **labeling tool** used by Actuate's data science team for ground truth annotation. It provides the human-labeled datasets that are essential for training, evaluating, and validating object detection and classification models.

## Purpose and Workflow

Ground truth annotation is the process of manually drawing bounding boxes, polygons, or labels on images to identify objects of interest (people, vehicles, weapons, animals, etc.). These annotations become the "ground truth" that supervised learning models are trained against. Spektar provides the interface where annotators view camera frames, draw detection regions, assign object classes, and mark attributes (e.g., occluded, truncated, far-away).

The typical workflow is:

1. **Frame selection** -- The [[training-data-sampler]] selects representative frames from production camera feeds, balanced across scene types, lighting conditions, and object categories.
2. **Annotation in Spektar** -- Annotators label the selected frames with bounding boxes and class labels. Quality control steps ensure annotation consistency.
3. **Export to training pipeline** -- Labeled data is exported from Spektar and registered in the [[actuate-data-registry-dvc]] for version tracking.
4. **SageMaker training** -- The [[ds-training-pipeline]] consumes the labeled datasets to train models on AWS SageMaker, producing model artifacts that are evaluated via [[actuate-eval]].

## Relationship to Other Labeling Tools

Spektar is distinct from the [[actuate-labeling-tool]] and the OpenCV-based labeling scripts in the [[shadow-test-pipeline]] (`shadow_label_local.py`, `shadow_label_s3.py`). The shadow pipeline labeling tools are lightweight TP/FP labeling interfaces used for model comparison, while Spektar provides full bounding-box annotation for training data. The [[actuate-labeling-tool]] serves as an additional annotation interface for specific workflows.

## Data Science Integration

Spektar sits at the start of the model development lifecycle. The quality and volume of Spektar annotations directly determine model accuracy. Engineers like [[carlos-torres]] (weapon models), [[otzar-jaffe]] (entrance models, site classification), and [[vlad-sapeshka]] (shadow test ground truth) all depend on Spektar-labeled data.

## See Also

- [[ds-training-pipeline]] -- consumes Spektar's labeled data
- [[actuate-data-registry-dvc]] -- version control for training datasets
- [[training-data-sampler]] -- selects frames for annotation
- [[actuate-eval]] -- evaluates models trained on Spektar data
