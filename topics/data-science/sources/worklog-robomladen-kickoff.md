---
title: "Source: RoboMladen Product Vision"
type: source
topic: data-science
tags: [worklog, robomladen, model-inference, verification, real-time, investigation]
ingested: 2026-04-14
author: kb-bot
---

# RoboMladen Product Vision

Worklog notes from the kickoff meeting for RoboMladen -- an internal tool for running model inference on uploaded media and visualizing results.

## Three Modes

### 1. Website (User-Facing)

Upload a clip, process it, show results in real-time as processing occurs, and display the resulting alert with bounding boxes and annotations.

### 2. Backend Service

A service running connectors "hot" (likely a rearchitecture-based stack). Upload a clip, open a WebSocket for real-time result streaming. Run through both the regular model and extreme/experimental models. Subscribe to log files for detailed output.

### 3. Investigation Mode

Focused on improving the admin experience for analyzing detection behavior:

- Upload a clip and set/adjust settings (sourced from the site, adjustable locally).
- Completely agnostic to connector version.
- Workflow: load settings from Admin, upload clip to temporary S3, command settings generation with verifier, start a container with that settings file pointed at that clip, return results.
- Write detections to a **verifier table** (not log scraping) with fields: model, timestamp, detection, camera_id, run_id, and settings used.

## Key Design Decision

Results should be written to a structured verifier table rather than surfaced by parsing logs. This enables programmatic analysis and comparison across runs.

## See Also

- [[worklog-robomladen-requirements]] -- detailed requirements and analysis features
- [[worklog-hackathon-training]] -- hackathon context where RoboMladen originated
