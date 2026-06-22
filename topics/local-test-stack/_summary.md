---
title: Local Test Stack
type: summary
topic: local-test-stack
tags: [local-testing, integration-testing, localstack, sqs, ddb, s3, autopatrol, vms-connector, autopatrol-server, immix-stub, harness]
created: 2026-05-20
updated: 2026-05-20
author: kb-bot
---

# Local Test Stack

Cross-repo developer-laptop harness for driving end-to-end flows through multiple Actuate services with **no real AWS infra**. First built 2026-05-20 to validate the [[2026-05-20_ap-summary-disable-plan|AutoPatrol summary-send disable]] change across vms-connector + autopatrol-server.

**Location:** `/home/mork/work/local-test-stack/` (local-only, not a GitHub repo — yet).

**Foundation:**
- [LocalStack 3.8](https://docs.localstack.cloud/) Docker container serving SQS + S3 + DynamoDB + Secrets Manager on `localhost:4566`.
- A `sitecustomize.py` import hook on `PYTHONPATH` that monkey-patches `actuate_integration_calls.autopatrol.autopatrol_api.AutoPatrolAPI` so every networked method is a no-op + a JSONL recording at `/tmp/local-test-stack/immix-calls.jsonl`.
- Seeded SQS queues / S3 buckets / DDB tables / Secrets Manager secret matching production names so the services boot without code changes.
- Helper scripts: `run-stack.sh`, `run-connector.sh`, `run-autopatrol-server.sh`.

## Flows the stack can drive today

| Flow | Status | Note |
|---|---|---|
| vms-connector AP run → SQS → autopatrol-server `action()` round-trip | ✅ working as of 2026-05-20 | Connector lifecycle reaches the SQS send + end_patrol call; server consumes and processes. |
| Other connector integrations ([[rtsp-deep-dive|RTSP]], Milestone, etc.) | ❌ not in scope yet | Could be added incrementally — most boto3 sends will Just Work since LocalStack covers all four services we use. |
| VCH (Video Camera Healthcheck) cycle | ❌ not yet | Would need a different settings file and possibly extra DDB schemas; future work. |

## Notes in this topic

### Syntheses
- [[2026-05-20_local-ap-e2e-stack-installed]] — durable record of the AP harness (artifacts, env, validation procedure).

### Concepts
- [[2026-05-20_immix-stub-via-sitecustomize]] — pattern: monkey-patch a CodeArtifact SDK at Python startup via `PYTHONPATH` + `sitecustomize.py` + a `MetaPathFinder`. Includes the infinite-recursion trap if you call `importlib.util.find_spec` from inside the finder.
- [[2026-05-20_localstack-vs-elasticmq-decision]] — why LocalStack over ElasticMQ for this harness.

## What this is NOT

- **Not a CI gate.** Today it's a developer-laptop tool. Adding to CI is future work.
- **Not a full functional simulator.** Camera streams aren't served (Immix `get_patrol_stream` is stubbed to return `None`), so cameras fail to fetch frames — the lifecycle still proceeds because the AP site manager tolerates per-camera failures, but you won't get realistic detections.
- **Not air-gapped from external APIs other than Immix.** `actuate-libraries` / Admin API calls inside autopatrol-server still go out to whatever endpoint the admin SDK resolves. Add stubs as needed.

## Cross-topic links

- [[autopatrol/_summary]] — the product this harness was first built for.
- [[autopatrol-server]] — the service the harness drives.
- [[2026-05-20_ap-summary-disable-plan]] — the change validated by this harness.
- [[branch-conventions]] — local-test-stack is local-only; no branch convention applies.
- [[engineering-process/_summary]] — local testing patterns broadly.

## History

- **2026-05-20** — Initial build. Triggered by AP-summary-disable cross-repo change (vms-connector + autopatrol-server). Recommended approach (LocalStack + sitecustomize Immix stub + dev-environment-style helper scripts) approved by user. Lives at `/home/mork/work/local-test-stack/`, local-only — promote to a real repo only if it earns its keep.
- **2026-06-11** — Used to pilot **per-camera AutoPatrol tiering** (the connector change). Fixture `ap_percam_test_settings.json` (3 cameras: intruder→T2, fire→T3, intruder+crowd→T2). Recorded `get_patrol_stream` calls in `immix-calls.jsonl` confirmed **per-device tiers 2/3/2 within one patrol** + `keepalive_tier=2` + crowd not escalating. **Workaround for limitation #3 (admin API `list_ai_models` 403):** set `customer.local: true` in the settings — `CustomerConfig` then sets `mock=True` and skips the real admin call (no stub or auth needed). GOTCHA: the connector runs the **working-tree source**, not the installed wheel — `git reset --hard origin/<branch>` the connector before piloting, or you'll silently test stale code (saw `tier=1` from pre-change code while the venv libs were current).
