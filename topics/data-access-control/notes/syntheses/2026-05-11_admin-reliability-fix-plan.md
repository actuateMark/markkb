---
title: "Admin Reliability Fix Plan — Code-Grounded"
type: synthesis
topic: data-access-control
tags: [reliability, admin, n-plus-1, cte, validation, fix-plan, phase-0]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
outgoing:
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-db-access-hardening.md
  - topics/data-access-control/notes/concepts/2026-05-11_admin-incident-catalog.md
status: draft-for-discussion
incoming:
  - topics/data-access-control/_summary.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-db-access-hardening.md
  - topics/data-access-control/notes/syntheses/2026-05-13_dig-followups.md
  - topics/data-access-control/team-brief.md
  - topics/personal-notes/notes/concepts/2026-05-11_next-session-handoff.md
  - topics/personal-notes/notes/daily/2026-05-11.md
incoming_updated: 2026-05-27
---

# Admin Reliability Fix Plan — Code-Grounded

Companion to [[2026-05-11_admin-db-access-hardening|the admin DB access hardening synthesis]] and [[2026-05-11_admin-incident-catalog|the incident catalog]]. Where the catalog identifies what failed and recommends categories of control, this plan goes a level deeper: actual admin code, specific line numbers, and concrete fixes with tradeoffs.

## TL;DR

After investigating the admin codebase against the 5 incidents in the catalog, the picture is:

