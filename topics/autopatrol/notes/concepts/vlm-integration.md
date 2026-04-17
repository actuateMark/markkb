---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [autopatrol, vlm, prompt-engineering, qwen, gemma, models]
---

# VLM Integration

Vision Language Model (VLM) integration is a key workstream in [[autopatrol]], using large multimodal models to analyse patrol clips and generate natural-language assessments of what is happening in a scene. This goes beyond traditional object detection -- VLMs can describe context, identify unusual behaviour, and provide reasoning about whether a scene warrants an alert.

## How It Works

During a patrol cycle, the [[autopatrol|Patrol Agent]] captures clips from each camera. These clips (or representative frames) are sent to a VLM along with a carefully engineered prompt. The model analyses the visual content and returns a structured assessment: what it sees, whether anything is anomalous, and a confidence level. This assessment feeds into the alerting pipeline -- if the VLM flags something concerning, an alert can be generated and dispatched to the operator or forwarded to [[immix-dispatch|Immix]].

The critical difference from traditional CV models: VLMs can handle novel scenarios that were not in the training data. A YOLO model detects "person" or "vehicle"; a VLM can describe "a person attempting to climb over a fence at 3 AM while carrying a large bag" and assess whether that constitutes a threat.

## Prompt Engineering

**Alena Prashkovich** leads VLM prompt engineering, currently in Phase III (AUTO-474, Medium priority, In Progress). Prompt engineering for security surveillance VLMs involves:

- **Scene description prompts** -- instructing the model to describe what it observes in structured format
- **Anomaly detection prompts** -- directing the model to identify anything unusual given the time of day, site type, and camera location
- **False positive suppression** -- tuning prompts to reduce alerts on benign activity (animals, weather, lighting changes)
- **Structured output** -- ensuring the model returns parseable responses that the alerting pipeline can act on programmatically

Phase III likely represents iterative refinement based on real-world patrol data, tuning prompts to reduce false positives while maintaining detection sensitivity.

## Models in Evaluation

Three models are currently being evaluated for production deployment:

| Model | Parameters | Notes |
|-------|-----------|-------|
| **Qwen3-VL-8B-Instruct** | 8B | Smallest, fastest inference. Part of the PROD-275 integration task assigned to Clarissa Herman. Also tracked under [[vlm-fp-reduction|VLM/LLM Version 2.0]] (PROD-272). |
| **Qwen2.5-VL-32B-Instruct-AWQ** | 32B (quantised) | AWQ quantisation keeps memory footprint manageable despite larger parameter count. Likely the accuracy/speed sweet spot. |
| **Gemma-3-12B-IT-FP8** | 12B | Google's Gemma family, FP8 quantised. Mid-range option. |

The evaluation involves Carlos Torres running assessment sub-tasks (PROD-276 through PROD-282) to compare these models on accuracy, latency, and false positive rate across real patrol footage.

## Frontend Planning

**Jessica Bae** is planning the VLM-based alerting frontend (AUTO-420). This will surface VLM assessments to operators in a way that adds value beyond the raw detection -- showing the model's reasoning alongside the clip so operators can make faster triage decisions. This connects to [[watchman]]'s [[triage-gamification]] concept, where VLM explanations could help operators learn what the system considers anomalous.

## Relationship to Other Initiatives

VLM work spans multiple projects. In AutoPatrol it powers patrol clip analysis. In [[settings-automation]] it drives the [[vlm-fp-reduction]] filter. In [[watchman]] it will be integrated into the Actuate Threat Agent's dual-track routing and the Assessment Agent's severity scoring. The VLM/LLM Version 2.0 epic (PROD-272) tracks the next generation of model integration across all products.
