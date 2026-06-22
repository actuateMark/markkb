---
title: autopatrol-server deployment
type: entity
topic: autopatrol
tags: [autopatrol-server, deployment, ci, ecr, argocd, kubernetes-deployments, dev-env]
created: 2026-05-21
updated: 2026-05-21
author: kb-bot
incoming:
  - topics/autopatrol/notes/syntheses/2026-05-27_ap-summary-disable-handoff.md
  - topics/personal-notes/notes/daily/2026-05-21.md
incoming_updated: 2026-05-28
---

# autopatrol-server deployment

How `/home/mork/work/autopatrol-server` gets built and shipped — prod and dev. Confirmed via investigation 2026-05-21 in service of the [[2026-05-20_ap-summary-disable-plan|AP summary-send disable]] cross-repo test.

## Quick reference

| Question | Answer |
|---|---|
| Where do images live? | `388576304176.dkr.ecr.us-west-2.amazonaws.com/autopatrol_service:<tag>` |
| Prod tag scheme | `<pyproject.toml version>` (e.g. `0.1.25`). Built by `.github/workflows/main.yml` on push to `main`. |
| Dev tag scheme | `<pyproject.toml version>-dev` (e.g. `0.1.26-dev`). Built by `.github/workflows/dev.yml` on push to ANY non-main branch. `continue-on-error: true` → CI failures Slack-notify but don't fail the job, so check Slack/Actions UI directly. |
| Tag collision risk | Every dev push overwrites `<version>-dev`. Two concurrent feature branches with the same `pyproject.toml` version clobber each other. **Bump `pyproject.toml` per feature** to avoid. |
| [[kubernetes-deployments]] branch | `helm` (NOT the working-tree default `eu-update` — `eu-update` does not have these manifests). Always `git show origin/helm:...` to inspect. |
| Live AutoPatrol service cluster | `inference-eks-Ny9n` in account `388576304176`, region us-west-2. Only place autopatrol-server runs. EU clusters set `enabled: false`. |
| Prod deployment | namespace `autopatrol-server`, image tag pinned at `argocd/env/388576304176/us-west-2/inference-eks-Ny9n/cluster-values.yaml` under `autopatrolServer.deployment.imageTag`. |
| Dev deployment | namespace `autopatrol-server-dev`, env `DEV=true` (consumes `_dev.fifo` queues) + `ANALYZE_SINGLE_IMG=true`, image tag pinned under `autopatrolServerDev.deployment.imageTag` in the same cluster-values.yaml. |
| CD mechanism | [[argocd|ArgoCD]] auto-sync (`syncPolicy.automated.prune+selfHeal+allowEmpty=true`). Push to `helm` → [[argocd|ArgoCD]] picks up within ~3 min. |
| Version-bump pattern | **Manual**, no bot. Example: branch `feature/bump-autopatrol-server-X.Y.Z` → edit one tag line → PR → merge. |
| DLQ consumer | **Not deployed independently.** Dockerfile CMD hardcodes `python3 -m server.app`. `server.dead_letter_app` exists as code but no chart runs it. Confirm DLQ drain mechanism before assuming DLQ changes deploy. |
| SQS queues | `autopatrol_jobs.fifo`, `autopatrol_jobs_dev.fifo`, `autopatrol_dead_letter.fifo`, `autopatrol_dead_letter_dev.fifo` in `388576304176`/us-west-2. **Not in terraform** — click-ops created. IAM role `autopatrol-microservice-role` references the queue ARN but doesn't create it. |

## Deploy recipe: feature branch → dev environment

