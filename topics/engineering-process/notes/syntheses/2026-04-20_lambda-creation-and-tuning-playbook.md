---
title: "Lambda Creation + Tuning Playbook"
type: synthesis
topic: engineering-process
tags: [lambda, aws, sqs, dynamodb, iam, deploy, local-testing, playbook, event-driven]
created: 2026-04-20
updated: 2026-04-20
author: kb-bot
incoming:
  - topics/autopatrol/notes/concepts/2026-04-20_cleanup-lambda-runbook.md
  - topics/autopatrol/notes/concepts/2026-04-22_cleanup-lambda-bake-state.md
  - topics/autopatrol/notes/entities/autopatrol-cleanup-lambda.md
  - topics/autopatrol/notes/syntheses/2026-04-17_stale-schedule-cleanup-design.md
  - topics/engineering-process/notes/concepts/2026-04-20_overnight-check-skill-pattern.md
  - topics/engineering-process/notes/concepts/2026-04-23_release-acceptance-criteria.md
  - topics/offboarding/notes/concepts/2026-06-23_autopatrol-handoff.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/runbooks/_backlog.md
incoming_updated: 2026-06-24
---

# Lambda Creation + Tuning Playbook

Lessons from building the AutoPatrol stale-schedule cleanup Lambda ([[2026-04-17_stale-schedule-cleanup-design]]) from plan to stage rollout in a single workstream. Applies to any new SQS-driven or Function-URL-driven Lambda in the Actuate stack.

Read this before:
- Designing a new Lambda that consumes SQS and mutates admin / Immix / external state
- Adding a new signal type to an existing Lambda pipeline
- Wiring up local testing for a Lambda that depends on cross-account secrets or private infra

## Core principles

### 1. Ship dark, then flip

Every new Lambda that mutates state ships behind an env-var kill switch (`CLEANUP_ENABLED=false` by default). Deploy the code first, observe metrics under DRY_RUN, then flip the switch. Two independent gates — `CLEANUP_ENABLED` for the master kill, `DRY_RUN` for "log what would happen without calling anything downstream" — because they serve different audiences:
- **`CLEANUP_ENABLED=false`** = rollout gate, flipped by ops
- **`DRY_RUN=true`** = test gate, used both on stage seed runs and in local invocations

Both default to "dark" so any accidental deploy of new code to prod is a no-op.

### 2. Stage-first routing lives in code, not config

When a feature rolls out stage → prod in a phased way, hard-code the phasing in a default-gating function:

```python
def _emit_enabled(config) -> bool:
    raw = os.environ.get("EMIT_FLAG", "").lower()
    if raw == "false": return False     # kill switch
    if raw == "true":  return True      # explicit opt-in
    return bool(config.use_dev_queue)   # default: on for stage, off for prod
```

Avoids needing a deployer/config-generator change to flip stage on. Prod stays explicit-opt-in via env var. The `use_dev_queue` check piggybacks on existing queue-routing convention so we don't invent a new primitive.

### 3. Emit best-effort, never block

Signal emit paths never raise. SQS failures are logged and swallowed. If the emitter can't talk to AWS, the pod keeps exiting cleanly:

```python
def emit_signal(...):
    try:
        sqs.send_message(...)
    except Exception as e:
        logging.warning(f"emit failed (non-blocking): {e}")
```

The Lambda + SQS chain is a visibility/observability layer for the actual service — never let it become a dependency that blocks the service.

### 4. Counter state in DDB, not the emitter

Stateful "how many times has this happened?" logic lives in the Lambda's DynamoDB table, not in the emitter. The connector pod is ephemeral — it must stay stateless. Two consequences:
- Emit every time the signal fires; let the Lambda dedupe + count
- Use FIFO `MessageDeduplicationId = <signal_key>:<floor(now, 1min)>` to prevent emit-storm from dead-looping pods
- Counter row has a TTL; absence of signals naturally resets state

## Architecture checklist for a new Lambda

- [ ] **SQS queue** FIFO + DLQ; `maxReceiveCount ≤ 3`; content-based-dedup OFF (use explicit `MessageDeduplicationId`).
- [ ] **DynamoDB counter table** if threshold-based; PK = logical signal key; TTL attribute enabled; pay-per-request unless volume is high and predictable.
- [ ] **Reserved concurrency cap** — set low (2-5) until you know the normal event rate. Prevents runaway actions from a queue flood.
- [ ] **DLQ alarm** — any depth > 0 should page.
- [ ] **Feature flags**: `<NAME>_ENABLED` (default `false`), `DRY_RUN` (default unset).
- [ ] **Slack audit** — every action the Lambda takes posts a line to a dedicated channel, including DRY_RUN / ENABLED=false cases so you can tell "nothing happened" from "we would've".
- [ ] **IAM** — scope down `sqs:Receive/Delete` to the specific queue, `dynamodb:Get/Put/Update/Delete` to the specific table. Start broad for parity with siblings, tighten post-ship.
- [ ] **NR instrumentation from day one** — don't ship a new Lambda without NR wrapping. Retrofitting observability is expensive.

