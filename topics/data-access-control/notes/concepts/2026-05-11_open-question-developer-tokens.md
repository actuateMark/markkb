---
title: "Open Question — Developer-Tier Tokens + Endpoint Composition Pathway"
type: concept
topic: data-access-control
tags: [open-question, team-discussion, developer-tokens, api-composition, scoping]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
outgoing:
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-db-access-hardening.md
status: needs-team-discussion
incoming:
  - topics/data-access-control/_summary.md
  - topics/data-access-control/notes/syntheses/2026-05-13_dig-followups.md
  - topics/data-access-control/team-brief.md
  - topics/personal-notes/notes/concepts/2026-05-11_next-session-handoff.md
  - topics/personal-notes/notes/daily/2026-05-11.md
incoming_updated: 2026-05-27
---

# Open Question — Developer-Tier Tokens + Endpoint Composition Pathway

> **Status:** Needs team discussion. Tied to the broader scope-vocabulary work in [[2026-05-11_admin-db-access-hardening|admin DB access hardening]]. This note exists to scope the discussion and surface specific design questions.

## TL;DR

Phase 2 of the hardening plan moves every application onto scoped API tokens. Engineers also need personal tokens for `curl`-style use, debugging, ad-hoc reads. The natural answer is **same scope vocabulary as service tokens, just issued to humans** ("developer-tier"). The real concern isn't the auth model — it's the **friction of adding a new admin endpoint** when a developer hits something that doesn't exist yet. If that friction is too high, developers will route around it by reaching for the shared CLI cred, and we drift back to today.

**Question for the team:** what does a frictionless "I need a new admin endpoint" pathway look like, and is there an "API composition" library/pattern that makes it cheap?

## Why this matters

The whole hardening initiative depends on developers preferring the scoped token + admin API path over the shared cred + direct SQL path. That preference is enforced primarily by **friction**: if adding an endpoint takes a week, developers will do `psql` instead. If adding an endpoint takes 30 minutes, they won't.

Today's pattern for adding a new admin endpoint:

1. Open admin codebase.
2. Define a serializer.
3. Write a viewset (or extend one).
4. Wire it into a router.
5. Update OpenAPI / Swagger annotations.
6. Write tests.
7. Open a PR; wait for review; merge; deploy admin.
8. Update `actuate-admin-api` client library with a typed method.
9. Open a PR there; wait for review; merge; CodeArtifact publish.
10. Bump pin in consumer; uv lock; deploy consumer.

That's potentially multiple days of round-trip across two repos and a CodeArtifact publish cycle, for what's often "I want to list field X on resource Y."

If we ship Phase 2 without making that cheaper, developers will (correctly) view scoped-token+API as more expensive than direct DB, and we'll have a discipline problem that no amount of policy can fix.

## What "developer-tier" tokens probably look like

Provisional shape (subject to discussion):

- **Issued via the same mechanism** as service tokens — extends `ExternalApiSetUp` to support a "human" account type.
- **Bound to the developer's SSO identity.** Cognito + Token; revocation tied to offboarding.
- **Scoped via the same resource:verb vocabulary** that service tokens use. A developer's token might have `cameras:read`, `customers:read`, etc., but typically not `cameras:write` unless explicitly elevated.
- **Default short-lived** (e.g., 7-day rotation enforced) to bound exposure.
- **Audit-traced** identically to service tokens — every call attributable.
- **Elevated tokens** (e.g., one with `cameras:write` scope) require an explicit issuance step + audit log + Slack notice. Same break-glass shape as the CLI policy in §5 of the parent synthesis.

This part is mostly mechanical and doesn't need much team discussion. The hard part is below.

## The friction problem — endpoint composition

When a developer wants to do something admin's API doesn't expose, what's the cheapest path that's still safe?

### Option A — DRF scaffolding (`startapi`-style generator)

A management command (`./manage.py scaffold_api_endpoint <resource> <verb>`) generates the serializer + viewset + router wiring + tests + OpenAPI annotation in one shot. Developer fills in the query logic and submits a PR.

