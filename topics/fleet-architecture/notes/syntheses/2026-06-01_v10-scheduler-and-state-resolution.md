---
title: "v10 Scheduler-Service & Per-Camera-Per-Product State Resolution"
type: synthesis
topic: fleet-architecture
tags: [scheduler-service, state-resolution, per-product, two-stage, sparse-rules, inheritance]
jira: ""
confluence: ""
created: 2026-06-01
updated: 2026-06-01
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/sources/2026-06-01_cloud-video-analytics-platform-v10.md
incoming_updated: 2026-06-02
---

# v10 Scheduler-Service & Per-Camera-Per-Product State Resolution

**From v10 architecture:** The scheduler-service implements a two-stage state resolution model for determining per-(camera, product) activation. This is a load-bearing design that merits detailed catalog, as it's the mechanism by which scheduling costs and customer flexibility are realized.

## Two-Stage Resolution Model

### Stage 1: Camera Lifecycle (Camera ← Tenant/Site/Override)

**Question:** Is this camera streaming right now? (Product-agnostic.)

**Inputs:**
- Tenant lifecycle rule (if any)
- Site lifecycle rule (if any)
- Camera lifecycle rule (if any)
- Alarm-panel state (if tenant uses panel-linked scheduling)
- Active override (customer-set, explicit expiry)

**Precedence (most specific wins):**
1. Active override (customer-set with expiry)
2. Alarm-panel state (if applicable)
3. Camera-level lifecycle rule
4. Site-level lifecycle rule
5. Tenant default lifecycle rule

**Output:** Boolean `streaming`. If false, all products are N/A.

### Stage 2: Product Activation (Per-Product ← Tenant/Site/Camera/Override)

**Gated by Stage 1:** Evaluated only if camera is streaming.

**Questions (parallel per product):**
- Is intruder active on this camera right now?
- Is weapon active on this camera right now?
- Is loitering active on this camera right now?
- Is fire active on this camera right now?

**Inputs (per product):**
- Tenant product rule (if any)
- Site product rule (if any)
- Camera product rule (if any)
- Alarm-panel state (if applicable)
- Active override (product-specific, explicit expiry)

**Precedence (identical to Stage 1):**
1. Active override
2. Alarm-panel state
3. Camera-level rule
4. Site-level rule
5. Tenant default

**Output:** Per-product enum (ON | OFF | custom schedule).

## Rules Storage: Sparse + Inheritance

**Design principle:** Rules are stored at whatever level the customer configures. Most customers set a tenant default and a handful of overrides.

### Sparse vs Dense — The Trade-Off

**Dense (avoid):**
```
cam_47.intruder = always
cam_47.weapon = always
cam_47.loitering = business_hours
cam_48.intruder = always
cam_48.weapon = always
cam_48.loitering = off
... × thousands of cameras
```

**Problem:** Adding a new product means writing rules for every existing camera. Adding a new camera means picking an inheritance source anyway — you end up reimplementing precedence logic.

**Sparse (recommended):**
```yaml
tenant_default:
  lifecycle: linked_to_alarm_panel
  products:
    intruder: always
    weapon: always
    loitering: business_hours

sites.brooklyn:
  products:
    loitering: off  # override: no loitering at Brooklyn

cameras.cam_47:
  products:
    loitering: always  # camera-level override: except this lobby

cameras.cam_12:
  products:
    weapon: off  # street-facing, false-positive prone
```

**Advantage:** Customers think in terms of levels (tenant default, site-specific, camera-specific). Data model matches their mental model. Adding a product = one tenant default line; adding a camera = inherit from tenant/site by default.

## Scheduler-Service Implementation

### Component Spec

| Aspect | Detail |
|--------|--------|
| **Type** | Stateless Python service |
| **[[sharding|Sharding]]** | By tenant_id (N shards for N tenants, or load-balanced pool) |
| **Instances** | c8g.xlarge × 6 (v10 spec) |
| **Trigger modes** | EventBridge Scheduler (time), alarm-panel webhooks, override API calls |
| **Output** | Commands on `control` Kafka topic (ingest, detector-router, alert, dispatch all subscribe) |
| **Latency SLA** | Rule eval <100ms; override propagation <1s end-to-end |
| **High-availability** | Jitter on cohort starts (60s spread to avoid thundering herd on schedule changes) |

### Pseudo-code (from v10)

```python
def resolve_camera_state(camera_id, now):
    # Load rules sparsely from config-service
    tenant_rules = config.get_tenant_rules(camera.tenant_id)
    site_rules   = config.get_site_rules(camera.site_id)
    camera_rules = config.get_camera_rules(camera_id)
    panel_state  = config.get_panel_state(camera.tenant_id)
    override     = config.get_active_override(camera_id, now)

    # Stage 1: camera lifecycle
    lifecycle = resolve_with_precedence(
        override.lifecycle,                          # P1
        panel_state_to_lifecycle(panel_state),       # P2 if applicable
        camera_rules.lifecycle,                      # P3
        site_rules.lifecycle,                        # P4
        tenant_rules.lifecycle,                      # P5
    )

    if not lifecycle.streaming:
        return CameraState(streaming=False, products={})

    # Stage 2: per-product activation (parallel, independent)
    products = {}
    for product in tenant.enabled_products:
        products[product] = resolve_with_precedence(
            override.products.get(product),
            panel_state_to_product(panel_state, product),
            camera_rules.products.get(product),
            site_rules.products.get(product),
            tenant_rules.products.get(product),
        )

    return CameraState(streaming=True, products=products)

def on_trigger(camera_id, now):
    new_state = resolve_camera_state(camera_id, now)
    old_state = state_cache.get(camera_id)
    if new_state != old_state:
        emit_commands(camera_id, old_state, new_state)
        state_cache.set(camera_id, new_state)
        audit.log_transition(camera_id, old_state, new_state, now)
```

