---
title: "Health Report"
type: entity
topic: camera-health-monitoring
tags: [lambda, aws, python, ses, email, healthcheck, scheduled-job]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/camera-ui.md
  - topics/camera-health-monitoring/notes/syntheses/2026-06-23_daily-report-pipeline-audit-and-deploy-fixes.md
  - topics/software-architecture/notes/syntheses/2026-04-16_code-health-dashboard.md
incoming_updated: 2026-06-24
---

# Health Report

Health Report (`healthcheck_report_generator`) is a Python-based AWS Lambda system that generates and sends daily camera health report emails to Actuate customers. It consists of two Lambda functions working in a fan-out pattern: a job generator that determines who receives reports and what sites they cover, and per-recipient email Lambdas that fetch health data and render/send the reports.

## Architecture

The system uses a two-stage Lambda fan-out design:

### Stage 1: Job Generator Lambda (`healthcheck_report_job_generator`)

The job generator runs on a daily schedule and:

1. Queries the [[actuate-admin-api]] for all healthcheck configurations (`GET /healthcheck/?deployment=3`) with pagination
2. Builds a map of email addresses to site IDs by parsing the `report_emails` field on each healthcheck config
3. Adds debug/internal recipients (`mark+allreports@actuate.ai`, `laura+allreports@actuate.ai`) who receive all sites
4. For each email recipient, asynchronously invokes the email Lambda via `boto3.client('lambda').invoke()` with `InvocationType='Event'`, passing the email address and associated site IDs

### Stage 2: Email Lambda (`healthcheck_report_email`)

Each email Lambda invocation receives `{ email, site_ids }` and:

1. Fetches customer configuration for each site via the [[actuate-admin-api]] (`/customer/{id}/about` and `/healthcheck/by_customer/{id}`)
2. Fetches today's healthcheck rollup data (`/healthcheck_result/rollup`) for the date range
3. Fetches yesterday's rollup data for day-over-day comparison
4. Categorizes issues into healthcheck packet types: connectivity, image quality, stream quality, recording status, scene change, server status, and motion status
5. Builds an `EmailData` object that aggregates site-level and cross-site statistics
6. Renders the email body via `email_template.py` with priority-tiered site sections
7. Sends the email via AWS SES using the [[actuate-alarm-senders]] `LightSesAlertSender`, from `healthmonitoring@actuate.ai`

## Email Content

The generated report is a plain-text email with the subject "Your {day} Camera Health Report". It includes:

- **Header**: Report period, site count, total camera count, overall system health percentage
- **Status changes summary**: Counts of high/medium/low severity issues with new vs. resolved breakdowns
- **Priority-tiered site sections**: Sites grouped into high priority (<75% health), medium (75-95%), low (95-99%), and fully resolved (100%)
- **Per-site detail**: Site name, health score, and per-issue-type counts with new/ongoing/resolved breakdowns using severity-colored indicators
- **Footer**: Link to the full dashboard at `https://config.actuateui.net/health`

## Dependencies

The project requires Python 3.12+ and relies heavily on [[actuate-libraries]]:

- `actuate-admin-api` (1.0.2) -- API client for the Actuate admin backend
- `actuate-integration-calls` (1.2.19) -- shared integration utilities
- `actuate-healthcheck-objects` (1.0.13dev3) -- data models for healthcheck packets (`HealthcheckPacket`, `ConnectivityPacket`, `StreamQualityPacket`, `RecordingPacket`, `SceneChangePacket`, `ServerStatusPacket`, `MotionStatusPacket`, `ImageQualityPacket`, `AlertDataPacket`)
- `actuate-config` (1.3.2dev2) -- `CustomerConfig` for site configuration
- `actuate-alarm-senders` (1.4.0dev1) -- SES email sending via `LightSesAlertSender`
- `actuate-image-cache` (1.0.3) -- image caching utilities
- `actuate-threadpool` (1.0.2) -- thread pool utilities

## Deployment

Each Lambda is deployed as a zip package uploaded to S3 (`actuate-lambda-zips` bucket) and then updated via `aws lambda update-function-code`. Deploy scripts in `src/report_email/deploy_prod.sh` and `src/report_email_job_generator/deploy_prod.sh` bundle the source files with all pip-installed dependencies from the virtualenv into zip archives. The email Lambda deploys to `healthcheck_report_email` and the job generator to `healthcheck_report_job_generator`.

## Related

- [[camera-ui]] -- the HealthMonitoring page provides the web dashboard counterpart to these email reports
- [[actuate-admin-api]] -- backend API that provides healthcheck data and customer configuration
- [[actuate-libraries]] -- shared libraries that provide the healthcheck object models and SES sender
