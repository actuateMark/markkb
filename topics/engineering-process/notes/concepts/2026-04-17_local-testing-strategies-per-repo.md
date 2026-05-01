---
title: "Local Testing Strategies Per Repo"
type: concept
topic: engineering-process
tags: [testing, local-dev, validation, actuate_admin, vms-connector, ds-terraform-eks-v2, autopatrol_onboarder, lambda]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
---

# Local Testing Strategies Per Repo

What you can actually check locally before pushing to stage, what requires a full [[dev-environment|dev environment]], and what you have to wait for the stage deploy to verify. Captured while making cross-repo changes (AutoPatrol stale-schedule cleanup) — applies to similar cross-repo work.

Rule of thumb: **syntax + format checks work everywhere; deeper validation needs the full environment**. Don't over-invest in clever local integration setups that the team doesn't already maintain.

## By repo

### `autopatrol_onboarder` — AWS Lambda, Python 3.12+, uv

- **Syntax:** `python3 -m py_compile lambda_function.py` — works anywhere. Fast, catches imports and parse errors.
- **Full dry run:** `DRY_RUN=true python3 lambda_function.py` — needs `AUTOPATROL_API_KEY`, AWS creds for Secrets Manager, and network to Immix. Not a quick local loop; usually faster to verify on the dev Lambda after a deploy.
- **What stage will tell you that local won't:** everything network-dependent (Immix response shape, admin API accept/reject, real contract data).

### `vms-connector` — Python 3.12+, uv, runs in K8s cronjob pod

- **Syntax:** `python3 -m py_compile <file>.py` — works anywhere. Imports may fail if you don't activate the venv first (`source .venv/bin/activate` or use `.venv/bin/python`) because `actuate_config`, `actuate_integration_calls`, `actuate_daos`, and friends are all private CodeArtifact packages.
- **Unit tests:** the repo ships unit tests under `connector_factories/tests/` and similar — run inside the venv. Fast enough for a local iteration.
- **End-to-end factory behavior:** the factories call live APIs, consume settings from S3, and wire up SQS + DDB DAOs. Not runnable standalone — only meaningful inside a pod with a full `settings.json`. Verify on stage.
- **What stage will tell you that local won't:** whether the emit actually fires at the right exit sites, whether SQS send succeeds, whether the payload matches the consumer's schema.

### `actuate_admin` — Django 6, Python 3.12, uv + `.venv/`

- **Syntax:** `.venv/bin/python -m py_compile <file>.py` — works anywhere.
- **Migration integrity:** `.venv/bin/python manage.py makemigrations --dry-run --check` would tell you if the model is missing a migration, **but** it tries to connect to Redis + AWS SSO on startup. Expect a 60s+ hang unless the [[dev-environment|dev environment]] is already up. Workaround: trust the AST check + visually verify the migration matches the model; run the real check on stage/CI.
- **Migration number collisions** — develop evolves, your local migration number will collide. Before pushing a PR: `ls inframap/migrations/ | tail -5` on `origin/develop` and renumber your migration one past the highest existing number. Also update its `dependencies` list to point at the actual latest migration, not whatever it was when you first wrote it. Django won't warn — the conflict shows up as "InconsistentMigrationHistory" in CI or at apply time.
- **PR target is `develop`, not `master`** — [[actuate_admin]] has `develop` as the integration branch. Rebase feature branches onto `develop`, not master/main (which may not exist or may be stale).
- **Unit tests:** `api/tests/test_autopatrol*.py` exist for the autopatrol surface. Also need Redis + DB to run — not a quick local gate.
- **What stage will tell you that local won't:** whether the migration applies cleanly, whether the serializer accepts new fields via the API, whether filters actually return the expected subset.

### `ds-terraform-eks-v2` — Terragrunt + Terraform, stages/ per region × env

