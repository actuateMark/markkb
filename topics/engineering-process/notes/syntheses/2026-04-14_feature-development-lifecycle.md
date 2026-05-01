---
title: "Feature Development Lifecycle"
type: synthesis
topic: engineering-process
tags: [process, lifecycle, development, planning, review, deployment]
created: 2026-04-14
updated: 2026-04-23
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-01
---

# Feature Development Lifecycle

A complete, repeatable process for building a new feature — from initial planning through production deployment. Derived from the v5 inference API project (ED-32, April 2026), the 2026-04-23 onboarder post-mortem, and codified for reuse.

This lifecycle assumes Claude Code as the development environment with access to the Obsidian KB, Jira/Confluence via MCP, and GitHub via `gh` CLI.

> **Overarching rule (April 2026 revision):** the lifecycle serves the #1 operational principle — *regression prevention + fastest-possible detection on every launch*. Every phase has a monitoring/verification hook. A release is not "done" until the dashboard ([[2026-04-23_dashboard-sketch]]) is GREEN against the deployed component. See [[engineering-process/_summary]] and [[2026-04-23_postmortem-onboarder-healthcheck]] for the source.

---

## Phase 1: Context Gathering

**Goal:** Understand what exists before proposing what to build.

### Steps

1. **KB lookup** — Read the relevant topic `_summary.md` and recent synthesis notes. Check for architecture decisions, related services, who is working on what, and known constraints.
   - Rule: *Always run before starting any non-trivial work in an Actuate codebase* (see global CLAUDE.md)

2. **Codebase exploration** — Use Explore agents (up to 3 in parallel) to understand:
   - The existing implementation you're extending
   - Request/response flow end-to-end
   - Configuration, environment variables, deployment
   - Test patterns and how existing tests mock dependencies

3. **External context** — Check Jira tickets, Confluence pages, and Slack threads for requirements, timelines, and stakeholder decisions that aren't in the code.

### Outputs
- Mental model of current architecture
- List of files and patterns to reuse
- Questions for the user if requirements are ambiguous

---

## Phase 2: Architecture Review

**Goal:** Resolve design questions before writing code.

### Steps

1. **Identify open questions** — What decisions need to be made? What constraints exist? What's the migration/deprecation path?

2. **Document as ADRs** — Write [[architecture-decision-records|Architecture Decision Records]] for non-obvious choices. Include:
   - Context (what prompted the decision)
   - Options considered (with pros/cons)
   - Decision and rationale
   - Status (Proposed / Accepted / Denied / Deferred)

3. **Team review** — Present questions to the user/team. Get explicit answers. Don't assume.

4. **Incorporate answers** — Update ADRs with decisions. Flag what changed from the original plan. Some answers may fundamentally alter the scope — that's expected and good.

### Rules
- *Don't plan for infrastructure changes until confirmed* — a past project planned a full infrastructure migration that was denied at architecture review
- *Don't over-engineer* — if the team says "just use API keys," don't design a customer_group system
- *Document cancelled decisions too* — future engineers need to know what was considered and rejected

### Outputs
- ADR document with Decided / Denied / Deferred sections
- Revised understanding of scope

---

## Phase 3: Implementation Planning

**Goal:** Concrete plan with files, functions, and a daily schedule.

### Steps

1. **Launch Plan agents** — Give them full context from Phase 1-2. Request:
   - File-by-file change list (new files, modified files)
   - Data structures and interfaces
   - What to reuse from existing code (with file paths)
   - Edge cases and risks

2. **Resolve design choices with the user** — Use AskUserQuestion for decisions that affect the plan:
   - Response format
   - Which models/features to include in Phase 0
   - Shared module extraction vs quick-and-dirty import

3. **Write the plan file** — Include:
   - Context section (why this change is being made)
   - Architecture diagram (request flow)
   - New files with descriptions
   - Modified files with change descriptions
   - Implementation sequence (daily breakdown if time-constrained)
   - Verification steps

### Rules
- *Match the scope to what was requested* — don't add features, abstractions, or "improvements" beyond the plan
- *Identify what can run in parallel* — independent workstreams (e.g., library consolidation and endpoint development) can run concurrently
- *Monitoring hooks are part of the plan, not an afterthought* — before sign-off, the plan must answer "how will we know this works in prod?" with a concrete signal (log pattern, metric, downstream side effect). If adding/modifying a production-critical flow, the signal goes in the dashboard catalog (`~/Documents/worklog/dashboard/config/signals.json`). See [[2026-04-23_release-acceptance-criteria]].
- *HTTP error-handling policy is a design decision, not an implementation detail* — for any new upstream call, explicitly decide whether non-200 responses (a) log-and-continue, (b) abort, or (c) retry-with-backoff-then-abort. Default is (a). Abort requires explicit user sign-off during planning — never added silently during implementation. See [[feedback_fail_fast_guards]].

