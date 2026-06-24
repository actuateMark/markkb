---
title: "actuate_admin release flow — feature → staging → main"
type: concept
topic: admin-api
tags: [release, branching, ci, pr-flow, staging, main, gotcha]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
outgoing:
  - topics/admin-api/_summary.md
  - topics/admin-api/notes/syntheses/2026-04-30_autopatrol-state-audit.md
  - topics/personal-notes/notes/daily/2026-05-01.md
incoming:
  - topics/admin-api/_summary.md
  - topics/admin-api/notes/syntheses/2026-04-30_autopatrol-state-audit.md
  - topics/offboarding/notes/concepts/2026-06-23_local-repo-audit.md
incoming_updated: 2026-06-24
---

# actuate_admin release flow — feature → staging → main

> **TL;DR:** `actuate_admin` uses a **release-train** branching model. Feature PRs target `staging`, **never** `main`. A CI workflow (`Protect Main Branch`) hard-rejects any PR to `main` whose head isn't `staging` itself. Then `staging` → `main` is opened periodically as the release-train PR (recent example: [PR #2385 v2.7.2](https://github.com/aegissystems/actuate_admin/pull/2385) — "AutoPatrol cascade-reenable + swagger/wireguard/migrations").

## The branches

| Branch | Role |
|---|---|
| `main` | Production. Each merge here is a tagged release. CD fans out to ECS. |
| `staging` | Pre-production integration. All feature PRs target this. CI runs full test suite + builds; `staging.actuateui.net` deploys from here. |
| `feat/<slug>` | Feature branches. PR target = `staging`. |
| `fix/<slug>` | Bug-fix branches. PR target = `staging`. |

## The CI gate

The workflow at `.github/workflows/protect-main.yml` is the gate. It triggers on `pull_request: branches: [main], types: [opened, reopened]` and runs `Verify PR is from staging`. It only succeeds when the PR's head branch is `staging` itself or a `hotfix/*` branch. Any other head fails immediately (4-second-fail) and cannot merge to `main`.

Note the trigger: `opened, reopened` — **not** `synchronize` or `edited`. So if you open a PR against `main` and then change the base to `staging`, the original failed check stays in the PR's history as a stale "fail" entry but is no longer relevant. To get a clean check list, close + reopen the PR with the right base.

## What CI runs on a PR to `staging`?

Currently: nothing. There are no `pull_request` triggers in `.github/workflows/` that target `staging`. The full test suite (`Sonar` / `python-test`) runs only on push, and only for these branches:

| Trigger | Workflow |
|---|---|
| push to `develop` | `develop.yml` (Dev CI) |
| push to `staging` | `staging.yml` (Staging CI) |
| push to `main` | `main.yml` (Deploy to ECR) |
| push to `container` | `container.yml` (Deploy to ECR alt path) |

So a PR to `staging` shows no CI status and is mergeable on review alone. The full test suite then runs **after** merge, on the push to `staging`. If tests fail post-merge, you fix forward with another PR — there's no pre-merge test gate at the staging tier. Be aware of this when reviewing — local-tested code is the floor, post-merge `Staging CI` is the catch-net.

The `staging → main` release-train PR is the only one where the `Verify PR is from staging` gate fires.

## The right `gh pr create` invocation

```bash
gh pr create --base staging --title "..." --body "..."
```

If you forget `--base staging`, GitHub defaults to `main` (the repo's default branch) and CI rejects the PR within seconds. Either retarget via `gh pr edit <num> --base staging` or close the PR and reopen with the right base.

## Other Actuate repos for comparison

| Repo | Default branch | Stage-first flow? |
|---|---|---|
| `actuate_admin` | `main` | **Yes** — feature → `staging` → `main` |
| `vms-connector` | `master` | feature → `master` → tagged-release branches feed `stage` and `rearchitecture` |
| `actuate-libraries` | `main` | feature → `main` (auto-publishes stable to CodeArtifact on merge) |
| `autopatrol_onboarder` | `master` | feature → `master` (CI auto-deploys US + EU prod) |
| `actuate-inference-api` | varies per service | mostly feature → main with CI-driven deploys |

Only `actuate_admin` enforces the stage-first gate at CI level. Other repos either deploy direct from main/master or use environment-tagged release branches.

## Gotcha — 2026-04-30 case study

When opening the audit-state mgmt command PR (now #[2389](https://github.com/aegissystems/actuate_admin/pull/2389), originally [#2388](https://github.com/aegissystems/actuate_admin/pull/2388)), there were **two compounding mistakes**:

1. **Base was `main` instead of `staging`** — failed `Verify PR is from staging` within 4 seconds. Retargeting the base to `staging` via API (`gh api -X PATCH repos/.../pulls/2388 -f base=staging`) cleared that gate.

2. **The branch was based off `origin/main`, not `origin/staging`** — even after retargeting, the PR diff included 13 unrelated files (the entire v2.7.2 release-train delta), because `main` is ahead of `staging` by commit `a265bfdf` (the squash-merge of release-train PR #2385). PR-ing a main-based branch to `staging` pulls in everything in that delta. The fix: close the old PR, branch fresh off `origin/staging`, cherry-pick the single commit, push, open a new PR.

**Future-self lessons:**

- **Never use `--base main` on [[actuate_admin]].** Always `--base staging` for feature work.
- **Always branch off `origin/staging`, not `origin/main`.** Because `main` is "ahead" of `staging` immediately after a release-train merge (until staging gets manually fast-forwarded, which doesn't appear to happen automatically), branching off main and PR-ing to staging shows a polluted diff.
- The "right" sequence:
  ```bash
  git fetch origin staging
  git checkout -b feat/<slug> origin/staging
  # ... work ...
  git push -u origin feat/<slug>
  gh pr create --base staging --title "..." --body "..."
  ```
- If you mess this up: closing + reopening with a fresh staging-based branch is cleaner than retargeting + force-pushing.

## Cross-references

- [[2026-04-30_data-model-cascade-semantics]] — admin data model context for recent PRs
- [[2026-04-30_autopatrol-state-audit]] — synthesis pointing to PR #2388
- `.github/workflows/main.yml` in [[actuate_admin]] — the workflow that enforces the gate
