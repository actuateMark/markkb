---
title: AP summary-send temporary disable — cross-repo plan
author: kb-bot
created: 2026-05-20
updated: 2026-05-20
tags: [autopatrol, vms-connector, autopatrol-server, immix, lifecycle, temporary-change]
---

# AP summary-send temporary disable — cross-repo plan

## Decision

Business decision: temporarily stop raising the per-camera `PATROL_SUMMARY` alert to Immix at the end of every AutoPatrol run. Summaries are still computed and persisted internally (DDB + S3). VCH, generic patrol, and main-run keepalives are untouched.

## Affected repos

| Repo | File | Change shape |
|---|---|---|
| `vms-connector` | `site_manager/connector/integrations/autopatrol_site_manager.py` | Add direct `end_patrol(...)` call. Comment out the final pre-handoff `self.keepalive()`. Keep SQS send, save-thread, billing emit, `keepalive_loop` daemon. |
| `autopatrol-server` | `server/autopatrol_queue.py` | Comment out both `self.keepalive(...)` calls (lines 86-89, 104-107) and the `raise_patrol_alert` loop (lines 130-153). Keep S3 saves, `summary()` → handler/DDB writes, the trailing `end_patrol`. |
| `autopatrol-server` | `server/dead_letter_queue.py` | **Open question** — symmetry says yes, but DLQ-only. |

## Current lifecycle (annotated)

```
vms-connector AutoPatrolSiteManager.run()
  start_patrol(STARTED)
  keepalive_loop daemon ─ every 55s, runs whole job  ← keep
  camera batches (the work)
  AutoPatrolDAO.save_patrol_result thread
  self.keepalive()                                    ← REMOVE (pre-handoff ping)
  sqs.send_message(autopatrol_jobs.fifo)              ← keep (handoff)
  _send_site_product_ended_events()                   ← keep (billing invariant)
  exit(0)
                                  │ (SQS)
                                  ▼
autopatrol-server AutoPatrolQueueConsumer.action()
  self.keepalive(...)             ← REMOVE (pre-summary)
  save_message_to_s3              ← keep
  summary() → AutoPatrolHandler.run() → DDB/S3 writes  ← keep
  self.keepalive(...)             ← REMOVE (post-summary, pre-Immix)
  save_patrol_to_s3               ← keep
  for camera: raise_patrol_alert(PATROL_SUMMARY)       ← REMOVE (Immix raise)
  end_patrol(FINISHED)            ← keep
```

## The Failed-status caveat

A standing in-code comment at `server/autopatrol_queue.py:122-128` warns that **without** at least one `raise_patrol_alert`, Immix's response to `update_patrol(Finished)` returns `patrolStatus=Failed`. The "always emit per-camera PATROL_SUMMARY before end_patrol" pattern was added precisely to avoid this (PR #23, see [[2026-05-06_cohort-f-investigation]] adjacent context).

Disabling the raise means **every patrol will look Failed on Immix's side** for the duration of this temporary change. The user's framing — "just end the patrol early for immix" — sounds like an explicit acceptance of this, but worth confirming before we ship.

## "End the patrol early" — two interpretations

The user said: *"Add the 'end patrol' call to the [[vms-connector|vms connector]] ... We will write the summaries internally ONLY, and just end the patrol early for immix."*

Two possible placements for the new connector-side `end_patrol`:

**A. Before the SQS send.** Immix sees FINISHED status the moment cameras stop, with no waiting for autopatrol-server to consume + process. The autopatrol-server's trailing `end_patrol` becomes a duplicate (idempotent — both just `update_patrol(FINISHED)`).

**B. After the SQS send (before/after billing emit).** Roughly the same end-state from Immix's POV, but with a few seconds' gap while the SQS message is in flight. No real benefit vs A.

Interpretation A matches "early" better. Plan assumes A unless told otherwise.

## Dashboard / signal impact

Once deployed, fleet-wide:
- `autopatrol_server_patrol_summary_rate` → 0 (real, expected).
- Any signal counting `raise_patrol_alert` calls → 0.
- Immix-side patrol status counters likely shift toward Failed.

Suggest tagging these as `expected-zero until <date>` in the dashboard config rather than deleting — they auto-restore when the raise is re-enabled. Out of scope for the code PRs; track as a follow-up.

