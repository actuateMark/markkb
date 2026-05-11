---
title: "Immix API zombie tenants — tenant_ids referenced in connector flow that return no data"
type: concept
topic: autopatrol
tags: [immix, autopatrol-onboarder, api-contract-violation, tenant-cascade, eu, zombie-tenants, immix, immix, immix, immix]
jira: ""
confluence: ""
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
incoming:
  - topics/admin-api/notes/concepts/2026-04-30_data-model-cascade-semantics.md
  - topics/admin-api/notes/syntheses/2026-04-30_autopatrol-state-audit.md
  - topics/autopatrol/notes/concepts/2026-04-23_immix-api-error-patterns.md
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/autopatrol/notes/entities/immix-vendor-api.md
  - topics/autopatrol/notes/syntheses/2026-05-07_consumer-side-websocket-close-feasibility.md
  - topics/personal-notes/notes/concepts/2026-04-29_cleanup-handoff.md
  - topics/personal-notes/notes/concepts/2026-04-30_admin-propagation-handoff.md
  - topics/personal-notes/notes/daily/2026-04-29.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-08
---

# Immix API contract violation — connector-flow tenant_ids return no data

**Reporting org:** Actuate
**Surfaced from:** `/aws/lambda/immix-autopatrol-onboarding` (eu-west-1), routine 5-min polling cycle
**Date observed:** 2026-04-29 (persistent for ≥7d, likely longer — predates 7-day log retention window)
**Severity:** Operationally noisy + design-blocking — these tenants have schedules in our admin DB that we cannot reconcile against Immix because the API will not return anything for them

## Tenant ID → name mapping (admin DB lookup, 2026-04-29)

