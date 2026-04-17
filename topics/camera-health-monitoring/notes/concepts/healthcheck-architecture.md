---
type: concept
author: kb-bot
created: 2026-04-14
updated: 2026-04-14
tags: [chm, architecture, flask, dynamodb, healthcheck-runners, dependency-tree]
---

# Healthcheck Architecture

The Camera Health Monitoring (CHM) system is a standalone health assessment service for customer cameras. It runs independently of the detection pipeline -- a site can be "healthcheck only" with no VMS connector workload.

## Component Stack

**Flask API** receives healthcheck job requests. These flow to the **Healthcheck Manager**, which dispatches work to **Healthcheck Runners** and collates results. The manager writes results to DynamoDB and returns them to the caller.

Runners are initialized at program start, each configured for a specific integration's check capabilities. They are organized in a **dependency tree**: if a parent check fails, all child checks automatically fail. The canonical example is connectivity -- if the camera is unreachable, stream quality, motion, and scene change checks cannot run and are marked as failed without execution. This prevents misleading error messages and wasted work.

## Camera Model

A healthcheck camera is a distinct camera type from the standard VMS connector camera. It has a puller (even if limited) and implements the `basecamera.py` interface. This deliberate alignment with the standard camera model means smart cameras can be augmented with healthcheck functionality later without architectural changes. The puller in HC mode is not real-time -- it listens to motion events and connects to the camera API on demand.

A standardized puller base class (abstract or interface) defines the functions needed for healthcheck execution. Each integration subclass implements only the diagnostics it can perform; the rest are graceful no-ops.

## Data Storage

Results land in the `Camera_Healthchecks` DynamoDB table with fields: `run_timestamp`, `site_id`, `site_name`, `camera_id`, `camera_name`, `report_generated`, plus per-check status fields (`connectivity`, `stream_quality`, `motion_status`, `scene_change`), `error_text`, and `sample_frame_location`. Each check field has a default failure message and an "inapplicable" message for cameras that cannot provide that metric.

## Job Scheduling

The job scheduler creates once-an-hour healthcheck jobs. For a given customer, the system pulls all associated sites and enqueues individual jobs per site to SQS. Each job is constrained to one DB call to prevent IO overload. Integration-specific checks (e.g., Alibi hard drive health via the Light API, Envera connectivity) are dispatched based on the integration type.

## Notification System

Email notifications are consolidated per CHM run per site. Only status changes trigger emails -- stable-healthy runs are silent. Alert severity influences email behavior: low-priority issues (stream/image quality) do not trigger standalone emails. The email template includes an overall health score, new issues grouped by priority, resolved issues, and a dashboard link.

## See Also

- [[health-check-types]] -- detailed breakdown of each check category
- [[worklog-project-structure]] -- original architecture notes
- [[worklog-chm-email-design]] -- email consolidation design
- [[worklog-integration-diagnostics]] -- per-integration diagnostic class hierarchy
