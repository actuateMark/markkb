---
type: entity
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [person, data-science, vlm, prompt-engineering, camera-screening]
---

# Alena Prashkovich

Alena Prashkovich is a data scientist at Actuate focused on VLM prompt engineering and camera screening. Her work directly impacts false-positive reduction and model accuracy across the platform.

## VLM Prompt Engineering Phase III (AUTO-474)

Alena leads Phase III of VLM (Vision-Language Model) prompt engineering under ticket AUTO-474, part of the [[autopatrol]] initiative. VLM prompt engineering is the process of crafting and refining the natural-language prompts sent to vision-language models (currently [[qwen3vl-aws]]) to classify alert frames. Effective prompts determine whether the model correctly identifies true threats versus false positives like animals, shadows, or moving vegetation.

Phase III represents the maturation of this capability -- earlier phases established baseline prompts and evaluation methodology, while Phase III focuses on site-specific prompt tuning and edge-case handling. The prompts Alena develops feed into the [[vlm-fp-reduction]] pipeline, where VLM acts as a secondary filter after the primary object detection model. See [[vlm-integration]] for how VLM fits into the AutoPatrol architecture.

## UK Camera Screening (AI-213)

Alena works on UK camera screening under ticket AI-213. This initiative evaluates camera feeds from UK deployments to assess their suitability for Actuate's detection models. UK cameras often have different characteristics than US deployments -- different mounting heights, wider fields of view, different lighting conditions, and European-specific scene elements (e.g., bollards, different vehicle types). Camera screening determines which cameras can use standard models versus which need custom tuning or are unsuitable for automated monitoring.

This work connects to the broader EU deployment effort and the [[shadow-test-pipeline]], which provides the evaluation framework for comparing model performance across different camera populations.

## See Also

- [[vlm-integration]] -- VLM's role in AutoPatrol
- [[vlm-fp-reduction]] -- the false-positive reduction pipeline
- [[shadow-test-pipeline]] -- evaluation framework used for UK screening
- [[autopatrol]] -- parent initiative for Phase III work
