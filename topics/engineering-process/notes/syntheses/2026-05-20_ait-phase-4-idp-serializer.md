---
title: "AIT Phase 4 — `ImageDataPacket` serializer (brain-in-jar keystone)"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, brain-in-jar, image-data-packet, serialization, pipeline, actuate-pipeline-objects, roadmap]
created: 2026-05-20
updated: 2026-05-20
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-brain-in-jar-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-5-dump-replay-puller.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-6-pipeline-replay.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-8-camera-from-dump.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-9-site-dump-crash-hook.md
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-phase-11-simulate.md
  - topics/engineering-process/notes/syntheses/2026-05-27_zack-coordination-brain-in-jar.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-05-27
---

# AIT Phase 4 — `ImageDataPacket` serializer

The keystone of the brain-in-jar arc. `ImageDataPacket` (IDP) is the unit of work that flows through every pipeline step. Until it can serialize and deserialize, nothing else in Phases 5–10 works.

## Why this is Phase 4

Two facts converge:

1. `actuate-libraries/actuate-pipeline/src/actuate_pipeline/links/data_dump_link.py` already exists. It wraps any pipeline step and calls `actuate_instrumentation.data_dump(prefix=..., data=result.json())` before forwarding. The wiring is right.
2. `result.json()` is **not** a method on `ImageDataPacket`. There is no `to_dict`, no `from_dict`, no `__getstate__`, no `asdict()`. The link crashes the first time you try to use it. (Confirmed by grep on `actuate-pipeline-objects/src/actuate_pipeline_objects/image_data_packet.py`, 2026-05-20.)

Everything downstream — pipeline-step replay (Phase 6), camera reconstitution (Phase 8), site dump (Phase 9) — depends on round-tripping an IDP. So this is first.

## Design

### Two-part serialization

IDPs contain a mix of cheap (string/int) fields and expensive (numpy arrays, JPEG bytes, references to `ImageCache` keyed by `frame_id`) fields. Lumping them into one JSON blob ends up base64-encoding several MB of frame data per packet — slow to write, slow to parse, hostile to diffing.

The pattern is **JSON manifest + binary side-channel**:

```
dump_dir/
├── manifest.json                  # high-level dump metadata
├── idp_0001.json                  # per-IDP cheap fields + sidecar refs
├── idp_0001.frame.jpg             # JPEG bytes (if present on the IDP)
├── idp_0001.numpy.npy             # raw numpy frame (if present and JPEG isn't sufficient)
├── idp_0002.json
├── ...
```

Each `idp_N.json` references its sidecars by relative path:

```json
{
  "frame_id": "abc123",
  "timestamp": "2026-05-20T10:23:45.123Z",
  "camera_name": "Axis office camera",
  "_sidecars": {
    "frame": "idp_0001.frame.jpg",
    "raw": null
  },
  "metrics": {...},
  "product_data": {...}
}
```

