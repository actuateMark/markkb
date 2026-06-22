---
title: Local AP end-to-end test stack — proposal
author: kb-bot
created: 2026-05-20
updated: 2026-05-20
tags: [local-testing, autopatrol, vms-connector, autopatrol-server, sqs, localstack, elasticmq, infrastructure]
---

# Local AP end-to-end test stack — proposal

## Goal

Drive a single AutoPatrol run through the **full** pipeline on a developer laptop, no real AWS infra, so we can validate cross-repo lifecycle changes (like the [[2026-05-20_ap-summary-disable-plan|summary-send disable]]) before they hit prod or stage.

The flow we need:

```
local vms-connector (-l, autopatrol settings)
        │
        │ SQS send → autopatrol_jobs_dev.fifo
        ▼
local SQS emulator (ElasticMQ or LocalStack)
        │
        │ poll
        ▼
local autopatrol-server (server.app, DUMMY_JSON or live SQS mode)
        │
        ▼
side-effects (S3 writes, DDB writes, Immix end_patrol)
```

## Today's gap

| Capability | Status |
|---|---|
| autopatrol-server local-run docs | Only the README's `DUMMY_JSON=true` recipe; no KB note. README recipe is partly broken: `server/dummy_patrol.json` doesn't exist (use one of the captured `autopatrol_messages_*.json` instead). |
| autopatrol-server runs without AWS creds | **No** — `actuate_secrets.SecretManager` is instantiated unconditionally at startup (`server/autopatrol_queue.py:26`), before the `DUMMY_JSON` branch. Either provide prod AWS SSO creds (read-only) or mock `actuate_secrets.get_secret`. |
| vms-connector → SQS emulator | **No prior plumbing.** `dao_factory.py` always constructs the real `ConnectorSQSDAO` in `-l` mode. boto3 1.42 honors `AWS_ENDPOINT_URL_SQS` but `SQSDAO.send_message` embeds the queue URL built from `app_config.queue_url`, so we also need `QUEUE_URL` overridden to the emulator URL. No code change needed if env-var override works; one-line `[patch:actuate-daos]` fix as backup. |
| Local SQS emulator | Nothing checked in. |
| Local DDB / S3 / Secrets | Nothing checked in. autopatrol-server reads `WindowIdsV2`, `EnrichedFrameV2`, `MotionFrame`, `autopatrol_chm_issues`, `autopatrol-site-classification`, `camera-preview-descriptions`, `autopatrol-prompts` from DDB; writes `autopatrol-patrols` + `autopatrol-queue-archive`; reads `detection-frames-aegis-v2`. Real prod tables/buckets, no schemas in source. |
| Documented end-to-end recipe | None in KB. `.claude/skills/local-integration-test.md` covers `connector.py -l` but never crosses to autopatrol-server. |

## Choice 1: emulator — ElasticMQ vs LocalStack

**ElasticMQ** — single Docker container, ~50 MB image, FIFO-queue support out of the box, SQS-only.

- Pros: trivially fast to start, no resource drag. SQS-perfect API parity (built for this).
- Cons: only solves SQS. We'd still need to either mock or pass-through DDB/S3/Secrets/etc.

**LocalStack** (community edition) — multi-service AWS emulator (SQS + DDB + S3 + Secrets Manager + Lambda all in one).

- Pros: covers the entire AWS dependency set of autopatrol-server. Single env var (`AWS_ENDPOINT_URL=http://localhost:4566`) redirects every boto3 client at once. Once running, the e2e test becomes "boot LocalStack, seed schemas, run the two services."
- Cons: heavier image (~700 MB), slower to start, FIFO support is paid-tier in some versions (worth verifying against current free version). DDB schemas must be pre-seeded — fixture work.

**Recommendation: LocalStack**, because the connector-only side is the easy part — the autopatrol-server side needs DDB + S3 + Secrets all at once. ElasticMQ wins only if we're willing to hit prod for everything else, which I want to avoid for repeatable tests.

## Choice 2: where this tooling lives

| Option | Pros | Cons |
|---|---|---|
| **(A)** New repo `local-test-stack` | Clean home, can grow. | Yet another repo to maintain. |
| **(B)** New folder `local-stack/` inside [[dev-environment]] | Co-located with the laptop-setup that engineers already run. Already on GitHub. | Mixes "install dev tools" with "run an integration stack" — different cadence. |
| **(C)** A folder under one of the participating repos (e.g. `vms-connector/local-stack/`) | Always visible to anyone working on the connector. | Cross-repo doesn't have a natural home; biases toward the connector POV. |
| **(D)** Just KB docs + ad-hoc scripts copy-pasted into each repo as needed | Zero new infra. | High discovery cost; brittle. |