- **HCL format:** `terragrunt hcl format --check` in the stage dir — pure syntax, no AWS. Fast and reliable. Use this.
- **HCL validate:** `terragrunt hcl validate` — fails on legitimate stage files because it doesn't expand `include.locals.stage`. Not useful for per-stage checks.
- **Rendered inputs:** `terragrunt render --format json` — shows what values terragrunt actually passes to terraform. Crucial when debugging "why isn't my change in the plan". No AWS calls, fast.
- **Terraform plan:** `AWS_PROFILE=<env> terragrunt plan` — needs AWS creds for both the `actuate-tf-state` profile (state bucket in `prod` account) AND the provisioning profile (`dev`/`prod` for the resource's account). Use `AWS_PROFILE=dev` for dev/eu-west-1, `AWS_PROFILE=prod` for prod stages.
- **Pre-existing state drift is common.** The plan will show changes you didn't cause — `authorization-v2` orphan, in-place updates on unrelated queues, required variables that aren't set on modules you didn't touch. Filter for your specific resource name to confirm YOUR change is correct; don't get distracted by the rest.
- **Required setup:**
  - `~/.aws/config` must include `[profile actuate-tf-state]` for state access (README documents this, account ID is 388576304176 / AdministratorAccess via SSO session `actuate`). Not set by default.
  - `uv.toml` CodeArtifact token stale → MCP tools using `uvx` (AWS MCP via `mcp-proxy-for-aws`) will fail with 401. Fix with: `TOKEN=$(aws codeartifact get-authorization-token --domain actuate --domain-owner 388576304176 --query authorizationToken --output text --profile prod)` and regenerate `~/.config/uv/uv.toml`.
- **What stage-apply will tell you that local won't:** whether IAM policies are attached correctly, whether Lambda module variables resolve against the real source, whether resource dependencies plan without conflict.
- **Gotchas found 2026-04-17:**
  - Dev/EU `core-lambdas` stage has a variable passthrough mismatch (`remote_bucket_name` in stage file vs `remote_state_bucket` in module) — `terragrunt plan` fails before it can see your changes. Pre-existing; separate from any new module stanza.
  - Dev/EU `dynamodb` stage: rendered inputs contain new table entries correctly, but `plan` reports "0 to add" — this suggests the `object(...)` type on `var.tables` is silently dropping entries with extra unknown fields (e.g. `use_pay_per_request` isn't in the module schema), or there's an apply-then-revert drift. Investigate before merging any DDB change.

- **CLI provisioning as a terraform workaround** (2026-04-20): when the terragrunt plan path is blocked by the bugs above but you need the resource NOW for stage bake, provision via CLI then let terraform idempotently adopt it later:
  ```bash
  # SQS FIFO + DLQ
  aws sqs create-queue --queue-name <name>.fifo --attributes '{...}' --region eu-west-1
  # DDB table + TTL
  aws dynamodb create-table --table-name <name> --key-schema ... --billing-mode PAY_PER_REQUEST --region eu-west-1
  aws dynamodb update-time-to-live --table-name <name> --time-to-live-specification "Enabled=true, AttributeName=ttl" --region eu-west-1
  ```
  Note TTL needs a wait-table-exists first. Once the module bugs are fixed, `terragrunt apply` will see the existing resource and not recreate.

- **Two-profile reality** — terragrunt state lives in `prod` account (388576304176), provisioning targets `dev` account (558106312574). So `terragrunt plan` with `AWS_PROFILE=prod` errors with "AccessDenied" for dev-account resources, and `AWS_PROFILE=dev` errors on the state backend unless you have the `actuate-tf-state` profile (points at prod via SSO). Minimum setup: `[profile actuate-tf-state]` added to `~/.aws/config` pointing at prod SSO, then `AWS_PROFILE=dev terragrunt plan` works. Note the backend's `profile = "actuate-tf-state"` is hardcoded in `stages/root.hcl`.

### `actuate-libraries` — uv monorepo, 41 packages

- Covered by KB note series in `actuate-libraries/notes/` — this note doesn't duplicate that.
- TL;DR: `just test` + `just lint` at package level. Type check via `just check-types`.

## What to do when local can't validate

When the local ceiling is "syntax checks pass," shipping to stage *is* the test. Keep the stage blast radius small:

1. Feature flags on every new emit/path (`AUTOPATROL_EMIT_CLEANUP_SIGNALS`, `CLEANUP_ENABLED` — both default `false`). Ship code dark, flip on after observing.
2. `DRY_RUN` gates on write operations. Stage run with `DRY_RUN=true` to see what would happen without side effects.
3. Small, focused PRs so the stage diff is reviewable.
4. Put CloudWatch / NR queries into the PR description so reviewers can find evidence of the change working post-deploy.

## Commands I actually ran today

| Check | Command | Result | Meaningful? |
|---|---|---|---|
| Onboarder syntax | `python3 -m py_compile lambda_function.py` | pass | yes — catches basic errors |
| Connector syntax | `python3 -m py_compile cleanup_emitter.py autopatrol_factory.py vch_factory.py` | pass | yes |
| Admin syntax | `python3 -m py_compile autopatrol_schedule_model.py ... serializer.py ... view.py migrations/0539_*.py` | pass | yes |
| Terragrunt hcl format | `terragrunt hcl format --check` in sqs_queue/ dynamodb/ core-lambdas/ | pass | yes — catches hcl syntax |
| Terragrunt hcl validate | `terragrunt hcl validate` | fails on include.locals.stage | no — pre-existing pattern breaks this |
| Django `makemigrations --check` | `.venv/bin/python manage.py makemigrations --dry-run --check` | timed out at 60s (Redis/SSO) | no — needs full dev env |

## Related

- [[feature-development-lifecycle]] — where local testing fits in the PR flow
- [[autopatrol-onboarder]] / [[autopatrol-cleanup-lambda]] — Lambdas whose stage deploy IS the integration test
- [[agent-release-chain-watcher]] — post-deploy verification pattern
- Skills: `/validate-release`, `/stage-release`, `/post-deploy-monitor`
