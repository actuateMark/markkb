---
title: "Billing-reconciliation dashboard — admin ↔ emit signal (R1 design)"
type: concept
topic: billing
tags: [billing, reconciliation, dashboard, nrql, vms-connector, site_product_ended, sales-dashboard, R1]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
---

# Billing-reconciliation dashboard — admin ↔ emit signal (R1 design)

Design spec for [[_todos|topic todo]] **R1** — the continuous admin↔emit reconciliation signal. This is the post-mortem's headline action item: until we have it, the next [[2026-05-06_cohort-f-investigation|Cohort F]]-shaped gap will surface manually, weeks late, with **unknown drift duration**.

Scope here is **design, not implementation**. Output is a query shape + signal contract that a follow-up implementation PR can build against.

## What this signal answers

> *"Is every admin-active billable camera × product producing at least one `site_product_ended` emit in the last 24h?"*

That single sentence is the invariant. The signal computes the **gap** between admin's set of billable (camera, product) pairs and the set of (camera, product) pairs that emitted in the trailing window. Gap > threshold → alert.

This is the same shape that the cohort F audit used manually ([[2026-05-06_cohort-f-investigation]] §2 method). The design here is to **automate that audit on a daily cadence**, with green/yellow/red surface, and ship gap-row samples on alert so an operator can act.

## Scope boundary

| In scope | Out of scope |
|---|---|
| Admin DB ↔ SQS-emit reconciliation (the two layers we own) | Snowflake-side ingestion gap (F6/F5 — data-team-owned per [[_todos]] R2) |
| Daily cadence (mirrors the cohort-audit pattern) | Intra-day high-frequency reconciliation (future O2) |
| Per-product gap detection at the (camera, product) granularity | Per-`act_a` rate-anomaly detection (future T2-adjacent) |
| Separate billing dashboard surface (local first, sales-dashboard later) | Integration into the operational-health dashboard at `mork-firebat/dashboard/` (cross-link only) |

## Data source decision — NRQL-first

| Source | Pros | Cons | Verdict |
|---|---|---|---|
| **NRQL on `event_queue_analytics.fifo` logs** | Cheap, instant; no Snowflake access required; the `Sending event_info:` log line carries everything needed; same shape cohort F used | Misses pure-Snowflake-ingestion gaps (that's R2's territory) | **Picked.** Right side of the diff. |
| **Admin DB (Postgres) direct query** | Authoritative truth-1 source ([[2026-05-11_billing-pain-post-mortem]] diagram) | Need creds bootstrap from `prod/actuate/postgres` (already wired in `scripts/fetch_local_test_env.sh prod`) | **Picked.** Left side of the diff. |
| Snowflake | Closes the SQS-ingest gap too; richer joins | **Blocked on [[_todos]] C2 Jira ticket.** Even after access lands, this is R2's territory not R1's | **Deferred.** Reconsider after C2. |

**Implication:** R1 is buildable today against NRQL + admin DB. It does NOT require C2 to ship.

## Query shape

### Left side — admin-derived expected emit set

Authoritative set of (camera, product) pairs that *should* be emitting. Pseudocode against `actuate_admin` (Django ORM):

```python
# Pseudocode — collector will materialize as raw SQL or ORM query
expected_pairs: set[tuple[int, str]] = set()
for customer in Customer.objects.filter(active=True, is_deleted=False):
    for camera in customer.cameras.filter(is_deleted=False, active=True):
        for product in camera.products_or_inherited():  # camera-level + customer-level + site-level
            expected_pairs.add((camera.id, product.slug))
```

The product-resolution function `products_or_inherited()` is **not yet finalized** — it must match the resolution logic the connector uses at emit time. **Open question** (see §"Open questions" §1): is the right resolution chain camera-level → site-level fallback, or customer-level, or something else? Pin this against `connector_factories/shared/billing_emit.py` before locking the query.

Result: `expected_pairs = {(camera_id, product_slug)}` — typically O(10k-100k) at fleet scale.

### Right side — emit-observed pair set

NRQL on the connector's `Sending event_info:` log entries. The log line carries `cid`, `admin_camera_id`, `product`, `event_type`, `act_a`. From the [[billing-events-catalog]] §"Schema":

```sql
-- Right-side NRQL (sketch)
SELECT uniques(admin_camera_id, product)
FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%-cronjob-%'
  AND message LIKE 'Sending event_info:%'
  AND event_type = 'site_product_ended'
SINCE 24 hours ago
LIMIT MAX
```

Returns `observed_pairs: set[tuple[int, str]]` — every (camera, product) pair the connector emitted at least once in the window. `act_a` partition is **collapsed** here — we count any emit, regardless of patrol-vs-healthcheck path.

### Gap

```python
missing_pairs = expected_pairs - observed_pairs    # leaked billable rows
phantom_pairs = observed_pairs - expected_pairs    # emitted but not admin-active (zombie cameras, stale streams)
gap_pct = len(missing_pairs) / max(1, len(expected_pairs))
```