### Outputs
- Plan file ready for approval (includes monitoring signal + error-handling policy per call)
- KB synthesis note capturing the plan (for future reference)

---

## Phase 4: Implementation

**Goal:** Write the code, test as you go.

### Steps

1. **Branch from develop** — Feature branch naming: `feature/{ticket}-{slug}`

2. **Foundation first** — Build in dependency order:
   - Extract shared modules (e.g., `make_filters` to `filter_builder.py`)
   - Create data models (Pydantic schemas, registry entries)
   - Create utility modules (frame handler, validators)
   - Run lint after each file to catch issues early

3. **Endpoints** — Run `/api-endpoint-development` or follow its checklist:
   - Pydantic models with `json_schema_extra.examples` on every request AND response (no `additionalProp` or `"string"` placeholders in Swagger)
   - Schema-as-contract for multi-resource endpoints (registry + per-resource Pydantic schema)
   - RBAC: add role, add check function, add to `ENDPOINT_ROLE_MAPPING`, dynamic role check before validation
   - Discovery endpoints filtered by caller's roles
   - Error hints filtered by caller's roles
   - Wire up security roles, docs integration, model exports
   - Lint + test after wiring

4. **Test page / dev tooling** — Build local testing tools:
   - Interactive test page for visual verification
   - Startup scripts that bring up all dependencies (kubefwd, auth, server)
   - Make it one-command: `./tools/{feature}/run.sh`

5. **Unit tests** — Cover:
   - Happy path (single frame, multi frame, each model)
   - Validation errors (bad input, missing fields, wrong types)
   - Security (role enforcement, unknown model, invalid data)
   - Edge cases (empty detections, max frames, float sensitivity)

6. **Live regression suite** — Build a browser-based test runner that hits real endpoints:
   - Covers ALL API versions (v1 through current), not just the new one
   - Uses real images through the full stack (kubefwd → model servers)
   - Shows pass/fail/skip with elapsed time and detection counts
   - "Copy Results JSON" button for pasting results back into Claude Code for analysis
   - Served from the dev server itself (same origin, no CORS issues)
   - Auto-skips endpoints that require more input than provided (e.g., multi-frame endpoints)

### Rules
- *Lint after every file* — catch import errors and unused variables immediately
- *Run full test suite after wiring* — catch regressions from shared module extraction
- *Run live regression before merge* — unit tests mock the inference client; live regression catches real integration issues
- *Don't batch tasks* — mark each done as you go so progress is visible

### Outputs
- Working code on feature branch
- All tests passing (new + existing)
- Live regression passing across all API versions
- Local dev server functional

---

## Phase 5: Security Hardening

**Goal:** Validate every input, leak no internal state.

### Steps

1. **Audit every input path** — For each field the user can control:
   - What types are accepted? (string, int, float, bool — watch for JSON type coercion)
   - What are the bounds? (max length, min/max value, regex pattern)
   - What happens with malicious input? (SQL injection, path traversal, oversized payloads)

2. **Audit frame/file handling** — Images are the highest-risk input:
   - Validate base64 is actually valid base64 (`validate=True`)
   - Validate decoded bytes are a real image (PIL `Image.open`)
   - Enforce dimension limits (8192x8192)
   - Enforce size limits (50MB)
   - Normalize format (convert to RGB JPEG)
   - Run validation in thread pool to avoid blocking

3. **Audit error responses** — Never leak:
   - Stack traces or exception messages from internal libraries
   - File system paths
   - Database connection strings or internal URLs
   - Full exception chains (use `from e` for chaining but generic detail messages)

4. **Audit processing order** — Check RBAC *before* validation. Don't let unauthenticated users probe which inputs are valid.

5. **Write security-specific tests** — Separate test class for:
   - Invalid base64 rejection
   - Non-image base64 rejection (valid base64 but not an image)
   - Oversized model_id
   - Too many frames
   - Too many ignore_labels
   - Invalid enum values (stationary_filter)
   - Invalid sensitivity values

### Rules
- *RBAC before validation* — check roles before spending CPU on data validation
- *Generic error messages* — "Invalid image data" not "PIL cannot identify image file: OSError..."
- *Test page paths must not leak in production* — return "not available" not the filesystem path

### Outputs
- Hardened input validation on all boundaries
- Security test class passing
- No internal state leakage in error responses

---

## Phase 6: Performance Optimization

**Goal:** Identify and fix hot-path bottlenecks. Don't micro-optimize.

### Steps

