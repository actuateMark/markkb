---
title: "S3 Cost Reduction — Ranked Action Plan with Savings / Effort Table"
type: synthesis
topic: aws-cost
tags: [synthesis, aws, s3, cost, action-plan, savings, effort, ranking, lifecycle, storage-lens, intelligent-tiering, multipart-upload]
created: 2026-04-28
updated: 2026-04-29
author: kb-bot
jira: "ENG-183"
status: active
incoming:
  - topics/aws-cost/_summary.md
  - topics/aws-cost/notes/concepts/2026-04-30_dashboard-cost-signal-expansion.md
  - topics/aws-cost/sources/2026-04-29_minio-self-hosted-s3-tutorial.md
  - topics/personal-notes/notes/daily/2026-04-28.md
  - topics/personal-notes/notes/daily/2026-04-29.md
incoming_updated: 2026-05-01
---

# S3 Cost Reduction — Ranked Action Plan with Savings / Effort Table

## Why this exists

Yesterday (2026-04-27) the [[aws-cost/_summary|aws-cost topic]] was spun off and seeded with seven new sources + a [[2026-04-27_aws-cost-topic-spinoff|tier-1/2/3/4 attack plan]]. The plan ranked actions by ROI/friction but didn't quantify per-action savings against effort in one comparable view. This synthesis fills that gap: a single savings × effort × confidence table across every actionable S3 lever surfaced to date, with grouping and dependencies made explicit so the next attack pick is defensible.

Scope is **S3-only** (per user direction). EBS / EFS / snapshot / Compute Optimizer opportunities are tracked separately in [[2026-04-27_eks-storage-applicability]] — pointer at the bottom.

**Plan + tracking:**
- Plan file (per-action approval gates, command snippets, verification, rollback): `~/.claude/plans/methodical-pruning-oak.md`
- Jira parent: **ENG-183** "S3 Cost Reduction — Ranked Action Plan"
- Sub-tasks: ENG-184 (Action 1) … ENG-194 (Action 11). Action 12 not ticketed — fleet-arch coupled.

**Status:** Drafted, awaiting per-action approval. NO implementation runs autonomously.

## Ground truth (cost picture as of 2026-04-23)

- **S3 spend:** ~$398k/yr annualized (30d window: $32,752.97). Source: [[2026-04-23_s3-tier3-breakdown]].
- **Composition:** 46% Tier1 PUTs ($15k/30d), 35% storage GB-mo ($11.6k/30d), 11% Tier3 lifecycle ($3.5k/30d, ~$42k/yr), 6% Tier2 GETs, 2% data transfer.
- **Tier3 driver (confirmed):** lifecycle-expiration on per-frame "24h auto-delete" buckets — NOT replication. Zero buckets had `ReplicationConfiguration`. The CE label "Replication/Lifecycle (Tier3)" is misleading in this account.
- **Largest single lever (structural):** ~$30-60k/yr ceiling from eliminating non-detection-positive frame writes (motion-gating at the puller, proposals D/E). Coupled to fleet-arch direction selection — not a standalone cost project.
- **Largest untapped visibility lever:** S3 Storage Lens Free tier — currently disabled.

## The action table

Single comparable view. Savings are annualized (USD/yr); effort is wall-clock for the action itself, not preceding analysis. Confidence labels explained below the table.

