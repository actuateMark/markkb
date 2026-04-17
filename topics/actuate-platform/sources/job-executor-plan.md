---
title: "Source: Job Executor Project Plan"
type: source
topic: actuate-platform
tags: [worklog, job-executor, django-q, admin-jobs, scheduler, workflows, migration]
ingested: 2026-04-14
author: kb-bot
---

# Job Executor Project Plan

Source: comprehensive project plan for building a unified job executor to replace scattered admin scripts, lambdas, and scheduled tasks.

## Architecture Vision

Every job -- whether scheduled or on-demand -- should be registered in a central system with both a creation endpoint and an on-demand execution endpoint. This enables:

- **Frontend-driven job creation** during onboarding (e.g., schedule refresh, healthchecks).
- **Workflow chains** using Django-Q's chain pattern -- compound jobs where one step feeds into the next (e.g., run multi-camera healthcheck then auto-send report).
- **Iterable tasks** -- given a list of sites for a customer, spawn one task per site.
- **Job tracking** -- a DynamoDB table storing `job_id | type | status`, with the job ID returned at creation time so results can be polled or URLs pre-constructed (e.g., S3 frame URLs).

## Job Catalog (30+ jobs identified)

The plan catalogs jobs across several categories:

- **Schedule management**: start/stop, schedule override, dusk-to-dawn adjustment, daylight savings redeploy, cleanup old schedules, redeploy schedules.
- **Monitoring/reporting**: no-motion reports, cameras-not-restarted reports, connectivity reports, motion summaries, detection summaries, motion upload (Datadog, Genesis).
- **Infrastructure checks**: duplicate container detection, old container checks, CPU/memory review, connection checks.
- **Camera operations**: camera status check, stream checks, YOLO instance checks, camera configuration, DW HTTP motion config, trigger camera motion, update camera names.
- **Onboarding**: update AWS logs, update NewRelic logs, configure cameras, auto-onboard checks.
- **Integrations**: Bold heartbeat, auto-training workflow, CRM updates (Close.com), healthchecks per integration type (LightAPI, Envera).
- **Lambda migrations**: create_ticket, check_number_of_alerts, memory_across_instances, CRM lambdas.

## Migration Strategy

Jobs fall into tiers:
1. **Standalone executors** -- jobs that do not need admin models (Bold heartbeat, reports, container checks). Move to independent job executors immediately.
2. **SSM-based bridge** -- jobs that still need admin but can be triggered externally via SSM, with an eye toward full migration later.
3. **Admin-coupled** -- jobs that heavily use admin models (schedule management, redeploy). Require admin API endpoints first.

## Job Executor UI

Plans include a UI for browsing supported job types, generating vanilla job instances, and migrating existing Django admin forms for job types that warrant dedicated configuration.
