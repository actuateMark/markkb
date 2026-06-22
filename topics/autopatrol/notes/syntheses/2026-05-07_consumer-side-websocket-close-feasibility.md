---
title: "Consumer-side websocket close: feasibility, race timing, frame-coverage tradeoff"
type: synthesis
topic: autopatrol
tags: [autopatrol, vch, immix, websocket, lifecycle, deferred, experiment-design, streamfailed]
jira: ""
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-05-07.md
  - topics/vms-connector/notes/syntheses/2026-05-06_immix-streamfailed-worker-lifespan.md
incoming_updated: 2026-05-08
---

# Consumer-side websocket close: feasibility, race timing, frame-coverage tradeoff

**Status: deferred 2026-05-07** pending Immix-side response on [[2026-05-06_immix-streamfinished-inquiry|the StreamFinished inquiry]] and broader product/ops discussion of the experimental tradeoff.

Investigated whether `AutopatrolWebSocketStreamPuller` can pre-emptively close its websocket at the API-requested duration boundary instead of waiting for Immix's DeviceWorker hard-lifespan timer to tear it down. Goal: test whether consumer-initiated close changes the Immix UI label from `streamfailed` to `StreamFinished` ([[2026-05-06_immix-streamfailed-worker-lifespan]]).

**One-line conclusion:** mechanically straightforward; ~15–20% inference-frame-coverage cost to actually win the race; the literal "close at duration with zero margin" knob is likely a no-op because we'd lose the race anyway.

## Q1: Can we close cleanly?

**Yes.** Two equivalent paths through the existing code in `actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py`:

1. Reduce `consume_stream`'s loop bound so it exits on time rather than on `ConnectionClosed`. The `async with websockets.connect(self.url, open_timeout=10, close_timeout=10) as ws:` block runs the websockets-library Close handshake (Close frame, normal-closure code, bounded by `close_timeout=10`) on natural exit.
2. Track elapsed-since-first-frame and `break` early. Same effect — exits the `async with`, same handshake.

**Today the loop never voluntarily exits.** `restart_puller` in `vms-connector` `camera/shared/base_stream_camera.py:1541` calls `puller.run` with no args, so `run()` defaults to `duration=60*60*24*7` (7 days), which threads to `consume_stream` and renders `while time.time() < start_time + duration:` effectively infinite. The block exits today only because Immix's force-killed worker severs the socket and our `ConnectionClosed` handler `break`s once `frame_returned=True`. Net: **the connector currently never initiates the close — it only ever observes Immix's tear-down.**

### Draft diff (reverted, not committed)

`actuate-libraries:feat/autopatrol-consumer-close-experiment` was created and reverted on 2026-05-07. The draft added:

- `local_close_bound = min(duration, self.connection_duration)` computed once at the top of `consume_stream`
- inner loop bound switched from `start_time + duration` to `start_time + local_close_bound`
- a `while/else` log distinguishing the natural-completion path ("we won the race") from the `ConnectionClosed` and `TimeoutError` `break` paths ("Immix tore down first")

Existing tests (`tests/test_autopatrol_stream_id_history.py`, 16 tests) passed against the change. No commit made; branch deleted.

## Q2: Will it actually change the Immix label?

**Genuinely uncertain.** Evidence both directions:

**Hopeful:**
- Immix's internal `AutoPatrolActionType` enum has `StreamFinished` as a sibling to `StreamFailed` ([[immix-vendor-api]] §"AutoPatrolActionType Gap"). Their data model has a clean-exit category.
- Worker emits `Stream heartbeat` lines so it does observe stream state.

**Concerning:**
- Worker log explicitly says `Worker has a hard life-span and is therefore not reusable. Life span limit set to 10 seconds`. "Hard" reads as unconditional — the timer fires regardless of consumer state, and the exit cause is `lifespan expiry` no matter what. Final lines confirm: `Worker life span limit hit. Signaling the worker to close` → `Force closing worker due to life-span expiry`.
- The labeling layer is upstream of the worker; even if the worker observes our close, the labeling logic may collapse "lifespan ran out *while* consumer happened to be already gone" into the same `streamfailed` bucket.
- The captured run shows zero log lines indicating the worker noticed/distinguished consumer-side close behavior.

The only way to resolve this is empirical, but the experiment carries cost (next section).

## Race timing

From the captured worker log ([[2026-05-06_immix-streamfailed-worker-lifespan]] §"Triggering Evidence"):

```
T+0:  Worker started
T+2:  Encoder initialized event detected. Lifespan starts now (10s).
T+12: Worker life span limit hit. Force closing.
```

From our connector side: `start_time = time.time()` resets on first frame received (line ~308 of `consume_stream`). First frame arrives some δ seconds *after* their encoder-init (encoder needs to init before sending; network + buffering adds latency, plausibly 100–500ms).

So:
- Their lifespan fires at `T_encoder_init + 10`
- Our close (margin=0) fires at `T_first_frame + 10` ≈ `T_encoder_init + 10 + δ`

**They win by δ.** A literal "close at the duration" change is likely a no-op: we never reach our local bound because `ConnectionClosed` fires first. The experiment proves nothing in this case.