When the dump is zipped (per the spec's atomicity rule), the zip preserves the directory layout. `from_dict` resolves sidecars relative to the unzipped root.

### `to_dict` field selection

Walk every field on `ImageDataPacket` and classify:

- **Always-include cheap**: `frame_id`, `timestamp`, `camera_name`, `pipeline_metrics`, detection results, observer state, sliding-window state, alert-pending state.
- **Include via sidecar**: `frame` numpy array → `.npy` *or* JPEG → `.frame.jpg` if encodable.
- **Skip**: live thread refs, queue handles, lock objects, `ImageCache` instance refs (only the `frame_id` key is preserved; the cache itself is reconstructed on `from_dict`).
- **Best-effort with fallback**: anything we can't classify gets `repr()`'d to a `_unserializable` block in the JSON so it's at least *visible* in a dump even if it can't replay.

### `from_dict` reconstitution

Given the dict + a base path for sidecars, reconstruct an IDP. The constructor must accept either:

1. A "live" IDP (legacy path — what production constructs today).
2. A serialized dict (new path — what replay tools use).

Suggested API:

```python
idp = ImageDataPacket(frame=..., timestamp=..., ...)         # live path
idp = ImageDataPacket.from_dict(data, base_path=Path("..."))  # replay path
```

`from_dict` validates required cheap fields, lazily-loads sidecar files (so a dump can be inspected without forcing every frame into memory), and rebuilds the `ImageCache` reference by registering the loaded frame under the original `frame_id`.

### `DataDumpLink` repair

Once `to_dict` lands, fix `DataDumpLink` to call `result.to_dict()` (not the nonexistent `result.json()`). Confirm it works end-to-end with a synthetic IDP. Add a regression test in `actuate-pipeline` so future renames don't silently break the link again.

### `actuate-instrumentation.data_dump` growth

Currently `data_dump(prefix, data)` writes one JSON file. Phase 4 expands it to:

```python
data_dump(prefix, data, sidecars={"frame": frame_bytes, "numpy": numpy_array})
```

Sidecars get written next to the JSON. The manifest auto-populates `_sidecars`. `data_load(filename)` returns `(data, sidecar_loader)` where the loader is a callable that materializes a sidecar on demand (so big dumps don't OOM the inspector).

This is a meaningful version bump on `actuate-instrumentation` — `0.0.3` stub → `0.1.0` or even `1.0.0` once the API stabilizes.

## TODOs (Phase 4)

### 4A — `ImageDataPacket.to_dict` + sidecar split

- [ ] Enumerate every field on `ImageDataPacket` (read `actuate-pipeline-objects/src/actuate_pipeline_objects/image_data_packet.py` thoroughly; also walk `ProductDataPacket` and any nested types).
- [ ] Classify each field as cheap / sidecar / skip / best-effort.
- [ ] Implement `to_dict(self) -> tuple[dict, dict[str, bytes | np.ndarray]]` — returns the JSON-safe dict + a sidecars-by-name mapping.
- [ ] Decision: JPEG encode (if [[opencv-entity|cv2]] available) vs raw `.npy` for the frame. Default JPEG, fall back to raw if encoding fails. Document the choice.
- [ ] Add `_unserializable` capture for anything that surprises the walker — `repr()` truncated to 500 chars.
- [ ] Unit tests: round-trip a synthetic IDP; assert all cheap fields recover; sidecar references resolve; the `_unserializable` block is empty for normal IDPs.

### 4B — `ImageDataPacket.from_dict`

- [ ] Implement `from_dict(data: dict, base_path: Path | None = None) -> ImageDataPacket`.
- [ ] Lazy-load sidecars: don't read frame bytes until accessed. Use `functools.cached_property` or similar.
- [ ] Rebuild `ImageCache` ref by registering the loaded frame under the original `frame_id`.
- [ ] Handle missing sidecar (file removed / corrupted) gracefully — frame=None, log warning.
- [ ] Unit tests: round-trip from `to_dict` → `from_dict` is value-equal on all cheap fields; lazy-load works without sidecar present until accessed; corruption recoverable.

### 4C — `actuate-instrumentation` v0.1.0 growth

- [ ] Extend `data_dump(prefix, data, sidecars=None)` signature.
- [ ] Add `data_load(filename) -> (data: dict, sidecar_loader: Callable[[str], bytes])`.
- [ ] Bump version to `0.1.0` with `[minor:actuate-instrumentation]` in commit message.
- [ ] Update `actuate_instrumentation` README to document the new API.
- [ ] Per [[feedback_library_version_field_ci_managed]]: do NOT edit `version =` in pyproject.toml directly; tag the commit.

### 4D — Fix `DataDumpLink`

- [ ] Change `result.json()` → `result.to_dict()` (or however the final API names it).
- [ ] Pass sidecars through to `data_dump`.
- [ ] Add a regression test in `actuate-pipeline/tests/links/test_data_dump_link.py` that spins the link with a synthetic IDP, confirms the dump materializes, then `from_dict`s it back.
- [ ] Bump `actuate-pipeline` with `[patch:actuate-pipeline]`.

### 4E — Smoke test against a real captured IDP

- [ ] Stage a connector locally (`python connector.py -l`) with `DataDumpLink` spliced into one step.
- [ ] Confirm a real IDP dumps cleanly to `./local_data/`.
- [ ] Inspect the dump dir; check JSON looks reasonable and sidecars are present + non-empty.
- [ ] Load the dump back via `ImageDataPacket.from_dict`; assert it round-trips.

### 4F — Documentation

- [ ] Add a "Serialization contract" section to `actuate-pipeline-objects/README.md` listing what's cheap / sidecar / skip.
- [ ] Update the [[2026-05-20_ait-brain-in-jar-spec]] cross-cutting concerns once the field classification settles (especially "dump size" estimate — it depends on what we choose to include).
- [ ] Write a KB concept note `2026-05-20_idp-serialization-contract.md` so the field-classification table has a permanent home.

## Estimate

~3–4h focused. 4A is ~1h walking + classifying fields. 4B is ~1h. 4C is ~30min. 4D is ~30min. 4E + 4F are ~30min combined.

## Risk

The biggest unknown is **what surprising fields live on `ImageDataPacket`** today. The serialization contract may need a follow-up tightening pass once we see the real shape. The `_unserializable` block exists precisely to keep us from getting stuck — anything unexpected falls back to `repr()` and the dump still completes.

## Cross-references

- [[2026-05-20_ait-brain-in-jar-spec]] — parent
- [[2026-05-20_ait-phase-5-dump-replay-puller]] — Phase 5 (independent, can land in parallel)
- [[2026-05-20_ait-phase-6-pipeline-replay]] — Phase 6 (requires Phase 4)
- [[project_actuate_instrumentation_intent]] — `actuate-instrumentation` is the intended home for `data_dump`
- [[feedback_library_version_field_ci_managed]] — version-bump discipline
