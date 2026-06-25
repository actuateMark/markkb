---
title: "AutoPatrol Server release process"
type: concept
topic: autopatrol
tags: [autopatrol, autopatrol-server, release-process, deploy, kubernetes-deployments, argocd, runbook]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
incoming:
  - home/offboarding/2026-06-23_local-repo-audit.md
  - topics/autopatrol/notes/entities/autopatrol-server.md
  - topics/autopatrol/notes/syntheses/2026-05-04_autopatrol-server-nr-upgrade-plan.md
  - topics/personal-notes/notes/daily/2026-05-04.md
incoming_updated: 2026-06-25
---

## Two-repo chain — DO NOT skip steps

The autopatrol-server release flow is a **two-repo chain**: code lands in [[autopatrol-server]], CI publishes a versioned image to ECR, and the [[kubernetes-deployments]] repo pins [[argocd|ArgoCD]] to that tag. Skipping the build-wait or skipping the version bump will leave the cluster on an old image while the code repo looks merged. We've tripped on this before.

**Order of operations (prod):**

1. **Merge PR to `main`** in `aegissystems/autopatrol-server`.
2. **Bump `pyproject.toml` version** in a follow-up commit on `main` (or include it in the PR). The image tag is the `pyproject.toml` version — without a bump, ECR tries to push to an existing tag and the build fails. *Observed 2026-05-04: PR #26 merged without a version bump → first ECR build failed → Clarissa pushed `bump to 0.1.25` as a follow-up commit → second build succeeded.*
3. **[[watch-entity|Watch]] the `Deploy to ECR` workflow run to completion (success).** Run list: `gh run list --repo aegissystems/autopatrol-server --branch main --limit 5`. Don't move on until status=completed AND conclusion=success for the SHA you care about.
4. **Open a PR in `aegissystems/kubernetes-deployments`** bumping `imageTag` for `autopatrolServer` in the prod cluster-values.
5. Merge that PR. [[argocd|ArgoCD]] (`syncPolicy: automated: true`) reconciles within minutes.

## Where things live

| Thing | Where |
|---|---|
| Source code | `aegissystems/autopatrol-server`, branch `main` |
| Version source | `pyproject.toml` `version` field (CI reads this for ECR tag) |
| Prod CI workflow | `.github/workflows/main.yml` ("Deploy to ECR") |
| Dev CI workflow | `.github/workflows/dev.yml` ("Deploy to ECR (dev)"), runs on every non-main branch |
| ECR repo | `autopatrol_service` (account 388576304176, us-west-2) |
| ECR tag — prod | `<pyproject-version>` (e.g. `0.1.25`) |
| ECR tag — dev | `<pyproject-version>-dev` (e.g. `1.0.1-dev`) |
| K8s manifest | `aegissystems/kubernetes-deployments`, file `argocd/env/388576304176/us-west-2/inference-eks-Ny9n/cluster-values.yaml` |
| K8s default branch | `helm` (NOT `main`) |
| Prod imageTag key | `actuate.applications.autopatrolServer.deployment.imageTag` |
| Dev imageTag key | `actuate.applications.autopatrolServerDev.deployment.imageTag` |
| EU clusters | `autopatrolServer.enabled: false` — autopatrol-server only runs in **us-west-2 prod**. EU is disabled. |

## Branch / image-tag relationship

- **`main` → 0.1.x** — production line. Image: `autopatrol_service:0.1.x`. Pinned in `autopatrolServer.deployment.imageTag`.
- **`dev/rev2` → 1.0.x-dev** — VLM-pipeline rework branch. Image: `autopatrol_service:1.0.x-dev`. Pinned in `autopatrolServerDev.deployment.imageTag`. Auto-builds on every push.
- Other feature branches → also tagged `<version>-dev` but **not pinned anywhere** (just sit in ECR until a future dev branch merge).

## Verification after deploy

The autopatrol-server has **no NR instrumentation** (known gap, see CLAUDE.md in the repo). Verification = look at the cluster:

```bash
# Confirm deployment image matches what you bumped to
kubectl -n autopatrol-server get deploy autopatrol-server -o jsonpath='{.spec.template.spec.containers[0].image}'

# Or hit the in-cluster /health endpoint
kubectl -n autopatrol-server port-forward svc/autopatrol-server 8080:80
curl http://localhost:8080/health
```

[[argocd|ArgoCD]] UI also shows the synced commit SHA on the Application row.

For customer-visible behaviour changes (like patrol-summary text edits): **wait for a real patrol run and grep the CloudWatch logs** for `Patrol summary:` to see the rendered text. Don't trust "image rolled out" alone.

## Sibling deploys (not on this chain)

[[autopatrol-onboarder]], [[autopatrol-cleanup-lambda]], and `immix-autopatrol-schedule-reenable` are **Lambdas in `autopatrol_onboarder` repo** with their own deploy scripts (`deploy_prod.sh`, `deploy_prod_eu.sh`). They do NOT go through the [[kubernetes-deployments]] / [[argocd|ArgoCD]] chain. They have their own acceptance criteria — see [[2026-04-23_release-acceptance-criteria]].

## Common trip-ups

1. **Forgetting the `pyproject.toml` bump.** First ECR build after merge fails because the tag already exists. Symptom: red CI on `main` immediately after merge. Fix: push a `bump to <next>` commit.
2. **Bumping the k8s tag before the build finishes.** [[argocd|ArgoCD]] will try to pull a tag that doesn't exist yet → ImagePullBackOff. Always confirm the ECR build is `success` first.
3. **Bumping in the wrong cluster-values.** EU autopatrolServer is disabled. The only live one is `inference-eks-Ny9n` (us-west-2 prod 388576304176). Don't waste a PR editing EU.
4. **Targeting the wrong default branch in the k8s repo.** It's `helm`, not `main`. `gh pr create --base helm`.
5. **Bumping prod when the change was a rev2 / VLM-pipeline change.** Different image-tag key (`autopatrolServerDev`). Don't conflate.

## Today's deploy reference (2026-05-04)

- PR #26 (autopatrol-server, `main`): connection-failure summary fix → 0.1.25
- PR #27 (autopatrol-server, `dev/rev2`): same fix cherry-picked → 1.0.1-dev
- [[kubernetes-deployments]]: branch `ap-0.1.25` (commit `05822dc4 bump ap server to 0.1.25`) merged into `helm`. Both `autopatrolServer.imageTag: 0.1.25` and `autopatrolServerDev.imageTag: 1.0.1-dev` confirmed live in cluster-values on `origin/helm`.

## See also

- [[autopatrol-server]] — entity note (codebase overview)
- [[2026-04-23_release-acceptance-criteria]] — global rule that every merge gets verified post-deploy, not just on CI green
- [[kubernetes-deployments]] — the k8s repo (worth its own entity note if not yet)
