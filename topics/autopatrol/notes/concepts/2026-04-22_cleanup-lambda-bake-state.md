---
title: "Cleanup-Lambda Stage Bake State — 2026-04-22"
type: concept
topic: autopatrol
tags: [autopatrol, cleanup-lambda, stage-bake, iac-drift, ddb, step-e-readiness, historical]
jira: "ENG-166"
created: 2026-04-22
updated: 2026-04-23
author: kb-bot
status: superseded
outgoing:
  - topics/autopatrol/notes/concepts/2026-04-23_cleanup-rollout-day.md
  - topics/operational-health/notes/syntheses/2026-04-23_overnight-check.md
  - topics/personal-notes/notes/daily/2026-04-22.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/autopatrol/notes/concepts/2026-04-23_cleanup-rollout-day.md
  - topics/autopatrol/notes/syntheses/2026-05-07_cleanup-lambda-state-matrix-verify.md
  - topics/offboarding/notes/concepts/2026-06-23_autopatrol-handoff.md
  - topics/operational-health/notes/syntheses/2026-04-23_overnight-check.md
  - topics/personal-notes/notes/daily/2026-04-22.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-24
---

> **Superseded 2026-04-23.** Step E.2 has happened: `CLEANUP_ENABLED=true` flipped at 17:59Z and `CLEANUP_TARGET_HOURS` lowered 48→18 at 18:12Z. For live state see [[autopatrol-cleanup-lambda]] entity. For 2026-04-23 incident + rollout changes see [[2026-04-23_postmortem-onboarder-healthcheck]].

# Cleanup-Lambda Stage Bake State — 2026-04-22 (historical)

Snapshot of the AutoPatrol stale-schedule cleanup Lambda stage-bake state as of 2026-04-22T14:30Z, ~37 hours after first counter rows were recorded (2026-04-21T00:04Z earliest `first_failure_at`). Written to document (a) DDB counter progression, (b) architectural facts surfaced by the morning fan-out, and (c) the Step E flip-readiness decision posture.

Pairs with [[2026-04-17_stale-schedule-cleanup-design]] (load-bearing design synthesis) and [[autopatrol-cleanup-lambda]] (entity page).

## 1. DDB counter state (us-west-2, acct 388576304176)

Queried via `AWS_PROFILE=prod aws dynamodb scan --table-name autopatrol_cleanup_counters-dev --region us-west-2` at 2026-04-22T14:30Z.

**5 rows, same `schedule_id`s as the 2026-04-21T16:15Z baseline.** Counters advancing at the expected 6-hour cadence (4 ticks per row in the ~24h interval). No new sites entered terminal-exit state during the observation window.

| `admin_pk` | type | yesterday | today | progress | last tick (UTC) | `schedule_id` (first 8) |
|------------|------|-----------|-------|----------|-----------------|-------------------------|
| 138 | patrol_exit | 3/8 | **7/8** | 87.5% | 12:04Z | `ee1822f1` |
| 223 | patrol_exit | 3/8 | **7/8** | 87.5% | 13:56Z | `c3808175` |
| 235 | patrol_exit | 3/8 | **7/8** | 87.5% | 13:09Z | `636be1ba` |
| 159 | patrol_exit | 3/8 | 6/8     | 75%   | 09:40Z | `fbdfdba6` |
| 234 | site_disabled | 3/56 | 7/56 | 12.5% | 12:38Z | `1e2ee05f` |

**Row semantics:**
- `patrol_exit` rows use generic field names (`count`, `threshold`, `first_failure_at`, `last_failure_at`) and have the tighter 8-tick / 48-hour threshold (cadence 6h × 8 = 48h). Cleanup-Lambda soft-disables when `count >= threshold`.
- `site_disabled` rows use type-qualified field names (`count_site_disabled`, `threshold_site_disabled`, `first_site_disabled_at`, `last_site_disabled_at`) and have the 56-tick / 14-day threshold (cadence 6h × 56 = 336h / 14d). The longer window reflects that `SiteDisabledOrDisarmed` can be legitimately transient (a site armed only during business hours should not be soft-deleted after 48 hours of being disarmed).
- TTL values are Unix-epoch seconds; next TTL-expiry on the closest row (admin_pk 223) is 2026-05-22T02:36Z — well beyond the 1-week bake.

**Predicted first threshold crossings (with `CLEANUP_ENABLED=false`):**

| `admin_pk` | last tick | next tick (6h) | becomes |
|------------|-----------|----------------|---------|
| 138 | 12:04Z | **~18:04Z tonight** | 8/8 |
| 235 | 13:09Z | ~19:09Z | 8/8 |
| 223 | 13:56Z | ~19:56Z | 8/8 |
| 159 | 09:40Z | ~21:40Z (tomorrow) | 7/8 |

