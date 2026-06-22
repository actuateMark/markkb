---
title: LocalStack vs ElasticMQ — local-test-stack decision
type: concept
topic: local-test-stack
tags: [localstack, elasticmq, decision, integration-testing, sqs, ddb, s3, secrets-manager]
created: 2026-05-20
updated: 2026-05-20
author: kb-bot
incoming:
  - topics/local-test-stack/_summary.md
  - topics/personal-notes/notes/daily/2026-05-21.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-27
---

# LocalStack vs ElasticMQ — local-test-stack decision

Decision record for choosing the AWS emulator at the foundation of the [[2026-05-20_local-ap-e2e-stack-installed|local-test-stack]].

## Options considered

| | ElasticMQ | LocalStack (community) |
|---|---|---|
| Services | SQS only | SQS + S3 + DDB + Secrets Manager + Lambda + many more |
| Image size | ~50 MB | ~700 MB |
| Boot time | ~1 s | ~5-10 s |
| FIFO queue support | Built-in | Built-in (community edition) |
| Single env var to redirect all boto3 | No (SQS only) | Yes (`AWS_ENDPOINT_URL=http://localhost:4566`) |
| Real prod parity | Very close on SQS | Close on all services we care about |

## Decision: LocalStack

**Why:** autopatrol-server's hot path touches SQS, DDB, S3, and Secrets Manager — all four — and `actuate_secrets.SecretManager` is instantiated *unconditionally* at startup (`server/autopatrol_queue.py:26`), before the `DUMMY_JSON` branch. With ElasticMQ we'd need to either provide prod AWS SSO creds (couples local tests to a live account and pollutes prod DDB on writes) or mock `actuate_secrets` separately. LocalStack covers all four in one container and one env var.

The boot-time + image-size cost is paid once per dev session and is worth it for the simplicity.

## Why this is not just "use moto"

`moto` (the Python in-process AWS mock) is a great unit-test tool, but it lives inside the Python process. We need a service we can run **two separate Python processes** (connector and autopatrol-server) against. That demands an out-of-process emulator. Could use `moto_server` (its standalone HTTP shim) — but LocalStack is more battle-tested and supports a wider service set.

## Why not paid LocalStack Pro

Community edition covers everything we need today (SQS / S3 / DDB / Secrets / Lambda). Pro adds IAM enforcement, Cognito, RDS, and a few other niche services. None are on autopatrol-server's hot path. Re-evaluate if we ever extend the harness to test connector → IAM-gated S3 or Lambda fan-out paths.

## Open question: ElasticMQ fallback?

If LocalStack ever becomes a drag (slow boot, flaky on a particular machine), the harness is small enough that swapping in ElasticMQ + real prod for the rest is plausible. But that would re-introduce the prod-AWS coupling we're trying to avoid.

## Cross-refs

- [[2026-05-20_local-ap-e2e-stack-installed]] — the harness using LocalStack.
- [[2026-05-20_local-ap-e2e-test-stack-plan]] — the original proposal that listed both options.
