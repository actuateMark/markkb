---
title: "Source: RoboMladen Requirements Gathering"
type: source
topic: data-science
tags: [worklog, robomladen, requirements, false-positive, miss-detection, pandas, confidence-tuning]
ingested: 2026-04-14
author: kb-bot
---

# RoboMladen Requirements Gathering

Worklog notes from a requirements gathering session for RoboMladen, covering analysis features, miss detection workflow, and false positive tooling.

## Core Analysis Pipeline

1. Get the video, run full inspection at ~20fps (as many frames as the video has).
2. Process all frames through the model, collect YOLO detection output files.
3. Load into a **pandas DataFrame** with columns including confidence scores and image paths.
4. Filter by confidence in pandas, display images with the applied filter.
5. Mark detections by second and sub-frame for precise temporal analysis.

Pandas is well-suited for post-analysis. An offline test pipeline and Ajay's window analysis tool are existing related work.

## Deployment Comparison

- Run locally with the ability to add additional model endpoints.
- Send directly to model without deploying a full VMS connector.
- **Sanity check**: compare local model output with deployed (cloud) model output to verify they are 1:1 within a margin of error. This validates that Neuron compilation or other deployment transformations do not alter model behavior.

## False Positive Elimination

Integrated into post-analysis: a selection/elimination tool to flag false positives and assess their impact on detection thresholds.

## Miss Detection Workflow

The ideal miss detection tool (from Brandon's perspective):

- External-facing report capability showing where the system would have caught an event.
- Model comparison (e.g., regular vs. extreme models).
- Localized motion analysis.
- Customer-facing upload: customer uploads video, sees how their camera configuration would perform.
- **Tradeoff analysis**: "What happens if we move this entire site from 60% to 30% confidence? How many more false positives vs. how many fewer misses?"
- Ability to write recommended settings back to Admin.
- Email reports to customers for specific analyses.

## Key Insight

Downloadable results and the ability to run scripts vs. full workflows are both needed. The tool should support both quick one-off analysis and comprehensive investigation modes.

## See Also

- [[worklog-robomladen-kickoff]] -- product vision and architecture
- [[worklog-automation-brainstorm]] -- settings automation that could consume RoboMladen output
