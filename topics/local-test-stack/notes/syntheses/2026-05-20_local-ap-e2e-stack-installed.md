---
title: Local AP end-to-end stack — installed
type: synthesis
topic: local-test-stack
tags: [autopatrol, vms-connector, autopatrol-server, localstack, sqs, integration-testing, harness, installed]
created: 2026-05-20
updated: 2026-05-20
author: kb-bot
incoming:
  - topics/autopatrol/notes/entities/autopatrol-server-deployment.md
  - topics/autopatrol/notes/syntheses/2026-05-20_ap-summary-disable-plan.md
  - topics/autopatrol/notes/syntheses/2026-05-27_ap-summary-disable-handoff.md
  - topics/local-test-stack/_summary.md
  - topics/local-test-stack/notes/concepts/2026-05-20_immix-stub-via-sitecustomize.md
  - topics/local-test-stack/notes/concepts/2026-05-20_localstack-vs-elasticmq-decision.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/vms-connector/notes/syntheses/2026-05-26_pyav17-local-validation.md
incoming_updated: 2026-05-28
---

# Local AP end-to-end stack — installed

Durable record of the local-test-stack as it exists at the AP-validation milestone. Companion to the design proposal [[2026-05-20_local-ap-e2e-test-stack-plan]].

## What was built

| Artifact | Path | Purpose |
|---|---|---|
| `docker-compose.yml` | `/home/mork/work/local-test-stack/docker-compose.yml` | LocalStack 3.8 with SQS + S3 + DDB + Secrets Manager on `localhost:4566`. Healthcheck via `awslocal sqs list-queues`. |
| `env.sh` | same dir | Sourced env: `AWS_ENDPOINT_URL*=http://localhost:4566`, fake `test`/`test` creds, `QUEUE_URL=http://localhost:4566/000000000000/`, `PYTHONPATH` includes our stub dir, `IMMIX_STUB_RECORD_PATH=/tmp/local-test-stack/immix-calls.jsonl`. |
| `seed.sh` | same dir | Creates SQS queues (`autopatrol_jobs[_dev].fifo`, DLQ), S3 buckets (`autopatrol-patrols`, `autopatrol-queue-archive`, `detection-frames-aegis-v2`, `actuate-settings`), 8 DDB tables with placeholder `id:S` keys, and the `prod/actuate/autopatrol` Secrets Manager secret. |
| `pythonpath/sitecustomize.py` | same dir | Auto-loaded Python startup hook — installs a `MetaPathFinder` that patches `AutoPatrolAPI` methods to record-and-return-None. See [[2026-05-20_immix-stub-via-sitecustomize]]. |
| `ap_local_test_settings.json` | same dir | Connector settings: derived from `vms-connector/test_settings/ap_settings.json`, single AP camera, `queue_stage: dev` + `endpoint_stage: dev` to route the SQS send to `autopatrol_jobs_dev.fifo`. |
| `run-stack.sh` | same dir | `up` / `down` / `reset` / `status` commands. |
| `run-connector.sh` | same dir | Symlinks settings, sources env, runs `uv run --no-sync python connector.py -l` with a 180s timeout, prints recorded Immix calls + queue depth. |
| `run-autopatrol-server.sh` | same dir | Live SQS poller mode (default) or `--once` to drain one message via DUMMY_JSON. |
| `README.md` | same dir | Quick-start + validation checklist. |

## Boot procedure

```bash
cd /home/mork/work/local-test-stack
./run-stack.sh up                # boot LocalStack + seed
source ./env.sh                  # load env into current shell
./run-autopatrol-server.sh       # terminal A — live poller
./run-connector.sh               # terminal B — one connector AP run
./run-stack.sh status            # verify queues + recorded Immix calls
```

## Validation checklist for the AP-summary-disable change

After `run-connector.sh` + `run-autopatrol-server.sh --once`, the recordings in `/tmp/local-test-stack/immix-calls.jsonl` must show:

| Call | Source PID | Expected |
|---|---|---|
| `start_patrol` | connector | ≥1 |
| `get_patrol_stream` | connector | ≥1 (keepalive_loop daemon) |
| `end_patrol` | **connector** | exactly 1 (pre-SQS-send call added by the change) |
| `raise_patrol_alert` | either | **0** (Immix raise disabled in autopatrol-server) |
| `end_patrol` | **autopatrol-server** | **0** (server-side end_patrol disabled too) |
| `get_patrol_stream` | autopatrol-server | **0** (both keepalives disabled) |

The `pid` field distinguishes the two services.

In addition (**storage audit — required, not optional**):

> Lesson 2026-05-21: a green log line is not the same as a successful write. Always audit the actual storage. The autopatrol-server logged "Saved data to ... in bucket autopatrol-patrols" *and* the object existed; the connector logged its DDB write *and* the row existed — but neither could be assumed. The DDB lookup with `GetItem patrol_id=...` returned `ValidationException` because the `autopatrol_results` table has a **composite key (patrol_id, timestamp)** and requires both.

- `autopatrol_jobs_dev.fifo` queue depth should be **0** after the run (server consumed it).
  - `aws sqs get-queue-attributes --queue-url ... --attribute-names ApproximateNumberOfMessages`