## Concrete Example (v10)

**Tenant:** Retail chain. 200 stores (sites). 8 cameras per store (1600 total).

**Configuration:**
- Tenant default: intruder 24/7, weapon 24/7, loitering business-hours (9am–9pm)
- Brooklyn site override: loitering OFF (customer's choice for that location)
- cam_47 (Brooklyn lobby) override: loitering ON (despite site rule, because it's the main entrance)
- cam_12 (Brooklyn street-facing) override: weapon OFF (too many false positives on street reflections)

**Resolutions at time T:**

| Camera | Site | Lifecycle | Intruder | Weapon | Loitering | Note |
|--------|------|-----------|----------|--------|-----------|------|
| cam_47 | Brooklyn | STREAMING | ON (tenant) | ON (tenant) | ON (camera override) | Lobby, linked to alarm panel |
| cam_12 | Brooklyn | STREAMING | ON (tenant) | OFF (camera) | OFF (site) | Street-facing, FP-prone |
| cam_88 | Brooklyn | NOT STREAMING | N/A | N/A | N/A | Stockroom, triggered-only, no motion |
| cam_03 | Manhattan | STREAMING | ON (override) | ON (override) | ON (override) | Extended by Maria until 7pm |

## Cost Realization: Detector-Router

The scheduler-service **specifies** per-(camera, product) state, but the **cost savings happen at detector-router**.

**Detector-router logic:**
```
for each frame from ingest on frame_bus:
    camera_id, product_states = scheduler_cache.get(camera_id)
    if product_states['intruder'] == ON:
        forward frame to detector_intruder
    if product_states['weapon'] == ON:
        forward frame to detector_weapon
    if product_states['loitering'] == ON:
        forward frame to detector_loitering
    # if all OFF, frame gets to frame-bus but is not processed by any detector
```

Example: If cam_12 has weapon OFF, frames from cam_12 never reach detector_weapon. This is where the per-product pricing model (and cost reduction) actually materializes.

## Config-Service Schema

**Tables:**
- `tenant_rules` (tenant_id, lifecycle, products dict)
- `site_rules` (site_id, lifecycle, products dict)
- `camera_rules` (camera_id, lifecycle, products dict)
- `product_overrides` (legacy? or absorbed into config tables)
- `alarm_panel_links` (tenant_id, panel_id, state → lifecycle/product mapping)
- `active_overrides` (camera_id, product, state, expiry_ts)

**Indexing strategy:** Fast lookups by camera_id (to fetch all rules for a camera) and tenant_id (for sharded scheduler access).

## Override-Service API

**Endpoints:**
- `POST /override/{camera_id}/arm` → set lifecycle to STREAMING, expiry = NOW + 24h
- `POST /override/{camera_id}/disarm` → set lifecycle to PAUSED, expiry = NOW + 24h
- `POST /override/{camera_id}/extend?until=<timestamp>` → extend lifecycle, expiry = provided ts
- `POST /override/{camera_id}/vacation?from=<ts>&to=<ts>` → set lifecycle OFF for interval
- `GET /override/{camera_id}/history` → list all overrides (for audit/transparency)

**Constraints:**
- Every override has explicit expiry (no "permanent" overrides via this path)
- Overrides are scoped to camera, not (camera, product) — v10 keeps that level unified at override layer
- Deletion is soft (mark as revoked, keep history for audit)

## Alarm-Panel Integration

**Flow:**
1. Alarm panel webhook → alarm-panel-integration service
2. Translates partner state → canonical event: `{tenant_id, panel_id, state, ts}`
3. Publishes to `control` topic (or direct callback to scheduler)
4. Scheduler applies precedence: panel state (P2) beats site/camera rules but loses to explicit overrides

**Example:** If alarm panel arms the site, cameras in that site's lifecycle rule defaults to ARMED unless a camera-level override says DISARMED.

## Customer-Facing UI

**Mental model exposed to customer:**

Per-camera, per-product view with inheritance shown:

```
Camera              Intruder                Weapon                 Loitering
─────────────────────────────────────────────────────────────────────────────
cam_47 (lobby)      ON (tenant default)     ON (tenant default)    ON (camera ⟵ site is off)
cam_12 (street)     ON (tenant default)     OFF (camera)           OFF (site)
cam_88 (stockroom)  — (camera not streaming)
cam_03 (emp entry)  ON (override · 7pm)     ON (override · 7pm)    ON (override · 7pm)
```

**UX principle:** "Where does this rule come from?" is as important as the rule value itself. Tapping a cell drills into the rule chain ("ON because of tenant default; site rule is OFF; camera override is ON").

## Relationship to Watch Management Service

v10's scheduler-service is the **specific realization** of the [[2026-05-28_watch-management-service-design|Watch Manager]]'s **state resolver** component. [[watch-entity|Watch]] Manager is the broader orchestrator (applies to [[watchman-repo|Watchman]], fleet proposals); scheduler-service is the cloud-product specific instance.

Key alignment: Both use two-stage resolution (lifecycle + product/mode), both use sparse rule storage with inheritance, both integrate with alarm-panel webhooks.

---

**Source:** [[2026-06-01_cloud-video-analytics-platform-v10|v10 architecture doc]]
**Related:** [[2026-06-01_v10-cloud-platform-vs-fleet-proposals]]