1. **Profile the request flow** — Where does time go?
   - Base64 decode + PIL validation (CPU-bound, blocks event loop)
   - Model server HTTP round-trip (network-bound, 200-3000ms)
   - Filter application (CPU-bound, usually <10ms)
   - Response serialization (CPU-bound, usually <5ms)

2. **Fix event loop blockers** — Any synchronous CPU work in an async handler should use `asyncio.to_thread()`:
   - PIL image validation → thread pool
   - [[opencv-entity|OpenCV]] frame difference computation → thread pool

3. **Parallelize where possible** — Use `asyncio.gather()` for:
   - Multiple frame validations
   - URL downloads + base64 validation concurrently
   - Multi-model inference

4. **Defer micro-optimizations** — File a GitHub issue for items that are measurably small:
   - Client instance caching
   - Schema generation caching
   - Serialization round-trip elimination

### Rules
- *Model server latency dominates* — don't over-optimize the 5ms items when inference takes 2000ms
- *File issues for deferred items* — don't just note them in a comment, create a trackable issue

### Outputs
- Hot-path blockers fixed
- GitHub issue for deferred micro-optimizations

---

## Phase 7: Documentation

**Goal:** API docs, backend docs, and KB all reflect what was built.

### Steps

1. **External API documentation** (`docs/api/`) — Run `/write-external-docs` or follow [[external-documentation-standards]]. For each new endpoint:
   - Request format with all parameters, types, defaults, and constraints
   - Response format with field descriptions
   - Error codes and when they occur
   - curl examples
   - **Zero internal details** — no role names, infrastructure, library names, file paths, or processing internals
   - Use `<!-- MODEL_TABLE -->` placeholders for role-filtered dynamic content

2. **Backend documentation** (`docs/backend/`) — Update:
   - Security doc (new roles, RBAC patterns, input validation table)
   - Local development doc (new test tools, startup scripts)
   - Model discovery doc (static registry vs dynamic)
   - Adding new endpoints doc (if the pattern changed)

3. **KB synthesis note** — Write to `topics/{relevant-topic}/notes/syntheses/`:
   - What was built and why
   - Files created and modified
   - Security integration details
   - What was deferred and why
   - Test results

4. **KB topic summary** — Update `_summary.md` with:
   - Current roadmap status
   - Phase completion dates

5. **Remove outdated docs** — Delete docs for endpoints/features that no longer exist (e.g., `detection-classes.md` when folded into `models.md`).

### Rules
- *Update docs before merge, not after* — docs are part of the deliverable
- *Delete obsolete docs* — stale docs are worse than no docs
- *Docs sync to Confluence automatically* — changes to `docs/` trigger the sync workflow on push to develop

### Outputs
- All API docs accurate
- All backend docs updated
- KB synthesis note written
- No stale/contradictory documentation

---

## Phase 8: Code Review

**Goal:** Intensive review before merge. Find what testing missed.

### Steps

1. **Read every changed file** — Not the diff, the full file. Understand the context around changes.

2. **Check for:**
   - Imports at module top (not inline in functions)
   - Proper resource cleanup (patches stopped in tearDown, files closed)
   - Unbound variables in conditional paths
   - Unnecessary try/except wrapping (catch-and-re-raise is a no-op)
   - Repeated code that should be extracted (DRY)
   - Type coercion edge cases (int vs float in JSON, bool is subclass of int)

3. **Verify test cleanup** — Every `.start()` has a `.stop()`. Every `dependency_overrides` is reset.

4. **Run lint + full test suite** — After every fix in the review.

5. **Check deprecation warnings** — Are they from our code or pre-existing?

### Rules
- *Fix issues immediately* — don't note them and move on
- *Re-run tests after every fix* — review changes can introduce regressions
- *Separate pre-existing issues from new ones* — note pre-existing but don't mix them into your feature commit

### Outputs
- Clean code with no lint warnings
- All tests passing
- All review findings addressed

---

## Phase 9: Deployment Planning

**Goal:** Safe rollout to dev/stage, then prod.

### Steps

1. **Verify CI/CD compatibility** — Check that:
   - Dockerfile copies all new files (wildcard `ADD` vs explicit paths)
   - No new dependencies that need special auth (CodeArtifact)
   - No new environment variables needed (or add to tfvars)
   - No terraform changes needed (API Gateway routes, Lambda config)

2. **Assess blast radius** — What can break?
   - New endpoints alongside existing — zero risk to existing
   - Shared module extraction — tested, import-only change
   - New security role — additive, doesn't affect existing roles

3. **Manual steps** — Document anything CI doesn't handle:
   - DynamoDB API key creation/update
   - DNS verification
   - Smoke test after deploy