## Signal design

### Route by reason, not by source

When multiple conditions can trigger the same pipeline, don't assume they share a threshold. Add a `reason` field to the SQS payload and let the Lambda route on it:

```python
REASON_ROUTING = {
    "no_patrols":    ("patrol_exit",   "TARGET_HOURS",               48),
    "site_disabled": ("site_disabled", "SITE_DISABLED_TARGET_HOURS", 336),
}
```

Each reason gets a bucket (namespaced DDB fields) and a tunable target hours. Adding a new reason = add a row in the map. No schema migration.

### Per-reason fields on the same DDB row

For a schedule-scoped Lambda, one row per schedule. Separate buckets by field prefix:
```
schedule_id                       (PK)
cadence_hours, admin_pk, ttl      (shared, schedule-level)
count, threshold, ...             (patrol_exit bucket — legacy names preserved)
count_site_disabled, ...          (site_disabled bucket)
```

Keep the first bucket's fields on their original names so existing rows keep incrementing without migration. New buckets use a suffix.

### Cadence-aware thresholds

`N = max(3, target_hours / cadence_hours)` is better than a fixed N. An hourly schedule needs ~48 emits to reach 48 hours; a daily schedule needs 3. Floor of 3 prevents a very-frequent schedule from tripping on its first noisy hour.

TTL = `max(threshold × cadence_hours × 2, 72h)` from last emit. Guarantees the counter window is wide enough to actually reach threshold, and long enough that a legitimate pause doesn't wipe state prematurely.

### Resolve metadata once, cache

Expensive lookups (cadence from Admin API, Immix tenant binding) happen on first sighting of a schedule. Cache on the DDB row:

```
admin_pk:    "597"
cadence_hours: "24.0"
```

Subsequent emits for the same key skip the lookup.

## Local testing

Lambda-as-deployed depends on cross-account Secrets Manager + per-region DDB + SQS. Local reproduction needs all of those. Three practical patterns:

### Pattern A — Token override in the Lambda

Hardcoded Secrets Manager calls in shared libs (e.g. `AdminApi.get_api_token` → `SecretManager.get_secret("prod/actuate/postgres")`) block local runs from a dev SSO session. Add an env-var override in your Lambda's wrapper:

```python
class AdminApiHandler(AdminApi):
    def __init__(self, stage, region):
        env_token = os.getenv("ADMIN_API_TOKEN")
        if env_token:
            self._override_token = env_token
        super().__init__(stage=stage)
        self.region = region

    def get_api_token(self):
        if getattr(self, "_override_token", None):
            return self._override_token
        return super().get_api_token()
```

Deployed Lambda still uses Secrets Manager (env var not set). Local invocation sets the env var after pulling with `aws --profile prod secretsmanager get-secret-value`.

### Pattern B — Fetch script + harness

Pair the override with a fetch script and a smoke-test harness:
- `scripts/fetch_local_test_env.sh` — pulls all needed secrets via `AWS_PROFILE=prod`, exports as env vars
- `scripts/local_smoke_test.py <key>` — synthesises an SQS event and invokes `lambda_handler` with `DRY_RUN=true`

Source one, run the other. Separates the privileged read (prod Secrets Manager) from the privileged write (dev DDB/SQS) cleanly.

### Pattern C — S3 is the source of truth for pod state

For signals emitted by a deployed pod, the physical `settings.json` in S3 is the practical source for fields admin API doesn't surface (tenant_id, subscription_id). When testing locally, pull from S3:

```python
s3.get_object(Bucket="actuate-settings", Key=f"connector-{cust}-autopatrol-{pk}/settings.json")
```

Avoids duplicating the admin API schema-extract logic in your test harness.

### Forced logging config

AWS Lambda's default logging works, but local invocation often inherits handlers from `botocore` / `requests` imported at the top of the module — `logging.basicConfig()` becomes a no-op. Force-clear root handlers at the top of `lambda_handler`:

```python
root = logging.getLogger()
for h in list(root.handlers):
    root.removeHandler(h)
logging.basicConfig(stream=sys.stdout, level=logging.INFO, format="...")
logging.getLogger().setLevel(logging.INFO)
```

Otherwise your local runs look mute while production logs fine.

## Library coupling

If the Lambda consumes a signal produced by code in a shared library (`actuate-pullers`, `actuate-integration-calls`, etc.), prefer **optional callbacks over direct SQS calls in the lib**:

```python
# In the library
class Puller:
    def __init__(self):
        self.on_init_error = None  # optional callback
    def init_stream(self):
        if res.status_code != 200:
            if self.on_init_error:
                try: self.on_init_error(error_class, status_code, text)
                except: pass
```

