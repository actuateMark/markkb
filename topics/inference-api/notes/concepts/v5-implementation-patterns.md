---
title: "v5 Implementation Patterns Reference"
type: concept
topic: inference-api
tags: [v5, patterns, implementation, reference]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# v5 Implementation Patterns Reference

Concrete examples from the v5 project that illustrate general patterns documented in the [[engineering-process/_summary|Engineering Process]] topic. Use this as a reference implementation when applying those patterns to other projects.

## File Paths

| Pattern | v5 Implementation |
|---------|-------------------|
| Schema-as-contract registry | `inference_api/api/v5/registry.py` |
| Unified endpoint | `inference_api/api/endpoints/v5.py` |
| Request/response models | `inference_api/models/v5.py` |
| Shared filter builder | `inference_api/api/endpoints/filter_builder.py` |
| Frame handler (async validation) | `inference_api/api/dependencies/validation/v5_frame_handler.py` |
| Security roles | `inference_api/api/security/check_api_key.py` |
| Role mapping for docs | `inference_api/api/docs/generator.py` |
| Test page | `tools/v5-test-page/index.html` |
| Regression suite | `tools/v5-test-page/regression.html` |
| Startup script | `tools/v5-test-page/run.sh` |
| Docs wiki viewer | `tools/v5-docs/index.html` |

## Model/Role Names

| Model ID | Role | Confidence Function |
|----------|------|---------------------|
| intruder | `intruder` | `get_confidence_thresholds` |
| weapon | `weapon` | `get_confidence_thresholds` |
| pet | `pet` | `get_confidence_thresholds` |
| intruder-plus | `intruder_plus` | `get_confidence_thresholds` |
| intruder-plus-with-vehicle | `intruder_plus_with_vehicle` | `get_confidence_thresholds` |
| sliced-intruder-plus-with-vehicle | `sliced_intruder_plus_with_vehicle` | `get_slice_...` |
| motion-plus | `motion_plus` | `get_motion_plus_...` |

## Endpoint-Specific Patterns

### `/vs/` Legacy Endpoints
- Use `files` field (with filenames) instead of `frames`
- Require `id` parameter (string)
- Return `LegacyResponse` format (different from standard `List[List[DetectedObject]]`)

### Stationary Filter
- `"true"` removes, `"tag"` marks, `"false"` disables
- Requires 2+ frames
- motion-plus has no stationary filter (uses frame differences instead)

### Inference Timeout
- `INFERENCE_TIMEOUT_SECONDS` env var (default 3s, local dev 10s in `server.py`)
- Lambda-specific: container images don't include `tools/` directory

## v5 Project Timeline

| Phase | What Happened |
|-------|---------------|
| Context | KB lookup, 3 parallel Explore agents mapped the full v4 codebase |
| Architecture | Reviewed architecture-decisions.md; ADR-001 (k8s migration) denied, scope narrowed |
| Planning | Plan agent designed approach; user chose: frames list, dict-keyed response, extract make_filters |
| Implementation | 7 new files, 5 modified; model registry, endpoints, frame handler, filter builder, test page, run script |
| Security | Two audit passes: base64 validation, size limits, RBAC order, path disclosure, int/float coercion |
| Performance | PIL validation in thread pool via asyncio.to_thread; deferred items in [#46](https://github.com/aegissystems/actuate-inference-api/issues/46) |
| Documentation | Rewrote v5 API docs, per-model pages, wiki viewer, updated backend docs |
| Code Review | Inline import, unbound variable, no-op try/except, leaked env patches, repeated constants |
| Deployment | Zero CI/CD changes; {proxy+} routes v5 automatically; image digest update only |

## External Documentation Translations

| Internal Term | External Language |
|---------------|------------------|
| SAHI sliced inference | analyzes images at multiple zoom levels |
| frame difference computation | detects moving objects, ignores static background |
| PIL image verification | validated as a valid image |
| Lambda payload limit of 6MB | maximum ~4.5 MB per base64-encoded frame |
| Pydantic schema validation | validated against the model's expected format |
