---
title: "Tenant-Status Sync Gap — Suspended Tenants Stay Active in Admin"
type: concept
topic: autopatrol
tags: [tenant, sync, suspended, onboarder, cleanup-lambda, admin, gap, finding, immix]
created: 2026-04-28
updated: 2026-04-28
author: kb-bot
---

# Tenant-Status Sync Gap

## The reported problem

Customer / Immix-side: tenants that go SUSPENDED on the Immix side do not flow through to our admin DB — sites and schedules under those tenants stay marked active forever, and connectors keep trying to run patrols against them. Manifests as "ghost" cameras / schedules in the admin UI for accounts the customer has actually paused.

## What we have today

- The [[autopatrol-onboarder|main onboarder Lambda]] (`immix-autopatrol-onboarding`, US + EU) calls `get_contracts()` every 5 min and processes the full result.
- For each contract it fetches `get_sites(tenantId)` then `get_devices(tenantId, siteId)`, builds a per-site dict, and POSTs to `auto_patrol/sync/` on admin.
- The site dict at `lambda_function.py:222-229` includes `siteId`, `siteName`, `devices`, `tenantId`, `tenantName`, `contractId`, `contractStatus`, `region` — but **NOT `tenantStatus`**.
- Admin's `/auto_patrol/sync/` creates / updates sites; per the in-code comment at `lambda_function.py:266-272`, the cleanup methods (`cleanup_sites/cameras/old_sites` in `actuate_admin`) are **dead code** and never called. **There is no reconciliation pass that disables admin-side sites when a tenant goes suspended.**
- The [[autopatrol-cleanup-lambda|cleanup Lambda]] (`immix-autopatrol-schedule-cleanup`) does classify Paused/Suspended/Removed/Deleted at the **schedule** level via `get_patrol_stream(schedule_id)` (per PR #9, deployed 2026-04-27), but not at the tenant level.

## Investigation (probe run 2026-04-28)

Live probe against Immix prod (`autopatrol.immixconnect.com/v`) using the prod Lambda's API key. Probe script: `autopatrol_onboarder/scripts/probe/tenant_status_probe.py`.

| Hypothesis | Result |
|---|---|
| H1: `GET /Tenants/{id}` exists | **404** — endpoint does not exist |
| H2: `GET /Tenants` listing exists | **404** — endpoint does not exist |
| H3: `get_contracts()` response includes a tenant-status field | **YES** — every contract dict has `tenantStatus` (and `contractStatus`) |
| H3c: `?contractStatus=Suspended` URL filter works server-side | **YES** — returns the suspended subset directly |
| H4: `get_sites(tenant)` items include a per-site status field | **NO** — only `devices`, `siteId`, `siteName` |

### Inventory snapshot — 2026-04-28 prod

```
contracts returned: 18

(contractStatus, tenantStatus) → count:
  'Active'    / 'Active':    14
  'Cancelled' / 'Active':     2
  'Suspended' / 'Suspended':  2

Non-Active-tenant contracts: 2
  tenantId=0ee7cb3f-4a3a-49b0-bcb5-73fce964b427  tenantName='Remote Security Solutions'  Suspended/Suspended
  tenantId=ac399cd6-2fdf-4659-b8e5-baea54075017  tenantName='Legacy'                     Suspended/Suspended
```

**Two tenants are CURRENTLY suspended in Immix prod and our admin DB has them as active.** Their sites and schedules are still in admin and (presumably) still being patrolled / generating "no patrols" signals.

The chronic anomaly-reset flappers in [[autopatrol-cleanup-lambda]] (`fbdfdba6`, `c3808175`, `ee1822f1`) are **NOT** suspended at the tenant level (their tenant is `Vendor.Actuate.Prod`, status=Active). Their flapping is a separate schedule-level issue — closing this tenant gap won't fix the flappers but will close a different real gap.

## Architectural answer

**Add tenant-status check to the cleanup Lambda as the first call** (Mark's call, 2026-04-28). The cleanup Lambda already receives a per-schedule signal that includes `tenant_id` in the SQS message payload. Before running the existing per-schedule classification, check whether the tenant is suspended; if yes, cascade-disable every site + schedule under that tenant in admin and skip the per-schedule path.

Why this fits better than onboarder-side handling:

- **Lazy / event-driven** — runs only when a "no patrols" signal fires (which is a strong proxy for "this tenant stopped doing things"). Avoids paying full-sweep cost every 5 min for a state change that's rare.
- **Re-uses existing infrastructure** — the cleanup Lambda already has the autopatroller client, admin client, retry semantics, NR instrumentation, and the SQS-FIFO retry-idempotency fix from PR #5.
- **No new component** — no extra IAM, no extra deploy chain, no extra alarms.
- **Naturally idempotent** — if the tenant is already suspended on our side, the cascade disable is a no-op.

Tradeoff vs onboarder-side: a suspended tenant whose connectors don't emit `no_patrols` for some reason will go undetected until something changes. Acceptable — the connectors WILL emit `no_patrols` on schedule boundaries (every cadence), so within a few hours of suspension the cleanup Lambda will see it.

## Implementation sketch

### Cleanup Lambda

```python
# At top of cleanup_lambda.process_record(), before existing classification:

# 1. Fetch suspended tenants once per cold-start, cache in module scope
_SUSPENDED_TENANTS: set[str] | None = None
_SUSPENDED_TENANTS_FETCHED_AT: float = 0
_SUSPENDED_TENANTS_TTL = 600  # 10 min — refresh per warm Lambda

def _get_suspended_tenants(autopatroller) -> set[str]:
    global _SUSPENDED_TENANTS, _SUSPENDED_TENANTS_FETCHED_AT
    now = time.monotonic()
    if _SUSPENDED_TENANTS is None or now - _SUSPENDED_TENANTS_FETCHED_AT > _SUSPENDED_TENANTS_TTL:
        # Use the server-side filter — returns only suspended contracts (tiny list)
        url = f"{autopatroller.base_url}/Contracts?pageNumber=1&pageSize=100&contractStatus=Suspended"
        r = autopatroller.request("GET", url, headers={}, data={})
        if r.status_code == 200:
            contracts = r.json().get("contracts", [])
            _SUSPENDED_TENANTS = {c["tenantId"] for c in contracts if c.get("tenantStatus") == "Suspended"}
            _SUSPENDED_TENANTS_FETCHED_AT = now
        # if the call fails, keep the old cache (fail-soft)
    return _SUSPENDED_TENANTS or set()

# 2. Early-exit branch in process_record:
def process_record(record, autopatroller, admin_api, ...):
    tenant_id = record["tenant_id"]
    if tenant_id in _get_suspended_tenants(autopatroller):
        # Cascade-disable everything under this tenant in admin (idempotent)
        admin_api.disable_tenant(tenant_id, reason="immix_tenant_suspended")
        emit_nr_event(type="TenantCascadeDisabled", tenant_id=tenant_id, ...)
        return  # skip per-schedule classification
    # ... existing per-schedule classification path ...
```

### Admin API

A new endpoint or a reuse of an existing pattern:

- `PATCH /auto_patrol/tenant/{tenant_id}/disable` — sets `is_disabled=True`, `disabled_by="cleanup_lambda_tenant_cascade"`, `disabled_at=now()` on every `AutoPatrolSite` and `AutoPatrolSchedule` whose ancestor maps to that `tenant_id`.
- Idempotent: PATCH-ing already-disabled rows is a no-op.
- Should have a corresponding "re-enable" path for when a tenant is unsuspended (sibling to the existing [[2026-04-23_cleanup-rollout-day]] re-enable Lambda — could be the same Function URL with a different code path).

### Rollout

1. Land cleanup-Lambda code change behind a feature flag `TENANT_CASCADE_ENABLED=false` initially.
2. Verify in stage logs that suspended tenants are correctly identified (no false positives) using the **2 known suspended tenants** as canaries.
3. Build admin endpoint + tests.
4. Flip `TENANT_CASCADE_ENABLED=true` after admin endpoint is live.
5. Audit: count `TenantCascadeDisabled` NR events for the first 7 days; expect a small startup spike then near-zero (only fires on actual suspensions).

## Why we're NOT changing the onboarder

The onboarder full-sweep approach (probe `tenantStatus` at sync time, cascade through admin) is also viable, but:

- It pays the cost on every 5-minute run, even though tenant suspensions happen rarely
- It would require shipping a refactor to the onboarder's site-dict construction at `lambda_function.py:222-229`
- The cleanup Lambda already has the right operational properties (FIFO retry, NR instrumentation pending, dry-run flag) — better fit for a state-change-detection workflow

The onboarder change would still be a reasonable belt-and-suspenders option later if the cleanup-side approach turns out to be insufficient.

## Risk: connector traffic for suspended tenants

If a connector for a suspended tenant is still running, it will keep emitting `no_patrols` signals (because admin still says active). Once cascade-disable lands, those signals will arrive at the cleanup Lambda but the **first** invocation per tenant per cold-start will trigger the cascade; subsequent invocations for the same tenant will be no-ops (the tenant is already disabled in admin).

This means there's a brief window per Lambda cold-start where multiple records for a suspended tenant might queue up; the cascade-disable should be safe to call repeatedly (idempotent). Not a blocker.

## Cleanup Lambda already has everything on the input side

Confirmed 2026-04-28:

| Capability | Source | Verified |
|---|---|---|
| `tenant_id` in input | SQS payload @ `cleanup_lambda.py:142` | ✅ |
| AutoPatrol client (can fetch suspended tenants) | `AutoPatrolAPI(...)` instantiated @ `cleanup_lambda.py:106` | ✅ |
| Admin client (can PATCH) | `AdminApiHandler` already used for `auto_patrol_schedule/` PATCH @ `cleanup_lambda.py:454` | ✅ |

The blocker is admin-side: no existing endpoint cascade-disables sites + schedules by `tenant_id`.

## Files affected (sketch)

- `autopatrol_onboarder/cleanup_lambda.py` — add `_get_suspended_tenants()` helper (cached) + early-exit branch in `process_record()` BEFORE the existing per-schedule path. Use the server-side filter `GET /Contracts?contractStatus=Suspended` (returns ~2 contracts in prod today, very cheap).
- `autopatrol_onboarder/cleanup_dao.py` (or `admin_api_handler.py`) — add `disable_tenant_cascade(tenant_id, reason)` method that wraps the new admin endpoint. Idempotent.
- `actuate_admin` — **the actual blocker.** Add `PATCH /auto_patrol/tenant/{tenant_id}/disable/` (or equivalent) that walks the AutoPatrol* model graph under that tenant and sets `is_deleted=True`/`is_disabled=True` on every site + schedule. Should respect the same `disabled_by` audit pattern the schedule-cleanup path already uses.
- **Workaround if admin work is blocked**: cleanup Lambda walks admin per-resource using existing endpoints (`GET /auto_patrol_site/?tenant_id=` → enumerate schedules per site → PATCH each). Slower (N+M round-trips per cascade) but unblocks the cleanup-side rollout. Requires `/auto_patrol_site/?tenant_id=` filter to actually exist server-side — needs verification.
- Tests for cleanup Lambda: mock `get_contracts` response with one suspended tenant, verify cascade is called and per-schedule path is skipped. Use the 2 known prod-suspended tenants (`Remote Security Solutions`, `Legacy`) as canaries during stage rollout.

## Implementation status (2026-04-28)

### Admin endpoint — LANDED (local; awaiting PR/deploy)

- **View:** `actuate_admin/api/serializers/integrations/autopatrol/autopatrol_view.py` — new `@action def disable_tenant` on `AutoPatrolViewSet`. Filters via `customer__group__tenant_id=tenant_id, is_deleted=False`. Iterates and calls `schedule.delete()` (which goes through `soft_delete(save=True)` AND `undeploy()` per `autopatrol_schedule_model.py:391-394`) + `customer.delete()` (cascades to cameras via Customer's existing soft-delete path). `dry_run` flag returns the cascade scope without mutating. Wrapped in `transaction.atomic()`.
- **Serializer:** `actuate_admin/api/serializers/integrations/autopatrol/autopatrol_disable_tenant_serializer.py` — `tenant_id` (required), `dry_run` (default False), `reason` (default "immix_tenant_suspended").
- **Tests:** `actuate_admin/api/tests/test_autopatrol_disable_tenant.py` — 7 tests, all passing in 2.87s. Tests double as the dry-run verification artifact: each demonstrates exactly which sites/schedules the cascade would affect under realistic FK shapes (Group → site_group → Customer → AutoPatrolSchedule).

  | Test | Asserts |
  |---|---|
  | `test_dry_run_returns_full_cascade_scope` | `dry_run=True` lists 5 schedules + 3 customers; DB unchanged after |
  | `test_apply_cascades_correctly` | `dry_run=False` flips `is_deleted=True` + `disabled_by="immix_tenant_suspended"` + `disabled_at` + `deleted_date` on every row |
  | `test_isolation_between_tenants` | Cascading tenant A leaves tenant B's rows untouched |
  | `test_idempotent_second_call_is_noop` | Second call returns counts=0; DB unchanged |
  | `test_missing_tenant_id_returns_400` | Body without `tenant_id` → 400 ValidationError |
  | `test_unknown_tenant_id_returns_zero_counts` | Unknown tenant_id → 200 with all counts 0 |
  | `test_already_deleted_rows_skipped` | Pre-deleted rows excluded from cascade; their existing `disabled_by` not overwritten |

### Side-effects to watch on prod rollout

1. **`Customer.delete()` triggers `delete_immediate_group()`** (`customer_model.py:1023-1030`) — when the last active customer in a Group drops to ≤1, the Group itself gets soft-deleted. For our 2 known suspended tenants that's likely correct (the tenant IS suspended), but worth eyeballing the first cascade in stage.
2. **`Customer.delete()` calls `event.send_event("site_deleted", self)`** — publishes to event bus in real envs. Tests don't currently mock `AdminEventLibrary`. Confirm staging env wiring before rollout.
3. **`schedule.delete()` calls `undeploy()`** — issues an HTTP DELETE to the [[connector-deployer|connector deployer]] (`{INGRESS_URL}/connector/deploy/chm/{container_name}`). For 5+ schedules under a tenant, that's 5+ deployer calls per cascade. Should be fine but worth observability (log line per call already exists at `autopatrol_schedule_model.py:524`).

### Stage verify (2026-04-28 PM, post actuate_admin PR #2376 merge to staging)

Probe `scripts/probe/stage_disable_tenant_dry_run.py` ran against `https://staging.actuateui.net/api/auto_patrol/disable_tenant/` with `dry_run=true` for each canary:

| Tenant | schedules_affected | customers_affected | HTTP |
|---|---|---|---|
| Remote Security Solutions (`0ee7cb3f-...`) | **12** | **12** | 200 |
| Legacy (`ac399cd6-...`) | **74** | **73** | 200 |
| **Total cascade scope** | **86** | **85** | — |

Re-running the probe yielded identical counts → dry-run is genuinely non-mutating. Endpoint is live and correctly enumerates scope.

Once the admin endpoint reaches prod and `TENANT_CASCADE_ENABLED=true` flips on the cleanup Lambda, the first cascade event will soft-delete those 86 schedules + 85 sites in admin.

### Cleanup Lambda — LANDED (local; awaiting commit + PR pair with admin)

Files: `cleanup_lambda.py` +149 lines, `tests/test_cleanup_lambda_tenant_check.py` (NEW, 427 lines, 7 tests, 0.21s, all passing), `pyproject.toml` (added pytest dev dep + config — repo had no test infra before). Implementation:

- **Module-level cache** of suspended Immix tenant_ids — TTL 600s, refreshed lazily on first call after expiry
- **`_get_suspended_tenants(autopatroller)`** — fetches `GET /Contracts?contractStatus=Suspended` (server-side filter; tiny payload). Fail-soft: keeps prior cache if Immix call fails (per repo CLAUDE.md "no fail-fast guards" rule).
- **`_cascade_disable_tenant(adminapi, tenant_id, reason, dry_run, enabled)`** — PATCHes the new admin endpoint. Mirrors existing per-schedule `_disable_on_admin` style: same `dry_run` / `enabled` log-and-return gate, same NR event emission pattern.
- **Early-trip in `_process_record()`**: at `count == TENANT_CHECK_THRESHOLD` (default 2), look up tenant in suspended set; if present, cascade and return early (skip per-schedule classification). Threshold is `==` not `>=` — fires once per anomaly-reset cycle. If admin endpoint is broken, per-schedule anomaly-reset (PR #9 logic) self-heals at the existing per-schedule threshold (~18h cycle). Could be loosened to `>=` for faster retry if admin failure is more common than expected.
- **NR event `AutoPatrolTenantCascadeDisabled`** — observability for the cascade trigger.

Test coverage:

| Test | Asserts |
|---|---|
| `test_tenant_check_at_counter_2_with_suspended_tenant_cascades` | count=2 + tenant suspended → admin endpoint called, per-schedule probe NOT called |
| `test_tenant_check_at_counter_2_with_active_tenant_continues_to_per_schedule` | count=2 + tenant active → falls through to per-schedule path |
| `test_tenant_check_below_threshold_skipped` | count=1 → tenant lookup not even attempted |
| `test_tenant_check_cache_hit_within_ttl` | Two records same tenant within 10min → only one Immix fetch |
| `test_tenant_check_dry_run_logs_only` | `DRY_RUN=true` → would-PATCH log, no admin call |
| `test_tenant_check_disabled_flag` | `CLEANUP_ENABLED=false` → would-PATCH log, no admin call |
| `test_tenant_check_fail_soft_on_immix_error` | autopatroller.request raises → empty set returned, per-schedule path continues |

## Related

- [[2026-04-17_stale-schedule-cleanup-design]] — original cleanup Lambda architecture
- [[2026-04-20_cleanup-lambda-runbook]] — operational reference
- [[autopatrol-cleanup-lambda]] — entity
- [[autopatrol-onboarder]] — entity
- [[mark-todos]] §16 — workstream tracking this fix
