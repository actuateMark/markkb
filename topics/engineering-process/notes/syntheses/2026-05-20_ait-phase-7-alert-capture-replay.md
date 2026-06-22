---
title: "AIT Phase 7 — alert sender capture/replay"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, brain-in-jar, alert-sender, actuate-alarm-senders, replay, roadmap]
created: 2026-05-20
updated: 2026-05-20
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-brain-in-jar-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-10-s3-sink-review-ux.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-6-pipeline-replay.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-8-camera-from-dump.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-05-27
---

# AIT Phase 7 — alert sender capture/replay

Closes the alert-flow half of the brain-in-jar loop: capture every alert payload as it leaves the connector, then replay any captured payload against the real sender code path (or a mock) for post-mortem debugging.

## Why this is Phase 7

`actuate-alarm-senders` already does half the work:

- `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/shared_alert/alert_data.py::AlertData.to_json()` serializes the payload immediately before send. That's the natural capture point.

What's missing:

- No `AlertData.from_json` / `from_dict` to round-trip the payload back into an `AlertData` instance.
- No record-and-replay sender wrappers. Today, every sender constructs the payload and sends it; there's no "capture, then forward" mode.
- No way to drive the *real* sender code path against a captured payload, except by manually crafting a fresh `AlertData` — which loses information (timestamps, frame refs, customer-specific fields).

Phase 7 closes those gaps. It's **independent of Phases 4–6** because the alert-side data flow is parallel to the pipeline; it can land in any order relative to the others.

## Design

### `AlertData.from_json` round-trip

Add a class method to `AlertData`:

```python
data = AlertData(...)
serialized = data.to_json()             # already exists
restored = AlertData.from_json(serialized)
assert restored == data                  # value equality
```

Walk every field, handle nested types (especially detection results, frame refs, customer-specific blocks). Add a unit test that round-trips through `json.dumps`/`json.loads`.

### `CapturingAlertSender` — production-safe capture, zero overhead off-default

**Perf constraint (Mark 2026-05-22):** when `ACTUATE_ALERT_CAPTURE_DIR` is unset, the wrapper short-circuits to a direct forward — no file I/O, no env-var re-check on every call (cached at init), no extra imports loaded. Cost: one branch + one method call (~1μs). 1:1 with no-wrapper baseline.

When `ACTUATE_ALERT_CAPTURE_DIR=/tmp/...` IS set: writes the AlertData JSON to a temp file then atomic-renames, before forwarding. Cost per send: ~1-3ms (filesystem write). Negligible at the alert fire rate (per-camera alerts fire seconds to minutes apart, not per-frame).

```python
sender = CapturingAlertSender(
    wrapped=PatriotAlertSender(...),
    capture_dir=Path("/tmp/alert-captures/"),   # None disables; reads env var by default
    capture_format="json",                       # or "binary" for raw bytes
)
sender.send(alert_data)                          # captures + forwards (or just forwards if disabled)
```

When capture is on, atomic-rename guarantees the capture survives mid-send crashes. The capture is what gets included in brain-in-jar dumps (Phase 9 site-level dump pulls captures into the manifest).

**Roll-out plan**: dev-side use only at first — internal stage / mork-test deployments opt in via env var, observe the on-path cost in real traffic, then expand. **Not enabled by default anywhere**; not pushed to customer pods until we've validated the on-path cost is acceptable.

### `ReplaySender` — drive a real sender against a captured payload

```python
sender = ReplaySender(
    target=PatriotAlertSender(...),       # the sender we want to exercise
    transport="mock",                     # or "live-staging" or "live-prod" (gated)
)
result = sender.replay(captured_alert_data)
```

Three transport modes:

- `mock`: HTTP calls captured-and-asserted-against, no real network. Default for tests.
- `live-staging`: real HTTP to staging endpoints. Manual flag, requires staging-env creds.
- `live-prod`: real HTTP to prod endpoints. **Refuses to run by default** — requires `--unsafe-live-prod` flag plus a confirm prompt. This exists only for the rare "I need to verify the production endpoint accepts this exact payload" workflow.

### `ait replay-alert` CLI

```bash
# List captured alerts in a dump
ait replay-alert <dump_path> --list

# Replay alert at index N against a mock sender (default)
ait replay-alert <dump_path> --index 0

# Replay against a specific sender class
ait replay-alert <dump_path> --index 0 --sender PatriotAlertSender

# Replay all captured alerts
ait replay-alert <dump_path> --all
```

