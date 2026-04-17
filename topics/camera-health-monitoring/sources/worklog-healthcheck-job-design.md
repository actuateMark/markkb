---
title: "Source: Healthcheck Job Design in Job Consumer"
type: source
topic: camera-health-monitoring
tags: [worklog, job-consumer, sqs, dynamodb, alibi, envera]
ingested: 2026-04-14
author: kb-bot
---

# Healthcheck Job Design in Job Consumer

Worklog notes on how healthcheck jobs are created, scheduled, and executed within the job consumer infrastructure.

## Job Scheduling

A dedicated endpoint in the **job scheduler** creates once-an-hour healthcheck jobs. For Alibi integrations specifically, healthcheck jobs are dynamically created and deleted. Results are written back to the **camera status DynamoDB table** (not a separate HC table -- this may represent an earlier design iteration before the dedicated `Camera_Healthchecks` table).

## Job Execution Pattern

Jobs follow this flow:

1. For a given customer (e.g., "Envera"), pull all associated sites via DB access.
2. Shoot off individual jobs for each site to the SQS queue.
3. Each job is limited to **one DB call** to prevent job factories from overwhelming DB access/IO.

Job arguments include: customer name and healthcheck type (e.g., "connection check").

## Integration-Specific Checks

- **Alibi**: Uses the Light API to query camera status, plus RTSP connectivity testing (connect and immediately drop if successful). Hard drive health data is pulled separately (see [[worklog-hard-drive-health-fields]]).
- **Envera**: Run connectivity tests, pull connectivity status.

## Frontend Integration

An indicator on the frontend shows which cameras have been checked. Results are initially printed to a consolidated list, with plans to update the Postgres `last_healthcheck` and `status` fields.

## Design Constraint

Cannot allow job factories to proliferate unchecked -- DB access and IO must be carefully controlled. The `call_endpoint` job type on the job scheduler is used for healthcheck invocations.

## See Also

- [[healthcheck-architecture]] -- overall system design
- [[worklog-hard-drive-health-fields]] -- Alibi-specific field details