- Library stays free of AWS SDK dependencies
- Callers opt in explicitly — no surprise behavior for other consumers of the same library
- The consumer (your Lambda's upstream) wires up the callback with its own SQS client

For rollout: push the lib change on a feature branch → CI publishes a `dev` version (e.g. `1.17.12.dev1+feature.xxx`) → pin in the consumer's `pyproject.toml`. Before prod-bound merge, revert the pin to a stable version.

## Cross-repo rollout phasing

A Lambda that spans multiple repos (lib patch + connector emit + admin-api fields + Lambda code + terraform) needs explicit step phasing. **Never bundle the whole chain into one merge**. The pattern that worked:

1. **Admin-api** schema change first — migrations are backward-compatible; ship ahead of anything that depends on them
2. **Library** change second — publish a dev version to CodeArtifact; pin in the consumer
3. **Producer** (connector) change third — merged to stage branch; emit starts flowing into the SQS queue
4. **Consumer** (Lambda) change fourth — merged to master; code deploys dark (`ENABLED=false`)
5. **Infra** (terraform) — in parallel with 1-4; in dev/EU first
6. **Flip stage** `ENABLED=true`, bake 1+ weeks
7. **Prod rollout** US → EU with its own terraform PR + its own flip

Each step has its own PR, its own merge trigger, its own verification. Stop at any boundary.

## Per-repo deployment notes

### autopatrol_onboarder / similar Lambda-only repos

- **master auto-deploys prod** via `.github/workflows/deploy.yml` on push. Keep PRs in **draft** until stage bake completes.
- Multiple entry points in one repo: ship a single shared zip containing all `.py` files, deploy to each function by name. Use `|| echo skipped` guards on `aws lambda update-function-code` for functions not yet provisioned.

### actuate_admin

- PR target is `develop`, not `master`/`main`. Rebase cleanly before PR to avoid carrying unrelated WIP from earlier branches.
- Migration number collisions are a real risk — `develop` evolves fast. Renumber your migration one past `ls inframap/migrations/ | tail -1` right before pushing, and update its `dependencies` list.
- Local `makemigrations --check` hangs on Redis + AWS SSO startup. Trust the AST check + stage verification instead of running Django locally.

### ds-terraform-eks-v2

- Two-profile dance: `actuate-tf-state` profile for the state bucket (lives in `prod` account 388576304176), and `AWS_PROFILE=dev` or `prod` for the resources being provisioned. Add `actuate-tf-state` profile to `~/.aws/config` as documented in the repo README.
- Prod and dev use different Lambda patterns (`core-lambdas` module stanzas vs `lambdas` module map). Don't assume your dev/EU stanza mirrors to prod without checking.
- Known latent bugs in the module schema (per-table TTL missing in `modules/dynamodb`, `remote_bucket_name` vs `remote_state_bucket` mismatch in `core-lambdas`). If your plan is blocked by these, provision via CLI + let terraform adopt the existing resource later.

### actuate-libraries

- **Never push to `main`** without explicit ask — `main` push triggers stable publish. Feature branches get `dev` versions via `publish-dev.yaml`.
- Use commit-message semver tags: `[patch:actuate-pullers]`, `[minor:actuate-config]`, etc. — picked up by `bump-dev.yaml` to pick the next version.
- Pre-commit hooks (ruff-format) sometimes modify files post-commit. Look for "files were modified by this hook" in commit output; if seen, re-stage + re-commit.

## Anti-patterns to avoid

- **Fabricating IDs client-side** — if an external API expects a GUID that only their backend knows (e.g. `streamId` from Immix), never generate a UUID to get past a 400. The backend will record it silently or fail on foreign-key checks. See [[2026-04-20_streamid-null-patrol-alert-bug]] for the disaster mode.
- **Fetching everything every run** — bulk "fetch all rows + sync all" jobs scale O(n) and one flaky upstream response corrupts everything. Prefer event-driven per-entity signals. See [[2026-04-17_autopatrol-sync-endpoint-behavior]] for why the onboarder's old sync approach was misaimed.
- **Merging the whole rollout chain in one PR** — forces rollback of everything if any piece has an issue. Each step = own PR = own revert granularity.
- **Running `manage.py makemigrations` locally for a quick check** — in practice it hangs on Redis/SSO. The syntax + AST check gives you 80% of the confidence, and stage apply is the real test.

## Related

- [[2026-04-17_stale-schedule-cleanup-design]] — the full design this playbook was distilled from
- [[2026-04-17_local-testing-strategies-per-repo]] — per-repo local testing ceiling
- [[2026-04-20_streamid-null-patrol-alert-bug]] — fabricated-UUID anti-pattern write-up
- [[autopatrol-onboarder]] — sibling Lambda that drove many of these conventions
- [[autopatrol-cleanup-lambda]] — the Lambda this playbook came out of
