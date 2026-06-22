---
title: "AIT Phase 12 — `ait sweep` (parameter search for QA workflows)"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, sweep, parameter-search, qa, actuate-validator, roadmap]
created: 2026-05-22
updated: 2026-05-22
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/personal-notes/notes/daily/2026-05-22.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-05-27
---

# AIT Phase 12 — `ait sweep`

Parameter-search workflow for QA. Given a known input (video + expected outcome), search across configurable parameters (model, confidence, raw metric keys, [[ignore-zones|ignore zones]], etc.) to find configurations that produce the expected behavior. The result is auditable and feeds directly into an `actuate-validator` golden-set manifest.

Surfaced 2026-05-22 from a QA team request — see the [[2026-05-22_actuate-testing-toolkit-overview|toolkit overview]] for the verbatim excerpt.

## Why this is Phase 12 (and not absorbed elsewhere)

The existing tools answer:

- "Given a config, what's its semantic state?" → `ait validate`
- "Given a config + library version, what's the parse delta?" → `ait diff`
- "Given a scenario template, generate inputs" → `ait simulate`
- "Given a captured state, what did the pipeline do?" → `ait replay`
- "Given a config + video + expectation, does it pass?" → `actuate-validator`

None of these answer the **inverse search question** QA is asking: *given a video + expectation, find a config*. It's a parameter sweep over the `actuate-validator` evaluation function. New verb, new home in the toolkit.

Could it live inside `actuate-validator` as a new harness type? Yes, but the integration plan ([[2026-05-21_ait-validator-integration-plan]]) keeps `actuate-validator` focused on regression-gating; exploration tools live in AIT. Sweep is exploration.

## Design

### CLI shape

```bash
ait sweep \
    --video data/gun-scene.mp4 \
    --expect "alert_label=gun_drawn" \
    --param "model_name=v9_general,v9_threat,v8_gun" \
    --param "confidence=0.3,0.5,0.7,0.9" \
    --param "raw_metric_keys=['gun'],['gun','weapon']" \
    --observer person_line_crossing
```

Cartesian product: 3 × 4 × 2 = 24 combinations. Each combination spins the same harness `actuate-validator` uses (so the test path is production-faithful), evaluates the expectation, and tallies results.

### Output formats

**Rich table** (default):

```
Sweep — gun-scene.mp4 → alert_label=gun_drawn (24 combinations)
┏━━━━━━━━━━━┳━━━━━━━━━━━━┳━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━┓
┃ Model     ┃ Confidence ┃ Metrics     ┃ Alerts  ┃ Match?   ┃ Notes     ┃
┡━━━━━━━━━━━╇━━━━━━━━━━━━╇━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━┩
│ v8_gun    │ 0.3        │ [gun]       │ 3       │ ✓        │ first hit │
│ v8_gun    │ 0.5        │ [gun]       │ 0       │ ✗        │ below thr │
│ v9_threat │ 0.5        │ [gun]       │ 1       │ ✓        │ frame 47  │
│ ...       │ ...        │ ...         │ ...     │ ...      │ ...       │
└───────────┴────────────┴─────────────┴─────────┴──────────┴───────────┘

Summary: 14 / 24 combinations matched expected outcome.
Best (highest confidence + match): v9_threat / 0.7 / [gun]
```

**JSON** (`--json`) for piping into other tools.

**Validator-manifest stub** (`--emit-validator-manifest <path>`): writes the winning combination's config as a validator manifest entry, ready to commit:

```json
{
    "id": "gun_scene_v9_threat",
    "description": "Gun drawn detection — v9_threat / 0.7 / [gun]",
    "video_path": "s3://actuate-test-sets/gun-scenes/v1/gun-scene.mp4",
    "observer": "person_line_crossing",
    "config_params": {
        "model_name": "v9_threat",
        "confidence": 0.7,
        "raw_metric_keys": ["gun"]
    },
    "expectations": {
        "should_alert": true,
        "expected_label": "gun_drawn"
    }
}
```

### Parameter syntax

```bash
--param "name=v1,v2,v3"             # 3 string values
--param "confidence=0.3,0.5,0.7"    # 3 numeric values (type inferred)
--param "metrics=['gun'],['gun','weapon']"   # JSON list literals
--param "zones=null"                # null / None
--param "range=0.3..0.9 step 0.1"   # range shorthand (future)
```

The parser is lenient — JSON-ish values are JSON-parsed; bare strings stay strings. Numeric coercion follows the validator's `config_params` schema for the chosen observer.

### Execution

- Builds the cartesian product up-front.
- Spins a process pool (default: `multiprocessing.cpu_count() - 1`) so combinations run in parallel.
- Each combination calls into `actuate-validator`'s `ObserverHarness.execute()` (or `PipelineHarness.execute()`) with a synthesized test_case dict.
- Inference-API rate limiting: configurable concurrency cap (`--max-concurrent N`) since each combination may issue model inference calls.
- Progress bar via `rich` so long sweeps are observable.

