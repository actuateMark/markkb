---
title: "Source: Lambda Function Catalog"
type: source
topic: infrastructure
tags: [worklog, lambda, aws, workshop, inventory, iam]
ingested: 2026-04-14
author: kb-bot
---

# Lambda Function Catalog

Source: workshop inventory of all Lambda functions and their associated IAM roles, with usage status.

## Active Lambdas

**Detection/Alert pipeline:**
- `create_detection_window` -- creates detection windows from frame data
- `upload_alert_to_cw_v3` -- uploads alerts to CloudWatch (v3, current)
- `create_detection_window_mp4` -- MP4 variant of detection window creation
- `upload_alert_to_cw` -- older alert upload version
- `create_alert_mp4` -- creates MP4 alert clips

**Frame/image processing:**
- `framefetcherV2` -- fetches frames from sources
- `AnalyticsFetcher` -- retrieves analytics data
- `video-analyzer-stack-ImageProcessorLambda` -- image processing pipeline
- `fetchEnveraEvent` -- Envera integration event fetcher

**Blur/metrics:**
- `calculateBlurCameras` -- camera blur metric calculation
- `check_number_of_alerts` -- alert volume monitoring

**Admin/infrastructure:**
- `sam-admin-status-AdminStatusFunction` -- admin status checks
- `sam-admin-camera-AdminCameraFunction` -- admin camera operations
- `container_monitor` -- container monitoring
- `healthcheck_report` -- healthcheck report generation
- `CommitModelServerDockerfileSagemakerLambda` -- model server Dockerfile management
- `cscustomersiteupdates` -- customer/site CRM updates
- `create_ticket_froms3` -- S3-triggered ticket creation

## Inactive / Deprecated

- `update_close_data` -- Close.com CRM sync (not in use)
- `update_customer_data_bi` -- BI data update (not in use)

## Notes

Some of these lambdas are candidates for migration to the [[job-executor-plan|job executor system]], particularly `check_number_of_alerts`, CRM-related functions, and the ticket creation lambda. The note also flags "questionable permissions" on several functions, suggesting an IAM audit is warranted.