**Primary alert signal: `missing_pairs`.** Phantom pairs are a secondary signal (suggests admin-side soft-delete didn't propagate to the connector — surfaces the S1/S2 propagation gaps from [[_todos]]).

## Edge cases — pin these before implementation

| Edge case | Handling |
|---|---|
| **Site-level fallback emits** (`admin_camera_id=null`, PR #1683 path) | Right side: include `(null, _MISCONFIGURED_FALLBACK_PRODUCT)` rows but bucket them separately in the report. They're emit-present but billing-degenerate; their *existence* is not a gap, but a sustained high count is its own signal. |
| **Misconfigured fallback product** (`_MISCONFIGURED_FALLBACK_PRODUCT`) | Same — separate bucket. Never present in `expected_pairs`. |
| **Paused-in-Immix camera, admin Active** (cohort F3b) | Will appear in `expected_pairs` but not `observed_pairs` if the connector doesn't emit on no-patrols paths. This is a real gap — **R1 should flag it.** It surfaces drift between admin and Immix that S1/S2 cascade hooks are owed for. |
| **act_a partition** | Collapsed at R1's granularity. A camera that's both AP-patrolled and VCH-healthchecked appears once on each side. (Per-`act_a` validation is a downstream signal — see "Future signals" below.) |
| **Per-process idempotency guard** | Irrelevant at this granularity. We're checking "did it emit at all" not "did it emit the right number of times." |
| **Cronjob cadence skew** | Daily window > any cronjob cadence at fleet scale. Edge: a camera with cronjob cadence > 24h would appear silent every other day; **none exist today** (AP and VCH both run sub-hourly) but worth a doc-note. |
| **Cameras added/removed mid-window** | Admin snapshot taken at query time; observed window is trailing-24h. Cameras created in last 24h may appear in left but not right (newly onboarded, hasn't run yet). **Mitigation: exclude cameras with `created_at > now - 24h`** from `expected_pairs`. |

## Surface

**Separate billing dashboard, local first.** Per the [[2026-05-11_billing-and-followups-handoff|R1 surface decision]]:

1. **Local sketch (Phase 1)** — Tier-1 script on Firebat OR laptop, writes signal to `~/.local/state/minipc-tasks/billing/reconciliation-YYYY-MM-DD.json`. Read by `/dashboard-check` collector as a new signal (or by a new `/billing-dashboard-check` skill if the catalog grows). Surfaces in the existing dashboard heat-grid alongside operational signals, **labeled distinctly** as a billing-class signal.
2. **Standalone billing dashboard (Phase 2)** — once 2-3 billing signals exist (R1 + O2 + O3 from [[_todos]]), break them out into a separate `/home/mork/Documents/worklog/billing-dashboard/` surface, served via Caddy same as the ops dashboard.
3. **Sales-dashboard integration (Phase 3)** — port the signal to `https://sales-dashboard.internal.actuateui.net/` once the deploy repo is identified per [[_todos]] C6. This is the "right" long-term home — it co-locates the reconciliation signal with the revenue surface stakeholders already watch.

The phasing is intentional: prove the signal locally before negotiating sales-dashboard real estate.

## Alert thresholds

Start permissive, tighten as gaps close:

| Phase | `missing_pairs %` threshold | Rationale |
|---|---|---|
| Phase 0 (baseline) | Yellow @ 1%, Red @ 5% | First 14 days; record baseline drift, calibrate from observed |
| Phase 1 (post-T1) | Yellow @ 0.5%, Red @ 2% | After crash-path emit gap closes |
| Phase 2 (steady state) | Yellow @ 0.1%, Red @ 1% | Target operating envelope |

**Alert payload requirements:**

- `gap_pct`, `missing_count`, `expected_count`, `observed_count`
- **Top 20 missing pairs** by customer (so an operator can investigate without re-running the query)
- **Cohort breakdown** — group missing pairs by `(customer_id, schedule_status, immix_status)` if available; mirrors the cohort F audit format
- Link to the dashboard tile

If the gap fires red, the payload should be self-contained enough that an operator can decide "real drift" vs "data lag" without re-running anything.

## Cadence

**Daily.** Aligns with the cohort-audit pattern and the natural variation in fleet emit counts. A daily run at a fixed off-peak time (suggest 04:00 PT to align with the dashboard collector cron) captures a full 24h window without intra-day cronjob cadence noise.

**Why not hourly:** the 24h window doesn't divide cleanly into hourly slices for a "did this camera emit" check — a healthy camera emits at sub-hourly cadence, so an hourly check would flap false-negative on every sleep gap. Future intra-day signal (O2 territory) measures *rate* not *presence*.

## Implementation outline (for a follow-up PR)

Out of scope for this design note, but the rough shape for the follow-up:

1. **Collector** — Python script (`scripts/ops/billing_reconciliation.py` in either `autopatrol_onboarder/` or a new home — TBD). Takes admin DB creds + NR query API key.
2. **Output** — JSON sink at `~/.local/state/minipc-tasks/billing/reconciliation-YYYY-MM-DD.json`. Schema TBD; should include `expected_count`, `observed_count`, `missing_pairs` (top-N sampled), `phantom_pairs` (top-N sampled), `bucket_breakdown`.
3. **Scheduling** — systemd `--user` timer on Firebat (per the [[2026-04-30_three-tier-routine-check-pattern|three-tier pattern]] — Tier 1).
4. **Signal definition** — entry in `~/.claude/skills/dashboard-check/config/signals.json` of new source type `billing_json`, following the `cohort_b_cameras` placeholder shape from [[autopatrol-deferred-backlog]] "Cohort dashboard signals" but with a real data source backing it.
5. **Alerting** — Slack webhook OR NR custom event; both wire from the Tier-1 script.

Sketch of the signals.json entry (illustrative — not load-bearing yet):

```json
{
  "id": "billing_admin_emit_gap",
  "component": "billing",
  "source": "billing_json",
  "query": "read ~/.local/state/minipc-tasks/billing/reconciliation-YYYY-MM-DD.json :: gap_pct",
  "unit": "percent",
  "description": "Daily admin↔emit reconciliation gap. (count of admin-billable (camera, product) pairs) minus (count of pairs emitting site_product_ended in trailing 24h), divided by admin count. R1 design: topics/billing/notes/concepts/2026-05-11_billing-reconciliation-dashboard-design.md.",
  "thresholds": {
    "yellow_above": 1.0,
    "red_above": 5.0
  },
  "window_hours": 24,
  "enabled": false,
  "would_have_caught": "Cohort F (642 cameras / 45 customers, surfaced 2026-05-04 — would have alerted at first gap appearance)"
}
```

## Open questions (resolve before implementation PR)

1. **Product resolution chain** — what's the exact precedence the connector uses when picking which `product` to emit? camera-level → site-level → customer-level → `_MISCONFIGURED_FALLBACK_PRODUCT`? Pin this against `connector_factories/shared/billing_emit.py` and document in [[billing-events-catalog]] before locking the left-side query.
2. **Admin product model location** — is "products on a camera" a direct FK relationship, M2M through a join table, or inherited from site? Affects both the query and the size of `expected_pairs`.
3. **Newly-onboarded camera exclusion window** — proposed `created_at > now - 24h` filter; confirm this matches the connector's onboarding-to-first-emit lag (cronjob first-run cadence).
4. **Phantom-pair semantics** — do we treat phantom pairs (emit-without-admin-row) as the **same** signal or a **separate** signal? They surface different failure modes; arguably separate.
5. **NR `uniques` cardinality limit** — for fleet-scale (potentially 100k+ unique pairs in 24h), does `uniques(admin_camera_id, product)` hit the 100k unique-value cap? If yes: paginate via `FACET cid` and union, or move to NRDB events instead of logs.

## Future signals (post-R1 — not in this design)

- **Per-`act_a` rate validation** — once R1 is steady, add a signal per (`act_a`, customer-tier) checking emit rate stays within ±X% of baseline. Surfaces T2 gaps (Snowflake filtering an `act_a` value).
- **Idempotency-guard duplicate rate** — surfaces O4. Requires `admin_camera_id` on log line (currently missing).
- **Phantom-pair persistence** — if a (camera, product) pair appears in `observed_pairs` but not `expected_pairs` for 3+ consecutive days, it's a propagation gap (S1/S2 territory). Promote to a separate signal.

## Acceptance for R1 (post-implementation, not this design note)

The design landing is the acceptance for *this* note. Implementation acceptance, when R1's collector ships:

- Daily run lands JSON at the expected path with non-empty `expected_count` / `observed_count`.
- `dashboard-check` renders the signal green at baseline.
- A synthetic gap-injection test (e.g. temporarily flag a small customer as `active=True` while disabling their cronjob) makes the signal go yellow then red.
- Replay against the 2026-05-04 cohort-F window shows the signal would have fired red — locks in the "would have caught" promise.

## Cross-references

- [[_summary]] — topic overview
- [[_todos]] R1 — the row this design closes (design-spec landing; implementation pending)
- [[2026-05-11_billing-pain-post-mortem]] — the firefight whose unknown drift duration this signal closes
- [[billing-events-catalog]] — schema authority for the right-side query
- [[2026-05-06_cohort-f-investigation]] — methodology blueprint (this design automates §2)
- [[2026-04-30_data-model-cascade-semantics]] — admin truth-1 source; phantom-pair semantics tie to §1/§3
- [[autopatrol-deferred-backlog]] "Cohort dashboard signals" — sibling signal pattern + placeholder shape
- [[autopatrol-cleanup-lambda]] — the self-righting prototype this signal alerts off of
- [[2026-05-11_billing-and-followups-handoff]] — handoff that prioritized R1 as next move
- [[mark-todos]] §28 — billing parent workstream (R1 promotes to this on implementation)
- `~/.claude/skills/dashboard-check/config/signals.json` — where the eventual signal entry lands
