---
title: "Detection models & products — catalog"
type: summary
topic: models
tags: [models, detection, products, catalog, moc]
updated: 2026-06-24
author: kb-bot
---

# Detection models & products

Catalog of the **detection products** Actuate ships (~27 notes). Each is a sub-topic with its own `_summary` under `topics/models/<name>/`.

> **`models` vs [[ai-models/_summary|ai-models]]:** this topic is the *product catalog* (what each detector does, its status, thresholds). **[[ai-models/_summary|ai-models]]** is the *DS/ML infrastructure* (model evaluation, shadow testing, the ds-server, YOLO-vs-VLM, training/eval pipelines). Use this for "what does line-crossing do?"; use ai-models for "how do we evaluate a candidate model?".

## Production
[[intruder-v5/_summary|Intruder v5]] (YOLOv5, prod) · [[intruder-v8/_summary|Intruder v8]] (YOLOv8) · [[weapon-v8/_summary|Weapon v8]] (YOLOv8 XL) · [[fire-detection/_summary|Fire Detection]]

## Detection products
[[loitering/_summary|Loitering]] (BoTSORT tracking) · [[line-crossing/_summary|Line Crossing]] · [[motion-plus/_summary|Motion+]] · [[crowd-detection/_summary|Crowd]] · [[fall-detection/_summary|Fall Detection]]

## Specialized
[[blacklist-reid/_summary|Blacklist / Re-ID]] · [[pet-detection/_summary|Pet]] · [[hardhat-detection/_summary|Hard Hat]] · [[thermal-intruder/_summary|Thermal Intruder]]

## How this fits
Models run inside the [[vms-connector/_summary|connector]] pipeline (via the inference client → [[inference-api/_summary|inference API]]). Sensitivity presets + per-product config are a [[fleet-architecture/_summary|fleet-arch]] / settings-automation concern. Evaluation + rollout: [[ai-models/_summary|ai-models]].