### Expectation matching

Initial scope — alert-level expectations only:

| Expectation | What it means |
|---|---|
| `alert_label=X` | At least one alert with `label==X` fires |
| `min_alerts=N` | At least N alerts fire |
| `max_alerts=N` | At most N alerts fire |
| `forbidden_label=X` | No alert with `label==X` fires |
| `min_motion_frames=N` | FDMD detects motion on at least N frames |

These mirror `actuate-validator`'s pipeline expectations schema. Future: detection-level (e.g. "detection class X appears in at least N frames"); confidence-statistics-level (e.g. "p95 confidence ≥ Y"); zone-overlap-level (e.g. "no alert from zone Z").

## Coordination with `actuate-validator`

Phase 12 sweeps invoke validator harnesses directly. This implies:

1. **Plays A + B from the integration plan must land first** ([[2026-05-21_ait-validator-integration-plan]]) so the harnesses + mocks have stable upstream homes that AIT can import.
2. **`actuate-validator` becomes a runtime dep of AIT.** Acceptable given the dep direction (sweep is exploration, validator is the gate; sweep depends on the gate's harnesses).
3. **Sweep operates ON the validator's test harnesses, not OVER them.** Same code path; different driver. A sweep finding can be promoted to a validator manifest entry directly.

## TODOs (Phase 12)

### 12A — CLI scaffolding

- [ ] Add `actuate-validator` as a runtime dep in `actuate-integration-tools/pyproject.toml` (path-pin until libraries publish, then version-pin).
- [ ] Create `actuate_integration_tools/sweep/` package + Typer subgroup.
- [ ] Wire `ait sweep` into the main CLI (alongside `validate`, `replay`, `simulate`, `diff`).

### 12B — Parameter parsing

- [ ] Implement `parse_param_spec("name=v1,v2,v3")` returning `(name, [v1, v2, v3])` with type coercion.
- [ ] Support JSON-literal values (lists, dicts, null).
- [ ] Reject invalid combinations early (e.g. unknown observer name).

### 12C — Execution loop

- [ ] `SweepRunner` class: builds cartesian product, drives parallel execution, collects results.
- [ ] Per-combination invocation: synthesize a test_case dict, call `ObserverHarness.execute(test_case, ctx)`.
- [ ] Optional concurrency cap (`--max-concurrent`).
- [ ] Progress bar via `rich.progress`.

### 12D — Expectation matching

- [ ] `evaluate_expectation(expected: dict, result: RunResult) -> (matched: bool, note: str)`.
- [ ] Support the 5 expectation types listed above.
- [ ] Detailed `note` field per combination (which frame fired, confidence, etc.).

### 12E — Output rendering

- [ ] Rich-table renderer.
- [ ] JSON output via `--json`.
- [ ] Validator-manifest emitter via `--emit-validator-manifest <path>`.
- [ ] `--top N` flag to surface the N highest-matching combinations.

### 12F — Tests

- [ ] Mocked-harness integration tests (no real model calls; synthetic detections).
- [ ] Property tests for the param-parser via Hypothesis.
- [ ] Smoke test against a real `actuate-validator` golden-set video.

### 12G — Documentation

- [ ] README section in AIT.
- [ ] Cookbook: "How to find a config for a new test case (QA workflow)".
- [ ] Cross-link from `actuate-validator/README.md` so QA discovers it.
- [ ] Update the toolkit-overview synthesis: mark Phase 12 as ✅ shipped when it lands.

## Estimate

~4-6h focused. Most of the time goes into 12C (execution loop + parallelism + rate-limiting) and 12D (expectation matching). 12A + 12B are mechanical; 12E + 12F + 12G are end-of-phase polish.

## Risks

- **Inference-API rate limits.** A 24-combination sweep × 100 frames × 1 inference call per frame = 2400 inference calls. Throttle aggressively; document the concurrency model.
- **Combinatorial explosion.** A sweep with 5 params × 4 values each = 1024 combinations. CLI should surface estimated combination count + duration before running, and refuse to start sweeps over a hard cap (configurable, default 100) without `--confirm-large`.
- **Sub-optimal local maxima.** Sweep finds "a config that matches" but maybe not "the *best* config". Mitigation: `--top N` ranks by a configurable score (default: match + highest confidence + fewest false-positive alerts).
- **Validator-harness drift.** If validator's `ObserverHarness` signature changes, sweep breaks. Mitigation: version-pin in AIT + bump deliberately; the dep direction is correct so this is normal library-bump discipline.

## Cross-references

- [[2026-05-22_actuate-testing-toolkit-overview]] — parent synthesis (QA gap section)
- [[actuate-validator]] — provides the harnesses sweep drives
- [[2026-05-21_ait-validator-integration-plan]] — Plays A + B must land before this can
- [[actuate-integration-tools]] — host repo
- [[2026-05-21_ait-phase-11-simulate]] — sibling Phase 11; same registry/factory conventions