With flag `false`: Lambda should log `threshold reached but CLEANUP_ENABLED=false, skipping disable` (or equivalent), reset the row's TTL, and continue observing. With flag `true`: Lambda calls Immix `get_patrol_stream` / equivalent, confirms 404 / DEACTIVATED, PATCHes `actuate_admin` to set `is_deleted=True` + provenance fields (`disabled_by=cleanup_lambda`, `disabled_at`, `disable_reason`).

## 2. Architectural clarification — emit source

Morning fan-out via [[agent-nrql-investigator]] on `cluster_name='Connector-EKS'` revealed that the SQS emit to `autopatrol_stale_schedule_cleanup_dev.fifo` **does not come from the main `vms-connector` pod.** Source containers match the pattern `connector-{site_id}-vch-{n}-chm-cronjob` — i.e. the per-site CHM cronjob pods, which is where the terminal "no patrols to run, exiting" path actually executes.

**Why this matters:** future debugging along the lines of "why isn't site X emitting to the cleanup queue?" will look in the wrong pod unless this is documented. NR query template that works:

```sql
FROM Log SELECT count(*) 
WHERE cluster_name='Connector-EKS' 
  AND container_name LIKE 'connector-%-chm-cronjob'
  AND message LIKE '%stale_schedule_cleanup%' 
SINCE 24 hours ago
FACET container_name
```

Not `container_name='vms-connector'` as one might reflexively reach for.

**Impact on §3 emit-helper wiring (from [[2026-04-17_no-patrols-emit-points]]):** the `cleanup_emitter.py` logic is imported into the CHM cronjob entry point, not the long-running vms-connector pod. This is the correct design — the terminal-exit path only executes in the cronjob — but it wasn't explicitly called out in the design synthesis or emit-points note.

## 3. IaC drift — all infra is CLI-provisioned in prod/us-west-2

Until 2026-04-22, mark-todos §3 rollout tracking showed Step C (`ds-terraform-eks-v2#69`) as open and targeting dev/EU. Morning fan-out surfaced that **the PR is documentation-only** — see the PR body update dated 2026-04-21:

> When this PR was written, it assumed the cleanup Lambda infra would live in dev/EU. That was wrong: **the cleanup Lambda runs in the prod account (`388576304176`) / `us-west-2`** because stage pods are deployed there and the existing `autopatrol_jobs*.fifo` queues live there.