## Tests

No tests in either repo assert the Immix raise happens or that keepalive runs (verified via grep in `test_vms/` and `autopatrol-server/server/test_api.py`, etc.). No test changes required.

## Cross-repo coordination

Two PRs. **Connector MUST merge first.** Corrected 2026-05-21 from earlier wrong reasoning.

| Order | Connector window state | Server window state | `end_patrol` fires per run | `raise_patrol_alert` per run | Verdict |
|---|---|---|---|---|---|
| **Connector first (correct)** | new: calls `end_patrol` pre-SQS | old: still raises + calls own `end_patrol` | 2 (both idempotent) | normal | safe — overlap, no gap |
| **Server first (wrong)** | old: doesn't call `end_patrol` | new: doesn't raise + doesn't call `end_patrol` | **0** | 0 | **broken** — patrols never transition to FINISHED until connector lands |

Order:

1. **vms-connector `feat/ap-disable-summary-send` → `stage`** first. Connector starts calling `end_patrol` itself. Server's redundant `end_patrol` is harmless until the next step.
2. **autopatrol-server `feat/disable-summary-immix-raise` → `main`** second. Server stops raising + stops its own `end_patrol`. Now the connector's `end_patrol` is the only one.

The cross-repo failure mode (server-first → no `end_patrol` at all) is the textbook case for transition-window analysis: when one repo drops a behavior and another picks it up, **the picker-up has to deploy first**.

## Decisions (resolved 2026-05-20)

1. ~~Failed-status acceptable?~~ — Ignored. Immix side is fixing it. Not our concern.
2. ~~`end_patrol` placement?~~ — **Before the SQS send.** Immix sees FINISHED immediately; autopatrol-server hand-off is unchanged.
3. ~~DLQ handler?~~ — **Yes**, comment out both `raise_patrol_alert` AND `end_patrol` in `dead_letter_queue.py`. No raises from the summary service at all.
4. ~~Keep `end_patrol` in autopatrol-server?~~ — **No.** Commented out from `autopatrol_queue.py` and `dead_letter_queue.py`. Connector owns the FINISHED transition.
5. ~~Reversal artifact?~~ — Comment-block markers (`# --- begin disabled ... ---`).
6. ~~Branches?~~ — vms-connector: `feat/ap-disable-summary-send` off `stage` (PR target `stage`). autopatrol-server: `feat/disable-summary-immix-raise` off `main` (PR target `main`).

## Final state (applied)

**vms-connector** `site_manager/connector/integrations/autopatrol_site_manager.py`:
- L199 `self.keepalive()` commented (pre-SQS keepalive removed).
- New `try: self.autopatrol_api.end_patrol(tenant_id, patrol_id) except` block inserted **before** the SQS send.
- Everything else (`keepalive_loop` daemon, save thread, SQS send, billing emit) untouched.

**autopatrol-server** `server/autopatrol_queue.py`:
- Both `self.keepalive(...)` blocks commented out (lines that were 86-89 and 104-107).
- Entire `try:` block (lines that were 117-165) commented out — covers per-camera `raise_patrol_alert` loop AND `api.end_patrol(...)`.
- S3 saves at lines 91-98 and 109-115 and `summary()` call intact.

**autopatrol-server** `server/dead_letter_queue.py`:
- Both `try:` blocks (lines that were 45-57 and 59-67) commented out — `raise_patrol_alert` AND `end_patrol`.
- `api = self._get_patrol_api(patrol_data)` kept with `# noqa: F841` so re-enable is a pure uncomment.

**Tests:** existing `test_vms/test_billing_emit_on_early_exit.py` (16 tests) passes. No autopatrol-server tests reference the disabled call sites.

**End-to-end validation:** PASSED 2026-05-20 via the [[2026-05-20_local-ap-e2e-stack-installed|local-test-stack]] harness. Recordings confirm exactly one `end_patrol` from the connector (pre-SQS-send), zero `raise_patrol_alert` calls, zero `end_patrol`/`keepalive` calls from autopatrol-server. Summary still written to `s3://autopatrol-patrols/`.

## Cross-refs

- [[autopatrol-server]]
- [[autopatrol-cleanup-lambda]]
- [[2026-05-14_autopatrol-tier-model-and-detection-types]]