| tenant_id | Region | Immix tenantName | Immix status | Admin DB customers (active) | Sample customer naming pattern |
|---|---|---|---|---|---|
| `c3047b59-ef3d-41e5-935b-c310dd6c79df` | EU | NOT in Immix /Contracts | gone (zombie) | **10** | Danish addresses — "00007891 - Lindevej 8", "00106331 - CBJ", "00251118 - Christoffer DJK Test", "XML Test", "00666666 - TEST" — looks like Danish customer test/demo tenant |
| `0d11fe79-450e-4f91-96e9-be471d2558c4` | EU | NOT in Immix /Contracts | gone (zombie) | **0** | No customer rows in admin DB — orphaned tenant_id reference (open question: where is the onboarder getting this ID?) |
| `b594cbbe-b7f0-4efb-b4b3-51e28520c2f5` | EU | NOT in Immix /Contracts | gone (zombie) | **0** | Same — 0 admin DB rows |
| `5b16b587-eb18-48d3-ac76-7f5f1b87c5d7` | EU | (didn't probe — network timeout case) | unknown | **60** | UK construction sites — "Barton Quarter Bellway Manchester", "Halewood Oaks Tower 5", "Bellway Holt Vale Tower" (Bellway / Solar CCTV / Hik branded) |

**For comparison — the §16 KNOWN-Suspended canaries (which DO work cleanly with our cascade design):**

| tenant_id | Region | Immix tenantName | Immix status | Admin DB customers (active) | Sample customer naming |
|---|---|---|---|---|---|
| `0ee7cb3f-4a3a-49b0-bcb5-73fce964b427` | US | Remote Security Solutions | Suspended/Suspended ✓ | 12 | T-Mobile + AT&T cellular sites — "1146 - NM01206E Montgomery, T-Mobile (TIER 2)", "200 - Cobb Parkway, AT&T", "242 - Chester Avenue, AT&T (TIER 2)" |
| `ac399cd6-2fdf-4659-b8e5-baea54075017` | US | Legacy | Suspended/Suspended ✓ | 66 | "AIS" + "iWatch" branded — "3680/West Marine/Aldi-AIS", "Capitol Smoke - iWatch", "Beard Equipment Mobile-AIS" |

**Probed via:**
- Immix US prod: `GET /Contracts` → tenantStatus inspection (US contract inventory 18 tenants)
- Immix EU prod: `GET /Contracts` → all 3 zombies absent from 18-tenant EU inventory; direct probes returned 400/401/empty body
- Admin DB: `https://admin.actuateui.net/api/customer/?group__tenant_id={id}&page_size=250` (US prod), `https://admin.actuateui.eu/api/customer/?group__tenant_id={id}&page_size=250` (EU prod). Token: `prod/actuate/postgres` Secrets Manager key `api-token-prod`.

## What's broken

Three tenant_ids that Immix is **simultaneously** (a) referenced as the active context for our connector flows AND (b) returning errors / no data when we query Immix for them. The same Immix `Ocp-Apim-Subscription-Key` / `Region-Override: EU` works fine for 18 other tenants on the same call sites — these specific tenant_ids are the broken set.

Failure pattern is **persistent on every poll cycle** (every 5 min, billing 76–97 sec/invocation just retrying). Not a transient Immix outage — the same tenant_ids fail every poll for at least the entire 7-day log retention window.

## Tenant 1: `c3047b59-ef3d-41e5-935b-c310dd6c79df`

Symptom: every poll attempts to fetch 3 specific sites; all 3 return empty body.

| Call | Endpoint | Response |
|---|---|---|
| GET /Sites/22325 | https://autopatrol.immixconnect.com/v/Sites/22325 (header tenantId: c3047b59-…, Region-Override: EU) | 200 with empty body b'' — JSON parser throws "Expecting value: line 1 column 1 (char 0)" |
| GET /Sites/22176 | same shape | 200 with empty body |
| GET /Sites/21220 | same shape | 200 with empty body |
| GET /Sites/{id} (direct probe today, same headers) | site 22325/22176/21220 | 401 "Unauthorized - No Tenant Found" |

Listing presence: tenant NOT in GET /Contracts?pageNumber=1&pageSize=100 response (which returns 18 contracts under Region-Override: EU). Tenant has no contractStatus / tenantStatus exposure — completely absent from the contracts inventory.

Frequency: ~1,730 error log lines / 24h (6 per invocation × 288 invocations).

**Admin DB state:** 10 active customer rows in EU prod admin DB. Sample names: "00007891 - Lindevej 8", "00106331 - CBJ", "00158971 - Krosvinget 4 (Horne)", "00251118 - Christoffer DJK Test", "00257583 - CWR", "00293702 - KC Anråbs Test", "00483110 - Kundehuset (DJK)", "00666666 - TEST", "00xxxxxx - TEST", "XML Test". The naming convention (Danish street addresses + "TEST" entries) suggests this was a customer-test or demo tenant on the Danish side. **These 10 customers are orphaned — they'll never be cleaned by the §16 cascade because Immix doesn't surface this tenant as Suspended; it just omits it entirely.**

## Tenant 2: `0d11fe79-450e-4f91-96e9-be471d2558c4`

Symptom: contract fetch fails with explicit "not found" body.

| Call | Endpoint | Response |
|---|---|---|
| GET /Contracts/0d11fe79-… | https://autopatrol.immixconnect.com/v/Contracts/0d11fe79-450e-4f91-96e9-be471d2558c4 (header tenantId: 0d11fe79-…, Region-Override: EU) | HTTP 400, body: "Contract with this ID not found" |

Lambda retry policy: 3 attempts back-to-back, all fail, then "Failed to get contract info after 3 attempts". Repeats every 5 min.

Listing presence: same tenant NOT in GET /Contracts response.

API contract issue: 400 Bad Request is the wrong HTTP semantic for "this resource does not exist." Per RFC 9110 §15.5.1, 400 means the request itself is malformed (bad syntax). For "ID not found", the correct response is 404 Not Found. We can't distinguish "your request is broken, fix the client" from "the data is gone, this is a cleanup signal" — both look like 400.

Frequency: ~3 retries × 288 invocations = ~864 attempts / 24h, all failing.

**Admin DB state:** 0 active customer rows. The tenant_id is not present in our admin DB at all. This raises a separate question — **where is the onboarder getting this tenant_id from?** Possibilities: (1) stale in-memory cache from a previous Immix /Contracts response that included it; (2) a hardcoded reference; (3) it's read from a dead entry in admin DB that's not surfaced via the customer/group endpoint. Worth a separate investigation. The operational impact here is "wasted Lambda time" rather than "orphaned customer data."

## Tenant 3: `b594cbbe-b7f0-4efb-b4b3-51e28520c2f5`

Symptom: sites listing for this tenant returns 400 permanent failure; the same tenant returns 401 when probed directly.

| Call | Endpoint | Response |
|---|---|---|
| GET /Sites?pageNumber=1&pageSize=100 | https://autopatrol.immixconnect.com/v/Sites?pageNumber=1&pageSize=100 (header tenantId: b594cbbe-…, Region-Override: EU) | HTTP 400 — Lambda log: "permanent failure, will not retry" |
| GET /Sites?pageNumber=1&pageSize=100 (direct probe today, same headers) | same | HTTP 401, body: "Unauthorized - No Tenant Found" |

Listing presence: tenant NOT in GET /Contracts response.

API contract issue (compounded): the SAME tenant_id + SAME auth credentials + SAME endpoint returns INCONSISTENT status codes — 400 from one call site, 401 from another. Both indicate "tenant doesn't exist" but use different HTTP semantics. 401 for "tenant doesn't exist" is wrong — 401 means the credentials are bad, but our credentials work for 18 other tenants on the same connection.

Frequency: 288 events / 24h (1 per invocation).

**Admin DB state:** 0 active customer rows. Same orphaned-reference pattern as Tenant 2. Same open question about source of the tenant_id.

## Honorable mention: `5b16b587-eb18-48d3-ac76-7f5f1b87c5d7`

Symptom: connection timeout, intermittent (2 occurrences in 24h vs persistent failures above).

```
auto patrol get site error: HTTPSConnectionPool(host='autopatrol.immixconnect.com', port=443):
  Max retries exceeded with url: /v/Sites/123 (Caused by ConnectTimeoutError(...,
  'Connection to autopatrol.immixconnect.com timed out. (connect timeout=None)'))
  tenant_id: 5b16b587-eb18-48d3-ac76-7f5f1b87c5d7  site_id: 123
```

Different failure mode — network-side, not API-contract — but flagged for completeness.

**Admin DB state:** 60 active customer rows. UK construction-site naming pattern (Bellway / Solar CCTV / Hik branded) — e.g. "Barton Quarter Bellway Manchester", "Halewood Oaks Tower 5", "Bellway Holt Vale Tower". This appears to be a real, active tenant — the network timeout was likely a one-off DNS/connection blip, not a structural API issue.

## Summary of API contract violations

| Violation | Affected tenant(s) | What Immix is doing | Correct behavior |
|---|---|---|---|
| A. 200 OK with empty body for resource that doesn't exist | c3047b59 (sites 22325, 22176, 21220) | Returns 200 + empty b'' body; JSON parser throws | Return 404 Not Found with explicit error body |
| B. 400 Bad Request for "ID not found" | 0d11fe79 (contracts) | Returns 400 + "Contract with this ID not found" | Return 404 Not Found. 400 means malformed request |
| C. 401 Unauthorized for "tenant doesn't exist" | b594cbbe, c3047b59 (direct probe) | Returns 401 + "Unauthorized - No Tenant Found" with valid credentials that work for 18 other tenants | Return 404 Not Found. 401 means credentials are bad |
| D. Inconsistent status codes for the same tenant on the same endpoint | b594cbbe (400 from one call site, 401 from another) | Same tenant_id, same auth, same endpoint → different HTTP codes | Single canonical response |
| E. No way to enumerate that a tenant is gone | All three | GET /Contracts listing omits these tenants entirely with no notification mechanism (no `Removed` status, no soft-delete flag). Onboarder has no way to learn the tenant is gone — it just retries the failing call forever | Either expose a tenantStatus=Removed/Deleted value in the contracts listing, OR a GET /Tenants/{id} endpoint that returns 404 with a documented body so we can detect "gone" cleanly |

## Why this is design-blocking for our cleanup work

Actuate is currently rolling out a tenant-cascade-disable feature that uses Immix's tenantStatus=Suspended as the signal to soft-delete every schedule + customer under that tenant in our admin DB. This works for the 2 tenants currently flagged Suspended in Immix prod (Remote Security Solutions, Legacy).

It does NOT work for the 3 zombie tenants above because they're not flagged as anything — they're just gone, with no API surface that tells us they're gone. Without a way to detect "tenant is removed", the onboarder will keep polling Immix for them indefinitely, and our admin DB's schedules under them stay active forever even though Immix has deleted the upstream tenant.

## Operational impact summary

| Bucket | tenant_ids | Admin DB orphaned rows | What §16 cascade does today | What we need |
|---|---|---|---|---|
| Immix says Suspended | RSS (`0ee7cb3f`), Legacy (`ac399cd6`) | 12 + 66 customers (and ~12 + 74 schedules per stage probe) | ✓ Cascades correctly when flag flipped | Already works — just complete the rollout |
| Immix says nothing (zombie, has admin orphans) | `c3047b59` (Danish tenant, EU) | 10 customers + unknown schedules | ✗ Never triggers — no Suspended status to detect | Fix from Immix (point 1, 2, or 3 above) OR §16 design extension to detect "absent from /Contracts" |
| Immix says nothing (zombie, no admin orphans) | `0d11fe79`, `b594cbbe` (EU) | 0 each — no impact on customer data, just wasted Lambda cycles | ✗ Never triggers | Fix from Immix + investigate the source of these tenant_id references in our codebase |

## Q2 verification (2026-04-29): Immix returns Suspended for RSS + Legacy as expected

Verified live against Immix US prod:

- `GET /Contracts` (full listing) — 18 contracts returned, `(contractStatus, tenantStatus)` distribution:
  - `'Active' / 'Active'`: 14
  - `'Cancelled' / 'Active'`: 2
  - `'Suspended' / 'Suspended'`: **2** ← these are RSS + Legacy
- `GET /Contracts?contractStatus=Suspended` — server-side filter returns **exactly RSS + Legacy**

Per-canary breakdown:
| Canary | contractId | contractStatus | tenantStatus | tenantName |
|---|---|---|---|---|
| RSS | `2044035a-53f0-4097-a07a-7f3b0862f32d` | Suspended | Suspended | Remote Security Solutions |
| Legacy | `5f8170a3-5205-4e71-a0b7-74a69888576a` | Suspended | Suspended | Legacy |

This confirms the §16 cascade trigger's input source works correctly — it's the EU zombie pattern that's NOT covered, not the Suspended detection itself.

What we need from Immix to fix this:

1. Either a per-tenant lookup endpoint (e.g., GET /Tenants/{id}) that returns 404 with a documented body when the tenant is gone — so we can call it and definitively know
2. Or include removed tenants in the GET /Contracts listing with a tenantStatus=Removed (or Deleted) value, so we can detect them in the same poll we already do
3. Fix the inconsistent status codes (200/empty, 400, 401) — replace with 404 consistently for "resource not found"

## Reproduction (for Immix engineering)

Each request signature:
```
Headers:
  Ocp-Apim-Subscription-Id: actuate
  Ocp-Apim-Subscription-Key: <our prod key>
  Region-Override: EU
  tenantId: <one of the 3 tenant_ids above>
  Cache-Control: no-cache
```

The same key + the same call sites return 200 with valid bodies for the 18 other tenant_ids in our EU contracts list (verified live 2026-04-29).

## Cross-references

- [[2026-04-28_tenant-status-sync-gap]] — original tenant-status sync investigation; this note extends it with the "zombie tenant" pattern (gone-from-Immix-entirely vs Suspended)
- [[2026-04-23_immix-api-error-patterns]] — catalog of [[immix-vendor-api|Immix API]] non-RESTful behaviors (this is another entry in that catalog)
- [vms-connector#1656](https://github.com/aegissystems/vms-connector/issues/1656) — similar contract violation: /Patrols/{id}/raise requires GUID streamId from the very call that's failing
- [autopatrol_onboarder PR #7](https://github.com/aegissystems/autopatrol_onboarder/pull/7) — workaround for similar issue: Immix returned 400 + "system is unavailable" for schedules that were actually gone
- [[autopatrol-onboarder]] — entity note for the EU Lambda that surfaces these
- [[2026-04-29_cleanup-handoff]] — session handoff doc that triggered this investigation

## Open follow-ups

- [ ] Pull schedule_ids + customer_ids under these 3 tenants from our admin EU DB once #2377 hits prod admin — strongest evidence of operational impact
- [ ] §16 design extension: detect "tenant absent from contracts list" as a third bucket alongside Suspended and Active. The cascade trigger should fire on absent-from-list too. Required before EU rollout (Step G) ships.
- [ ] Ticket / Slack thread to Immix engineering with this writeup
- [ ] Update [[2026-04-23_immix-api-error-patterns]] with the violations A-E listed above
- [ ] Investigate where `0d11fe79` and `b594cbbe` tenant_id references originate. They're not in Immix's contracts list and not in admin DB customer rows. Check (1) onboarder in-memory state caching, (2) any hardcoded tenant lists, (3) other admin tables (group? autopatrol_schedule? deleted-but-not-purged contract row?).
- [ ] Schedule-count probe on `c3047b59`'s 10 customer rows — once #2377 hits prod admin, dry_run the cascade endpoint against this tenant_id to get exact schedule scope. Strongest possible evidence for the Immix conversation.
