---
title: "Connector & Library Deployment Lifecycle"
type: synthesis
topic: engineering-process
tags: [process, deployment, vms-connector, actuate-libraries, stage, release, monitoring]
jira: "ENG-106, ENG-107, ENG-93, ENG-95"
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# Connector & Library Deployment Lifecycle

The end-to-end process for shipping a [[vms-connector]] feature that involves [[actuate-libraries]] changes — from library development through production release. Derived from the s3alerts/patrol-mode release (PR #1639, April 2026).

This is the **connector-specific deployment lifecycle** — a concrete specialization of the general [[feature-development-lifecycle]]. Where that doc covers planning, implementation, and review, this one focuses on the multi-repo deployment coordination that makes connector releases uniquely complex.

---

## Why This Is Different

The vms-connector is not a standalone application. It consumes 30+ packages from [[actuate-libraries]], each published independently to AWS CodeArtifact. A connector feature that touches library code must coordinate:

- Two git repos with independent CI pipelines
- Dev → stable version promotion in CodeArtifact
- Dependency pin updates in the connector
- Docker image builds for 2+ architectures
- Kubernetes deployment rollout across staging and production fleets
- [[new-relic|New Relic]] monitoring across multiple site deployments

Skipping or reordering steps causes real failures: broken stable publishes, dev pins reaching production, merge conflicts from stale branches, or silent regressions in the fleet.

---

## Phase 1: Library Development

### 1.1 Feature Branch in actuate-libraries

```
cd ~/work/actuate-libraries
git checkout -b feature/my-feature
# make changes across one or more packages
git push origin feature/my-feature
```

CI automatically publishes dev versions to CodeArtifact (e.g., `actuate-config==1.10.0.dev1+feature.my.feature`). The version suffix encodes the branch name.

### 1.2 Pin Dev Version in vms-connector

```toml
# pyproject.toml — ALWAYS include the full +branch local segment
"actuate-config==1.10.0.dev1+feature.my.feature",  # CORRECT
"actuate-config==1.10.0.dev1",                       # WRONG — ambiguous
```

Run `uv lock` (with CodeArtifact auth if needed), commit both `pyproject.toml` and `uv.lock`.

### 1.3 Validate on Stage Fleet

Dev pins are allowed on `stage`. Deploy the connector branch to staging sites and validate:
- Factory initialization succeeds
- No new ERROR patterns in [[new-relic|New Relic]]
- Feature works end-to-end (e.g., patrol runs complete, alerts fire)
- Memory and performance are stable

**This is the library's real validation.** Unit tests in the library repo catch API-level bugs. Stage deployment catches integration issues, config parsing edge cases, and performance regressions that only manifest under real workloads.

---

## Phase 2: Pre-Merge Stabilization

**This phase is mandatory. The order is non-negotiable: libraries first, then connector.**

See: `/pre-merge-workflow` skill in vms-connector.

### 2.1 Merge Library PR to Main

Once stage validation passes, merge the library PR to `actuate-libraries` main.

**Known issue — GitHub API merge token:** `gh pr merge` uses the default GITHUB_TOKEN, which does NOT trigger further CI workflows. If CI doesn't fire after the merge, push an empty commit:

```bash
git checkout main && git pull
git commit --allow-empty -m "chore: trigger CI for stable version publish"
git push origin main
```

### 2.2 Wait for Stable Version Publish

The `Publish Stable` workflow:
1. Runs `bump-version-stable.sh` — strips dev suffix, promotes to stable
2. Runs `publish-base.yaml` — builds and publishes to CodeArtifact (x86 + arm64)
3. Commits `[no ci] Bump stable versions for: <libs>` and pushes

**Known issue — JSON quoting bug:** The `bump-version-stable.sh` script has a `jq`/`xargs` quoting bug when `[patch]`/`[minor]` tags are in the commit message. Workaround: manually bump versions:

```bash
git checkout main && git pull
uv version --package actuate-config --frozen 1.9.12  # strip dev suffix
just lock
git add */pyproject.toml uv.lock
git commit -m "[no ci] Bump stable versions for: actuate-config,actuate-daos"
git push origin main
# Then push an empty commit to trigger publish
git commit --allow-empty -m "chore: publish stable library versions"
git push origin main
```

Monitor the publish run:
```bash
gh run list -R aegissystems/actuate-libraries --branch main --limit 3
gh run watch <RUN_ID> -R aegissystems/actuate-libraries
```

### 2.3 Update Connector to Stable Pins

```bash
cd ~/work/vms-connector
# Edit pyproject.toml — replace dev pins with stable versions
uv lock  # with CodeArtifact auth
uv run pytest test_vms/  # verify tests pass
git add pyproject.toml uv.lock
git commit -m "chore: bump actuate-config to X.Y.Z and actuate-daos to A.B.C (stable)"
git push origin <branch>
```

**Version number may change:** The dev version (e.g., `1.10.0.dev1`) from a feature branch may promote to a different stable version (e.g., `1.9.12`) because the s3alerts branch rebased the version series. Always check the actual stable version on main after CI publishes.

---

## Phase 3: PR Cleanup and Merge to Stage

### 3.1 Resolve Merge Conflicts

If `stage` has advanced since the feature branch was created, merge conflicts are likely. Always resolve these before anything else.

```bash
git fetch origin stage
git merge origin/stage
# resolve conflicts, commit
git push origin <branch>
```

### 3.2 Clean the PR

Before merging, verify:
- [ ] No dev pins in `pyproject.toml` (`grep dev pyproject.toml | grep actuate`)
- [ ] No debug artifacts (temp workflows, test scripts, `breakpoint()`)
- [ ] No unaddressed bot/review comments
- [ ] CI checks passing (tests, uv.lock diff)
- [ ] PR is MERGEABLE (no conflicts)

### 3.3 Merge Feature → Stage

```bash
gh pr merge <PR_NUMBER> --merge --subject "<title> (#<PR_NUMBER>)"
```

Use `--merge` (not `--squash`) for feature → stage. Stage retains full commit history for debugging.

---

## Phase 4: Stage Deployment Monitoring

### 4.1 ECR Image Build

The merge to `stage` triggers `Deploy to ECR Rearchitecture Stage`:
- Builds ARM64 + x86 Docker images
- Pushes to ECR
- Notifies Slack on completion

Monitor:
```bash
gh run list -R aegissystems/vms-connector --branch stage --limit 5
gh run watch <RUN_ID> -R aegissystems/vms-connector
```

**Note:** Only the ECR deploy workflow triggers on stage push. Tests, changelog, and diff-uv-lock only run on PRs, not on direct pushes to stage.

### 4.2 New Relic Monitoring

After images build, staging fleet deployments pull the new image. Monitor via NR (account `3421145`, cluster `Connector-EKS`):

**Staging connectors** (these pull the stage image):
```sql
-- Zero errors expected
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'staging-connector%'
  AND level = 'ERROR'
SINCE 30 minutes ago
FACET container_name, message LIMIT 20
```

**Production autopatrol sites** (running on rearchitecture image until promoted):
```sql
-- Check error trends — should not increase after merge
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND (container_name LIKE '%35831%' OR container_name LIKE '%35832%')
  AND level = 'ERROR'
SINCE 30 minutes ago
FACET message LIMIT 10
```

**Patrol run health** (task results should show complete data):
```sql
SELECT message FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%35831%'
  AND message LIKE '%task results%'
SINCE 30 minutes ago LIMIT 10
```

### 4.3 Monitoring Cadence

| Time after merge | Check | Expected |
|---|---|---|
| 0–5 min | ECR build triggered | Workflow queued |
| 5–15 min | ECR build complete | ARM64 + x86 success |
| 15–30 min | Staging connectors | Running, 0 errors |
| 30–60 min | Patrol runs | Task results flowing |
| 1–12 hours | Overnight soak | Error rate flat or declining |

---

## Phase 5: Stage → Rearchitecture Release

Once stage is validated (typically after overnight soak):

### 5.1 Pre-Release Checks

- [ ] No dev pins anywhere (`grep dev pyproject.toml | grep actuate`)
- [ ] CHANGELOG.md updated
- [ ] Library changes report (`.github/LIBRARY_CHANGES_*.md`) is clean
- [ ] All related Jira tickets updated

### 5.2 Create Release PR

```bash
gh pr create --base rearchitecture --head stage \
  --title "Release: <summary>" \
  --body "## Summary\n- <changes>\n\n## Validation\n- <stage results>"
```

Use **squash merge** for stage → rearchitecture. This keeps rearchitecture's history clean — each merge is one commit traceable to a PR.

### 5.3 Post-Release Monitoring

Same NR queries as Phase 4, but now watching for the production fleet to pick up the new image. Error rates should drop (e.g., the `NoneType shape` errors on 35831 should disappear with the new image).

---

## Phase 6: Jira Cleanup

After each phase gate, update related Jira tickets:
- Move to **Done** when the code is merged to stage
- Add a comment with: PR number, merge date, what shipped, validation results
- Close superseded tickets (e.g., if a hotfix ticket is resolved by the feature PR)

---

## Applying This to Future Projects

This lifecycle was derived from the s3alerts/patrol-mode release but is designed to generalize. Any connector feature that touches library code will follow the same phases. When adapting:

- **Phase 1** applies whenever you have dev pins in `pyproject.toml` — regardless of which libraries or how many
- **Phase 2** applies whenever library PRs need to become stable before the connector can merge — the CI workarounds are systemic, not release-specific
- **Phase 3** applies to every PR merge — debug artifacts and merge conflicts are recurring themes
- **Phase 4** monitoring queries work for any release — just change the `container_name` filter and the log patterns to watch for
- **Phase 5** (stage → rearchitecture) applies identically to every release

The NR queries, CI workarounds, and anti-patterns below are **not specific to this release** — they are structural properties of the actuate-libraries CI pipeline and the Connector-EKS deployment model.

## Anti-Patterns (Learned the Hard Way)

| Anti-pattern | What happens | Correct approach |
|---|---|---|
| Merge connector PR with dev pins | Dev pins break on rearchitecture; CI should block but verify | Always run `/pre-merge-workflow` — libraries first |
| Skip stage validation, merge library straight to main | Broken stable version published to CodeArtifact; can't yank | Validate on stage fleet with dev pins first |
| `gh pr merge` and assume CI fires | GitHub API token doesn't trigger workflows | Check for CI run; push empty commit if needed |
| Use `[patch]` tag in squash merge commit | `bump-version-stable.sh` JSON quoting bug crashes CI | Manually bump versions with `uv version`, commit with `[no ci]` |
| Squash merge feature → stage | Lose commit history needed for debugging | Use `--merge` for feature → stage; `--squash` only for stage → rearchitecture |
| Merge to stage without resolving conflicts | PR stays CONFLICTING, blocks deployment | Always resolve merge conflicts first — before anything else |

---

## Quick Reference: Command Sequence

```bash
# 1. Library: merge to main, get stable versions
gh pr merge <LIB_PR> --squash -R aegissystems/actuate-libraries
# wait for CI... if no run, push empty commit to trigger
# if bump script fails, manually version + push

# 2. Connector: update pins
cd ~/work/vms-connector
# edit pyproject.toml with stable versions
uv lock && uv run pytest test_vms/ && git add pyproject.toml uv.lock && git commit

# 3. Connector: clean and merge to stage
git fetch origin stage && git merge origin/stage  # resolve conflicts
# remove debug artifacts, verify no dev pins
git push origin <branch>
gh pr merge <CONN_PR> --merge

# 4. Monitor
gh run watch <ECR_RUN_ID>  # ECR build
# NR queries for staging-connector-* errors
# NR queries for production patrol task results

# 5. Update Jira
# transition tickets to Done, add PR reference comments
```

---

## Related Documents

- [[feature-development-lifecycle]] — general lifecycle (planning through review)
- [[dev-workflow]] — library promotion pipeline concept
- [[library-connector-dependency-map]] — which libraries affect which pipeline stages
- [[pipeline-architecture]] — frame processing pipeline internals
- `/pre-merge-workflow` skill — automated pre-merge checklist
- `/stage-release` skill — stage merge + monitoring automation
