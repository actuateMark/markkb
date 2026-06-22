---
type: entity
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [person, data-science, yam, model-evaluation, shadow-testing]
incoming:
  - topics/data-science/notes/entities/spektar.md
  - topics/models/intruder-v8/notes/syntheses/2026-05-13_v8-release-postgres-context.md
  - topics/team-structure/notes/entities/zack-schmidt.md
incoming_updated: 2026-05-27
---

# Vlad Sapeshka

Vlad Sapeshka is a data scientist at Actuate who leads the **YAM (Yet Another Model) re-evaluation** effort, currently the highest-priority data science initiative. His work centers on rigorous model comparison and [[shadow-testing-methodology|shadow testing methodology]].

## YAM Re-Evaluation (AI-211, Highest Priority)

Vlad leads the YAM re-evaluation under ticket AI-211, which is flagged as the **highest priority** item in the data science backlog. YAM re-evaluation is the systematic comparison of Actuate's current production model suite against newer candidates to determine whether model upgrades deliver real-world improvements. This is part of the broader YAM epic (AI-158) owned by [[zack-schmidt]].

The re-evaluation is critical because model upgrades carry significant risk -- a model that benchmarks better on test sets may perform worse on specific camera populations, lighting conditions, or object types that matter to Actuate's customer base. Vlad's role is to ensure upgrade decisions are backed by rigorous evidence rather than benchmark numbers alone.

## V8 vs V5 Performance Comparison

A core component of Vlad's work is comparing YOLOv8 versus YOLOv5 model performance. The [[intruder-v8-model]] is the candidate replacement for the [[intruder-v5-model]], and Vlad's analysis determines whether the v8 model delivers sufficient accuracy and latency improvements to justify the migration cost. This comparison feeds into the [[model-evaluation-framework]] and uses metrics defined in [[actuate-eval]].

## Shadow Testing Methodology

Vlad developed and refines the [[shadow-testing-methodology]] used to evaluate model candidates in production-like conditions without affecting live alert delivery. Shadow testing runs candidate models against the same camera feeds as the production model and compares outputs using the [[shadow-test-pipeline]]. Vlad's methodology defines the statistical framework for determining when differences are significant and actionable.

## See Also

- [[shadow-testing-methodology]] -- the evaluation framework he developed
- [[shadow-test-pipeline]] -- the tooling that implements shadow testing
- [[intruder-v8-model]] -- the candidate model under evaluation
- [[zack-schmidt]] -- YAM epic owner
- [[model-evaluation-framework]] -- evaluation metrics and methodology
