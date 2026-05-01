---
title: "Code Review Checklist"
type: concept
topic: engineering-process
tags: [code-review, checklist, quality]
created: 2026-04-14
updated: 2026-04-23
author: kb-bot
incoming:
  - topics/engineering-process/_summary.md
  - topics/engineering-process/notes/entities/agent-actuate-pr-reviewer.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/software-architecture/notes/syntheses/2026-04-16_architecture-enforcement.md
incoming_updated: 2026-05-01
---

# Code Review Checklist

Checklist for reviewing code before merge. Derived from issues found in the v5 inference API review + the 2026-04-23 onboarder silent-failure post-mortem.

## Observability & Release Acceptance (check FIRST per [[engineering-process/_summary|#1 principle]])

- [ ] **PR body includes acceptance criteria** — observable, grep-able post-deploy assertions (not "tests pass"). See [[2026-04-23_release-acceptance-criteria]].
- [ ] **"How will I know this works in prod?" answered** — for any new feature or change to a production-critical flow, the PR explicitly states the monitoring signal (log line pattern, metric, downstream side effect) that will prove it's working post-deploy.
- [ ] **Dashboard signal present or flagged** — if this change adds/modifies a production-critical path, confirm the corresponding signal is in `~/Documents/worklog/dashboard/config/signals.json`. If not, file a follow-up to add it (or add it in this PR).
- [ ] **HTTP error handling follows the "never abort unless asked" rule** — no new `if res.status_code != 200: return` or equivalent short-circuit unless the design explicitly requested it. Default is `logging.warning(...)` + continue; downstream calls are the real connectivity check. See [[feedback_fail_fast_guards]] / the 2026-04-23 post-mortem for why.
- [ ] **Post-deploy verification commands in PR body** — concrete commands the reviewer can run after merge (log tail, dashboard check, smoke curl). If reviewing: run them, don't just mentally assert.

## Imports and Module Structure

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
- [ ] Test [[settings-files|settings files]] reviewed for credentials — files in `test_settings/` may contain VMS credentials (`password`, `server_ip`, API tokens). Before merging: confirm it's not a production export, confirm credentials are shared test infra (already in repo) or redact them.
- [ ] No debug breakpoints or verbose logging left in production paths — `pdb.set_trace()`, `logging.setLevel(DEBUG)` in non-test code, temporary `print()` in camera/pipeline code.