```
# 1. On the autopatrol-server feature branch, bump pyproject.toml version
#    to something unique (e.g. 0.1.26 if main is at 0.1.25). CI tags by
#    `<version>-dev` and concurrent branches will clobber the same tag if
#    versions match.
cd /home/mork/work/autopatrol-server
# edit pyproject.toml: version = "0.1.26"
git commit -am "bump version to 0.1.26 for dev deploy"
git push origin feat/my-feature

# 2. CI runs dev.yml on push, builds linux/arm64 image, pushes
#    autopatrol_service:0.1.26-dev. Verify the build succeeded
#    (continue-on-error masks failures):
gh run watch  # or check the Actions tab
aws ecr describe-images --repository-name autopatrol_service \
  --image-ids imageTag=0.1.26-dev --region us-west-2

# 3. Bump the dev imageTag in kubernetes-deployments (helm branch).
cd /home/mork/work/kubernetes-deployments
git fetch origin helm
git checkout -b feature/autopatrol-dev-0.1.26 origin/helm
# edit argocd/env/388576304176/us-west-2/inference-eks-Ny9n/cluster-values.yaml
#   autopatrolServerDev.deployment.imageTag: 0.1.26-dev
git commit -am "bump autopatrol-server-dev to 0.1.26-dev"
git push origin feature/autopatrol-dev-0.1.26
gh pr create --base helm --title "..." --body "..."

# 4. After PR merges to helm, ArgoCD syncs within ~3 min.
#    Verify:
kubectl -n autopatrol-server-dev get pods
kubectl -n autopatrol-server-dev describe pod <pod> | grep Image:

# 5. (Optional, if you re-pushed the same tag) Force pod restart so the
#    new image is pulled, since imagePullPolicy: IfNotPresent.
kubectl -n autopatrol-server-dev rollout restart deploy/autopatrol-server-dev
kubectl -n autopatrol-server-dev rollout status deploy/autopatrol-server-dev
```

## Driving traffic to the dev deployment

The dev deployment consumes `autopatrol_jobs_dev.fifo` (and DLQ-dev). To test cross-repo, the connector side must produce to that same queue:

- **From a locally-run vms-connector** (`python connector.py -l`): use settings with `lead` containing `"actuate"` (triggers the legacy `lead_implies_dev` path in [[actuate-config]]'s `PatrolConfig`) OR explicitly set `"queue_stage": "dev"` in the `autopatrol` settings block. Confirm with `[[2026-05-20_local-ap-e2e-stack-installed#run-procedure|local-test-stack]]` if testing pure-local.
- **From a real customer-site connector deployment**: site settings drive the queue stage. Real customer AP sites (`Immix.*` leads) → prod queue, **won't hit dev autopatrol-server**. To exercise dev autopatrol-server with real connector code, you need either (a) a test/dev customer deployment whose settings route to `_dev.fifo`, or (b) a connector_deployer feature deployment with a settings overlay.

## Convention gotchas

1. **Working-tree branch trap.** `kubernetes-deployments`'s default in the working tree is `eu-update`. The live AP manifests are on `helm`. Always cross-reference.
2. **Dev tag overwrite.** `autopatrol_service:1.0.1-dev` was sticky from an earlier branch. If you push a feature branch with `pyproject.toml = 1.0.1`, you overwrite the dev image silently. Bump first.
3. **Prod / dev version inversion.** Prod is `0.1.25`, dev was `1.0.1-dev` for a while. Versions in `pyproject.toml` are not strictly monotonic — they're whatever the bumping engineer chose. Don't infer from version which is newer.
4. **DLQ blind spot.** If your change touches `server.dead_letter_app`, deploying autopatrol-server-dev won't exercise it. There may be a separate out-of-band DLQ runner not captured in any manifest. Confirm before assuming.
5. **CI [[dev-workflow|dev workflow]] has `continue-on-error: true` on build.** If the build fails, the job is green but no image is pushed. Always verify ECR has the expected tag before assuming a dev deploy is ready.

## Cross-refs

- [[autopatrol-server]] — service entity.
- [[autopatrol-cleanup-lambda]] — sibling AutoPatrol Lambda.
- [[2026-05-20_ap-summary-disable-plan]] — first cross-repo change that drove this investigation.
- [[2026-05-20_local-ap-e2e-stack-installed]] — pure-local alternative.
- [[branch-conventions]] — the autopatrol-server row.
