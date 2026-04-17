---
title: "Agent: actuate-pr-reviewer"
type: entity
topic: engineering-process
tags: [agent, pr-review, security, code-review, context-protection]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# actuate-pr-reviewer

Actuate-specific PR reviewer. Applies the KB's written standards, not generic best practices. Returns blockers / should-fix / nits / missing, with citations back to KB rules.

**File:** `/home/mork/.claude/agents/actuate-pr-reviewer.md`
**Model:** opus
**Mode:** read-only (identifies issues, does not fix)

## When to Use

- Any PR in `/home/mork/work/` repos (vms-connector, actuate_admin, actuate-inference-api, actuate-libraries, etc.)
- Pre-merge security audit of a branch
- Review of a specific file/module against the security checklist

## When NOT to Use

- Non-Actuate repos
- Trivial one-liners (typo fixes, version bumps) — overhead isn't worth it
- When you need the review to *fix* things — the agent only identifies

## What It Enforces (in order)

1. **Security** — RBAC before validation, bounded inputs, generic errors, role-filtered list endpoints, role-filtered 404 hints
2. **Pydantic contracts** — `json_schema_extra.examples`, per-resource schemas, discovery endpoint, `ENDPOINT_ROLE_MAPPING` consistency
3. **Test coverage** — functional + validation + role-enforcement tests; integration tests where the KB mandates real services
4. **Docs sync** — `docs/backend/security.md`, `docs/api/v5/*`, connector CLAUDE.md, per-model pages
5. **Ops hygiene** — uv.lock consistency, CI green, no accidental `actuate-libraries` main push

## Reference Rules Baked In

- [[security-hardening-checklist]]
- [[code-review-checklist]]
- [[pydantic-schema-as-contract]]
- [[external-documentation-standards]]

## Reporting Format

Structured markdown: Blockers / Should-fix / Nits / Missing / Summary. Every issue cites the KB rule it violates. Target < 500 words.

## Skill Callers

| Skill | Where in skill | Notes |
|-------|----------------|-------|
| `/api-endpoint-development` | Phase 7/8 pre-commit self-review | Validates output against security + pydantic-as-contract rules |
| `/stage-release` | Step 2 (after PR creation, before CI watch) | Pre-merge self-review |
| `/write-external-docs` | Step 5 (verify / internal-leak audit) | Applies external-documentation-standards |

## Related

- [[agents-catalog]]
- [[skill-api-endpoint-development]] — the skill this agent reviews output of
- [[feature-development-lifecycle]] — where PR review slots in
