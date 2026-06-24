---
title: AIT / brain-in-jar ↔ Watch Management Service — Integration Plan
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: engineering-process
type: synthesis
tags:
  - watchman
  - fleet-architecture
  - manager-service
  - ait
  - brain-in-jar
  - hypothesis
  - testing
  - instrumentation
related:
  - "[[topics/engineering-process/notes/syntheses/2026-05-20_ait-brain-in-jar-spec]]"
  - "[[topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff]]"
  - "[[2026-05-21_hypothesis-in-actuate]]"
  - "[[topics/engineering-process/notes/syntheses/2026-05-21_ait-phase-11-simulate]]"
  - "[[2026-05-28_watch-management-service-design]]"
  - "[[2026-05-29_watch-manager-observability]]"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/manager-touchpoint-catalog.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-observability.md
  - topics/watchman/notes/concepts/calendar-set.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
incoming_updated: 2026-05-30
---

# AIT / brain-in-jar ↔ Watch Management Service — Integration Plan

## TL;DR

AIT today ships five working primitives — IDP/PDP/WDP serializers + Hypothesis [[strategies]] (`actuate-pipeline-objects/testing/`), `DumpReplayPuller` (`actuate-pullers`), pipeline `replay` + `replay --step`, `AlertData` capture/replay, and `ait simulate` (synthetic IDPs with scenario CLI). These map onto Watch-Manager test needs **better than they map onto today's monolithic connector**, because the manager's schedule logic is a pure function of time + DB state (the brainstorm's Option B runner) — precisely the surface Hypothesis-driven property tests are built for. We can cover ~80% of the manager test surface today without Phase 8 (camera `from_dump`); F1–F9 land immediately. Phase 8 unlocks manager → pod integration replay.

## Inventory — what AIT/brain-in-jar provides today

Cited from [[2026-05-27_brain-in-jar-handoff]] and the per-phase syntheses.

| Primitive | Location | Status | Notes |
|---|---|---|---|
| IDP/PDP/WDP `to_dict`/`from_dict` | `actuate-pipeline-objects/.../brain_in_jar/` (`dd0542d6`) | Shipped (Phase 4) | Round-trips ~230 random packets in property tests |
| `data_dump` + sidecars + lazy loader | `actuate-instrumentation` (`48954367`) | Shipped (Phase 4) | JSON manifest + per-frame `.jpg` / `.npy` side-channel |
| `DataDumpLink` fix | `actuate-pipeline` (`50e961ba`) | Shipped (Phase 4) | Calls `to_dict()` correctly |
| `DumpReplayPuller` | `actuate-pullers/.../dump_replay/` (`78a46cf9`) | Shipped (Phase 5) | `BasePuller.push_frame` from dump |
| `MockStepRunner`/`MockPipelineRunner` integration | `actuate-pipeline`; AIT `replay_cli/` (`c91dcae`) | Shipped (Phase 6a/6b) | `ait replay <dump>` (inspect/diff) + `--step` |
| `AlertData.from_json` + `CapturingAlertSender` + `ReplaySender` | `actuate-alarm-senders/shared_alert/` (`e1c4bffe`); AIT `replay_alert_cli/` (`fde7b93`) | Shipped (Phase 7) | `ait replay-alert list/show/diff` |
| Hypothesis [[strategies]] | `actuate-pipeline-objects/testing/strategies.py` (`d0390952`) | Shipped (Phase 11) | `idp_strategy`, `pdp_strategy`, `wdp_strategy`, `alerting_idp_strategy` |
| Factories | `actuate-pipeline-objects/testing/factories.py` | Shipped (Phase 11) | `make_idp`, `make_pdp`, `make_wdp`, `make_alerting_window` |
| `ait simulate` CLI + scenarios | `actuate-integration-tools/.../simulate/` | Shipped (Phase 11) | 6 scenarios + `fuzz` |
| `ait validate <deployment_id>` | `.../validators/` | Shipped (Phase 2) | 9 invariants over admin settings |
| Camera `from_dump` | (sketched) | **Not shipped** (Phase 8) | Blocked on validator `MockDaoManager`/`MockImageCache` lift |
| Site dump + crash hook | (sketched, perf-discipline-reworked) | Not shipped (Phase 9) | Signal-based, off-by-default |
| S3 sink + `ait dumps` UX | (sketched) | Not shipped (Phase 10) | Needs `ds-terraform-eks-v2/modules/test-data-bucket/` |
| `ait sweep` | (sketched) | Not shipped (Phase 12) | Blocked on validator Plays A+B |

Five library commits sit on `feat/idp-serializer-brain-in-jar-phase-4`, **not pushed**.

## Mapping AIT primitives to manager-service test domains

| Manager test domain | Best AIT primitive(s) | Why it fits |
|---|---|---|
| Schedule evaluation determinism (Option B runner as a pure function) | Hypothesis [[strategies]] + factories (new: `watch_strategy`, `calendar_set_strategy`) | Schedule eval is `f(now, Watch, CalendarSet, ManualOverride) → armed: bool`. Pure function = property-testing's home ground. |
| Manual override TTL semantics | Hypothesis + `ManualOverride` factory; `RuleBasedStateMachine` for sequences | Constraint #10 in master design is exactly a stateful property bug. |
| DST / day-boundary transitions | Hypothesis with bounded-range time [[strategies]]; strategy parameterized over IANA zones | DST is the textbook "rare boundary; manual examples miss it" case. |
| Calendar-set composition (base + suppress stacking) | Hypothesis (compose `calendar_set_strategy(kind=base)` with `calendar_set_strategy(kind=suppress)`); [[shrinking]] finds minimal failing stack | Brainstorm calls out "suppress sets stack across Watches" — composition is what `@st.composite` is for. |
| K8s reconcile loop | Partial AIT fit. Desired-state derivation is pure-function (Hypothesis-testable). Actuator side needs a `CapturingDeployerClient` modeled after `CapturingAlertSender`. | Reconcile = observed vs. desired; brain-in-jar dump is the perfect snapshot of "observed state at moment X." |
| Billing-event lifecycle (`site_product_ended` exactly-once-per-(camera, product)) | `CapturingAlertSender` pattern + Hypothesis fuzzing of teardown ordering | Constraint #1 in master design. `VCHCamera._send_product_ended_events_once` is the canonical pattern. |
| Fork-safety verification | `fork-safety-check` agent in `.claude/agents/` — separate from AIT | Manager pods are reconciler-shape (no fork), so this mostly **doesn't apply** to the manager itself. |
| Manager → `connector_deployer` contract testing | `CapturingDeployerClient` (new); replay sender pattern for `POST /start`, `/stop`, `/chm` | Constraint #6 (no `/scale` endpoint) + slash-encode validation gotcha. |
| Manager → connector-pod signal handling (SIGTERM, graceful teardown timing) | **Phase 8 (`camera.from_dump`) would unlock**. Today: only `MockStepRunner` slice testable. | T13 needs end-to-end. Phase-8 dependency. |

## Specific test fixtures we can author today (Phase 8 absent)

| # | Fixture | Test type | AIT primitive | What it verifies | Complexity |
|---|---|---|---|---|---|
| F1 | `watch_strategy()` + `calendar_set_strategy()` + `manual_override_strategy()` in a new `actuate_watchman/testing/strategies.py` | Hypothesis composite | Phase 11 strategy template | Generators for the brainstorm's three core entities | S |
| F2 | `is_armed(watch, now)` property: armed(t) = base(t) ∧ ¬suppress(t) ∨ active_override(t) | Property | F1 + `@given` | Option B's "armed state is a pure function" | S |
| F3 | `evaluate_schedule_at(now)` round-trip across `to_dict`/`from_dict` | Property + serializer | Phase 4 template | Calendar-set persistence layer | S |
| F4 | `CapturingDeployerClient` recording every `start`/`stop`/`chm` call; never hits real deployer | Unit/integration | `CapturingAlertSender` template | Reconcile produces correct K8s mutations for arbitrary [[watch-entity|Watch]] states | M |
| F5 | `ManualOverrideStateMachine` (`RuleBasedStateMachine`): rules `apply_override`, `advance_time`, `tick_reconcile`, `revoke`; TTL invariants | Stateful property | [[stateful-testing]] | Constraint #10: manual disarm at 23:59 cannot block next-day arm | M |
| F6 | `simulate` scenario `arm_disarm_dance` — series of `(now, Watch, expected_armed)` fed through `evaluate(...)` | Scenario (mirrors `motion_signal_dance`) | AIT simulate scenario template | DST + suppress + manual-override interaction | M |
| F7 | `CapturingSQSConsumer` (or Kafka) recording every `site_product_started/_ended` envelope | Integration | `CapturingAlertSender` template | T17 — manager's billing-event subscription is the "did it run" oracle | M |
| F8 | Reconcile-loop replay: feed (observed K8s state, desired [[watch-entity|Watch]] state) into reconciler, assert mutations | Integration | Brain-in-jar dump format (Phase 4) repurposed | Manager reconcile is deterministic | L |
| F9 | DST fuzz: `@given(zone, year)` × spring-forward dates; assert no transition in missing hour | Property | F1 + bounded [[strategies]] | T3 — DST correctness | S |
| F10 | Connector-pod `endrun()` billing-emit test driven by `DumpReplayPuller` extended with manager-issued SIGTERM | Integration | Phase 5 puller | Constraint #1 exactly-once-emit under manager-induced shutdown | L |

## Manager-service instrumentation hooks (ranked by leverage)

Independent of AIT — what the manager itself needs to emit/expose. Top = highest leverage.

1. **Structured transition events** — every [[watch-entity|Watch]] state flip emits `{watch_id, from, to, cause, now, calendar_set_id, override_id|null, idempotency_key}` to a transitions topic (Kafka under [[watchman-repo|Watchman]], SNS today). Without this, F8 is impossible.
2. **Idempotency keys on every K8s mutation** — `{action, watch_id, image_tag, observed_generation}`. Replay-safety; constraint guard for no double create/delete.
3. **Reconcile-loop telemetry** — tick start/end timestamps, drift size, per-tick action count. Hypothesis can then assert "drift converges to zero within K ticks."
4. **Pure-function evaluation seam** — `evaluate_armed(now, watch, calendar_sets, overrides) -> bool` exposed as a top-level function with no side effects. F2/F9 target.
5. **State snapshot endpoint** — `GET /debug/state` returns serialized [[watch-entity|Watch]] + Override + CalendarSet domain. Equivalent to Phase 4's brain-in-jar dump for the manager.
6. **Dry-run flag** — `MANAGER_DRY_RUN=1` short-circuits at-init (Phase 7 discipline), making F4 trivial in CI without real K8s.
7. **SQS/Kafka observation log** — every `site_product_ended` observation to a local ring buffer with retention. F7 replay-assert without re-running connector pods.
8. **DST boundary observability** — log "DST transition detected: site=X, zone=Y, skipped_hour=02:00-03:00 on date Z." Feeds F9.
9. **Override-application audit trail** — every override logs `(watch_id, applied_at, expires_at, applied_by, reason)`. Constraint #10 regression detection.
10. **Reconcile-loop pause hook** — `MANAGER_PAUSE_RECONCILE=1` (env, off by default) freezes tick so tests can step deterministically. Mirrors AIT `replay --step`.
11. **Watch-state-as-resource** — [[watch-entity|Watch]] records as a K8s `CustomResource`. `kubectl get watches` is the observed-state source-of-truth for T5.
12. **Outcome attestation** — `(watch_id, run_id, actual_outcome)` after every connector pod terminates, with hash of the billing emit set. Single fact-line for "did this [[watch-entity|Watch]]'s run produce N billing events as expected?"

Hooks 1–4 unblock F2/F4/F8/F9. 5–6 nice-to-have. 7–12 forensic.

## Per-proposal testing fit

| Proposal | Natural AIT-driven surface | AIT leverage | Notes |
|---|---|---|---|
| A — Minimal Split | Per-site manager actuator (Django-Q rewrite); `CapturingDeployerClient` (F4) | Medium | Manager scope is smallest; AIT's connector-side replay more useful here. |
| B — Stage Fleets | Fleet-singleton manager publishing; **stage-fleet event-stream replay** | High | Capture once, replay against each fleet. |
| C — Camera-Worker | Assignment Controller IS manager; **bin-pack property tests** + assignment replay | High | Assignments are also pure functions; composable [[strategies]] extend cleanly. |
| D — Event-Driven | **Subject replay** is the natural fit. [[watch-entity|Watch]] state lives on a JetStream subject. | **Highest** | Brain-in-jar dump == JetStream subject snapshot. Phase 9 site-dump becomes "snapshot the relevant subject KV." |
| E — Hybrid Sidecar | Site Context IS manager; per-camera-group assignment replay | High | StatefulSet ordinal as the unit. |
| B′ — Stateless+Coordinator | FleetCoordinator state via Raft → **Raft log replay** | **Highest for correctness** | Raft-replicated tick makes Hypothesis properties provable, not just empirical. |

**Pattern.** Proposals with a built-in coordinator (C, E, B′) or message-bus contract (D) make brain-in-jar-style test capture trivial — the manager's state is already a serializable artifact.

## What Phase 8 would unlock (speculative)

- **End-to-end manager → pod integration tests on a laptop.**
- **Manager-issued SIGTERM regression tests** without spinning up K8s.
- **Cross-version replay** — capture on connector vX, replay on vY; surface drift the manager would otherwise inflict silently.
- **Validator dump-replay harness** (Play E from [[2026-05-21_ait-validator-dovetail]]).
- **Sharded teardown property** — ChunkedSiteManager parent + shard children reconstituted; manager-issued SIGTERM validates constraint #2.

Not a dependency for the bulk of the work above. F10 is the one fixture that materially benefits.

## Hypothesis properties to write today

New [[strategies]] in (e.g.) `actuate-watchman/src/.../testing/strategies.py`, mirroring `actuate-pipeline-objects/testing/strategies.py`:

- `watch_strategy()` → `Watch(site_id, cameras, product, timezone)` with bounded IANA zones
- `calendar_event_strategy()` → start/end bounded to 24h
- `calendar_set_strategy(kind=...)` → list of events, kind ∈ `base|suppress`
- `manual_override_strategy(armed=True, ttl_seconds_range=(1, 86400))` → expires_at NOT NULL by construction
- `clock_strategy()` → datetimes spanning at least one DST boundary

**Properties (ranked):**

1. **Pure-function determinism.** `evaluate_armed(...) == evaluate_armed(...)` for identical inputs (no hidden state).
2. **DST spring-forward never produces a transition in the missing hour.** `@given(zone, date)` over DST boundaries.
3. **`expires_at NOT NULL` invariant.** By construction in the strategy; also assert post-`from_dict`.
4. **Override revocation monotonicity.** Apply-then-revoke = never-applied.
5. **Suppress-set stacking idempotency on duplicates.** Applying twice == applying once.
6. **Manual arm overrides scheduled disarm during override window** (and converse).
7. **Override expiry monotonicity.** `evaluate_armed(t > expires_at) == evaluate_armed_without_override(t > expires_at)`.
8. **Day-boundary continuity at midnight.** `armed(23:59:59)` and `armed(00:00:01)` agree iff both inside the same base interval.

All properties layer on Phase 11's factories + [[strategies]] module. Effort ≈ 1 day for [[strategies]] + properties once the `Watch`/`CalendarSet`/`ManualOverride` data classes exist.

## Cross-references

- AIT spec: [[2026-05-20_ait-brain-in-jar-spec]]
- Brain-in-jar handoff: [[2026-05-27_brain-in-jar-handoff]]
- Hypothesis adoption: [[2026-05-21_hypothesis-in-actuate]]
- AIT validator dovetail: [[2026-05-21_ait-validator-dovetail]]
- AIT validator integration plan: [[2026-05-21_ait-validator-integration-plan]]
- [[watch-entity|Watch]] manager master design: [[2026-05-28_watch-management-service-design]]
- Observability primitives: [[2026-05-29_watch-manager-observability]]
