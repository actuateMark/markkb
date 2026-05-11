---
title: "stream_id history tracking and fallback iteration (Immix session refresh bug)"
type: concept
topic: vms-connector
tags: [bugfix, autopatrol, vch, immix, stream_id, patrol-api, websocket, immix, immix, immix, immix]
jira: ""
created: 2026-05-06
updated: 2026-05-06
author: kb-bot
outgoing:
  - topics/actuate-libraries/_summary.md
  - topics/personal-notes/notes/daily/2026-05-06.md
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/autopatrol/notes/data/2026-05-06_immix-streamfinished-inquiry.md
  - topics/autopatrol/notes/entities/immix-vendor-api.md
  - topics/autopatrol/notes/syntheses/2026-05-07_consumer-side-websocket-close-feasibility.md
  - topics/personal-notes/notes/daily/2026-05-06.md
incoming_updated: 2026-05-08
---

# stream_id history tracking and fallback iteration

Deployed fix for a critical Immix alert-dispatch gap where `AutopatrolWebSocketStreamPuller.consume_stream` lost track of the correct `stream_id` after WebSocket reconnect, causing `vch_alert_sender` to dispatch alerts with stale session identifiers that Immix silently rejected. The fix introduced a **stream_id history list** in the library and **fallback iteration** in the connector, so failed raises iterate backwards through all allocated sessions until one succeeds.

## The Bug

When `consume_stream`'s retry loop encountered a `ConnectionClosed` exception mid-run, it called `get_patrol_stream` again to obtain a fresh WebSocket URL. Each call to `get_patrol_stream` allocates a **new server-side session** on Immix with a **new `deviceStreamId`**. The recovery path captured the new `self.url` but left `self.stream_id` pinned to the original session's ID.

By the time a connect-failure raised, `self.url` and `self.stream_id` referred to **different** Immix sessions. When `raise_patrol_alert` was called with the original (now-orphaned) `stream_id`, Immix returned **HTTP 400 `$.streamId cannot convert to System.Guid`** — the same error class as the [[2026-04-20_streamid-null-patrol-alert-bug|null-streamId bug in GH#1656]], but with a fabricated-looking GUID instead of null.

The `vch_alert_sender.raise_alert` try/except swallowed the exception, so the failure was invisible from the outside: 3 connection attempts logged, no raise visibly failed. The audit trail still wrote locally (so forensics could recover the intent), but Immix never received the alert.

## The Fix

### Library Side: `actuate-pullers` 1.17.17

**History list replaces single value:**
- Replaced `self.stream_id = None` (single immutable value) with `self._stream_ids: list = []` (newest-first history)
- `stream_id` is now a `@property` reading `_stream_ids[0]` for back-compat with all external readers (7 confirmed: vms-connector + sibling libraries)
- Setter retained for the local-mode shim that assigns `puller.stream_id = 0`
- New `stream_ids` property exposes the full history as a copy-on-read

**Recording and reset:**
- New `_record_stream_id(sid)` helper prepends to history, deduplicates adjacent repeats, ignores falsy ids
- `init_stream()` resets the history at the top of each run (fresh-run semantics)

**Atomic updates on reconnect:**
- `consume_stream`'s `ConnectionClosed` recovery path now captures **both** `deviceStreamUrl` and `deviceStreamId` from the same response body in one operation
- No opportunity for drift: a single `get_patrol_stream` response populates both fields together

### Connector Side: `vms-connector` PR #1677

**Fallback iteration helpers:**
- New `_candidate_stream_ids(puller)` returns the full history list; falls back to `[puller.stream_id]` for older puller versions or non-autopatrol pullers (back-compat bridge)
- New `_raise_with_stream_id_fallback(detection_code, candidates, ...)` iterates candidates newest→oldest, calling `raise_patrol_alert` per candidate, stopping on first 2xx
  - Exhaustion path logs: `raise_patrol_alert {detection_code} exhausted all N stream_id candidates`
  - Successful-on-fallback path logs: `succeeded on stream_id candidate #N` — **money signal** for stage observation
- Both `send_vch_failed` and `raise_alert` rewritten to use the helper

**Invariants preserved:**
- Local `save_chm_issue` audit trail still fires regardless of Immix outcome (GH#1656 invariant)
- Graceful skip-on-exception if `raise_patrol_alert` throws (network, auth, Immix unavailable)

## Test Coverage

**Library:** 16 tests in `actuate-pullers/tests/test_autopatrol_stream_id_history.py`
- 12 unit tests on history mechanics: append, dedupe, reset, property access
- 4 integration tests driving real `init_stream()` + `ConnectionClosed`-refresh sequencing against mocked `autopatrol_api`

**Connector:** 12 tests in `test_vms/test_streamid_null_guard.py`
- 6 original guard tests preserved (back-compat validation)
- 6 new in `TestStreamIdFallbackIteration`: succeeds-on-first, falls-through on 4xx, exhausts all, exception-skip, `send_vch_failed` iteration, single-id back-compat

Full suite: 168 passed, 1 skipped on merged stage tree (2026-05-06).

## Rollout

| Step | Component | PR | Merge | Notes |
|---|---|---|---|---|
| Library publish | [[actuate-pullers]] | #344 | 2026-05-06T18:54Z | Squash body had `[no ci]` leak; Publish Stable silenced |
| Library backfill | [[actuate-pullers]] main | commit `3de7c30b` | 2026-05-06T19:07Z | Clean `[patch:actuate-pullers]` body re-triggered CI |
| Connector merge | vms-connector | #1677 | 2026-05-06T19:14Z, commit `3ee84734f` | Merged to stage; monitoring for `succeeded on stream_id candidate` log line |

## Related

- [[2026-04-20_streamid-null-patrol-alert-bug]] — precursor: GH#1656 null-streamId guard, first defense
- [[2026-05-06_immix-streamfailed-worker-lifespan]] — synthesis capturing the broader Immix surface and worker lifecycle implications
- `vms-connector/healthcheck/alerts/senders/vch_alert_sender.py` — modified `raise_alert` + `send_vch_failed`
- `actuate-pullers/socket/autopatrol_websocket_stream_puller.py` — `consume_stream`, `_record_stream_id`, `stream_ids` property