**Recommendation: (B) — a `local-stack/` folder in `dev-environment`**, with the artifacts being:

- `local-stack/docker-compose.yml` (LocalStack + optional Immix mock)
- `local-stack/seed.sh` (creates SQS queue, DDB tables, S3 buckets)
- `local-stack/env.template` (the env vars to source for both services)
- `local-stack/README.md` (run instructions, links to KB synthesis)

KB doc lives at `topics/engineering-process/notes/syntheses/2026-05-20_local-ap-e2e-stack-installed.md` once the stack is real (this current note is the design proposal).

**Decision 2026-05-20 (revised):** `dev-environment` turned out to be effectively abandoned (default branch `simple`, last touched Jan 2025, user does not recognize as active repo). New plan: artifacts live in a **local-only** folder `/home/mork/work/local-test-stack/` — no GitHub remote, no PR ritual. Promote to a real repo only if it earns its keep over time.

## Choice 3: what to mock vs accept upstream

| Dependency | Suggested handling |
|---|---|
| SQS | LocalStack. |
| S3 | LocalStack (with seeded `detection-frames-aegis-v2` fixtures). Write buckets created empty. |
| DDB | LocalStack (with `WindowIdsV2` + `EnrichedFrameV2` + `MotionFrame` + `autopatrol_chm_issues` schemas seeded; small fixture rows for one test patrol). |
| Secrets Manager | LocalStack — seed a fake `prod/actuate/autopatrol` secret with placeholder keys. |
| **Immix / `AutoPatrolAPI`** | Stub. Connector calls `start_patrol`/`end_patrol`; autopatrol-server (now) doesn't. Options: (a) monkey-patch `AutoPatrolAPI` in a dev-only entry-point wrapper, (b) point at an `httpbin`-style local responder. (a) is lighter. |
| **[[actuate-admin-api|Actuate Admin API]]** (`utils/admin_calls.py:9`) | Stub or point at the existing dev admin API. Used for site/camera name lookups in summarizer. |
| Connector → AWS for non-AP traffic (motion DAO, blacklist, healthcheck) | Constructed but not invoked on the AP path. LocalStack will satisfy boto3 client creation. |

## Choice 4: scope of the first deliverable

| Option | Cost | Value |
|---|---|---|
| **Minimal:** docker-compose + seed script + KB doc; manual `python connector.py -l` and `python -m server.app` in two terminals. | ~half a day. | Unblocks today's AP-summary-disable validation. |
| **Mid:** plus a single `./run-e2e.sh` that boots both services, tails logs, asserts the message round-trip succeeded. | ~1-2 days. | Repeatable; gives us a CI-able harness. |
| **Full:** plus pytest-based integration tests living in the stack repo, called from each contributing repo's CI. | ~1-2 weeks. | True regression gate. |

**Recommendation: Minimal first**, then promote to Mid once it's been used once. Skip Full unless we see real recurring cross-repo regressions.

## Clarifying questions

1. **Emulator: LocalStack or ElasticMQ?** Recommendation LocalStack for coverage, but it's heavier. If you want to start small and add more later, ElasticMQ + accept-prod-for-other-AWS is cheaper to ship.
2. **Home: `dev-environment/local-stack/` (recommended) or new repo `local-test-stack`?** Or somewhere else (e.g. inside vms-connector)?
3. **Immix `AutoPatrolAPI` calls**: stub them with a monkey-patch in a dev wrapper, OR point at the real `develop` endpoint? Real `develop` is simpler but couples local tests to a real external API (and our test patrol_ids show up there).
4. **Scope: minimal / mid / full?** Recommendation minimal.
5. **Today's AP-summary-disable validation**: do you want to use this stack to validate the change *before* opening the PRs, or open the PRs now and build the stack in parallel? Validation-before-PR is ideal but adds maybe a day before the PRs land.
6. **CodeArtifact + AWS auth**: assume the engineer running this has prod AWS SSO + CodeArtifact already working (the current `dev-environment` baseline), right? If so the stack only needs to bootstrap LocalStack + seed fixtures.

## Cross-refs

- [[2026-05-20_ap-summary-disable-plan]] — the change we'd validate first.
- [[autopatrol-server]] — entity note.
- [[branch-conventions]] — for the new repo question.
