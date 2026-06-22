---
title: "AutoPatrol Tier Spec ↔ API Code: Cross-Reference and Gap Analysis"
type: concept
topic: autopatrol
tags: [autopatrol, immix, tier, detection-codes, gap-analysis, code-review]
created: 2026-05-14
updated: 2026-05-14
author: mark
incoming:
  - topics/autopatrol/notes/syntheses/2026-05-14_autopatrol-tier-model-and-detection-types.md
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-3-audit-tier-emissions.md
  - topics/integrations/vch/notes/syntheses/2026-05-18_libav-decoder-warmup-frame-fix.md
  - topics/personal-notes/notes/daily/2026-05-15.md
incoming_updated: 2026-05-27
---

# AutoPatrol Tier Spec ↔ API Code: Cross-Reference and Gap Analysis

Cross-reference of the [[2026-05-14_autopatrol-tier-model-and-detection-types|Immix AutoPatrol tier spec]] against the code surface in `actuate-libraries/actuate-integration-calls/.../autopatrol/`. Identifies (a) what the code already aligns with, (b) where it lags or misclassifies, and (c) what we need to change to honor the spec's "report the highest configured tier" rule.

## Code surface today

`actuate-libraries/actuate-integration-calls/src/actuate_integration_calls/autopatrol/autopatrol_enums.py`:

```python
class TierEnum:
    HEALTHCHECK = 1
    INTRUSION   = 2
    THREAT      = 3
    # No Compliance (4) or Management (5) yet — matches PDF "Future, not in use."

class VCHDetectionCodeEnum:
    CONNECTION    = "CNCTNFAIL"
    LOW_RES       = "LOWRES"
    LOW_FPS       = "UNSTABLE"
    VIDEO_LOSS    = "NOVIDEO"
    VCH_FAILED    = "VCHFAIL"
    SCENE_CHANGE  = "FOV"
    BLURRED_VIEW  = "BLUR"

class AutoPatrolDetectionCodeEnum:
    # Healthcheck-flavoured codes (mirrors VCH but with -RISK suffixes)
    CONNECTION    = "CNCTNFAIL"
    LOW_RES       = "RESRISK"
    LOW_FPS       = "STREAMRISK"
    VIDEO_LOSS    = "VIDEORISK"
    VCH_FAILED    = "VCHFAIL"
    SCENE_CHANGE  = "FOV"
    BLURRED_VIEW  = "IMAGERISK"
    # Intrusion (Tier 2 in spec)
    PERSON        = "PERSON"
    VEHICLE       = "VEHICLE"
    BIKE          = "BIKE"
    # Threat (Tier 3 in spec)
    CROWD         = "CROWD"
    FIRE          = "FIRE"
    SMOKE         = "SMOKE"
    UPS           = "UPS"
    FEDEX         = "FEDEX"
    DHL           = "DHL"
    AMAZON        = "AMAZON"
    USPS          = "USPS"
    FIRE_TRUCK    = "FIRETRUCK"
    SCHOOL_BUS    = "SCHOOLBUS"
    NO_LABEL      = "NO_LABEL"
```

`autopatrol_api.py` exposes tier through exactly two endpoints (verified by grep — these are the only places `tier`/`Tier` appears anywhere in `actuate-integration-calls/src/`):

- `get_patrol_stream(tenant_id, patrol_id, device_id, tier=TierEnum.HEALTHCHECK, duration=2)` — `Tier` query param on the Immix `/videostream` URL.
- `raise_patrol_alert(..., tier=TierEnum.HEALTHCHECK, ...)` — `tier` field inside the `threatData[].tier` JSON payload.

Both **default to Tier 1**. Callers must override.

## Design decision (2026-05-14, confirmed with Mark)

**Both tier-bearing surfaces must carry the *highest tier applicable to the configured detection set* for the patrol.** Not the tier of the firing detection, not a hardcoded default, and not Tier 1 unless the patrol is genuinely VCH-only. This applies symmetrically to `get_patrol_stream` (URL fetch) and `raise_patrol_alert` (alert raise) — there is no asymmetric "you only need tier on the alert" semantics.

Rationale: the PDF rule reads *"The AI Provider should return the value corresponding to the highest Tier associated with the detection types configured for that AutoPatrol, regardless of whether any detections were actually raised"*. "Return" is endpoint-agnostic — Immix uses tier on both surfaces (billing/routing on the stream fetch, classification on the alert) and the spec doesn't carve out an exception.