| # | Action | Savings/yr | Effort | Confidence | Standalone? | Source/recipe |
|---|---|---|---|---|---|---|
| 1 | **Enable S3 Storage Lens (Free tier)** — daily metrics: missing lifecycle, orphan MPUs >7d, transition gaps, class distribution | **$0 direct** (visibility); enables actions 4, 7, 8 by surfacing latent gaps; estimate $1-5k/yr compounding | **5 min** (console toggle) | High | Yes | [[2026-04-27_s3-storage-lens]] |
| 2 | **Re-enable `aegis-all-frames-v2-sts` 24h-expiry rule** — currently `Enabled=False`, bucket accumulating StandardStorage that should expire daily | **$100s-$1k+** (depends on bytes accumulated since disable; needs measurement) | **15 min** (CLI verify + flip + audit cause) | Med | Yes | [[2026-04-23_s3-tier3-cost-investigation]] §2 |
| 3 | **Audit `actuate-envera-frame-0` StandardIA-at-PUT-time pattern** — 3.4 TB across Standard + StandardIA without lifecycle rule; could be intentional cost-opt or latent bug | **$0 if intentional**, **$0-$500** if buggy (worst case) | **30 min** | Low | Yes | [[2026-04-23_s3-tier3-cost-investigation]] §5 |
| 4 | **Orphan multipart upload audit + apply `AbortIncompleteMultipartUpload` everywhere it's missing** — Bash loop across all buckets | **$200-$2k** (typical small-fleet exposure; Actuate has 281 buckets so could land higher) | **1-2 hr** (loop + per-bucket lifecycle put) | Med directional, Low quantitative | Yes (better with item 1 output) | [[2026-04-27_s3-multipart-upload-cleanup]] |
| 5 | **Trusted Advisor cost-optimization scan** — covers idle/dangling resources, not S3-only | **Variable** (cross-service; surfaces orphan EBS too) | **5 min** (console) | High | Yes | [[2026-04-27_eks-storage-applicability]] |
| 6 | **Buckets-not-yet-probed sweep (40+ candidates)** — Group A/B classification on remaining `frame/alert/detect/clip/spray/autopatrol*` buckets; close attribution gap on the Tier3 $3.5k/mo line | **$0 direct** (analysis); confirms Group A dominance + identifies any further misconfig | **2-3 hr** (extension of 2026-04-23 method) | High (method validated) | Yes | [[2026-04-23_s3-tier3-breakdown]] § "not yet probed" |
| 7 | **Per-bucket lifecycle policy audit + apply missing rules** — heuristic: every bucket with >$X spend has either lifecycle config or explicit annotation | **$1-5k** (each missing-rule bucket compounds) | **2-4 hr** (after item 1 prioritizes) | Med | **Coupled to item 1** | [[2026-04-27_s3-lifecycle-rules]] |
| 8 | **Intelligent-Tiering evaluation on `actuate-2-month-storage` + `actuate-6-month-storage` (+ any >30d retention)** — cost-model object-size distribution; only enable where >128 KB objects dominate AND access pattern is unpredictable | **$2-10k** (30-50% storage savings on long-retention prefixes IF size profile is favorable; could be net-negative if many small objects) | **2-4 hr** analysis + **1 hr** enable per bucket | Med (data-dependent) | Yes | [[2026-04-27_s3-intelligent-tiering]] |
| 9 | **DEEP_ARCHIVE retention review** — `actuate-2-month-storage` + `actuate-6-month-storage` already transition `alerts/` prefix at 60d/180d. Verify alert prefix is the right retention boundary; check if transition cadence could be earlier (Standard → IA at 30d before DEEP_ARCHIVE at 60d) for storage savings without retrieval-pattern impact | **$500-$2k** | **2 hr** (review + change) | Low (needs retrieval-pattern data) | Yes | [[2026-04-23_s3-tier3-breakdown]] Group B |
| 10 | **Add `s3_lifecycle_rules_disabled` dashboard signal** — surfaced as candidate from OOM-surge config-drift triage; would alert on future repeats of the `aegis-all-frames-v2-sts` failure mode | **$0 direct** (preventive) | **1-2 hr** (signal definition + NRQL/CW source) | High | Yes | [[2026-04-23_oom-surge-connector-limit-drift]] |
| 11 | **Extend `/cost-check` to drill USAGE_TYPE for any category >$1k/mo** + lifecycle-churn-pattern probe (CW `list-metrics` class enumeration) | **$0 direct** (tooling) — turns 30-min investigations into 3-min ones | **2-4 hr** | High | Yes | [[2026-04-23_s3-tier3-cost-investigation]] § "lessons" |
| 12 | **Frame-bucket structural rework** — eliminate per-frame write/delete pattern (motion-gating at puller, proposals D/E) | **$30-60k** (Tier1 + Tier3 + storage delta combined) | **Multi-PR / multi-week** | Med (depends on 40-60% motion-drop rate) | **NO — coupled to fleet-arch direction** | [[2026-04-23_s3-tier3-cost-investigation]] §3, [[2026-04-22_frame-storage-design-deltas]] |

