---
title: "Job Executor Architecture"
type: concept
topic: actuate-platform
tags: [job-executor, django-q, scheduler, workflows, job-factory, migration]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
incoming:
  - topics/product-roadmap/notes/syntheses/improvement-opportunities.md
incoming_updated: 2026-05-01
---

# Job Executor Architecture

The job executor is the planned centralized system for running all scheduled and on-demand jobs across the Actuate platform, replacing the current patchwork of Django-Q scheduled commands, standalone scripts, Lambda functions, and SSM-triggered tasks.

## Design Principles

1. **Unified registration** -- every job, whether scheduled or on-demand, is registered in a central catalog with both a creation endpoint and an execution endpoint. This lets the frontend create jobs during onboarding and modify them later.
2. **Job factory pattern** -- each job type is implemented as a factory class behind a common interface (`jobFactory.<jobtype>.makejob()`). This keeps creation uniform and makes adding new job types mechanical.
3. **DynamoDB tracking** -- a jobs table stores `job_id | type | status`. The job ID is returned at creation time, enabling result polling and pre-constructable result URLs (e.g., S3 frame paths).
4. **Workflow chains** -- compound jobs where one step feeds into the next, using Django-Q's chain pattern. Example: run a multi-camera healthcheck, then auto-send the results as a report.
5. **Iterable tasks** -- given a list (e.g., all sites for a customer), spawn one task per item.
6. **Per-site scoping** -- jobs are organized per site, not per camera.
7. **Kill hung jobs** -- if a job hangs for more than one minute, terminate it.

## Job Categories (30+ identified)

- **Schedule management**: start/stop, redeploy, dusk-to-dawn, daylight savings, cleanup.
- **Monitoring/reporting**: no-motion, cameras-not-restarted, connectivity, motion/detection summaries.
- **Infrastructure checks**: duplicate containers, old containers, CPU/memory review, connection checks.
- **Camera operations**: status checks, stream checks, YOLO instances, configuration, motion triggers.
- **Onboarding**: AWS/NewRelic log activation, camera configuration, auto-onboard validation.
- **Integrations**: [[bold-components|Bold]] heartbeat, auto-training workflow, CRM sync, per-integration healthchecks.

## Migration Strategy

Jobs are tiered by admin dependency:
- **Standalone** -- no admin models needed; migrate directly to independent executors.
- **SSM bridge** -- trigger from outside admin via SSM while planning full migration.
- **Admin-coupled** -- require admin API endpoints to be built first before migration.

## Queue Consumer Reliability

The [[queue-consumer|queue consumer]] (K8s pod reading SQS FIFO) is the execution engine for alert delivery and other queued work. Operational incidents with the Immix integration exposed several reliability gaps in the original design:

- No healthcheck on the consumer itself, so failures went undetected.
- No exception recovery -- transient errors crashed the entire consumer.
- No redundancy -- a single consumer was a single point of failure.

Hardening measures: wrap the queue listener in try/catch for graceful recovery, add self-healthchecks, create redundant consumer tasks, schedule periodic restarts to prevent state accumulation, and enable ECS exec for live debugging.

## Healthcheck Job Fan-Out

When a healthcheck targets a customer, the scheduler pulls all sites for that customer in a single DB call, then enqueues individual per-site jobs to SQS. Each downstream job is constrained to one DB call to prevent job factories from overwhelming database IO. This pattern balances parallelism with resource control.

## Sources

- [[job-executor-plan|Job Executor Project Plan]] -- full catalog and migration analysis
- [[django-q-scheduler-architecture|Django-Q Scheduler Architecture]] -- scheduler design and factory pattern
- [[lambda-function-catalog|Lambda Function Catalog]] -- Lambda candidates for migration
- [[worklog-immix-after-action]] -- [[queue-consumer|queue consumer]] operational lessons
- [[worklog-healthcheck-job-design]] -- healthcheck job scheduling patterns