**All 11 resources are CLI-provisioned** in prod/us-west-2. Inventory (from PR #69 body):

| Resource | Identifier |
|---|---|
| Stage queue | `arn:aws:sqs:us-west-2:388576304176:autopatrol_stale_schedule_cleanup_dev.fifo` |
| Stage DLQ | `arn:aws:sqs:us-west-2:388576304176:autopatrol_stale_schedule_cleanup_dlq_dev.fifo` |
| Prod queue | `arn:aws:sqs:us-west-2:388576304176:autopatrol_stale_schedule_cleanup.fifo` |
| Prod DLQ | `arn:aws:sqs:us-west-2:388576304176:autopatrol_stale_schedule_cleanup_dlq.fifo` |
| Counter table | `autopatrol_cleanup_counters-dev` (shared stage+prod by design; UUID keys prevent collision) |
| Cleanup Lambda | `immix-autopatrol-schedule-cleanup` (event source mappings to both queues) |
| Reenable Lambda | `immix-autopatrol-schedule-reenable` (IAM-auth'd Function URL) |
| Cleanup IAM role | `immix-autopatrol-schedule-cleanup-role` |
| Reenable IAM role | `immix-autopatrol-schedule-reenable-role` |
| Stage DLQ alarm | `autopatrol-cleanup-dlq-has-messages-dev` |
| Prod DLQ alarm | `autopatrol-cleanup-dlq-has-messages-prod` |

**PR #69 is kept open as a reference document**, not meant to merge; title is prefixed `[DOCS-ONLY / WRONG LOCATION]`.

**Drift consequences:**
- No atomic rollback via `terragrunt destroy`.
- Resource changes (e.g. memory/timeout bumps, IAM tightening, adding alarms) have to happen via console/CLI and get documented post-hoc.
- Onboarding new team members to operate the Lambda requires handing them the resource-inventory table rather than a terraform stage.
- Two mark-todos Not-Yet-Prioritized items (`dev/eu-west-1/dynamodb` "0 to add" bug, `dev/eu-west-1/core-lambdas` var-name mismatch) are now superseded — those blockers targeted a dev/EU deploy that will never happen.

**Port-to-terraform workstream** (documented in §3 Not-Yet-Prioritized): rewrite stanzas under `stages/prod/us-west-2/`, extend `modules/dynamodb` for per-table TTL support, extend `core-lambdas` for Function URL support (or use direct resource), `terraform import` each existing resource. Substantial PR — deferred until Step F (prod US) rollout forces the issue or until someone has a free afternoon.

## 4. §3 rollout state — further along than tracked

Fan-out also surfaced that three of the four §3 rollout PRs have **already merged**, not just "open for stage rollout" as mark-todos showed:

| Step | PR | Status | Notes |
|------|----|--------|-------|
| A | [vms-connector#1657](https://github.com/aegissystems/vms-connector/pull/1657) | MERGED 2026-04-20 | Stage emit confirmed healthy |
| B | [actuate_admin#2361](https://github.com/aegissystems/actuate_admin/pull/2361) | MERGED 2026-04-20 | Provenance fields + scheduleId filter live |
| C | [ds-terraform-eks-v2#69](https://github.com/aegissystems/ds-terraform-eks-v2/pull/69) | OPEN, docs-only | Real infra CLI-provisioned (see §3 above) |
| D | [autopatrol_onboarder#3](https://github.com/aegissystems/autopatrol_onboarder/pull/3) | MERGED 2026-04-21T16:20Z | **Merged despite title "STAGE BAKE ONLY — DO NOT MERGE YET" and `CHANGES_REQUESTED` review** |
| E | flip `CLEANUP_ENABLED=true` on stage | pending | Gated on D merge-legitimacy confirmation |
| F | prod US rollout | pending | Gated on Step E 1-week bake |

**Step D merge-legitimacy question:** was the merge intentional (decision to ship code with flag off early, effectively making E a pure flag-flip rather than a code-deploy)? Or accidental (the "DO NOT MERGE YET" title suggests so)? Not resolvable from this session's context — needs the cleanup-lambda session's memory. Captured as a Not-Yet-Prioritized follow-up in [[mark-todos]].

## 5. Step E flip-readiness

**System is observably healthy and predictable.**

Arguments in favor of flipping `CLEANUP_ENABLED=true` tonight:
- Counters advance at expected cadence (exactly 6h per tick, across 37h × 5 rows × 4 ticks — zero missed ticks).
- Counter set is deterministic — same 5 schedule_ids 2026-04-21 → 2026-04-22; no runaway accumulation, no new terminal-exit sites.
- First real threshold cross is imminent (~18:04Z tonight for admin_pk 138); flipping now means the first real disable-attempt happens inside the bake window rather than on a fresh flip-day.
- 1-week bake from a tonight-flip ends ~2026-04-29 — aligns well with week-2 Step F scheduling.
- NR-level validation: the "threshold reached, skipping because CLEANUP_ENABLED=false" log line has not yet been observed (can't validate until a threshold actually crosses). Flipping captures this validation implicitly in the first real disable.

Arguments against:
- **Step D merge legitimacy unresolved.** If the merge was accidental and a hot-fix revert or follow-up PR is expected, flipping now could land on top of an in-progress code change.
- Without confirmation that the `CLEANUP_ENABLED=false` gate is actually consulted correctly (vs hardcoded at deploy time), flipping moves from "verified observer" to "hopefully a disabler" in a single step.

**Recommended sequence:**

1. Confirm Step D intent with cleanup-lambda session owner.
2. Grep NR tonight ~18:04Z for the threshold-crossed log line at flag-off state (validates the gate wiring even if we don't flip).
3. If D confirmed intentional + gate log observed correctly: flip early tomorrow morning, 1-week bake ends 2026-04-30. Cleanest.
4. If D confirmed intentional + gate log NOT observed: investigate gate wiring before flip.
5. If D was accidental: coordinate with cleanup-lambda session on whether to revert + reland.

**Not blocking from this session:** the cleanup-lambda session appears to own Steps C / D / E / F end-to-end; this session's role was to provide a snapshot + analysis. Handoff to that session for the actual flip decision.

## Related

- [[2026-04-17_stale-schedule-cleanup-design]] — load-bearing design synthesis
- [[autopatrol-cleanup-lambda]] — entity page
- [[2026-04-17_no-patrols-emit-points]] — emit-helper wiring (CHM cronjob context)
- [[2026-04-20_lambda-creation-and-tuning-playbook]] — post-hoc lambda build/tune recipe (should be cross-linked from §3 Related)
- [[autopatrol-onboarder]] — sibling Lambda entity
- [[mark-todos]] §3 — workstream tracker + Not-Yet-Prioritized follow-ups
- PR references: [vms-connector#1657](https://github.com/aegissystems/vms-connector/pull/1657), [actuate_admin#2361](https://github.com/aegissystems/actuate_admin/pull/2361), [autopatrol_onboarder#3](https://github.com/aegissystems/autopatrol_onboarder/pull/3), [ds-terraform-eks-v2#69](https://github.com/aegissystems/ds-terraform-eks-v2/pull/69)
