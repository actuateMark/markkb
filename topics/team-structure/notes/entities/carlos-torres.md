---
type: entity
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [person, data-science, weapon-model, vlm, model-training, model-routing]
incoming:
  - topics/ai-models/_summary.md
  - topics/ai-models/notes/entities/weapon-v8-model.md
  - topics/ai-models/notes/syntheses/yolo-vs-vlm-detection-future.md
  - topics/autopatrol/notes/concepts/vlm-integration.md
  - topics/data-science/notes/concepts/training-pipeline-architecture.md
  - topics/data-science/notes/entities/spektar.md
  - topics/data-science/notes/syntheses/model-lifecycle-end-to-end.md
  - topics/data-science/notes/syntheses/model-lifecycle.md
  - topics/jira-organization/notes/concepts/confluence-spaces-map.md
  - topics/models/weapon-v8/_summary.md
incoming_updated: 2026-05-27
---

# Carlos Torres

Carlos Torres is a data scientist at Actuate focused on weapon model training, VLM false-positive filtering, and automated model routing. His work spans model development and the systems that decide which models run on which cameras.

## Weapon Model Training

Carlos handles the training pipeline for Actuate's weapon detection models, including the [[weapon-v8-model]]. Weapon model training requires carefully curated datasets with high-quality annotations of firearms, knives, and other threat objects across diverse conditions (lighting, angles, occlusion, camera quality). Carlos works with the [[ds-training-pipeline]] and [[actuate-labeling-tool]] to manage training data and model iterations. He coordinates with [[zack-schmidt]] on weapon model acceptance criteria and production readiness.

## VLM FP Filter

Carlos develops the VLM (Vision-Language Model) false-positive filter, a component of the [[vlm-fp-reduction]] pipeline. The VLM FP filter takes alert frames that the primary detection model has flagged and runs them through a vision-language model (currently [[qwen3vl-aws]]) to determine whether the detection is a true positive or a false positive. This acts as a second-stage filter that can catch context-dependent false positives the object detection model misses -- for example, distinguishing a person from a mannequin, or a real weapon from a toy.

Carlos's filter work connects to [[laura-reno]]'s VLM FP MVP initiative (SA-221) and [[alena-prashkovich]]'s prompt engineering efforts. Carlos focuses on the model-side implementation while Laura drives the product requirements and Alena optimizes the prompts.

## Automated Model Routing

Carlos works on automated model routing, the system that decides which detection model runs on which camera. Different cameras benefit from different models based on their scene characteristics (indoor vs outdoor, close-range vs perimeter, high-traffic vs low-traffic). Automated routing removes the need for manual model assignment by using site classification data (from [[otzar-jaffe]]) and camera metadata to select the optimal model automatically.

## See Also

- [[weapon-v8-model]] -- the weapon model he trains
- [[vlm-fp-reduction]] -- the VLM false-positive pipeline
- [[ds-training-pipeline]] -- training infrastructure
- [[zack-schmidt]] -- weapon model decision owner
