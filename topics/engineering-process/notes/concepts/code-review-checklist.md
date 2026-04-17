---
title: "Code Review Checklist"
type: concept
topic: engineering-process
tags: [code-review, checklist, quality]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Code Review Checklist

Checklist for reviewing code before merge. Derived from issues found in the v5 inference API review.

## Imports and Module Structure

- [ ] All imports at module top — no inline `import` inside functions
- [ ] No unused imports (ruff catches these, but verify)
- [ ] No circular import risk from new module dependencies

## Resource Cleanup

- [ ] Every `unittest.mock.patch.*.start()` has a corresponding `.stop()` in `tearDown`
- [ ] Every `app.dependency_overrides[x] = ...` is reset in `tearDown` (`app.dependency_overrides = {}`)
- [ ] File handles opened in `setUp` are closed in `tearDown`

## Defensive Programming

- [ ] No unbound variables in conditional paths (if `x` is assigned inside `if`, is it reachable in the `else`?)
- [ ] No catch-and-re-raise without modification (`try: ... except X: raise` is a no-op — remove the try/except)
- [ ] No bare `except:` clauses — always catch specific exceptions

## Type Safety

- [ ] JSON `int` vs `float` — Python receives `int` for `1` and `float` for `1.0`. If your code checks `isinstance(x, float)`, it misses `int`. Use `isinstance(x, (int, float))`.
- [ ] `bool` is a subclass of `int` — `isinstance(True, int)` is `True`. Exclude explicitly if needed: `isinstance(x, (int, float)) and not isinstance(x, bool)`.
- [ ] Pydantic `model_validate` with default `strict=False` coerces types silently. Be aware of what it accepts.

## DRY

- [ ] Repeated constants extracted to module-level variables (e.g., test env dicts used 4 times → `_TEST_ENV_VARS`)
- [ ] Shared logic extracted to functions/modules (e.g., common utility shared between API versions)

## Error Handling

- [ ] Error messages don't leak internal state (no `str(e)` from internal exceptions, no file paths, no stack traces)
- [ ] `HTTPException` is re-raised correctly (use `except HTTPException: raise` or just don't catch it)
- [ ] Generic fallback messages for unexpected errors

## Deprecation Warnings

- [ ] Are warnings from our code or pre-existing? Don't mix fixes.
- [ ] Async test methods require `IsolatedAsyncioTestCase`, not `TestCase`

## Live Regression

- [ ] Regression suite run with real data through the full stack
- [ ] All existing API versions still pass — not just the new endpoints
- [ ] Results JSON reviewed for unexpected failures or elevated latency
- [ ] Endpoints with special requirements (e.g., multi-frame) tested with sufficient input

## Branch Hygiene (Connector-Specific)

- [ ] No temporary or debug workflow files committed — `.github/workflows/` files added for debugging (e.g., one-off auth tests) must be removed before merge. The `Deploy to ECR Rearchitecture Custom` workflow fires on every non-protected branch push and will build real ECR images from anything in `.github/workflows/`.
- [ ] Test settings files reviewed for credentials — files in `test_settings/` may contain VMS credentials (`password`, `server_ip`, API tokens). Before merging: confirm it's not a production export, confirm credentials are shared test infra (already in repo) or redact them.
- [ ] No debug breakpoints or verbose logging left in production paths — `pdb.set_trace()`, `logging.setLevel(DEBUG)` in non-test code, temporary `print()` in camera/pipeline code.