Operational consequence: an AutoPatrol whose configured detection set includes any Threat-tier code (Fire, Smoke, branded Vehicle ID, etc.) sends `Tier=3` on both endpoints; a patrol with only Intrusion-tier codes (Person, Vehicle, Bike) sends `Tier=2` on both. A patrol with no AutoPatrol-flavoured detections (i.e. VCH-only) sends `Tier=1` — but that's exactly the VCH path which the PDF says should not be returned as AutoPatrol anyway.

## Mapping: PDF detection types → code

| PDF Detection Type (Tier) | `AutoPatrolDetectionCodeEnum` | Coverage |
|---|---|---|
| Person Detection (T2) | `PERSON` | ✅ |
| Vehicle Detection (In Motion & Static) (T2) | `VEHICLE` | ✅ |
| Classification — car, truck, bus (T2) | *(no per-class codes)* | ⚠️ Only one generic `VEHICLE`; sub-classification not surfaced as distinct codes. |
| Bike Detection — bicycle, motorcycle (T2) | `BIKE` | ⚠️ Single `BIKE` code; no granularity for bicycle vs motorcycle. |
| Fire & Smoke (T3) | `FIRE`, `SMOKE` | ✅ |
| Vehicle ID — Amazon (T3) | `AMAZON` | ✅ |
| Vehicle ID — DHL (T3) | `DHL` | ✅ |
| Vehicle ID — FedEx (T3) | `FEDEX` | ✅ |
| Vehicle ID — School Bus (T3) | `SCHOOL_BUS` | ✅ |
| Vehicle ID — UPS (T3) | `UPS` | ✅ |
| Vehicle ID — USPS (T3) | `USPS` | ✅ |
| Vehicle ID — Fire Truck (T3) | `FIRE_TRUCK` | ✅ |
| Non-UPS Vehicle ID (T3) | *(no explicit code)* | ⚠️ Spec lists "Non-UPS Vehicle ID" as a distinct detection; enum has no `NON_UPS` code. Possibly conveyed via `NO_LABEL` or unbranded `VEHICLE`. Confirm with product. |
| Crowd Detection | `CROWD` | ⚠️ Page 1 tier table does **not** list CROWD in any tier. Page 2 puts it in Management (Tier 5, future). Page 3 commercial agreement lists it under Base Detection. **Inconsistent across PDF pages — tier classification of CROWD needs product clarification.** |
| Visual Camera Health (T1) | `VCHDetectionCodeEnum.*` (separate enum) | ✅ Handled on the VCH code path. |

## Call-site audit — which tier does today's code actually send?

| Call site | Endpoint | Tier passed | Spec expectation | Status |
|---|---|---|---|---|
| `vms-connector/healthcheck/alerts/senders/vch_alert_sender.py:64` | `raise_patrol_alert` (VCH alerts) | default `HEALTHCHECK` (=1) | Tier 1 (VCH) | ✅ |
| `actuate-libraries/actuate-alarm-senders/.../immix/autopatrol_sender.py:174-183` | `raise_patrol_alert` (AutoPatrol detection alerts) | **Hardcoded `THREAT` (=3)** | Highest configured tier — could be 2 OR 3 | ⚠️ Always sends Tier 3 even when only intrusion-class detections (Person, Vehicle, Bike) are configured. |
| `actuate-libraries/actuate-pullers/.../autopatrol_websocket_stream_puller.py:334, 398` | `get_patrol_stream` (live stream + retry) | default `HEALTHCHECK` (=1) | Highest configured tier per spec rule (assuming it applies symmetrically to stream fetches) | ⚠️ Always sends Tier 1 even for non-VCH AutoPatrols. |
| `vms-connector/site_manager/connector/integrations/autopatrol_site_manager.py:232` | `get_patrol_stream` (keepalive) | default `HEALTHCHECK` (=1) | Likely Tier 1 is fine for a keepalive — not a billable detection | ✅ (assumed) |

## Gaps to address

The spec's load-bearing rule is:

> "The AI Provider should return the value corresponding to the highest Tier associated with the detection types configured for that AutoPatrol, regardless of whether any detections were actually raised."

The connector does not implement this. Concrete gaps:

### G1. No `detection_code → tier` mapping

There is no function that, given a list of `AutoPatrolDetectionCodeEnum` values, returns the highest applicable `TierEnum`. We need one — likely in `actuate-integration-calls/autopatrol/autopatrol_enums.py` or a new helper module — e.g.:

