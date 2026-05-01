---
type: entity
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [person, engineering, autopatrol, infrastructure, vlm, inference]
incoming:
  - topics/jira-organization/notes/concepts/confluence-spaces-map.md
  - topics/settings-automation/_summary.md
incoming_updated: 2026-05-01
---

# Clarissa Herman

Clarissa Herman is an engineer at Actuate working on [[autopatrol-server|AutoPatrol server]]/microservice integration and [[vlm-inference|VLM inference]] server infrastructure. Her work connects the application layer to the inference layer, ensuring that AutoPatrol features have the backend plumbing to function at scale.

## AP Server/MS Integration (AUTO-449)

Clarissa leads the [[autopatrol-server|AutoPatrol server]]/microservice integration under ticket AUTO-449, part of the [[autopatrol/_summary|AutoPatrol (H1.2)]] initiative. This work involves connecting the [[knowledgebase/topics/autopatrol/notes/entities/autopatrol-server]] to the broader microservice ecosystem -- ensuring that patrol schedules, camera assignments, ignore-zone configurations, and alert routing flow correctly between the [[autopatrol-server|AutoPatrol server]], the [[actuate-admin-api]], and the inference pipeline. The integration must handle edge cases like cameras going offline during a patrol, schedule conflicts, and graceful degradation when downstream services are unavailable.

## VLM Inference Server -- QWEN3-VL (PROD-275)

Clarissa works on the [[vlm-inference|VLM inference]] server under ticket PROD-275, specifically the deployment and optimization of the QWEN3-VL model (see [[qwen3vl-aws]]). The [[vlm-inference|VLM inference]] server hosts the vision-language model that powers false-positive filtering ([[vlm-fp-reduction]]) and site description features. This is infrastructure-level work: managing GPU resource allocation, model loading, request batching, latency optimization, and autoscaling on the [[kubernetes-deployments]] infrastructure.

The QWEN3-VL deployment is particularly challenging because vision-language models are significantly larger than object detection models, requiring more GPU memory and longer inference times. Clarissa's work ensures the inference server can handle production traffic volumes without becoming a bottleneck in the alert processing pipeline.

## Cross-Cutting Role

Clarissa's combination of application-level integration (AUTO-449) and infrastructure-level inference work (PROD-275) makes her a bridge between the AutoPatrol product team and the platform/infrastructure team. She understands both the product requirements driving VLM adoption and the infrastructure constraints that shape deployment decisions.

## See Also

- [[autopatrol/_summary|AutoPatrol (H1.2)]] -- the parent initiative for AP server work
- [[knowledgebase/topics/autopatrol/notes/entities/autopatrol-server]] -- the service she integrates
- [[qwen3vl-aws]] -- the VLM model she deploys
- [[vlm-fp-reduction]] -- the pipeline powered by [[vlm-inference|VLM inference]]
