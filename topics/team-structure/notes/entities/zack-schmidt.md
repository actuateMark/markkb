---
type: entity
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [person, data-science, yam, weapon-model, testing, productionization]
---

# Zack Schmidt

Zack Schmidt is a data scientist at Actuate who owns the **YAM (Yet Another Model) epic** (AI-158) and drives weapon model decisions, DS testing infrastructure, and model productionization workflows.

## YAM Epic Owner (AI-158)

Zack owns the YAM epic under ticket AI-158, the umbrella initiative for all model upgrade evaluation and deployment decisions at Actuate. The YAM epic encompasses model candidate selection, evaluation criteria, shadow testing, and production rollout planning. While [[vlad-sapeshka]] leads the hands-on re-evaluation work (AI-211), Zack owns the epic-level coordination -- determining which models enter evaluation, setting acceptance criteria, and making the final go/no-go decisions on model upgrades.

## Weapon Model Decisions

Zack drives decisions around Actuate's weapon detection models, including the [[weapon-v8-model]]. Weapon detection is a high-stakes capability because false negatives (missed weapons) have severe consequences, while false positives (alerting on benign objects like umbrellas or tools) erode operator trust. Zack's role involves setting the precision/recall tradeoff for weapon models, deciding when new weapon model versions are ready for production, and coordinating with [[carlos-torres]] on weapon model training.

## DS Testing and Productionization

Zack focuses on the testing and productionization side of the data science workflow -- the process of taking a trained model from a research notebook to a production-deployed service. This includes:

- **Evaluation pipelines** -- Using [[actuate-eval]] to run standardized model evaluation against held-out test sets and production data samples.
- **Production readiness** -- Ensuring models meet latency, memory, and accuracy requirements before deployment to the [[kubernetes-deployments]] infrastructure.
- **Rollout coordination** -- Working with engineering to stage model rollouts using the [[shadow-test-pipeline]] before full production deployment.

## See Also

- [[vlad-sapeshka]] -- leads the YAM re-evaluation under Zack's epic
- [[carlos-torres]] -- weapon model training
- [[weapon-v8-model]] -- the weapon detection model
- [[actuate-eval]] -- evaluation tooling
- [[model-evaluation-framework]] -- evaluation methodology
