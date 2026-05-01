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

Automating camera/site settings configuration -- settings recommendations, automated model routing, ignore zone suggestions, PPF ([[pixels-per-foot|Pixels Per Foot]]) calculation, VLM-based false positive reduction filter, Classifyr for automation, and UX simplification.

## Active Workstreams (April 2026)

### VLM FP Reduction MVP (SA-221, updated April 13)
**[[laura-reno|Laura Reno]]** driving definition. MVP includes:
- Quantified FP reduction performance
- FE components for viewing alerts filtered by VLM verdict
- Adequate [[new-relic|New Relic]] logging
- Internal/external support docs, marketing docs, demo video/site
- Also tracked as PROD-2 (initiative level)

### PPF (Pixels Per Foot) (SA-177)
**[[otzar-jaffe|Otzar Jaffe]]** -- improving code quality, reducing output file size. Active since March.

### Settings Recommender (SA-7, Epic)
**Thomas Kornfeld** -- long-standing epic, not yet actively staffed.

## Planned Work

- **SA-105** (Highest) -- Simplify Intruder product
- **SA-107** (Highest) -- List all intruder models and best fit use cases
- **SA-167** (Epic) -- Suggesting [[ignore-zones|ignore zones]] (Otzar)
- **SA-160** (Epic) -- Classifyr for Settings Automation (Otzar)
- **SA-171** (Epic) -- [[vlm-fp-reduction|VLM FP Reduction]] filter ([[carlos-torres|Carlos Torres]])
- **SA-103** (High) -- UX simplification

## VLM/LLM Version 2.0 (PROD-272)

New epic (created April 8):
- **PROD-273** -- Integrate new Supervisor Models
- **PROD-274** -- Upgrade Temporal Linker
- **PROD-275** -- Integrate QWEN3-VL-8B Thinking ([[clarissa-herman|Clarissa Herman]])
- **PROD-276-282** -- Evaluation sub-tasks ([[carlos-torres|Carlos Torres]])

## Key People

| Person | Focus |
|--------|-------|
| [[laura-reno|Laura Reno]] | VLM FP MVP definition |
| [[otzar-jaffe|Otzar Jaffe]] | PPF, [[ignore-zones|ignore zones]], Classifyr |
| [[zack-schmidt|Zack Schmidt]] | Testing, productionization |
| [[carlos-torres|Carlos Torres]] | Model routing, VLM FP filter |
| Thomas Kornfeld | Settings Recommender (epic owner) |