```python
DETECTION_CODE_TIER = {
    # Tier 2 — Intrusion
    AutoPatrolDetectionCodeEnum.PERSON:    TierEnum.INTRUSION,
    AutoPatrolDetectionCodeEnum.VEHICLE:   TierEnum.INTRUSION,
    AutoPatrolDetectionCodeEnum.BIKE:      TierEnum.INTRUSION,
    # Tier 3 — Threat
    AutoPatrolDetectionCodeEnum.FIRE:       TierEnum.THREAT,
    AutoPatrolDetectionCodeEnum.SMOKE:      TierEnum.THREAT,
    AutoPatrolDetectionCodeEnum.UPS:        TierEnum.THREAT,
    AutoPatrolDetectionCodeEnum.FEDEX:      TierEnum.THREAT,
    AutoPatrolDetectionCodeEnum.DHL:        TierEnum.THREAT,
    AutoPatrolDetectionCodeEnum.AMAZON:     TierEnum.THREAT,
    AutoPatrolDetectionCodeEnum.USPS:       TierEnum.THREAT,
    AutoPatrolDetectionCodeEnum.FIRE_TRUCK: TierEnum.THREAT,
    AutoPatrolDetectionCodeEnum.SCHOOL_BUS: TierEnum.THREAT,
    # CROWD: tier classification ambiguous in spec — confirm with product before mapping.
}

def highest_tier_for(detection_codes: Iterable[str]) -> int:
    if not detection_codes:
        return TierEnum.HEALTHCHECK
    return max(DETECTION_CODE_TIER.get(c, TierEnum.HEALTHCHECK) for c in detection_codes)
```

### G2. `autopatrol_sender.py` hardcodes Tier 3

The single live call site that sends AutoPatrol detection alerts (`send_autopatrol_alert` in `actuate-alarm-senders/.../immix/autopatrol_sender.py:174`) passes `tier=TierEnum.THREAT` unconditionally. It should compute the highest tier across the AutoPatrol's *configured* detection set (from the patrol's `feature_deployments` / detection-code configuration), not the per-firing detection's tier.

The spec is explicit: *"regardless of whether any detections were actually raised."* So a Person-detection AutoPatrol that happens to fire a Person alert should still report Tier 2 (its highest configured tier) — not the tier of the specific detection that fired.

### G3. `get_patrol_stream` always requests Tier 1 [confirmed in scope]

The puller fetches video streams with `tier=TierEnum.HEALTHCHECK` for AutoPatrol runs. Per the 2026-05-14 design decision above, this must be the patrol's highest configured tier — not just on the alert raise but on the stream URL fetch as well. Two call sites in `actuate-libraries/actuate-pullers/src/actuate_pullers/socket/autopatrol_websocket_stream_puller.py`:

- Line 398 — initial `init_stream()` fetch.
- Line 334 — `ConnectionClosed` retry path that re-fetches a fresh stream URL.

Both must pass `tier=highest_tier_for(patrol_configured_codes)` from G1. The connector-side keepalive call (`autopatrol_site_manager.py:232`) is arguably exempt because it's not associated with a specific patrol's detection set — leave as Tier 1 unless product disagrees.

### G4. Ambiguous `CROWD` tier

`CROWD` appears in three places with different implications:
- PDF page 1 tier table: **not listed**.
- PDF page 2 module hierarchy: in **Management** (Tier 5, future, not in use).
- PDF page 3 commercial agreement: in **Base Detection Features**.

The enum has `CROWD = "CROWD"` but the highest-tier mapping is unclear. Product clarification required before we ship a mapping. Conservative default: treat as Tier 3 (Threat) since it's available in Base Detection and Tier 5 is not yet active — but flag this to product first.

### G5. Missing detection codes

The PDF Page 1 tier table mentions:
- **Classification (car, truck, bus)** — no sub-codes in enum. Likely fine if `VEHICLE` carries class metadata, but the granularity isn't visible at the enum level.
- **Non-UPS Vehicle ID** — no explicit code. May be implicit (i.e. `VEHICLE` without one of the branded sub-codes), but the spec treats it as a distinct Tier 3 detection. Confirm with product.

### G6. Compliance & Management tiers absent (intentional)

`TierEnum` doesn't define 4 (Compliance) or 5 (Management). This matches the spec's "Future, not in use, subject to change." **No change required today;** track this so we don't get caught off-guard when product activates those tiers.

## Where "configured detection types" lives in code

Pre-work for implementation — the configured detection set for a patrol is derivable but not in one place today:

