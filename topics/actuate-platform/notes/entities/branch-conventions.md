---
title: Branch & PR Conventions per Repo
type: entity
topic: actuate-platform
tags: [repos, github, branches, pull-requests, conventions, vms-connector]
created: 2026-05-20
updated: 2026-05-27
author: kb-bot
incoming:
  - topics/admin-api/notes/entities/admin-api-auth.md
  - topics/autopatrol/notes/entities/autopatrol-server-deployment.md
  - topics/engineering-process/notes/syntheses/2026-05-20_local-ap-e2e-test-stack-plan.md
  - topics/local-test-stack/_summary.md
  - topics/local-test-stack/notes/syntheses/2026-05-20_local-ap-e2e-stack-installed.md
  - topics/personal-notes/notes/concepts/2026-05-28_session-handoff.md
  - topics/personal-notes/notes/daily/2026-05-21.md
  - topics/personal-notes/notes/daily/2026-05-27.md
  - topics/vms-connector/notes/syntheses/2026-05-28_per-frame-log-volume-stage-vs-rearch.md
incoming_updated: 2026-05-29
---

# Branch & PR Conventions per Repo

Canonical table of branch conventions for every Aegis/Actuate repo Claude is likely to touch. **Before creating a branch, opening a PR, or merging in a repo not listed here, ASK the user** for the missing details and add a row before proceeding. See [[feedback-check-branch-conventions]] for the enforcement rule.

Columns:

- **Default branch** — the `origin/HEAD` / what `git pull` lands on for a fresh clone.
- **Feature-branch base** — where a new feature branch should branch FROM. Often the default; sometimes not (e.g. vms-connector).
- **PR target** — where feature branches PR INTO. Often the default; sometimes not.
- **Merge style** — squash / merge-commit / direct-push. With any CI / commit-tag implications.
- **Notes** — gotchas, auto-publish behavior, CI-skip-token sensitivity, etc.

## Table

