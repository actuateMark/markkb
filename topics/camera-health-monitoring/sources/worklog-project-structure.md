---
title: "Source: Healthcheck Architecture and Project Structure"
type: source
topic: camera-health-monitoring
tags: [worklog, architecture, flask, dynamodb, healthcheck-runners]
ingested: 2026-04-14
author: kb-bot
---

# Healthcheck Architecture and Project Structure

Original worklog notes describing the full architectural design for the camera health monitoring system.

## Architecture Overview

The system is built around three core components:

1. **Flask API** -- receives healthcheck jobs from external callers.
2. **Healthcheck Manager** -- orchestrates job execution. When a call comes in, it dispatches jobs to each runner, collates results, writes them to DynamoDB, and returns the aggregated response.
3. **Healthcheck Runners** -- initialized at program start, each configured to run specific sets of healthchecks for different integrations. Runners are organized in a dependency tree: if a parent check fails, all child checks automatically fail (e.g., no connectivity means no FPS check is possible).

## Camera Model

A dedicated healthcheck camera is a separate camera type from the standard VMS connector camera. It does not need the full puller pipeline, but it is intentionally organized in the same fashion so that smart cameras can be augmented with healthcheck functionality in the future. A HC camera should still have a puller (even a limited version) and implement the interface pseudo-defined in `basecamera.py`. There must be a standardized puller base class (abstract or interface) containing the functions needed to run healthchecks -- in the HC case, these pullers are not real-time but listen to motion events and connect to the camera API on demand.

## Check Types

Four core checks: **connectivity**, **stream quality**, **motion status**, and **scene change**. Each has a default failure message and an "inapplicable" message for cameras that cannot provide that metric.

## DynamoDB Schema

Table: `Camera_Healthchecks`. Fields: `run_timestamp`, `site_id`, `site_name`, `camera_id`, `camera_name`, `report_generated`, `connectivity`, `stream_quality`, `motion_status`, `scene_change`, `error_text`, `sample_frame_location`.

## Design Consideration

The notes raise the possibility of running all cameras within a single pod, acknowledging this departs from the standard one-pod-per-site deployment pattern but may be worth exploring for healthcheck-only workloads.

## See Also

- [[health-check-types]] -- detailed breakdown of each check category
- [[healthcheck-architecture]] -- synthesized concept note