To win the race we need our local bound `< 10 - δ`. A 1–2s margin (close at 8–9s after first frame) likely wins, but cuts into frame coverage.

## Frame-coverage tradeoff

Captured run: 39 native frames over 10.18s ≈ 3.8 fps native. Downsampling in the puller (`frame_interval = 1.0 / self.highest_fps`) reduces this to the model's `highest_fps` — typically 1–2 fps for AutoPatrol motion-plus models — so ~10–20 inference frames per patrol.

| Margin | Native frames lost | Inference frames lost | Coverage cost | Race-win? |
|---|---|---|---|---|
| 0s (literal "at duration") | ~0 | ~0 | none, but no-op | unlikely |
| 1s | ~3 | ~1–2 | ~10% | likely |
| 2s | ~7 | ~2–4 | ~15–20% | very likely |

**For AutoPatrol detection:** a subject who only enters frame in seconds 8–10 of a 10s window would be missed if we close at 8s. Whether this is acceptable depends on AutoPatrol product expectations — open question for product/ops.

**For VCH (2s window):** even a 1s margin halves the inference window. Recommend any future experiment scope to **AutoPatrol only**.

## Other considerations surfaced during analysis

- **Today's tear-down isn't graceful either.** When Immix's worker is force-killed at lifespan, the close from their end isn't a Close-frame handshake — it's a process kill that severs the socket. So today's "10s of frames" probably loses some in-flight frames as well; hard to compare *effective* coverage between today and the experimental version without measurement.
- **Both AutoPatrol and VCH share the puller class.** `connection_duration` is per-instance from `autopatrol_config.duration`. Any change applies to both unless explicitly scoped (e.g., guard on `self.autopatrol_config.patrol_type == "AutoPatrol"`).
- **Race-loss case muddies the experiment.** If we ship margin=0 and the loop never naturally completes, we get no signal on whether consumer-side close changes the label. The experiment must actually win the race to be informative, which forces a non-zero margin and the associated coverage cost.
- **No consumer-callable `StreamFinished` endpoint exists** in the [[immix-vendor-api|Immix Vendor API]] ([[immix-vendor-api]] §"AutoPatrolActionType Gap"). The OpenAPI 3.0.1 spec has no schema or endpoint to POST a stream-level action; `PatrolStatus` (Pending/Started/Finished) is patrol-level only and we already set it correctly. So we cannot signal clean termination explicitly — only by behavior (close before lifespan fires).

## Why deferred

1. **Pending Immix-side answer.** The outbound inquiry [[2026-05-06_immix-streamfinished-inquiry]] asks whether (a) there's an undocumented endpoint to POST `StreamFinished` ourselves, or (b) Immix can derive it server-side from observed websocket close behavior. Either resolves the labeling cleanly with no frame-coverage cost on our side.
2. **Frame-coverage cost is non-trivial.** Even a 1s margin sacrifices ~10% of the inference window. Without product/ops sign-off that this is acceptable for AutoPatrol detection sensitivity, we shouldn't ship.
3. **Need broader discussion.** Tradeoff between cosmetic UI labeling and detection coverage. Worth more eyes before running the experiment.

## When to revisit

- After Immix responds to [[2026-05-06_immix-streamfinished-inquiry]]
- If Immix confirms `StreamFinished` is server-derivable from clean close → no connector change needed, just verify after their roll
- If Immix confirms it's not server-derivable AND there's no `StreamFinished` write endpoint → reconsider this experiment with explicit margin/scope decision
- If product/ops decide the `streamfailed` label is cosmetic-only and not worth a coverage hit → close out as wontfix

## Cross-references

### Direct lineage (this thread)
- [[2026-05-06_immix-streamfailed-worker-lifespan]] — parent synthesis: root cause of `streamfailed` label, full DeviceWorker log evidence, original "Secondary fix" proposal that this note evaluates
- [[2026-05-06_immix-streamfinished-inquiry]] — outbound inquiry to Immix on `StreamFinished` semantics; this note's deferral hinges on Immix's response
- [[immix-vendor-api]] — [[immix-vendor-api|Immix Vendor API]] entity note; OpenAPI 3.0.1 spec analysis; `AutoPatrolActionType` enum gap

### Adjacent surface (related connector-side work on Immix websocket lifecycle)
- [[2026-05-06_bugfix-stream-id-history-iteration]] — companion connector-side fix shipped 2026-05-06; stream_id history accumulation across `ConnectionClosed` retries; affects how the puller tracks ids during the same retry path the proposed change would alter
- [[2026-04-20_streamid-null-patrol-alert-bug]] — earlier streamId-null bug on the raise side (GH#1656); validated stream_id presence at alert dispatch
- [[2026-04-23_immix-api-error-patterns]] — error response catalogue for Immix endpoints
- [[2026-04-29_immix-zombie-tenants]] — operational issue with stale tenant onboarding state

### Operational context
- [[autopatrol-server]] — orchestrator that drives the patrol cronjob; consumer of this puller via `vms-connector`
