---
title: "PR #1731 — AutoPatrol-to-prod promotion review"
type: synthesis
topic: vms-connector
tags: [vms-connector, autopatrol, release, pyav, promotion, tier, streaming, envera, billing, ffmpeg]
jira: "ENG-352, BT-1049"
created: 2026-06-15
updated: 2026-06-15
author: kb-bot
incoming:
  - topics/engineering-process/notes/concepts/2026-06-16_squash-merge-ci-skip-suppression-recurrence.md
  - topics/personal-notes/notes/daily/2026-06-15.md
  - topics/personal-notes/notes/daily/2026-06-16.md
incoming_updated: 2026-06-24
---

# PR #1731 — AutoPatrol-to-prod promotion review

**Decision made 2026-06-15:** ship PR #1731 stage→rearchitecture **as-is**, rolling the remaining AutoPatrol work to production with the full training train. Rationale: the train is promotable (clean soak + green CI + no code-review blockers); shipping AP on the same branch preserves the whole-branch convention and avoids isolated re-validation.

## The Question

How to get the remaining AutoPatrol work to production? The work spans seven themes (tier refinement, end_patrol, stream-listener exclusion, metrics guard, Envera handling, publish-on-demand streaming, WindowIdsV2 TTL) across 50 files, +6358−718 in PR #1731, a large feature train off `stage`. vms-connector promotes stage→rarch as a single squash merge, so AutoPatrol can't be trivially split out into a separate path.

## Pending AutoPatrol Slice (prod-ready)

