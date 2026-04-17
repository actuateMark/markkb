---
title: "Source: Django-Q Scheduler Architecture"
type: source
topic: actuate-platform
tags: [worklog, django-q, scheduler, job-factory, healthcheck, dynamo]
ingested: 2026-04-14
author: kb-bot
---

# Django-Q Scheduler Architecture

Source: internal working notes on the Django-Q scheduler setup and job factory pattern.

## Job Registration and Tracking

Every job, including on-demand jobs, should be registered so they can be accessed later. The proposed tracking model uses a DynamoDB table:

| Field | Description |
|-------|-------------|
| job_id | Returned by the job factory at creation time |
| type | Job type identifier |
| status | Current status (created, running, complete, failed) |

## Job Factory Pattern

A factory-based architecture where each job type has its own factory class implementing a common interface:

```
jobFactory.<jobtype>.makejob(args)
```

Each file in the job factory module is a factory derived from a shared interface, making job creation uniform and extensible.

## Scheduler Design

- The Django-Q scheduler should live in a **separate repo** containing the plugin, relevant configuration, and a connection to the proper database.
- The scheduler can call local commands -- existing "shortcuts" all live in the same admin repo.
- Jobs should be scoped **per site**, not per camera.
- If a job hangs for more than one minute, the system should kill it.

## Healthcheck Integration

The site hierarchy UI should include a "enable camera status monitoring" toggle that creates a per-site healthcheck job. This repurposes existing admin UI patterns for job creation.

## Key Decisions

- The admin shortcuts need to be replaced with proper API endpoints rather than being ported directly.
- A "fake SSM command" mode enables local development/testing of jobs that would normally run via SSM in production.
