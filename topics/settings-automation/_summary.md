---
title: Settings Automation (H1.4)
type: summary
topic: settings-automation
tags: [settings, h1-4, sa, vlm, ppf, classifyr, fp-reduction]
jira: "SA"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Settings Automation (H1.4)

Automating camera/site settings configuration -- settings recommendations, automated model routing, ignore zone suggestions, PPF (Pixels Per Foot) calculation, VLM-based false positive reduction filter, Classifyr for automation, and UX simplification.

## Active Workstreams (April 2026)

### VLM FP Reduction MVP (SA-221, updated April 13)
**Laura Reno** driving definition. MVP includes:
- Quantified FP reduction performance
- FE components for viewing alerts filtered by VLM verdict
- Adequate New Relic logging
- Internal/external support docs, marketing docs, demo video/site
- Also tracked as PROD-2 (initiative level)

### PPF (Pixels Per Foot) (SA-177)
**Otzar Jaffe** -- improving code quality, reducing output file size. Active since March.

### Settings Recommender (SA-7, Epic)
**Thomas Kornfeld** -- long-standing epic, not yet actively staffed.

## Planned Work

- **SA-105** (Highest) -- Simplify Intruder product
- **SA-107** (Highest) -- List all intruder models and best fit use cases
- **SA-167** (Epic) -- Suggesting ignore zones (Otzar)
- **SA-160** (Epic) -- Classifyr for Settings Automation (Otzar)
- **SA-171** (Epic) -- VLM FP Reduction filter (Carlos Torres)
- **SA-103** (High) -- UX simplification

## VLM/LLM Version 2.0 (PROD-272)

New epic (created April 8):
- **PROD-273** -- Integrate new Supervisor Models
- **PROD-274** -- Upgrade Temporal Linker
- **PROD-275** -- Integrate QWEN3-VL-8B Thinking (Clarissa Herman)
- **PROD-276-282** -- Evaluation sub-tasks (Carlos Torres)

## Key People

| Person | Focus |
|--------|-------|
| Laura Reno | VLM FP MVP definition |
| Otzar Jaffe | PPF, ignore zones, Classifyr |
| Zack Schmidt | Testing, productionization |
| Carlos Torres | Model routing, VLM FP filter |
| Thomas Kornfeld | Settings Recommender (epic owner) |
