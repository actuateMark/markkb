---
title: "Stale-PR triage punch list — 2026-05-12 sweep"
type: concept
topic: engineering-process
tags: [handoff, pr, triage, backlog, reviewer]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
outgoing:
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/personal-notes/notes/daily/2026-05-12.md
[]
incoming:
  - topics/personal-notes/notes/daily/2026-05-12.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-13
---

# Stale-PR triage punch list — 2026-05-12 sweep

> **Status:** Survey done 2026-05-12; **zero actions executed**. Each item below is ready to be acted on with the listed next step. Designed for morning pickup ([[mark-todos]] Today's Scope 2026-05-13 lead item).
>
> **Root cause pattern across the stale set:** three of the open PRs have **zero reviewers assigned** — they're sitting clean-merge but invisible. Action is social, not technical.

## Entry point

Run `gh pr view <repo> <num>` to confirm current state before any of the actions below — these snapshots are from 2026-05-12 afternoon and the world may have moved.

## Punch list

### 1. kubernetes-deployments#366 — djangoq v2.7.5 in prod-us

- **State:** `APPROVED` but `mergeStateStatus=DIRTY` (conflicts). Updated 2026-05-01.
- **Action:** rebase `bump-djangoq-us-v2.7.5` against `helm`. Conflicts likely trivial (version-bump PRs rarely have deep semantic conflicts). After rebase, GitHub should auto-merge given approval.
- **Time:** 5–10 min.
- **Risk:** low — version bump in cluster-values.yaml. No code path change.

### 2. ds-terraform-eks-v2#69 — `[DOCS-ONLY / WRONG LOCATION]`

- **State:** Title literally says "WRONG LOCATION". Sitting open since 2026-04-21. Branch: `feature/autopatrol-stale-schedule-cleanup`.
- **Action:** close as superseded by #77 (`feat/autopatrol-microservice-iam-tf-import`) and/or the actual cleanup-Lambda terraform that landed elsewhere. Add a closing comment pointing to where the real work landed.
- **Time:** 5 min.
- **Risk:** zero — PR was already known-wrong.

### 3. actuate_admin#2408 — `mgmt: deactivate_customers_by_cids`

- **State:** **DRAFT**, no reviewers, no CI checks. Base: `staging`, head: `feat/deactivate-customers-by-cids`. Updated 2026-05-06.
- **Action:** decide one of:
  - **Promote from draft + assign reviewer** (if the management command is ready). Quick path — was probably draft just because it lacked confidence at the time.
  - **Close** (if no longer needed). Branch already has the commit; can recreate any time.
- **⚠️ Important:** this is the branch the §29 deploy-branch stub files are currently sitting on (untracked). **Before any action on this PR, move the §29 stubs to a fresh `feat/deploy-branch-lane-stubs` branch off `staging`.** See §29 sub-items.
- **Time:** 10 min (including the stub move).
- **Risk:** low — DRAFT promotion is reversible.

### 4. autopatrol_onboarder#14 — `ops: cohort-F deep classifier + per-customer tracker`

- **State:** Not draft, `mergeStateStatus=CLEAN`, **zero reviewers**. Updated 2026-05-06. Base: `master`, head: `feat/cohort-f-deep-classifier`.
- **Action:** request review from the autopatrol-onboarder owner. This is sitting clean for 6 days purely because nobody's been asked.
- **Time:** 2 min.

### 5. actuate_admin#2405 — `feat(autopatrol): schedule->customer cascade hook (Cohort B, behind flag)`

- **State:** Not draft, `mergeStateStatus=CLEAN`, **zero reviewers**. Updated 2026-05-05. Behind a feature flag (per [[2026-05-07_cohort-b-no-backfill-decision]] the cascade hook stays flag-disabled; not blocked on landing).
- **Action:** request review from the admin-side owner. Same pattern as #14 — social step gap.
- **Time:** 2 min.

## NOT on the punch list (intentional)

- **connector_deployer#168** (VPA log downgrade) — today's PR, normal review-required state. Wait a day.
- **[[ds-terraform-eks-v2]]#77** (eks-irsa autopatrol) — active §3 IaC work, not actually stale.
- **actuate-inference-api#60** (v5 prod-promote) — explicitly held back by user for more testing ([[2026-05-12]] Notes/Learnings). Do NOT push forward.

## Followups to capture if anything changes

- If #366 rebase surfaces non-trivial conflicts: file a sub-task in §N (or open a new workstream); don't quietly force-resolve.
- If #2408 close-decision lands as "close": consider whether the `deactivate_customers_by_cids` management command should re-emerge as a §N admin-API endpoint family member (§29 lane).
- Once #14 and #2405 get reviewers, [[watch-entity|watch]] the review-decision: requested-changes can re-stale them.

## Related

- [[mark-todos]] Today's Scope 2026-05-13 — punch list is the lead item
- [[2026-05-12]] — daily note where the survey was done
- [[2026-05-12_internal-test-deploy-lane]] — §29 design (relevant for #2408 stub branch move)
- [[2026-05-07_cohort-b-no-backfill-decision]] — context for #2405 being flag-disabled
