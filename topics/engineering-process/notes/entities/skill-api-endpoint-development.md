---
title: "Skill: /api-endpoint-development"
type: entity
topic: engineering-process
tags: [skill, api, fastapi, swagger, pydantic, endpoints]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# /api-endpoint-development

Skill for building FastAPI endpoints with production-quality Swagger documentation and security integration.

## What It Covers

1. **Pydantic models with Swagger examples** — `json_schema_extra.examples` on every request/response model so Swagger shows realistic data instead of `"string"`, `0`, or `additionalProp` placeholders
2. **Schema-as-contract** — per-resource Pydantic schemas for unified endpoints serving multiple resource types, exposed via discovery endpoint
3. **RBAC integration** — role enum, check function, docs mapping, dynamic per-resource role checking before validation, role-filtered discovery and error hints
4. **Input validation** — bounds on every user-controlled field, PIL image validation in thread pool, int/float/bool coercion handling
5. **External documentation** — chains to `/write-external-docs` for partner-facing docs with zero internal leaks
6. **Testing** — functional, validation, and role enforcement test patterns

## When to Use

- Adding new API endpoints
- Adding new resource types to existing endpoints
- Reviewing Swagger documentation quality
- Auditing endpoint security

## Skill Chain

```
/api-endpoint-development → /write-external-docs → /validate-release
```

## Reference Implementation

See [[v5-implementation-patterns]] in the inference-api topic for the concrete file paths and project timeline.

## Related

- [[feature-development-lifecycle]] — Phase 4 references this skill
- [[external-documentation-standards]] — prose rules and leak prevention
- [[security-hardening-checklist]] — input validation and RBAC standards
- [[pydantic-schema-as-contract]] — the schema validation pattern