| Repo | Default branch | Feature branch base | PR target | Merge style | Notes |
|---|---|---|---|---|---|
| **vms-connector** | `rearchitecture` | `stage` | `stage` | Squash on stage→rearch; individual commits OK to stage. | Feature branches **PR to stage, NOT rearchitecture** (recurring mistake — see [[feedback-feature-branches-target-stage]]). Stage→rearch is direct (no overlay branch — see [[feedback-stage-rearch-overlay-branch]]). Squash subject/body must NOT contain CI-skip tokens (see [[feedback-ci-skip-tokens-anywhere]]). |
| **actuate-libraries** | `main` | `main` for stable patches; feature branch for dev-version testing | `main` | Direct commits to `main` for stable patches with `[patch:lib]` / `[minor:lib]` / `[major:lib]` tag in commit message → CI auto-publishes. PRs squash-merge with the same tag preserved in the squash subject. | **Never push to main without explicit user OK** — auto-publishes to CodeArtifact. Squash body must be stripped of dev-bump bot's CI-skip tokens (recurring incident — see [[feedback-library-no-dev-versions]]). Never manually edit `version =` in pyproject.toml — CI bumps from commit tag (see [[feedback-library-version-field-ci-managed]]). |
| **autopatrol-server** | `main` | `main` | `main` | Squash via gh PR merge. | No `stage` branch; small repo. Tagged versions live as commits like `bump to 0.1.25` after merge. |
| **autopatrol_onboarder** | `master` | `master` | `master` | Squash to master. | Lambda repo. **Push to `master` AUTO-DEPLOYS the prod Lambda** via `.github/workflows/deploy.yml` (`on: push: branches: [master]`) — every merge to master is a prod deploy. Manual deploy scripts also exist (`deploy_prod.sh`, `deploy_prod_eu.sh`, `deploy_cleanup.sh`, `deploy_reenable.sh`). Default branch is `master` (not `main`). Confirmed 2026-06-17 merging PRs #14/#15/#16. |
| **[[dev-environment]]** | `simple` | — | — | — | **Effectively abandoned.** Last touched Jan 2025; user doesn't recall it as an active repo. Don't add new tooling here — prefer a fresh local folder or new repo. Default branch is `simple` (not `main`), 4 PRs ever. |
| **connector_deployer** | `main` | `main` | `main` | unknown — ask | FastAPI service. |
| **[[actuate_admin]]** | `main` (= **PROD**) | `staging` | `staging` | unknown — ask | Django config backbone. **`main` IS production** (merge → prod deploy). Feature work goes to **`staging`** (confirmed 2026-06-11, e.g. admin PR #2506). NOTE: there is **no `stage` branch — it's `staging`**; many stale `develop-*`/dated branches exist, ignore them. **Never push without asking + never edit existing migration files** (a *new* RemoveField/AddField migration is fine, but generate via `makemigrations` and confirm the dependency = current `staging` migration tip, which is ahead of `main`). See [[feedback-admin-repo-rules]]. |
| **queue_consumer** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | SQS alert delivery. |
| **[[kubernetes-deployments]]** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | [[argocd|ArgoCD]] Helm charts. Deploy implications of any merge. |
| **[[ds-terraform-eks-v2]]** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | Terraform — IAM, SQS, DDB. AutoPatrol Lambda infra. |
| **camera-ui** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | React SPA. |
| **[[alertviewer]]** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | Alert viewer. |
| **[[alert-ui]]** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | Vue 3 alert dashboard. |
| **[[ds-server-container]]** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | Rust YOLO inference server. |
| **actuate-inference-api** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | External detection API. |
| **actuate-monitoring-api** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | Read-only dashboards. |
| **[[actuate-external-api-repo|actuate-external-api]]** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | Partner API proxy. |
| **actuate-ailink** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | WebSocket server. |
| **health_report** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | CHM email Lambda. |
| **watchman** | unknown — ask | unknown — ask | unknown — ask | unknown — ask | Greenfield agentic AI. |

## Rule for unfamiliar repos

When you (Claude) start work in a repo not listed here, or whose row is marked `unknown — ask`:

1. **Stop** before creating a branch or PR.
2. **Ask the user** for the four fields (default branch, feature-branch base, PR target, merge style).
3. **Add a row** to this file with the answers, plus any gotchas mentioned.
4. **Then proceed.**

Even cheap reconnaissance is allowed (e.g. `git branch --show-current`, `git branch -r`, `gh pr list`) to inform the question — but **don't infer-and-commit**. The vms-connector "feature branches target stage" trap is a recurring example of inferring wrong from a `git status` snapshot.

## vms-connector: branch → ECR image → deployment fleet

**This is the section that prevents the "merged to rearchitecture = pre-prod / not in prod" mistake** (made + corrected-wrongly 2026-05-27 — see [[feedback-rearch-is-a-prod-fleet]]). Branches are NOT a single linear `dev → stage → prod` chain. There are **two parallel production fleets** fed by two ECR repos, plus a per-customer override axis. Verified from the workflow files 2026-05-27.

| Branch | Workflow | ECR repo:tag | Fleet it deploys to | Prod? |
|---|---|---|---|---|
| `master` | `master.yml` "Deploy to ECR" | `arm_connector:latest` | **Legacy prod fleet** | **YES** (legacy architecture) |
| `rearchitecture` (default branch) | `rearch.yml` "Deploy to ECR Rearchitecture" | `arm_connector_rearch:latest` | **Rearchitecture prod fleet** | **YES** (new architecture) |
| `stage` | `stage.yml` "Deploy to ECR Rearchitecture Stage" | `arm_connector_rearch:stage` | Rearch **staging** fleet (Actuate-owned test sites) | no |
| `rearch-dev` | `rearch_dev.yml` "Deploy to ECR Rearchitecture-dev" | `arm_connector_rearch:rearch-dev` | Rearch **dev** fleet | no |
| `develop` | `develop.yml` "Deploy to ECR Dev" | (dev image) | Dev | no |
| *any other branch* (feature/PR branches) | `custom.yml` "Deploy to ECR Rearchitecture Custom" | `arm_connector_rearch:<sanitized-branch-name>` | **Nothing by default** — image just sits in ECR until a customer is explicitly pinned to that tag | n/a |

### The two axes (the thing that gets confused)

1. **Fleet-wide promotion axis** (`stage → rearchitecture`): merging `stage → rearchitecture` builds `arm_connector_rearch:latest`, which the **entire rearchitecture production fleet** pulls. **This IS a production deploy** — it reaches every customer on the rearch fleet. It is not "pre-prod." The promotion ladder within the rearch repo is `rearch-dev → stage → rearchitecture(=latest)`; `latest` is the promoted/live prod state. (Legacy customers still on the `master`/`arm_connector` fleet are NOT reached by a rearchitecture merge — a change for them needs a `master` path too.)

2. **Per-customer custom-branch axis** (§29 deploy-branch): `custom.yml` builds `arm_connector_rearch:<branch-name>` for *any* non-mainline branch push (e.g. `featurepyav-17-bump-clean`). That image deploys to **nobody** until an operator pins a specific customer to it via admin's `POST /api/customers/{id}/deploy_branch/` (sets `deployment_phase=CUSTOM` + `connector_version`). This is the "branches we tag different images with" mechanism — orthogonal to the fleet-wide promotion. Reverting (`revert_branch`) flips the customer back to its prior phase (→ back onto the fleet-wide image). Full lifecycle: [[2026-05-20_deploy-branch-full-scope]].

**Mental model:** the fleet-wide image (`:latest`, `:stage`, `:rearch-dev`) is what a customer runs *based on its deployment_phase*; a custom-branch tag is an *override* that pins one customer off the fleet-wide image onto a feature build. "Production AutoPatrol sites run on the rearchitecture image" (from [[2026-04-14_connector-library-deployment-lifecycle]]) means: prod AP customers are on the rearch fleet, so they run `arm_connector_rearch:latest` — i.e. a `stage → rearchitecture` merge ships straight to them.

### Implication for "is X in prod?"

- "Merged to `rearchitecture`" → **in prod for the rearch fleet.** Say "shipped to the rearchitecture prod fleet," not "pre-prod."
- "Merged to `stage`" → in the rearch **staging** fleet only (Actuate-owned test sites). Not prod.
- "On a custom/feature branch image" → in prod for **only** the specific customers pinned to that tag via deploy_branch; nobody otherwise.
- A change that must reach ALL customers needs both a `rearchitecture` merge AND (if any legacy customers remain) a `master` merge.

## Cross-refs

- [[core-repo-suite]] — canonical repo list with categories + local clone status.
- [[feedback-check-branch-conventions]] — enforcement rule (auto-loaded memory).
- [[feedback-feature-branches-target-stage]] — vms-connector specific.
- [[feedback-stage-rearch-overlay-branch]] — vms-connector specific.
- [[feedback-library-no-dev-versions]] — actuate-libraries CI-skip-token trap.
- [[feedback-admin-repo-rules]] — [[actuate_admin]] push/migration rules.
- [[feedback-rearch-is-a-prod-fleet]] — `rearchitecture` is a prod fleet, not pre-prod (the mistake this section prevents).
- [[2026-05-20_deploy-branch-full-scope]] — §29 per-customer custom-branch deploy lifecycle.
- [[2026-04-14_connector-library-deployment-lifecycle]] — the multi-repo deploy coordination flow.
- [[admin-api-auth]] — how to authenticate to the prod admin API programmatically (DRF token route, dead ends).