All validated on stage; no urgent customer impact (first tier fix [[2026-06-09]] shipped to prod via #1729):

- **ENG-352 per-camera tier refinement** (#1733, first tier fix dependency) — refines tier computation to camera-level (not schedule-level) with improved crowd detection (crowd ≠ Tier 3, crowd uses school_bus logic). Integrated into tier-calculation site manager and autopatrol_camera classes.
- **#1709 connector-side end_patrol** — closes detection window during `endrun()` with proper observer/tracker cleanup and idempotent re-entry guard.
- **#1712 ap-empty-metrics WARN guard** — produces WARN when patrol metrics are empty (observability for stuck/zero-emit conditions).
- **Autopatrol/VCH stream-listener exclusion** — AutoPatrol stream-listener routes only AP messages; VCH routes VCH messages; mutual exclusion via routed mp.Queue key.
- **[[actuate-daos]] WindowIdsV2 flat-60-day TTL** — simplifies retention from per-product to fleet-wide 60-day shelf-life.

## Options Considered

1. **Ship as-is** ← CHOSEN. Train is itself promotable; AP rides along; no splitting friction.
2. **Split AP onto separate rarch branch.** Deviate from whole-branch convention; isolated re-validation cost; no urgent driver.
3. **Hold AP pending something else.** No blockers; first tier fix in prod; nothing unblocked by holding.

**Decision: Option 1.** The train passed clean soak (weekend 2026-06-12→06-15), green CI, zero code-review blockers. Fork-safety verified (memory-cleanup thread moved __init__→run; streaming/Envera listeners start in parent, route via fork-crossing mp.Queue proxies — same topology as motion queue, validated by test_fork_safety.py + test_motion_queue_fork.py). Billing lifecycle untouched (tier changes only affect alert tier value, not site_product_ended emission calls). Streaming env gate is fail-closed (3 required vars, no defaults; EU bounded degradation via test_publish_on_demand_env_gate.py).

## Soak Evidence (2026-06-12 → 2026-06-15)

Weekend validation — clean fleet signal:

- **AmeriGas 41399** (PyAV17/[[ffmpeg-entity|FFmpeg]] 8.1.1 ARM wheel, [[h265-hevc-deep-dive|HEVC]] anchor) — **0 ERRORs, 0 AVDiscard starvation events, RSS ~75MB/camera, restartCount=0**. Corruption signal still live (pre-2026-05-19 baseline ~28 reconnects/4h); no gray-frame misses. Leg-2 of the PyAV17 bump A/B.
- **connector-16851** (publish-on-demand streaming, new feature) — clean init, no MediaMTX/SQS failures, pod lifecycle steady.
- **connector-47873** (Envera Eagle Eye, shard-safe state attaching every boot) — outcome 200s, no hangs or state-corruption edge cases.
- **General fleet** — all errors pre-existing device issues (dead Exacq at 209.171.216.141; connector-44300-fs S3-settings crash-loop, pre-existing).
- **CI green** on stage tip 756b8a48 (Python tests + uv.lock diff + ECR ARM64+x86 build).

## Code Review Signal

Zero blockers. Fork-safety verified in detail:

- **Streaming listeners** (`StreamSignalSQSListener.run()`, `Envera.listener_thread()`) start during parent's `__init__`, **after** process-fork point — they inherit file handles and use mp.Queue/mp.Manager proxies (cross-process-safe). Same topology as motion-queue (tested by `test_motion_queue_fork.py`).
- **Memory cleanup thread** moved from __init__ → run() (post-fork), so signal handler in child can call it during shutdown (no double-signal races).
- **Billing lifecycle** — AP changes only modify tier value (alert-tier field on alarm). site_product_ended emission path unchanged; conditional guard on tier remains intact.
- **Streaming fail-closed** — 3 env vars (S3_STREAMING_BUCKET, STREAMING_PUBLISHER_TOKEN, AWS_REGION_STREAMING) with no defaults; missing any one → streaming disabled (test_publish_on_demand_env_gate.py validates this). EU region has bounded degradation (S3 region optional, defaults to conn region).
- **Sibling handoff correct** — StreamSignalSQSListener.run() deletes only the routed messages it processes; DynamoDB lease is the source of truth for message ownership.
- **Nits** (non-blockers, fixable post-merge or in follow-up):
  - Redundant `start_stream_signal_listener()` call in local branch (cosmetic).
  - `strip_sha_challenge()` assumes single recv (works for Envera webhook, but document the assumption).
  - Envera intruder-svc URL hardcoded to prod (should be config-driven for test sites).
  - Lazy imports inside Envera methods (avoidable refactor).

## The #367 Guard Gap (resolved as non-blocker)

**Question:** actuate-libraries #367 (PyAV17 followups — AVDiscard anti-thrash, stale-preview guard) is OPEN/CONFLICTING, NOT in the pinned pullers 1.20.3. Friday's note flagged this as a risk.

**Resolution:** Moot. [[ffmpeg-entity|FFmpeg]] 8.1.1 sets `AV_FRAME_FLAG_CORRUPT` natively (closes [[ffmpeg-entity|FFmpeg]] upstream #9805), and the weekend soak showed **zero starvation or gray-frame events**. The guards in #367 (C1 hysteresis, stale-preview WARN) are hardening measures, not blockers. #367 should be reconciled separately (71 commits behind main); re-base + merge in parallel track, bump pullers pin 1.20.3 → ~1.21 before fleet rollout to pick up the guards. **Not blocking stage→rarch promotion.**

## Cross-Repo Ordering: actuate_admin #2506

`actuate_admin` PR #2506 (remove vestigial AutoPatrolSchedule.tier field) is **decoupled from this train** — the connector never read schedule-level tier. Tier is computed per-camera at runtime (autopatrol_camera.py:163, autopatrol_site_manager.py:297). No transition-window constraint.

**Plan:** Land #2506 independently post-merge; re-run `makemigrations --check` at merge (migrations 0557/0556 must be tip); admin main = prod.

## Path to Production

1. ✅ **Soak confirmed** — comment posted to PR with fleet signal; weekend clean.
2. **In progress** — flip #1731 out of draft + obtain review/approval.
3. **Merge cleanup** — squash body must strip library-report bot bookkeeping commit lines (auto-generated `Bump versions for:` lines) and any CI-skip markers (GitHub Actions scans ENTIRE message and aborts all workflows if found anywhere). Keep the `[patch:vms-connector]` bump tag.
4. **Post-merge** — Envera cutover (scale master→0, scale rarch up, 60s queue retention bounds the dispatch gap).
5. **Observability** — run `/post-deploy-monitor` + schedule `/overnight-logs`.
6. **Sequels** — separately land #2506 (admin tier field removal); rebase + reconcile #367 (pullers guards).

## Related

- [[2026-06-02_handoff-pyav17-corner-case-plan]] — PyAV17 bump train + guards (parent context for #1714/#367)
- [[feedback_autopatrol_tier_mapping|tier-mapping reference]] — Authoritative tier code→tier lookup (crowd ≠ Tier 3)
- [[project_chm_streams_sites_on_stage]] — Stream-listener topology & sibling handoff patterns
- mark-todos § "Promotion: #1731 AP + streaming + PyAV17 train" (workstream context)