**Confidence labels:**
- *High* = plan-of-action and outcome are both validated; pulling the lever doesn't risk surprise
- *Med* = direction validated but quantification depends on data we don't have yet
- *Low* = analysis-required before acting; outcome could be near-zero

## Grouping

### A — Visibility (do first, no risk, enables others)
**Items 1, 5, 6.** Storage Lens + Trusted Advisor + buckets-not-yet-probed sweep. No production change; outputs drive priorities for items 4, 7, 8. Total effort 3-4 hours, total direct savings $0 — payoff is in **better targeting** of items 4, 7, 8 and reducing investigation overhead going forward.

### B — Hygiene (already-broken; fix in place)
**Items 2, 3.** Both surfaced by the 2026-04-23 investigation as already-known anomalies. Effort <1hr each. Item 2's value depends on accumulated bytes (likely small; rule was disabled at unknown date but only one bucket affected).

### C — Bounded cleanups (table-stakes config that should be everywhere)
**Items 4, 7.** Multipart-upload abort rule + per-bucket lifecycle-rule audit. Both are "every bucket should have this" patterns. Item 4 is fully standalone; item 7 benefits from item 1's output for prioritization. Combined exposure $1-7k/yr depending on what the audit surfaces.

### D — Targeted optimization (data-dependent)
**Items 8, 9.** Intelligent-Tiering evaluation + DEEP_ARCHIVE cadence review. Both need analysis before action. Larger potential payoff than C ($2-10k + $500-$2k) but lower confidence. Defer until A is in place to avoid acting on guesses.

### E — Tooling (force-multiplier)
**Items 10, 11.** Dashboard signal + `/cost-check` skill extension. Both prevent future investigation overhead and config drift. No direct savings; high leverage on every future cost investigation.

### F — Structural (single largest lever, NOT standalone)
**Item 12.** Frame-bucket pattern rework. $30-60k/yr ceiling — bigger than items 1-11 combined — but is coupled to fleet-architecture direction selection. Tracked under [[fleet-architecture/_summary]] proposals D/E, not under this plan. Mentioned here for completeness; **do not pull this lever as a standalone cost project.**

## Dependency map

```
        ┌── 1 (Storage Lens) ──┐
        │                      ├── 7 (lifecycle audit)
        │                      ├── 4 (MPU cleanup)  [also standalone]
visibility ── 5 (Trusted Advisor)
        │                      └── 8 (Int-Tiering eval)
        └── 6 (bucket sweep) ──┘                         │
                                                         ├── 9 (DEEP_ARCHIVE review)
hygiene ──── 2 (sts rule)                                │
        ──── 3 (envera audit)                            │
                                                         │
tooling ──── 10 (lifecycle-disabled signal)              │
        ──── 11 (/cost-check extension)                  │
                                                         │
structural ── 12 (frame-bucket rework) [fleet-arch coupled]
```

Items 4, 7, 8 are the cluster where item 1 (Storage Lens) most pays back. Items 2, 3, 5, 6 can run in parallel. Item 12 is on a separate track entirely.

## Recommended sequence (first attack to last)

1. **Item 1 — Enable Storage Lens** (5 min)
2. **Item 5 — Trusted Advisor scan** (5 min)
3. **Item 2 — Re-enable `aegis-all-frames-v2-sts` rule + investigate why it was disabled** (15 min)
4. **Item 4 — MPU audit + abort rule everywhere** (1-2 hr)
5. **Item 6 — Probe remaining 40+ buckets** (2-3 hr) — *now that items 1+5 are running, bucket sweep targets are easier*
6. **Item 11 — Extend `/cost-check`** (2-4 hr) — *codifies methodology for items 6/7*
7. **Item 7 — Per-bucket lifecycle audit + missing rules applied** (2-4 hr)
8. **Item 10 — Dashboard signal `s3_lifecycle_rules_disabled`** (1-2 hr)
9. **Item 8 — Intelligent-Tiering evaluation** (2-4 hr) — *needs Storage Lens data to be representative*
10. **Item 9 — DEEP_ARCHIVE cadence review** (2 hr)
11. **Item 3 — `actuate-envera-frame-0` audit** (30 min) — *low-confidence, easy to keep slipping; pin to a specific session*
12. **Item 12 — Frame-bucket structural rework** — *do not own here; track via fleet-arch*