**Buys:** Cheap mechanical setup; consistent shape; low friction for the common case ("expose existing model X with these fields").
**Costs:** Generator code to maintain. Still requires a PR + deploy cycle. Doesn't help with custom queries that don't fit the "model exposure" shape.

### Option B — Declarative API composition library

A library that lets engineers describe an endpoint as data, not code:

```python
# Something like:
@api_endpoint(scope="cameras:read", path="/cameras/by_site/{site_id}")
def list_cameras_by_site(site_id: int) -> list[CameraSchema]:
    return Camera.objects.filter(site_id=site_id)
```

The library handles serializer generation, scope wiring, OpenAPI, tests.

**Buys:** Much smaller surface to add an endpoint. The endpoint *is* a function + decorator, not 4 files.
**Costs:** Library code to design and maintain. Constrained expressiveness — anything outside the library's model has to drop down to full viewset.

### Option C — OpenAPI-first generation

Engineer writes an OpenAPI spec change; codegen produces serializer + viewset stubs + client lib method on both sides (admin + `actuate-admin-api`).

**Buys:** Spec is the source of truth. Client lib stays in sync automatically. Naturally supports versioning.
**Costs:** Codegen tooling investment. Friction is moved (write a spec instead of write code) rather than eliminated. Two-way generation is hard to get right.

### Option D — Just keep the current friction, accept some shared-cred fallback

Don't invest in tooling. Accept that a small fraction of developer ad-hoc reads will route through a shared "developer break-glass" cred, audited and rate-limited.

**Buys:** No tooling investment.
**Costs:** Discipline drift over time. The hardening initiative becomes less effective in proportion to how much developers actually use the break-glass path.

## Questions to land in the discussion

1. **How much of developer ad-hoc DB access today is "expose existing model X with these fields" vs. genuinely custom queries?** If 80% is the former, Option A or B is high-ROI. If 50% is custom analytics, Option D might be more honest.
2. **Does the team have appetite for tooling investment up front?** Options A/B/C all require dedicated build time before they pay off.
3. **What's the right ratio of "any developer can do this" vs. "admin maintainer reviews it"?** Some developers should be able to add endpoints freely; some changes need careful review (anything touching billing, integrations, etc.). The PR review process needs to differentiate.
4. **Should we have a separate `admin-extensions` repo / module** for developer-driven endpoints that aren't owned by admin maintainers, so the PR-review burden doesn't fall on Tatiana for every small add?
5. **What's the SLA for endpoint additions?** If a developer needs an endpoint to unblock work, what's the expected turnaround — same day? Same week?
6. **Does Vini's external-API work already have an opinion here?** If partner-facing endpoints follow a pattern, the internal pathway could just be "do that, but for internal scope tokens."

## Mark's lean

I lean toward **Option B (declarative composition library) as the long-term path**, with **Option A (scaffolding) as the interim** while the library is being designed. Reasons:

- Most admin endpoint additions are mechanically similar; a declarative shape captures the common case cheaply.
- Scaffolding pays off immediately and the generated code is easy to migrate to the library later.
- Option C (OpenAPI-first) is appealing in principle but codegen tooling has a long tail of edge cases. I'd reach for it only if we discover the declarative library doesn't compose well.

But this is the call where I have the least informed opinion — the team has more context on what kinds of endpoint adds are actually common, and whether the PR-review bottleneck is real or imagined.

## Decision needed by

Phase 2 can start without this decision (we can use today's "manual endpoint addition" pattern for the initial cutover of the 4 Bucket B sites). But this decision must land before we declare Phase 2 done, because by then we'll have committed developers to the scoped-token path and the discipline question becomes load-bearing.

## Cross-references

- [[2026-05-11_admin-db-access-hardening]] — parent synthesis
- [[2026-05-11_admindao-call-site-inventory]] — Phase 2 migration scope
- [[2026-05-11_open-question-vini-gateway]] — sibling open question; some overlap if Vini's auth tooling becomes shared
