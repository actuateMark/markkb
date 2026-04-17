---
title: "Source: Onboarding and Settings Automation Brainstorm"
type: source
topic: settings-automation
tags: [worklog, onboarding, automation, camera-settings, robomladen, confidence-tuning]
ingested: 2026-04-14
author: kb-bot
---

# Onboarding and Settings Automation Brainstorm

Worklog notes from a brainstorming session on automating camera onboarding and ongoing settings optimization.

## Two Tracks

### 1. Onboarding Automation (Frontloaded Effort)

Automate the initial camera setup process. Key questions raised:

- How standard is the onboarding process across customers?
- Can we create a "one-click onboarding" experience for easy integrations?
- Task-based automatic burn-in: configure settings within cameras where possible.

### 2. Settings Automation (Continuous Process)

Ongoing optimization of detection settings after deployment. This is the higher-value, harder problem.

**Quick settings** (can be determined immediately): camera range, camera pitch, resolution, color space, classification type, dynamic slicing for large images, crops for blocked views.

**Slow settings** (require observation period): confidence threshold, frame threshold, max_slices. Start with standard defaults, then tweak over a ~2 week period or after reaching an event count threshold. RoboMladen could assist by pulling clips, running them through analysis, and examining confidence distributions.

**Update cadence**: Re-optimize every X months AND every time a new model is deployed by Data Science.

### Mathematical Approach

Have operators manually label detections as TP/FN/TN/FP to build a confusion matrix. Customers could then choose optimization profiles:

- **F1** -- balanced precision/recall
- **F0.5** -- minimize false positives ("no false alarms")
- **F2** -- minimize missed detections ("no missed events")

These profiles would be saved to customer and site profiles. Pitched as a marketing angle: "help our models learn your specific needs."

### Stretch Goals

- Ignore zone automation
- Settings automation integrated with model deployment pipeline

## See Also

- [[worklog-robomladen-kickoff]] -- RoboMladen tool that could power the slow-settings analysis
