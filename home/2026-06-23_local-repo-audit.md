---
title: "Local-repo documentation audit — CLAUDE.md / KB-port handoff status"
type: concept
topic: offboarding
tags: [offboarding, audit, claude-md, documentation, repos, handoff]
created: 2026-06-23
updated: 2026-06-23
author: kb-bot
incoming:
  - home/2026-06-22_manual-action-checklist.md
  - home/README.md
  - home/offboarding-overview.md
incoming_updated: 2026-06-25
---

# Local-repo documentation audit (2026-06-23)

> Audited the 25 repos in `/home/mork/work` (4-agent fan-out + parent footprint scan) for offboarding: **does each have significant Mark work, does it need a CLAUDE.md, and is there KB knowledge that should flow *into* the repo** so it survives Mark's departure. Footprint = exact Mark-commit counts (parent `git log`); the audit agents had Bash denied so their footprint was inferred — those are corrected here with real counts.
>
> **Decision:** draft CLAUDE.md / doc-ports for all 🔴 HIGH + 🟠 MED repos, **branch + PR per repo**. Tracking: this note + the PRs.

## Priority table

| Repo | Mark commits | CLAUDE.md | Action | Pri |
|---|---|---|---|---|
| **local_network_scripts** | 27 (≈all) | none | new CLAUDE + port firebat KB — *the automation base* | 🔴 |
| **autopatrol-server** | 40 | none (has README+ARCHITECTURE) | new CLAUDE + port release-process; core analysis backend | 🔴 |
| **[[ds-terraform-eks-v2]]** | 11 (in-flight) | none | new CLAUDE — PG16 fix only on branch; capture branch state + roadmap | 🔴 |
| **actuate_bi** | low / role-critical | none | new CLAUDE — canonical billing DDL; tf-vs-sql drift rule KB-only | 🔴 |
| **actuate-integration-tools** | 9 (Mark-only) | none | ✅ **was local-only → pushed to `aegissystems/actuate-integration-tools` 2026-06-23** + CLAUDE.md | 🔴 |
| **actuate-libraries** | 1380 | 120L | update — **CI-skip-token / dev-version CI-safety knowledge** | 🔴 |
| **vms-connector** | 2463 | 360L (strong) | port architecture rationale (AIMD/fork-safety) → docs/ | 🟠 |
| **[[actuate_admin]]** | 522 | 76L (thin) | port release-flow + local-bringup + AutoPatrol PATCH gotcha | 🟠 |
| **actuate-inference-api** | 100 | 117L | update — auth chain / v5 design / multi-model | 🟠 |
| **queue_consumer** | 136 | none | new CLAUDE — factory pattern + per-consumer CI | 🟡 MED |
| **[[kubernetes-deployments]]** | 79 | 94L (narrow) | update — [[argocd|ArgoCD]] / app-of-apps / Karpenter workflow | 🟡 MED |
| **camera-ui** | 12 | 84L | update — tech stack + live-streaming flag | 🟡 MED |
| **software-arch-sketches** | 3 | none | thin CLAUDE — make targets + links to 5 sketch-findings | 🟡 MED |
| autopatrol_onboarder | 68 | 183L (gold) | fine — optional postmortem backfill | ⚪ LOW |
| health_report | 58 | 75L (good) | fine as-is | ⚪ LOW |
| connector_deployer | **2** (not Mark's) | none | owner's call — not an offboarding gap | ⚪ LOW |
| [[actuate-automation-test]] | 1 (team E2E) | none | fine — 175L README + KB entity | ⚪ LOW |

## What to write per repo (source KB notes to distill)

**🔴 local_network_scripts** — three-tier role, provisioning walkthrough (phase-00…11), per-timer service inventory (cadence/auth), ops runbook, secrets/recovery. Sources: [[2026-06-22_firebat-operations-runbook]], `host-firebat.md`, [[2026-04-30_three-tier-routine-check-pattern]], [[2026-04-30_morning-prep-scripts-runbook]].
**🔴 autopatrol-server** — overview, entry points (`server/app.py`, `autopatrol_queue.py`), dev-vs-prod queue routing, ECR→manifest→[[argocd|ArgoCD]] release chain (+ "don't bump manifest before ECR tag"), alert-race gotcha, post-deploy acceptance criteria. Sources: `autopatrol-server.md` entity, [[2026-05-04_autopatrol-server-release-process]], [[2026-04-16_deferred-alert-race-condition]]. Port the release-process note to `docs/`.
**🔴 [[ds-terraform-eks-v2]]** — branch state (PG16 fix on `integration/rds-pg16-extended-support`, NOT main), the 3-DB upgrade roadmap (jobschedulerdjangoq PG13 + dev-eu Aurora PG12 outstanding; supportwiki done 2026-06-17), Phase-0 decommission gate. Source: [[2026-06-02_rds-extended-support-upgrade-runbook]].
**🔴 actuate_bi** — Snowflake DDL canonical source, the **tf/ over stale sql/** rule, 3 operational risks (non-transactional SPRD swap, top-parent race, SQL-drift CI gap). Sources: `actuate-bi-repo.md` (217L), `snowflake-billing-tables.md`, [[2026-05-11_eng-242-substantially-answered]].
**🔴 actuate-integration-tools** — roadmap, setup/auth (S3 settings.json load via [[actuate-config]]), validator catalog, brain-in-jar replay, Hypothesis bindings. Sources: `actuate-integration-tools.md` entity, [[2026-05-20_ait-brain-in-jar-spec]], [[2026-05-21_hypothesis-in-actuate]].
**🔴 actuate-libraries** — fold CI mechanics into CLAUDE.md or `docs/CI.md`: bump-stable/publish-base sequences, the CI-skip-token + dev-version-leak hazards (source of repeated incidents), the 6-step dev→stable promotion. Sources: [[2026-04-14_ci-pipeline-mechanics]], [[dev-workflow]], [[dependency-graph]].
**🟠 vms-connector** — distill the architectural "why" to `docs/`: layer evolution, AIMD inference-pool tuning (initial 48 / floor 8 / 200ms), fork-safety constraints. Sources: [[connector-evolution]], [[inference-pool]], [[performance-optimization-landscape]].
**🟠 [[actuate_admin]]** — add AutoPatrol PATCH camelCase-vs-snake_case silent-drop gotcha to CLAUDE.md; port release-flow + local-bringup to `docs/`. Sources: [[actuate-admin-api]], [[release-flow-stage-first]], [[2026-05-20_actuate-admin-local-bringup]].
**🟠 actuate-inference-api** — add auth chain ([[rust-lambda-authorizer|Rust Lambda authorizer]] + DynamoDB RBAC), v5 design (unified endpoint + model registry), multi-model (InferenceContext caching, merge-then-filter). Sources: deep-dive-rust-authorizer, v5-api-design, multi-model-inference.
**🟡 queue_consumer** — factory pattern (`consumer_factory.make_consumer`), 16 consumer types, per-consumer path-triggered CI, SIGTERM/liveness. Sources: [[queue-consumer]] entity, queue-consumer-aws-permissions.
**🟡 [[kubernetes-deployments]]** — absorb [[argocd|ArgoCD]]/Helm/app-of-apps + Karpenter + 3-cluster RBAC beyond the existing Cognito incident runbook. Sources: [[kubernetes-deployments]] entity, [[argocd]], argocd-gitops-workflow.
**🟡 camera-ui** — merge version/coverage/styling + the `enable-live-streaming` LD flag reference. Sources: [[camera-ui]] entity, [[2026-05-19_live-streaming-v1-plan]].
**🟡 software-arch-sketches** — thin CLAUDE: make targets, `SKETCH_INPUT_REPO` env, `data/*.json` outputs, links to the 5 sketch-findings notes.

## Execution status (2026-06-23)

**🔴 HIGH new-CLAUDE.md — PRs opened:**
- autopatrol-server → [PR #29](https://github.com/aegissystems/autopatrol-server/pull/29) (CLAUDE.md + docs/release-process.md)
- actuate_bi → [PR #12](https://github.com/aegissystems/actuate_bi/pull/12)
- [[ds-terraform-eks-v2]] → [PR #104](https://github.com/aegissystems/ds-terraform-eks-v2/pull/104) (captures the PG16-fix-on-branch state)
- local_network_scripts → [PR #1](https://github.com/aegissystems/actuate-dev-toolkit/pull/1)
- **actuate-integration-tools → ✅ PUSHED to `aegissystems/actuate-integration-tools`** (private) 2026-06-23 — was local-only; CLAUDE.md included.

**🔴 HIGH updates/ports + 🟡 MED — PRs opened:**
- vms-connector → [PR #1765](https://github.com/aegissystems/vms-connector/pull/1765) (docs/architecture-rationale.md)
- [[actuate_admin]] → [PR #2537](https://github.com/aegissystems/actuate_admin/pull/2537) (CLAUDE.md gotchas + docs/release-flow + docs/local-bringup)
- actuate-inference-api → [PR #95](https://github.com/aegissystems/actuate-inference-api/pull/95) (CLAUDE.md auth/v5/multi-model)
- actuate-libraries → [PR #392](https://github.com/aegissystems/actuate-libraries/pull/392) (docs/CI.md — CI-skip-marker hazards)
- [[kubernetes-deployments]] → [PR #419](https://github.com/aegissystems/kubernetes-deployments/pull/419) (CLAUDE.md [[argocd|ArgoCD]] workflow)
- queue_consumer → [PR #194](https://github.com/aegissystems/queue_consumer/pull/194) (CLAUDE.md)
- **software-arch-sketches → ✅ PUSHED to `aegissystems/software-arch-sketches`** (private) 2026-06-23 — was local-only; CLAUDE.md included.
- **camera-ui → SKIPPED.** Local main is 249 commits behind and CLAUDE.md base differs; the minor append (tech-stack + a not-yet-landed live-streaming flag) isn't worth a stale-base PR. Recommend a manual 2-line touch on current main.

**Note:** all PRs were opened from clean git worktrees off each repo's real default branch (main/rearchitecture/helm) to avoid the stale/divergent local checkouts — docs only, no code. **2 local-only repos** (actuate-integration-tools, software-arch-sketches) — the notable finding — are now **pushed to the org** (2026-06-23). A full 25-repo sweep confirmed no others lack a remote.

## Related
- [[2026-06-22_offboarding-plan]] · [[2026-06-22_manual-action-checklist]] · [[2026-06-22_actuate-footprint-handoff]]