- **The recursive-CTE problem is solvable with a known pattern already in the codebase.** `Group.get_descendants()` uses a Redis-cached recursive CTE (5-min TTL); the catastrophic version (BT-926) is `GroupAdmin.sites()` calling it once per row in a list view. An adjacent admin method (`GroupAdmin._compute_camera_counts()`) **already implements a batched-precompute pattern that avoids exactly this**, and the fix is to replicate it for `sites()`. Low-friction, well-precedented fix.
- **The Customer admin N+1 is mostly missing prefetches.** `CustomerAdmin.get_queryset()` calls `.prefetch_related("group_customer", "immix_credentials")` but is missing `integration_type`, `connector_version`, and a path for `customer_monitoring` (the latter drives `last_alert_time()`'s per-row query). Adding the missing prefetches is a one-line change per relationship.
- **Validation is in forms, not models.** `Camera`'s integration-linked fields (`immix_device_id`, `yoursix_device_id`, `sentinel_camera_id`) have no model-level validators or `clean()` method — all validation lives in `CameraForm.clean()`. API serializers that bypass the form bypass the validation. The right move is a model-level `clean()` that DRF serializers can invoke via `.full_clean()`.
- **There's zero query-count discipline in the test suite.** `conftest.py` has 80 lines of fixtures but no `assertNumQueries`. The N+1 in `sites()` could be reintroduced after a fix without breaking any test.
- **The codebase already documents MPTT as "broken"** — the raw CTE is the workaround. That historical context is worth knowing before anyone proposes "just use MPTT."

## Methodology

Read the relevant admin source against each of the 5 incidents in the catalog. Captured file:line citations and 3–5 line excerpts where helpful. No code changes. Investigation conducted 2026-05-11.

## Failure Mode 1 — Runaway query / N+1 / unoptimized CTE

### What's actually happening

**The recursive CTE itself** is in `Group.get_descendants()` at `actuate_admin/inframap/group/group_model.py:836–895`. It walks the `inframap_group` parent chain on the DB side via a CTE rather than in Python. **It's already Redis-cached with a 5-min TTL** (lines 879–884). On a cache hit, it doesn't touch the DB; on miss, it's one CTE execution per group, cached for the next 300 seconds.

The catastrophic case isn't the CTE itself — it's that `GroupAdmin.sites()` at `group_view.py:272–276` calls `get_descendants(include_self=True).aggregate(...)` **once per row in the admin list view**:

```python
def sites(self, obj):
    count = obj.get_descendants(include_self=True).aggregate(...)
    return count.get("site_count", 0)
```

If the admin renders 50 group rows, that's 50 CTE executions. If multiple admin users (or a cron) load this concurrently, you get the BT-926 picture: 10 concurrent recursive CTEs, 98.7% RDS CPU, 15 minutes.

**The historical context that matters:** MPTT is explicitly disabled in this codebase. Line 842–843 of `group_model.py` includes the comment `"Because mptt is broken"`. So the raw CTE isn't a clever optimization — it's a workaround for a tree-traversal library the team gave up on. Any "just use MPTT" suggestion will hit that wall.

**The good news:** there's already a sophisticated batched-precompute workaround **in the same admin class**. `GroupAdmin._compute_camera_counts()` at `group_view.py:615–661` does a post-order DFS over groups in Python, fetching all groups once and accumulating counts as it goes — no per-row DB query. Then `cameras()` reads from `self._camera_counts` instead of triggering a DB call per row.

That pattern was applied for `cameras()` but **not for `sites()`**. The `sites()` method is BT-926.

### Root cause

Repeated calls to a CTE-backed method inside a list-view row renderer, without the batched-precompute pattern that the same class uses elsewhere.

### Proposed fixes

#### Fix 1A — Replicate `_compute_camera_counts()` for `sites()` (preferred)

`GroupAdmin.get_queryset()` (where `_camera_counts` is populated) gains a sibling `_site_counts` precompute. `sites()` reads from `self._site_counts[obj.id]` instead of calling `get_descendants()`. Zero recursive-CTE invocations in the list view.

- **Effort:** Small. The DFS template already exists in `_compute_camera_counts`. Probably <100 lines, one PR.
- **Risk:** Low. Same pattern, applied to an adjacent method.
- **Test discipline required:** Add `assertNumQueries` on a `GroupAdmin` list-view test before the fix; verify the count drops dramatically after.

#### Fix 1B — Tighten Redis cache invalidation (defense in depth)

`invalidate_group_cache_on_save()` at `group_model.py:968–972` deletes a group's descendant cache when that group is saved. But bulk-update admin actions (`apply_lead`, `apply_video_loss`, etc.) iterate descendants and call `.save()` in a loop — each iteration invalidates one cache entry, defeating caching for the whole operation. Replace with batch invalidation that runs once at the end of the bulk operation.

- **Effort:** Small.
- **Risk:** Low.
- **Note:** Helpful only if Fix 1A doesn't fully eliminate `get_descendants()` from hot paths.

#### Fix 1C — `statement_timeout` on the read-replica role

Even with 1A + 1B, some future bad query will fire. Setting `statement_timeout` to a few seconds on the role the connector fleet uses caps blast radius — a 15-min RDS-pinning event becomes a fast failure for the offending caller. Already in the parent synthesis's Phase 0 starter set; this investigation confirms it's the right ceiling.

- **Effort:** Trivial (Terraform / RDS parameter).
- **Risk:** Low if the timeout is generous (5–10s); could surface latent slow queries the team didn't know about.

#### Fix 1D — CI query-count assertion

Add a pytest fixture that runs admin list-view tests under `assertNumQueries(<baseline>)`. The baseline can be generous initially; tightened over time. This makes reintroducing an N+1 fail CI rather than fail prod.

- **Effort:** Small (one fixture, applied per critical view).
- **Risk:** Trivial.

#### Fix 1E — `django-silk` in staging

Continuous N+1 detection in staging. Catches issues code review misses. Not necessary if 1D is rigorous, but useful for catching emergent patterns.

- **Effort:** Medium (config + ongoing maintenance).
- **Risk:** Low.

## Failure Mode 2 — Customer-admin N+1 (BACK-623 surface)

### What's actually happening

`CustomerAdmin.get_queryset()` at `customer_view.py:677`:

```python
qs = qs.prefetch_related("group_customer", "immix_credentials")
```

That's everything that's prefetched. The list view, however, touches:

- `obj.integration_type` (`customer_view.py:180`) — FK, **not** prefetched. One query per row.
- `obj.customer_monitoring.get(section="heartbeat")` (`customer_view.py:206`, inside `last_alert_time()`) — reverse FK, not prefetched. One query per row.
- `obj.connector_version` (referenced elsewhere) — FK, not prefetched.
- `obj.timing` property — costly computation; source not fully traced but called per row.

Each is a one-line fix in `get_queryset()`.

### Proposed fixes

#### Fix 2A — Add the missing prefetches

```python
qs = qs.prefetch_related(
    "group_customer",
    "immix_credentials",
    "customer_monitoring",         # for last_alert_time()
).select_related(
    "integration_type",            # for is_clips and display
    "connector_version",           # for display
)
```

- **Effort:** Trivial.
- **Risk:** Trivial. Adding prefetches doesn't change behavior, only query patterns.

#### Fix 2B — `Customer.timing` (investigated 2026-05-11, no fix needed)

Follow-up investigation traced `Customer.timing` to `customer_model.py:1270-1288`. It's a plain `@property` that calls `list_active_flex_schedules()` and `get_timing()`. **Both operate on already-prefetched relations** (`customer_schedules`, `customer_flex_schedules` — prefetched at `customer_model.py:1370-1371`). All filtering happens in-memory; per-row cost is effectively zero DB queries.

Marginal improvement available: convert to `@cached_property` to memoize within a single request lifecycle, since `.timing` is called from both the list view column and the serializer. But this is a polish-tier change, not a reliability fix.

## Failure Mode 3 — Cascade-delete / autovacuum blast radius (BACK-622)

### What's actually happening

The cascade graph in admin:

- `Customer → Group`: `on_delete=PROTECT` ✓ (good; blocks Group deletion if Customers reference it)
- `Customer → IntegrationType`: `on_delete=PROTECT` ✓
- `Stream → AIModel`: `on_delete=PROTECT` ✓
- `Customer → Cameras → Streams`: `CASCADE` (intentional)
- `Group → Group (parent)`: `CASCADE` (intentional; deleting a parent group deletes the subtree)
- `Group → Server`: **`CASCADE` (footgun)** — deleting a Server deletes all Groups that reference it. Almost certainly not what's wanted.

The autovacuum spike comes from bulk-deleting `Stream` rows (or the Cameras/Customers that cascade to them) and the resulting cleanup work.

### Proposed fixes

#### Fix 3A — Audit and probably change `Group.current_server` to `SET_NULL` or `PROTECT`

`Server` should rarely be a "delete this and everything dependent gets nuked" entity. `SET_NULL` makes deleted servers detach from groups; `PROTECT` forces the operator to detach groups before deleting a server. Either is safer than `CASCADE`.

- **Effort:** Small (migration + tests).
- **Risk:** Medium — requires understanding the deployment model. If there's an operational reason for the current CASCADE (e.g., spinning a Server down means tearing down associated groups), this is wrong.
- **Open question:** what's the actual operational lifecycle of `Server` rows? Worth asking Tati.

#### Fix 3B — Autovacuum tuning per high-churn table

Reduce `autovacuum_vacuum_scale_factor` for `Stream`, metrics tables, and any cascade-delete child table. Set via Terraform / RDS parameter group.

- **Effort:** Small.
- **Risk:** Low if conservative defaults are picked.

#### Fix 3C — Bulk-operation runbook

Document a procedure for bulk Stream/Camera deletes: estimate row counts, do during low-traffic window, monitor autovacuum, expect the post-script CPU spike. Operational hygiene, not a code change.

- **Effort:** Trivial.
- **Risk:** None.

## Failure Mode 4 — Schema/validation regression (BACK-648)

### What's actually happening

The Camera model has integration-specific identifier fields (`immix_device_id`, `yoursix_device_id`, `sentinel_camera_id`) with **no field-level validators or model-level `clean()` method**. All validation lives in `CameraForm.clean()` at `camera_view.py:150–167`.

Example: SmartPSS name validation is form-only:
```python
if customer and customer.integration_type.name == Integrations.smartpss.name:
    if re.search(r"[./]", camera_name) or "\\" in camera_name:
        raise ValidationError("Slashes and periods are not allowed in the camera name.")
```

If a Camera is saved via:
- A DRF serializer that doesn't explicitly call `.full_clean()` ✗ no validation
- A management command that does `Camera.objects.create(...)` ✗ no validation
- A direct ORM call from anywhere ✗ no validation

Only `CameraForm`-driven saves get validation. The [[evalink-components|Evalink]] `deviceId` saved by an integration API endpoint that uses a serializer wouldn't trip the form validation path — which is exactly the BACK-648 shape.

### Proposed fixes

#### Fix 4A — Move integration-aware validation into a model `clean()` method

```python
class Camera(models.Model):
    ...
    def clean(self):
        super().clean()
        if not self.customer:
            return
        integration = self.customer.integration_type.name
        if integration == Integrations.smartpss.name:
            if re.search(r"[./\\]", self.camera_name):
                raise ValidationError({"camera_name": "Slashes and periods are not allowed."})
        if integration == Integrations.evalink.name:
            if len(self.evalink_device_id or "") != 32:
                raise ValidationError({"evalink_device_id": "Must be a 32-character ID."})
```

DRF serializers that opt in via `full_clean()` get the validation for free. The form's `clean()` can call into the model's `clean()` to avoid duplication.

- **Effort:** Medium. Touches every integration-specific field rule. Test discipline needs to cover each.
- **Risk:** Medium — might surface latent bad data already in the DB (existing rows that don't satisfy the new rules). Needs an audit + cleanup pass before the validator is enforced strictly.

#### Fix 4B — DRF serializer-level enforcement of `full_clean()`

Centralize: every admin serializer that touches `Camera`, `Customer`, or other integration-linked models calls `.full_clean()` on the instance before save. A custom `Serializer` base class or mixin enforces this.

- **Effort:** Small once the base class exists.
- **Risk:** Trivial.

#### Fix 4C — Post-deploy data-quality gate

Before marking a deploy "live," run sample audit queries for integration-linked fields. Example: count cameras where `customer.integration_type == 'evalink'` AND `len(evalink_device_id) != 32`. Non-zero means a regression got through.

- **Effort:** Small (set of audit SQL + a wrapper that runs them).
- **Risk:** Trivial.

## Failure Mode 5 — Schema/migration regression (BACK-604/605)

### What's actually happening

Django + Postgres major upgrades that worked in staging but had migration failures in prod. Migration history shows multiple failed attempts.

The investigation didn't find a specific code-level root cause (this is more an operational practice than a code defect). The recommended controls are operational:

### Proposed fixes

#### Fix 5A — Dry-run migrations against a prod snapshot

Restore the latest prod backup to a pre-prod instance; run pending migrations there; capture any failures. Gate prod migrations on the dry-run passing.

- **Effort:** Medium. Tooling work: snapshot-restore automation + migration runner + reporting.
- **Risk:** Low.
- **Note:** `actuate_admin_rds` already has snapshot-restore tooling — this builds on it.

#### Fix 5B — Staging traffic mirroring for major upgrades

For major version bumps (Django, Postgres, framework-level changes), mirror N% of prod traffic to staging for a 24–48h soak before prod deploy. Catches behavior that synthetic staging traffic doesn't surface.

- **Effort:** Large. Traffic mirroring infra is real work.
- **Risk:** Medium — mirrored traffic that performs writes is dangerous; needs read-only mirroring or careful side-effect isolation.

#### Fix 5C — Explicit rollback plan + tested rollback path

Every major upgrade lands with: a documented "if this fails, run X to revert" runbook, and that runbook is tested in the dry-run environment first.

- **Effort:** Small (cultural / process change).
- **Risk:** Trivial.

## Observability gaps

The investigation surfaced concrete observability gaps:

- **`django-silk` / `django-debug-toolbar`:** Toolbar exists but is opt-in (`DEBUG_TOOLBAR` env var). Not enabled in CI/test. `django-silk` not present.
- **`assertNumQueries`:** Not used anywhere in the test suite.
- **NR custom query metrics:** Not wired in admin views.
- **Slow query log:** **Status unconfirmed (2026-05-11).** RDS Performance Insights *is* enabled per `ds-terraform-eks-v2/stages/prod/us-west-2/rds/terragrunt.hcl:37`. But the actual parameter group (`actuateadminprodcluster-pg16-logical-replication`) is referenced from Terraform but **not defined in IaC** — its values live in the AWS console / RDS API only. So we don't know from the repo whether `log_min_duration_statement`, `log_statement`, or `pg_stat_statements.track` are set. Verification path: `aws rds describe-db-cluster-parameters --db-cluster-parameter-group-name actuateadminprodcluster-pg16-logical-replication --region us-west-2`. Performance Insights gives us an AWS-native slow-query view as a fallback even if the slow-query log is off.
- **No slow-query → NR pipeline.** Even if the slow-query log is on, nothing in the repos pipes it to [[new-relic|New Relic]]. Would require CloudWatch Logs subscription → NR or NR's Postgres integration. This is a real build, not just a config flip.
- **Parameter group not in IaC (drift risk).** That `actuateadminprodcluster-pg16-logical-replication` exists only in AWS and isn't defined in Terraform is itself a Phase 0 hardening item. We can't reason about, review, or revert changes to it without an AWS console round-trip. Should be Terraformized so all RDS tuning is reviewable in PRs.

These are the "we can't see the next BT-926 coming" gaps. All have cheap fixes; none are blocked.

## Prioritization — what to ship first

Ranked by effort × impact × risk reduction:

### Tier 1 (ship in Phase 0, low effort, high payoff)

1. **Fix 1A — Replicate `_compute_camera_counts()` for `sites()`.** Eliminates the BT-926 hot path entirely. Pattern already exists in the codebase.
2. **Fix 2A — Add missing prefetches to `CustomerAdmin`.** One-line change per relationship; eliminates per-row query for `integration_type`, `connector_version`, `customer_monitoring`.
3. **Fix 1C — `statement_timeout` on the connector read-replica role.** Caps blast radius of any future bad query.
4. **Fix 1D — CI query-count assertion** on critical admin list views (`GroupAdmin`, `CustomerAdmin`, `GroupUserAdmin`). Prevents regression.
5. **Fix 4C — Post-deploy data-quality gates** for integration-linked fields. Catches the next BACK-648.
6. **Verify slow-query log status.** Run `aws rds describe-db-cluster-parameters` against `actuateadminprodcluster-pg16-logical-replication`. Document current values for `log_min_duration_statement`, `log_statement`, `pg_stat_statements.track`. If off, turn on (probably 1000ms threshold). Performance Insights is already on as a fallback view.
7. **Terraformize the RDS parameter group.** Move `actuateadminprodcluster-pg16-logical-replication` definition into `ds-terraform-eks-v2` so all RDS tuning is reviewable. Prereq to any future parameter change being safe.

### Tier 2 (Phase 1 / early Phase 2)

7. **Fix 4A — Model-level `clean()` for integration-aware validation.** Larger surface; needs per-integration tests + DB cleanup of existing violations.
8. **Fix 4B — DRF serializer base class enforcing `full_clean()`.** Pairs with 4A.
9. **Fix 1B — Batch Redis cache invalidation** for bulk admin actions.
10. **Fix 3A — Audit `Group → Server` CASCADE.** Investigation-blocked; talk to Tati first.

### Tier 3 (longer-term)

11. **Fix 3B — Autovacuum tuning per table.** Important but lower urgency than the N+1 fixes.
12. **Fix 5A — Dry-run migrations on prod snapshot.** Worth doing before the next major version bump.
13. **Fix 5B — Staging traffic mirroring.** Heavy lift; defer until we know whether 5A + 5C are enough.

## Open questions for the team

- **`Group → Server` CASCADE — change to `SET_NULL` or `PROTECT`?** Looks like a footgun: deleting a Server today deletes every Group referencing it. **Mark's lean: yes, change it.** Probably `SET_NULL` (deleted server detaches from groups, operator manages re-attachment) unless there's an operational reason CASCADE is intentional. Needs Tati/Adam input on the actual Server lifecycle before the migration ships.
- **Is the slow-query log on in prod?** Status unconfirmed (2026-05-11). Parameter group `actuateadminprodcluster-pg16-logical-replication` is not in IaC, so its current values aren't reviewable from the repo. **Action: verify via `aws rds describe-db-cluster-parameters` — should be a 5-minute confirmation.** If off, turn on at ~1000ms threshold. Performance Insights is enabled as a fallback regardless.
- **Should we Terraformize the RDS parameter group?** Right now, all admin RDS tuning lives in the AWS console only. Mark's lean: yes — drift risk is real and any future parameter changes (autovacuum tuning, statement_timeout, log thresholds) should land via PR review like everything else.
- **Are existing Cameras / Customers in violation of integration-specific format rules?** Need to run an audit pass before Fix 4A (model-level `clean()`) is enforced strictly. Otherwise a deploy that adds validators will break saves on pre-existing bad data.

### Resolved 2026-05-11

- ~~Where does `Customer.timing` come from, and what does it cost?~~ Investigated: it operates on already-prefetched relations, ~0 per-row queries. Marginal `@cached_property` improvement available, not urgent. See Fix 2B.

## Cross-references

- [[2026-05-11_admin-db-access-hardening]] — parent synthesis
- [[2026-05-11_admin-incident-catalog]] — failure-mode taxonomy and recommended controls (this doc refines those into specific code-level fixes)
- [[2026-05-11_admindao-call-site-inventory]] — Phase 2 migration scope; some fixes here (Fix 2A) are independent of the API migration and can ship sooner
- [[database-performance]] — pre-existing admin-api topic note on Aurora CPU / BACK-623