4. **Deploy to dev/stage first** — Merge to `develop` or `stage`, let CI build and deploy. Verify before touching prod.

### Rules
- *Never push to main without dev verification* — prod promotes the dev image, doesn't rebuild
- *Never push to main on actuate-libraries without explicit approval* — triggers auto-publish
- *Document manual steps in the PR description* — reviewers need to know what happens post-merge

### Connector-Specific Deployment

For [[vms-connector]] features that involve [[actuate-libraries]] changes, the deployment process is significantly more complex — involving multi-repo CI coordination, library version stabilization, ECR image builds, and fleet monitoring. See **[[connector-library-deployment-lifecycle]]** for the full step-by-step process.

### Outputs
- Pre-merge checklist complete
- Deployment plan documented
- Manual steps identified
- **Pre-deploy dashboard snapshot** — run `/dashboard-check` to capture the current baseline BEFORE merge. This is the comparison point for post-deploy verification in Phase 10.

---

## Phase 10: Post-Deploy Verification (MANDATORY)

**Goal:** Prove the deployed change actually works in prod/stage. Not "CI passed." Not "deploy workflow succeeded." Observable signals that the core flow runs.

Added after 2026-04-23 onboarder post-mortem ([[2026-04-23_postmortem-onboarder-healthcheck]]) where 47h of silent failure went undetected because no one ran a behavioral check.

### Steps

1. **Wait one real-traffic / cron window.** Cron Lambdas need at least one full cron cycle (e.g., 5 min for the onboarder). Scheduled jobs need at least one execution. Request-driven services need real traffic.

2. **Run repo-level check skill.** Every production-critical repo should have a `/some-check-skill` that encodes the acceptance criteria. If one doesn't exist yet, that's a prerequisite — write the skill before declaring the release verified.

3. **Run `/dashboard-check`.** The cross-repo dashboard snapshots every signal and flags red/yellow. Verify:
   - All components touched by this release are GREEN
   - No regressions vs the pre-deploy snapshot from Phase 9
   - No regressions vs the 7-day trailing baseline

4. **Grep for activity-marker log lines.** `Errors=0` is NOT a health signal if the service is silently returning early. Grep for the thing that proves the work happened:
   - Lambda: "Fetched N contracts", "processing schedule_id=", "activating X"
   - API: 2xx on key endpoints with non-empty response bodies
   - Connector: frames processed, alerts fired, inference calls made

5. **Confirm no new ERROR patterns.** Diff against pre-deploy baseline. Any new error pattern must be explained or investigated.

6. **Document the verification.** Post in the PR: "Verified at [timestamp]: [signal A observed] / [signal B in range] / [dashboard GREEN]." This is the closure step — no release is complete without it.

### Rules

- *A release is not verified until the dashboard is GREEN against the deployed component.* Every launch, every time. No exceptions.
- *If verification fails, roll back immediately.* Don't debug forward on live customer flows. Restore the known-good state, then investigate.
- *`Errors=0` is not sufficient.* Silent early returns have 0 errors. Require activity-marker signals.
- *Every launch includes a post-deploy `/dashboard-check` run.* Every morning too (daily-scope ritual). The dashboard is the shared truth.

### Outputs

- Dashboard GREEN on affected component for at least one cycle
- Activity-marker log lines grep'd and confirmed > 0
- No new error patterns vs pre-deploy baseline
- Verification comment posted to the PR

---

## Full Lifecycle Diagram

```
Context Gathering ──→ Architecture Review ──→ Implementation Planning
        ↓                     ↓                        ↓
    KB lookup            ADR creation              Plan file
    Codebase explore     Team Q&A                  User approval
    Jira/Confluence      Decision docs             Daily schedule
                                                        ↓
                                               Implementation
                                                   ↓
                                    ┌──────────────┼──────────────┐
                                    ↓              ↓              ↓
                              Security         Performance    Documentation
                              Hardening        Optimization   Update
                                    ↓              ↓              ↓
                                    └──────────────┼──────────────┘
                                                   ↓
                                             Code Review
                                                   ↓
                                          Deployment Planning
                                             (+ pre-deploy dashboard snapshot)
                                                   ↓
                                            Merge → CI → Dev
                                                   ↓
                                           Verify → Promote → Prod
                                                   ↓
                                    Post-Deploy Verification (Phase 10)
                                     • one real cycle
                                     • repo-level check skill
                                     • /dashboard-check GREEN
                                     • activity-marker greps
                                     • document in PR
```

---

## Reference Implementation

This lifecycle was first executed on the [[inference-api/_summary|Actuate Inference API]] v5 project (ED-32, April 2026). For the concrete timeline, file paths, and project-specific details, see [[v5-implementation-patterns]] in the inference-api topic.