- S3 bucket `autopatrol-queue-archive` should contain `<patrol_id>_message.json` (server's `save_message_to_s3`).
  - `aws s3 ls s3://autopatrol-queue-archive/ --recursive | grep <patrol_id>`
- S3 bucket `autopatrol-patrols` should contain `<patrol_id>.json` (server's `save_patrol_to_s3` — the summary itself).
  - `aws s3 ls s3://autopatrol-patrols/ --recursive | grep <patrol_id>` and `aws s3 cp s3://autopatrol-patrols/<patrol_id>.json -` to inspect body.
- DDB `autopatrol_results` should contain a row keyed `(patrol_id, timestamp)` written by the connector's `save_patrol_result` thread (`actuate_daos/autopatrol_dao.py:69`).
  - **Use `Query`, not `GetItem`**: `aws dynamodb query --table-name autopatrol_results --key-condition-expression "patrol_id = :pid" --expression-attribute-values '{":pid":{"S":"<patrol_id>"}}'`.
  - The row should contain `patrol_id`, `timestamp`, `tenant_id`, `site_id`, `schedule_id`, `group_id`, `alert_window_ids`, `ttl`.

A validation pass that confirms recordings but not storage is incomplete — the writes are what matter to downstream consumers.

## Known limitations

1. **DDB schemas are placeholders** (all `id:S`). Real prod schemas would need to be dumped via `aws dynamodb describe-table` if you need realistic clip lookups.
2. **Camera streams not served.** `get_patrol_stream` is stubbed → cameras get `None` → per-camera task results are empty. AP lifecycle still proceeds. For realistic frames, point at the `rtsp-camera-simulator` Docker container on port 8554 and rewrite the settings.
3. **[[actuate-admin-api|Actuate Admin API]]** (`autopatrol-server/utils/admin_calls.py:9`) — instantiated at module import, hits real dev/prod admin. Stub if needed.
4. **CodeArtifact dev-version pins** in autopatrol-server must still be reachable (`uv sync` must succeed).
5. **Re-entrance trap in sitecustomize**: see [[2026-05-20_immix-stub-via-sitecustomize#recursion-trap]] — fixed 2026-05-20 first try.
6. **Not in CI.** Developer-laptop only.

## Recovery / debugging

| Symptom | Likely cause | Fix |
|---|---|---|
| `connector exited with rc=1` + `RecursionError` in sitecustomize | Old import of `importlib.util.find_spec` re-entering the finder. | Should be fixed already — see [[2026-05-20_immix-stub-via-sitecustomize#recursion-trap]]. |
| `aws ... could not be resolved` | LocalStack not booted. | `./run-stack.sh up`. |
| `immix-calls.jsonl` empty after a run | `PYTHONPATH` wiring lost (subprocess didn't inherit). | Make sure `source env.sh` ran in the shell that invokes the connector / server. The runner scripts do this automatically. |
| Connector errors about `Patrols` table key schema | Real prod schema differs from placeholder `id:S`. | Catch is broad — should not block the lifecycle. If it does, dump the prod schema and update `seed.sh`. |

## Validation run 2026-05-20

First end-to-end run after the harness was assembled. Used to gate the AP-summary-disable PRs.

**Procedure:** `./run-stack.sh up && source env.sh && ./run-connector.sh && ./run-autopatrol-server.sh --once`.

**Result: PASS.** Recordings in `/tmp/local-test-stack/immix-calls.jsonl`:

```
pid 2904221 | get_patrols        (connector boot — fake patrol returned)
pid 2904221 | start_patrol       (connector run start)
pid 2904221 | get_patrol_stream  (puller init, tier=1, duration=10)
pid 2904221 | get_patrol_stream  (keepalive_loop tick, duration=2)
pid 2904221 | end_patrol         ← THE NEW CALL from AP-summary-disable
```

All five recorded calls have `pid 2904221` — the connector. Zero calls from the autopatrol-server process (would show up with a different pid).

**S3 artifacts:** both expected writes landed.
- `s3://autopatrol-queue-archive/52a25cb0...._message.json` (server's `save_message_to_s3`).
- `s3://autopatrol-patrols/52a25cb0....json` (server's `save_patrol_to_s3`).

**Non-blocking errors observed:** the autopatrol-server log surfaced two expected errors that the change does not fix and is not meant to fix:
1. `DDB ValidationException` querying `autopatrol_chm_issues` — because our placeholder seed schema (`id:S`) doesn't match the table's real key. Server catches and proceeds with no-clips path.
2. `403 Forbidden` from `admin.actuateui.net/api/customer/35272/` — the Admin API doesn't accept our fake CodeArtifact token. Server catches and proceeds.

Both are properties of the harness, not the change under test.

**Iteration cost:** four cycles of "run, find next missing seed, add to seed.sh" — `prod/actuate/new_relic` secret, `CONNECTOR_API_KEY` inside it, `autopatrol_results` DDB table with `patrol_id` key. All captured in the current `seed.sh`.

## Cross-refs

- [[2026-05-20_local-ap-e2e-test-stack-plan]] — the proposal that birthed this.
- [[2026-05-20_ap-summary-disable-plan]] — the change validated.
- [[2026-05-20_immix-stub-via-sitecustomize]] — companion concept note.
- [[autopatrol-server]] — service entity note.
- [[branch-conventions]] — repo conventions table.