- Per-camera `feature_deployments` are attached to each `CameraStream` (e.g. `actuate-config/.../base_connector_config.py:230` and per-integration camera_stream subclasses). Each `FeatureDeployment` carries the model's `Labels` / detection metadata.
- Outbound model labels are mapped to detection codes via `OutboundLabelsConverter` (`actuate-config/.../outbound_labels_converter.py`), which converts raw model class names into the strings consumed by alert senders.
- The bridge from "configured model labels" to `AutoPatrolDetectionCodeEnum` strings goes through the same converter / per-product observer config.

So `highest_tier_for(...)` (G1) needs a feed of detection-code strings, sourceable from iterating each camera stream's feature_deployments → outbound labels → mapped codes, deduped per patrol. **The patrol-level aggregation is new — today's code only ever asks "what code is *this* detection?"**, not "what's the union of codes across this patrol's cameras?". Likely lands as a small helper on `AutoPatrolConnectorConfig` (the config class shared by AP + VCH) or on `AutoPatrolConfig` directly.

## Suggested implementation order

1. **(Spec sync — still open)** Confirm with product/Immix: (a) Non-UPS Vehicle ID concrete code, (b) CROWD tier classification. Both block the *contents* of the mapping table but not the existence of it. Items G1–G3 can proceed in parallel with placeholder/conservative entries for CROWD/Non-UPS.
2. **(Library — `actuate-integration-calls`)** Add `DETECTION_CODE_TIER` mapping + `highest_tier_for(codes: Iterable[str]) -> int` helper. Unit tests for: empty → HEALTHCHECK, intrusion-only → INTRUSION, mixed intrusion+threat → THREAT, unknown code → HEALTHCHECK (conservative fallback) or raise (strict — pick one).
3. **(Library — `actuate-config` or new helper)** Add a patrol-level accessor — e.g. `AutoPatrolConnectorConfig.configured_detection_codes` — that walks `camera_streams[].feature_deployments[]` and yields the union of mapped detection codes for the patrol. Unit tests with synthetic feature_deployments.
4. **(Library — `actuate-alarm-senders`)** Update `autopatrol_sender.send_autopatrol_alert` to call `tier=highest_tier_for(autopatrol_config.configured_detection_codes)` instead of hardcoded `TierEnum.THREAT`. Backward-compat: existing intrusion+threat patrols still send Tier 3; intrusion-only patrols start sending Tier 2 (spec-correct).
5. **(Library — `actuate-pullers`)** Update both call sites in `AutopatrolWebSocketStreamPuller.consume_stream` (line 398 init + line 334 retry) so `get_patrol_stream(..., tier=...)` carries the patrol's highest configured tier. Plumbing: thread `tier` into `__init__` from `autopatrol_config` or compute lazily on first fetch.
6. **(Connector)** Pull the bumped library pins, validate on a feature deployment with a Tier-2-only patrol (Person-detection only) and confirm Immix accepts `Tier=2` on both `/videostream` and `/raise`. Then PR to `stage`. (Per [[feedback_feature_branches_target_stage]].)

Cost / risk: changes are confined to the alarm-sender library + the puller + a small config accessor. No changes to VCH (VCH defaults to Tier 1 and that remains correct). Backward compatibility: Immix has always accepted `tier=3` for AutoPatrol alerts; changing to `tier=2` for intrusion-only patrols is the intended behavior per the spec, and `tier=2|3` on `/videostream` aligns with how Immix bills/routes per the spec rule.

## Open product questions (block step 1 only)

- **CROWD tier:** Tier 3 (Threat) by conservative default vs. defer to product. Page 2 hints at Management (T5, future) but T5 isn't active yet.
- **Non-UPS Vehicle ID:** Distinct enum entry? Or implicit (any `VEHICLE` without a branded sub-code)?
- **"Classification (car, truck, bus)":** Same question — are these distinct codes or `VEHICLE` + metadata?
- **Keepalive (`autopatrol_site_manager.py:232`) tier:** Assume Tier 1 is fine because it's not patrol-scoped. Confirm.

## Cross-references

- [[2026-05-14_autopatrol-tier-model-and-detection-types]] — the verbatim Immix spec this note cross-references.
- [[vch-components]] — VCH = Tier 1 in this spec, unchanged.
- [[2026-05-06_immix-streamfailed-worker-lifespan]] — Immix-side worker lifecycle; relevant when revisiting `get_patrol_stream` tier behavior.
- [[feedback_feature_branches_target_stage]] — branching discipline for the connector-side rollout.