Total wall-clock for items 1-11: roughly **15-25 hours of focused work** across multiple sessions. Total direct annualized savings range: **$3-20k** (the majority of which lands in items 4, 7, 8 if the Storage Lens output reveals broad coverage gaps). Items 10 and 11 don't save money directly but reduce future investigation cost.

The single biggest payoff is still item 12 (~$30-60k/yr) — but pulling it requires committing to a fleet-arch direction.

## What this synthesis intentionally omits

- **EBS / EFS / snapshot / Compute Optimizer levers** — covered in [[2026-04-27_eks-storage-applicability]]. Worth a parallel-tracking action plan once EBS spend is quantified (currently unknown — first step would be `aws ec2 describe-volumes` audit pass, which is item 1 in the EKS-storage list).
- **Savings Plans / Reserved Instances** — queued in [[aws-cost/_dive-queue]]; not yet investigated against current spend profile.
- **ECR lifecycle policies** — also in dive queue.
- **VPA / EKS 1.35** — externally tracked under ENG-78 and ENG-79, not this synthesis's scope.

## Open questions worth resolving before deep work

1. **What was the date / cause of `aegis-all-frames-v2-sts` lifecycle rule being disabled?** Item 2's value depends on accumulated bytes since that date. CloudTrail lookup would answer this.
2. **What's the object-size distribution in `actuate-2-month-storage` + `actuate-6-month-storage`?** Item 8's go/no-go decision pivots on whether >128 KB objects dominate. Storage Lens (item 1) surfaces this automatically once enabled for ~7 days.
3. **Which 40+ unprobed buckets actually contribute to the Tier3 $3.5k/mo line?** Item 6's bucket sweep would close attribution; until then, the Group A vs B split is bounded but not pinned.
4. **What's the actual MPU exposure today?** Item 4's savings can't be quantified before running the `list-multipart-uploads` audit.

These resolve naturally as items 1, 4, 5, 6 execute — they're not blocking, they're refinement.

## Cross-refs

- [[2026-04-27_aws-cost-topic-spinoff]] — yesterday's tier-1/2/3/4 ranking that this synthesis reorganizes into a single savings/effort view
- [[2026-04-23_s3-tier3-cost-investigation]] — load-bearing investigation that anchors the cost picture
- [[2026-04-23_s3-tier3-breakdown]] — raw bucket-level data
- [[cost-architecture]] — full Actuate cost layer map
- [[2026-04-27_eks-storage-applicability]] — the EBS / EFS adjacent action plan, tracked separately
- [[2026-04-27_s3-storage-lens]], [[2026-04-27_s3-multipart-upload-cleanup]], [[2026-04-27_s3-lifecycle-rules]], [[2026-04-27_s3-intelligent-tiering]] — source notes for items in the table
- [[2026-04-22_frame-storage-design-deltas]], [[2026-04-22_fleet-proposal-rescore-with-delta]] — where item 12 (structural rework) lives
- [[skill-cost-check]] — operational primary for ad-hoc cost queries; item 11 extends this
- [[aws-cost/_summary]], [[aws-cost/_dive-queue]] — topic landing pages

## Reviewed sources (no plan amendment)

Sources reviewed against this plan that produced **no net-new actions**, kept as a record so they don't get re-litigated:

| Date | Source | Why no amendment |
|---|---|---|
| 2026-04-29 | [[2026-04-29_minio-self-hosted-s3-tutorial]] (pavloshargan gist) | Hobbyist self-hosted MinIO recipe; doesn't transfer to enterprise infra. Reinforced egress-dominance framing but our S3 data-transfer is only 2% of total — fractionally tiny vs Tier1 PUTs (46%) and storage GB-mo (35%). |