Uses `DumpLoader.get_alert(index)` from Phase 6. Outputs a structured report: payload, transport response, any assertion failures.

### What to capture

- The full `AlertData` JSON.
- The wrapped sender's class name + version (so replay can rebuild the right sender).
- The timestamp the send was *attempted*.
- The transport response on the original send (status code, body) — useful for verifying the captured payload was actually accepted at the time.
- The transport latency — surfaces regressions in subsequent replays.

Privacy note: `AlertData` includes customer-specific fields (site IDs, camera identifiers, sometimes frame URLs). Captures get the same RBAC as brain-in-jar dumps per the spec's PII section.

## TODOs (Phase 7)

### 7A — `AlertData.from_json`

- [ ] Implement `AlertData.from_json(data: str | dict) -> AlertData`.
- [ ] Walk every field, including nested detection results / frame refs.
- [ ] Add `__eq__` if not present, so round-trip equality is provable.
- [ ] Unit tests: round-trip a representative `AlertData` (one of each sender type — Lisa, Patriot, Immix, etc.) through `to_json` → `from_json`.
- [ ] Bump `actuate-alarm-senders` with `[patch:actuate-alarm-senders]`.

### 7B — `CapturingAlertSender`

- [ ] Create `actuate_alarm_senders/shared_alert/capturing_sender.py`.
- [ ] Implement the wrapper pattern: pass-through to `wrapped`, capture on a `send()` call.
- [ ] Atomic write (tempfile + rename) so capture survives mid-send crashes.
- [ ] Async-safe; doesn't block the real send.
- [ ] Add env var `ACTUATE_ALERT_CAPTURE_DIR` to opt in production-side without code changes.
- [ ] Unit tests: capture creates expected file shape; failure of wrapped sender doesn't lose the capture; concurrent sends don't corrupt files.

### 7C — `ReplaySender`

- [ ] Create `actuate_alarm_senders/shared_alert/replay_sender.py`.
- [ ] Three transport modes (`mock`, `live-staging`, `live-prod`).
- [ ] Mock transport asserts HTTP method + URL + headers + body against a recorded snapshot OR a fresh outgoing send; configurable.
- [ ] `live-prod` is gated behind explicit flag + confirm prompt. Document loudly.
- [ ] Unit tests: replay round-trips through mock transport; live-staging mode is exercisable in CI against a stub stage endpoint.

### 7D — `ait replay-alert` CLI

- [ ] Add `ait replay-alert <dump_path>` subcommand.
- [ ] Flags: `--list`, `--index`, `--all`, `--sender`, `--transport`.
- [ ] Wire to `DumpLoader.get_alert(index)`.
- [ ] Render results as a `rich` table.

### 7E — Stage opt-in for `CapturingAlertSender`

- [ ] Wire `ACTUATE_ALERT_CAPTURE_DIR` into the stage deployment env (via `kubernetes-deployments`).
- [ ] Add a `/dashboard-check` panel that counts captures-per-deployment and flags anomalies.
- [ ] Document the opt-in in the connector CLAUDE.md.

### 7F — Documentation

- [ ] Add a "Capture & replay" section to `actuate-alarm-senders/README.md`.
- [ ] Update `actuate-integration-tools/README.md` with the `ait replay-alert` example.
- [ ] Cross-link from the alert-flow KB notes ([[2026-04-20_dev-powerplus-ssl-cert-verify-failure]], etc.) where capture would have made debugging faster.

## Estimate

~3h. `from_json` is ~30min; `CapturingAlertSender` is ~1h; `ReplaySender` ~1h; CLI + docs ~30min.

## Risk

The biggest unknown is **per-sender quirks** in payload structure. Lisa, Patriot, Immix, [[hikcentral-components|Hikcentral]], Verifier, [[sentinel-components|Sentinel]], [[softguard-components|Softguard]], US Monitoring all have their own `AlertData` subclasses or extensions. `from_json` needs to round-trip each. Plan: round-trip test per sender type in 7A; surface failures early.

`ReplaySender` mock-transport mode is the most fiddly part — but tests build up the asserted snapshots organically as they're written, so the work is amortized across the sender types.

## Cross-references

- [[2026-05-20_ait-brain-in-jar-spec]] — parent
- [[2026-05-20_ait-phase-6-pipeline-replay]] — Phase 6 (`DumpLoader` reused here)
- [[2026-05-20_ait-phase-9-site-dump-crash-hook]] — Phase 9 pulls captures into the site-level dump
- [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]] — alert-flow incident debugging would benefit
