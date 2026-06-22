---
title: "Run Service — Translation Layer + Schema Drift"
type: synthesis
topic: fleet-architecture
tags: [fleet-architecture, run-service, settings-json, translator, schema-drift, canary, sensitivity-presets]
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
status: drafting
incoming:
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/api-contract.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-c.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-d.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-e.md
incoming_updated: 2026-05-27
---

# Run Service — Translation Layer + Schema Drift

How `RunSpec.v1` (the public API contract from [[api-contract]]) becomes a full `settings.json` that the connector image consumes, and how the design stays drift-resistant given that admin-API holds **zero state** about run-service runs.

## The translation problem in one paragraph

The connector's `settings.json` is a 200+ line tree with deeply nested per-camera, per-stream, per-product, per-detection-threshold config — most of which the caller of a run shouldn't have to know about. The API exposes a curated surface (cameras, products with sensitivity presets, alerts, duration); the translator fills in the long tail (model registry lookups, monitoring thresholds, S3 key roots, raw detection thresholds, healthcheck stubs). The translator is the **only** code in the system that knows the full settings.json shape.

## Field categorization

Every field in `settings.json` falls into one of four buckets:

| Bucket | Source | Examples | What changes break it |
|---|---|---|---|
| **A. Caller-supplied** | Direct from `RunSpec` | `cameras[].base_url` from `cameras[].rtsp.url`, `customer.password` from `cameras[].rtsp.password`, alert recipients, product zones | Caller sends bad input → 422 in the API layer |
| **B. Platform-default** | Static config in the translator | `customer.locale` (with caller override), `customer.use_new_relic: true`, `customer.log.level`, `monitoring.fps_alarms`, healthcheck shape, sensitivity preset → numeric mapping | Connector adds new required field → canary catches |
| **C. Derived per run** | Computed from the spec | `customer.site_id` (synthetic id), `customer.display_name` from `name`, `cameras[].stream_id` (synthetic), `models[]` array filled by resolving caller's products against the registry | Model/product registry shape changes → translator unit test catches |
| **D. Hardcoded for the run-service path** | Never derived; constants for runs that originate via run-service vs admin-api | `customer.demo: false`, `customer.flex_schedule_id: null`, `customer.healthcheck.deployment: 0` (logic platform-side, not admin-driven), `patrol: null` (when not autopatrol), `customer.store_local: false` for ephemeral | Mostly stable; if connector requires a new field here, canary catches |

The translator's job is to assemble all four buckets into a valid `settings.json`. The split lets us reason about drift surface area: bucket A is caller-shape coupled; bucket B is platform-policy coupled (and is where sensitivity presets live); bucket C is registry-coupled; bucket D is fixed.

## RTSP-only translation, with extension hooks

v1 accepts only `site.integration_type: "rtsp"`. The translator dispatches on this discriminator at the **site level** (which credentials block to read) and on the per-camera credentials (which [[rtsp-deep-dive|RTSP]] fields to consume):

```python
SITE_TRANSLATORS = {
    "rtsp": translate_rtsp_site,
    # Future:
    # "avigilon":  translate_avigilon_site,
    # "milestone": translate_milestone_site,
    # "genetec":   translate_genetec_site,
}

def translate(spec: RunSpec) -> Settings:
    fn = SITE_TRANSLATORS.get(spec.site.integration_type)
    if fn is None:
        raise UnsupportedIntegration(spec.site.integration_type)
    return fn(spec)
```

Adding Avigilon later = (1) extend the spec with an `avigilon: {...}` site-level credentials block + per-camera config, (2) write `translate_avigilon_site`, (3) register it. No changes to the rest of the translator. v1 ships RTSP-only with a clean `unsupported_integration` error for the rest.

### RTSP camera translation example

```
spec.cameras[i] = {
  id: "cam-1",
  rtsp: { url, username, password, transport },
  schedule: { mode: "always" },
  crop: null,
  products: [
    { product: "intruder", sensitivity: "medium", models: ["weapon-mid"], alert_triggers: ["main-ops"] },
    { product: "loitering", sensitivity: "low", alert_triggers: ["main-ops"] }
  ]
}

   ↓  translate_rtsp_camera(spec_cam, run_ctx)

settings.cameras[i] = {
  base_url: "<host:port/path from spec.rtsp.url>",
  camera_name: spec_cam.id,                # caller's id surfaces in alerts
  admin_camera_id: synthetic_id(spec_cam.id, run_ctx.run_id),
  http_port: 80,
  streams: {
    production: {
      threat: assemble_threat_config(spec_cam.products, run_ctx)
    }
  }
}
```

`assemble_threat_config` is where products + sensitivity presets get expanded — see the next two sections.

The `customer.username` / `customer.password` / `customer.server_ip` / `customer.server_port` / `customer.protocol` / `customer.integration_type` fields at the top of `settings.json` look like a single-camera-per-site holdover. For multi-camera [[rtsp-deep-dive|RTSP]] runs, the translator needs a story:

**Open:** the existing single-camera fields (`customer.server_ip`, `customer.username`, etc.) are vestigial when `cameras[]` carries per-camera [[rtsp-deep-dive|RTSP]] urls. Either (1) the translator picks the first camera's [[rtsp-deep-dive|RTSP]] and writes those fields for compatibility, (2) we confirm with the connector team that the per-camera entries are sufficient and these top-level fields can be defaulted to placeholder values, or (3) the connector image needs a small change to accept missing top-level fields when `cameras[]` is fully populated. **This is the highest-priority open question for the translator** — flagged for follow-up.

## Sensitivity preset → numeric mapping

The API exposes `sensitivity: "low" | "medium" | "high"` per product. The translator maps each preset to a bundle of numeric thresholds the connector consumes. Mapping lives in-code (see "Defaults" below).

**Per-product sensitivity bundles** (illustrative; final values calibrated by the inference team):

| Product | Preset | `first_layer_confidence` | `iou_thresh` | `denominator` | `pre_alarm` | `window_length` | Notes |
|---|---|---|---|---|---|---|---|
| `intruder` | low | 50 | 0.85 | 8 | 8 | 20 | Fewer alerts, fewer false positives |
| `intruder` | medium | 40 | 0.85 | 5 | 5 | 15 | Default; matches today's typical settings |
| `intruder` | high | 30 | 0.80 | 3 | 3 | 10 | More alerts, more false positives |
| `weapon` | low | 60 | 0.90 | 5 | 3 | 10 | |
| `weapon` | medium | 50 | 0.85 | 3 | 2 | 8 | |
| `weapon` | high | 40 | 0.80 | 2 | 1 | 5 | |
| `loitering` | low | 50 | 0.85 | dwell ≥ 60s | — | — | Dwell-time semantics differ from instant detection |
| `loitering` | medium | 40 | 0.85 | dwell ≥ 30s | — | — | |
| `loitering` | high | 30 | 0.80 | dwell ≥ 15s | — | — | |

**Caller experience consequence:** sensitivity is the only knob callers expose for detection tuning. Internal tuning of `first_layer_confidence` (or any other numeric) is a platform decision; we can change `medium`'s underlying numbers and all callers benefit.

**Versioning:** if we tune a preset's underlying values, two options:
- **Pin** — existing runs keep their original values; new runs get the new mapping. Cleaner; no behavior surprises.
- **Migrate** — existing runs immediately pick up the new values. Necessary if a tuning fixes a real bug.

Default to **pin** for v1; migrate only when justified. The DynamoDB `run_service_runs` record stores the resolved numeric values alongside the original `sensitivity` preset for traceability.

### Per-product preset taxonomy is unconstrained

Some products may want sensitivities outside `low / medium / high`. Loitering already needs a dwell-time scale; line-crossing might want directionality presets; weapon detection might add `extreme` for the highest-stakes deployments. The translator is permissive: each product registers its own allowed presets. The default is `low / medium / high`; products can add more without breaking the v1 schema.

## Product → threat config mapping

Each product in `spec.cameras[i].products[]` translates into one or more entries inside `settings.cameras[i].streams.production.threat`. The `threat.metrics` block carries product-specific config; `threat.raw_metrics` carries the per-class detection thresholds.

```python
def assemble_threat_config(products: list[ProductSpec], ctx: TranslationContext) -> dict:
    threat = {
        # Bucket B platform defaults
        "merge_vehicles": True,
        "ensemble": False,
        "slice": False,
        "split": False,
        "stationary_filter": False,
        "desired_size": 608,
        "fps": 1,
        "candidate_parameter": 0.2,
        "save_result_probability": 0.0,
        # Bucket C derived
        "stream_id": ctx.synthetic_stream_id(),
        "s3_key_frames_root": f"runs/{ctx.run_id}/{ctx.camera_id}/",
        "s3_bucket": PLATFORM_FRAMES_BUCKET,
        # Bucket D run-service hardcoded
        "live_alert": True,
        "motion_recording": False,
        "use_blacklist": False,        # run-service runs don't use blacklist
        # Per-product expansion below
        "metrics": {},
        "raw_metrics": {},
    }

    for product in products:
        preset = SENSITIVITY_PRESETS[product.product][product.sensitivity]
        threat["metrics"][product.product] = build_product_metrics(product, preset)
        merge_raw_metrics(threat["raw_metrics"], preset.raw_metrics_classes)

    # Merge model_name / model_id from all products' driving models
    threat["model_name"] = pick_or_compose_model_name([p.product for p in products])
    threat["first_layer_confidence"] = min_first_layer_confidence(products)
    return threat
```

### Product-specific `threat.metrics` shape

Each product gets its own block in `threat.metrics`. Shapes are product-specific:

```python
# Intruder
threat.metrics["intruder"] = {
    "sensitivity": preset.label.capitalize(),   # "Medium"
    "thresh": preset.intruder_thresh,            # 2
    "denominator": preset.denominator,           # 5
    "tag_zones": product.zones or [],
    "line_crossings": product.line_crossings or [],
}

# Weapon
threat.metrics["weapon"] = {
    "sensitivity": preset.label.capitalize(),
    "thresh": preset.weapon_thresh,
    "tag_zones": product.zones or [],
}

# Loitering
threat.metrics["loitering"] = {
    "sensitivity": preset.label.capitalize(),
    "dwell_threshold_seconds": preset.dwell_seconds,
    "tag_zones": product.zones or [],
}
```

Adding a new product type = new entry in `SENSITIVITY_PRESETS`, new block-builder, register in `assemble_threat_config`. Schema-versioned; canary catches if connector parser changes its expected shape.

### `raw_metrics` (per-class thresholds)

Every product contributes which inference classes it cares about. The translator unions these across the camera's products:

```python
def merge_raw_metrics(target: dict, classes: list[str]) -> None:
    defaults = {"minimum_confidence": 50, "iou_thresh": 0.85}
    for cls in classes:
        target.setdefault(cls, defaults.copy())
```

If two products on the same camera disagree on a class threshold (rare), the translator picks the **looser** (lower confidence threshold) so neither product is starved. Logged as a warning.

## Alert plumbing → settings.json mapping

`RunSpec.alerts[]` is a flat list of alert configs with channels and trigger filters. The translator expands these into multiple settings.json fields, depending on channel type and trigger type:

| RunSpec alert channel | settings.json target | Notes |
|---|---|---|
| `email` | `customer.healthcheck.alert_emails[]` (when `triggers` includes healthcheck) AND `cameras[].streams.production.threat.healthcheck.alert_emails[]` (when product alert) | Routed by trigger type |
| `sms` | `customer.healthcheck.cell_numbers[]` AND `cameras[].streams.production.threat.cell_numbers[]` | Same routing logic |
| `webhook` | `cameras[].streams.production.threat.webhook_event_types[]` + a webhook-target lookup | Connector dispatches via alert-sender |
| `sns` | `cameras[].streams.production.threat.label_watch_sns_topic_arns[]` | SNS topic must allow our principal (caller's responsibility) |
| `integration: crisis_go` | `cameras[].streams.production.threat.crisis_go_alarm: true` + integration config | Alert-sender wires up |
| `integration: envera` | `cameras[].streams.production.threat.envera_alarm: true` | |
| `integration: genetec` | `cameras[].streams.production.threat.genetec_alarm: true` | |
| `integration: stages` | `cameras[].streams.production.threat.stages_alarm: true` | |
| `integration: immix` / `label_watch` | Specific config blocks per integration | Each integration's translator branch owns its mapping |

### Per-trigger routing

The `triggers[]` field on each alert config determines which settings.json subtree the channels get attached to:

| Trigger | Settings.json subtree |
|---|---|
| `product_alert` | `cameras[].streams.production.threat.*` (per-product) |
| `healthcheck` | `customer.healthcheck.*` |
| `scene_change` | `customer.healthcheck.scene_change_check.*` |
| `stream_quality` | `customer.healthcheck.stream_quality_check.*` |
| `motion_status` | `customer.healthcheck.motion_status_check.*` |
| `connectivity` | `customer.healthcheck.connectivity_check.*` |

Each healthcheck sub-block has its own `alert_emails[]` (and similar) — which is how the same channel can fire for `product_alert` events from one config and `connectivity` events from another, with different recipients per type.

### Per-product alert filtering

Today's `triggers[]` applies to **all** products in the run. Per-product filtering ("this config fires for intruder + weapon, not loitering") is **not** in v1. Open question 10 in [[api-contract]] tracks whether to add it.

## Healthcheck / monitoring as platform-defaults

Healthcheck **logic** is platform-side. The translator writes a fixed `customer.healthcheck` skeleton:

```python
PLATFORM_HEALTHCHECK_DEFAULTS = {
    "deployment": 0,                    # Run-service runs aren't admin-deployment-bound
    "debug": False,
    "disabled_cameras": [],
    "sensitivity_level": "medium",
    "connectivity_check":  {"enabled": True},
    "scene_change_check":  {"enabled": True},
    "motion_status_check": {"enabled": True},
    "recording_check":     {"enabled": True},
    "stream_quality_check":{"enabled": True},
    "image_quality_check": {"enabled": True},
}
```

**Recipients** for these healthcheck-type alerts come from the caller's `alerts[]` configs whose `triggers[]` include the relevant trigger type. Translator weaves them in:

```python
healthcheck = PLATFORM_HEALTHCHECK_DEFAULTS.copy()
for alert in spec.alerts:
    for trigger in alert.triggers:
        if trigger == "healthcheck":
            healthcheck["alert_emails"] += [c.address for c in alert.channels if c.type == "email"]
            healthcheck["cell_numbers"] += [c.number  for c in alert.channels if c.type == "sms"]
        elif trigger == "scene_change":
            healthcheck["scene_change_check"]["alert_emails"] = [...]
        # ... and so on per trigger
```

Same model for `monitoring.{cpu, memory, fps_alarms, heartbeat, motion, processing_alarms}` — platform defaults, no caller knobs in v1.

## Defaults — where they live, how they version

Bucket B (platform defaults) is the largest and most fragile. Approaches considered:

| Approach | Location | Pros | Cons |
|---|---|---|---|
| **In-code constants** | Python module in the translator | Easy to read, change tracked in git, atomic with code | Requires Lambda redeploy to tweak |
| **JSON manifest + S3** | `s3://run-service-platform/defaults/v{N}.json` | Tweak without redeploy, environment overrides | Defaults can drift from translator version |

**Recommendation:** in-code constants for v1 (Lambda redeploys are fast and cheap, and we want defaults change-tracked alongside translator code). Sensitivity preset bundles, healthcheck skeleton, monitoring defaults, S3 bucket name — all in-code.

Defaults are versioned with the translator; the connector image declares minimum supported translator-default-version in its own metadata, and the canary asserts compatibility.

## Model resolution

Caller specifies models per-product (e.g., `models: ["weapon-mid"]`). Most products have a default model; callers usually omit `models` and accept the default. The translator resolves to:

1. The full `settings.cameras[].streams.production.threat.raw_metrics` map (per-class thresholds; from sensitivity preset).
2. The `settings.models[]` array entries (model_name → endpoint → port → id).

Resolution table is hardcoded in the translator and updated when the inference layer adds models. The translator validates that every model the caller references is known **before** running connector validation, so callers get a clean `unknown_model` error instead of a connector parse failure.

```python
MODEL_REGISTRY = {
  "weapon-mid": {
    "settings_model_name": "EKS to EKS weapon",
    "model_ip": "weapon-svc.ds-model-prod.svc.cluster.local",
    "model_port": 8080,
    "model_id": 42,
    "raw_metrics_classes": ["weapon", "person"],
  },
  "person": {
    "settings_model_name": "EKS to EKS intruder",
    "model_ip": "intruder-svc.ds-model-prod.svc.cluster.local",
    "model_port": 8080,
    "model_id": 31,
    "raw_metrics_classes": ["person", "car", "bicycle", ...],
  },
  ...
}

PRODUCT_DEFAULT_MODELS = {
    "intruder":   ["person"],
    "weapon":     ["weapon-mid", "person"],
    "loitering":  ["person"],
    "line-crossing": ["person", "car"],
}
```

Drift surface: when the inference team retires a model or changes its endpoint, the registry needs an update. The canary catches drift within an hour.

## Layered validation — three checkpoints, three failure modes

```
Caller's POST body
    │
    ▼
[1] RunSpec.v1 validation                    (Pydantic / JSON Schema)
    │  fails → 422 spec_validation_failed
    ▼
[2] Translator                                (pure function)
    │  fails → 422 translation_failed
    │           (e.g., unknown_model, unknown_product, unsupported_integration)
    ▼
[3] Connector validate init container        (`connector validate /config/settings.json`)
    │  fails → 422 connector_validation_failed   ← drift signal: page on this
    ▼
Real K8s workload scheduled (paradigm-specific)
```

Each layer's failure is **distinguishable** in the error response:

- (1) failures = caller sent bad input → caller fixes the request.
- (2) failures = caller sent valid spec, translator rejected → either user error (unknown model/product) or our defaults are stale.
- (3) failures = translator output rejected by connector → **schema drift**. Page ops; canary should have caught this earlier.

## `validate` init container

The connector image gets a validation entrypoint that loads `settings.json` and exits:

```bash
# Real run (existing behavior)
$ connector run /config/settings.json

# New for run-service
$ connector validate /config/settings.json
# exit 0 if parse + structural validation succeeds
# exit 1 if parse fails (with a structured error to stderr)
# exit 2 if validation fails (e.g., model_name not in models[])
```

Pod spec sketch:

```yaml
spec:
  initContainers:
  - name: validate-settings
    image: <connector-image>:<tag>
    command: ["connector", "validate", "/config/settings.json"]
    volumeMounts:
    - name: settings
      mountPath: /config
  containers:
  - name: connector
    image: <connector-image>:<tag>
    command: ["connector", "run", "/config/settings.json"]
    # ...
```

If the init container exits non-zero, the workload fails fast (~5s of pod start) without burning model-loading time. The Lambda watches workload status; if init failed, it returns the structured error to the caller as `connector_validation_failed`.

**Why an init container, not a pre-flight in Lambda:** the connector's parser is the source of truth, and shipping a duplicate Pydantic model into Lambda would be exactly the kind of duplicated-schema-that-drifts we're trying to avoid. The init container runs the same code path the real container does, by definition matching production parser behavior.

**Cost:** ~3-5 seconds per run for init-container pull (cached after first pull on a node) + parse. Well below the 60s API-response budget.

**Open:** does the connector image already have a `validate` subcommand, or is this a new feature on the connector itself? If new, add it as part of the run-service rollout. The implementation is small (Pydantic `Settings.model_validate(json.loads(open(path).read()))` + exit code mapping); the work is integrating it into the connector's CLI cleanly.

## Stub-site canary — periodic drift detector

The canary catches drift between the translator's output and what the **latest** connector image accepts, **before** a real customer call hits a `connector_validation_failed`.

### What runs

A small program — pure Python, no LLM — that:

1. Reads a known-good `RunSpec` fixture from the canary's repo.
2. Calls the production translator (importable as a library, or via a deployed dev API endpoint).
3. Pipes the output `settings.json` to a temporary container running the latest connector image with `connector validate`.
4. On non-zero exit, posts to PagerDuty + writes to NR custom event `RunServiceCanaryFailure`.

### Where it runs

Tier 1 of the [[../engineering-process/notes/syntheses/2026-04-30_three-tier-routine-check-pattern|three-tier routine-check pattern]] — Firebat systemd timer, hourly. Falls back to GH Actions if Firebat is unreachable. A `/canary-check` skill is the Tier 3 LLM fallback only when both scripts fail (and that fallback's job is to **diagnose why and patch the script**).

### What "known-good" means

The fixture set covers spec features that have nontrivial translator paths:

| Fixture | Mode | Cameras | Products | Why |
|---|---|---|---|---|
| `01-ephemeral-single-rtsp-intruder.json` | ephemeral | 1 | intruder@medium | Smallest possible run |
| `02-ephemeral-multi-rtsp-mixed.json` | ephemeral | 4 | intruder + weapon, mixed sensitivities | Multi-camera, multi-product |
| `03-ephemeral-rtsp-with-schedule.json` | ephemeral | 1 | intruder | Time-windowed schedule |
| `04-ephemeral-rtsp-with-zones.json` | ephemeral | 1 | intruder + line-crossing | Zone tagging, line crossings |
| `05-ephemeral-rtsp-inline-alerts.json` | ephemeral | 2 | intruder | Inline email + webhook recipients |
| `06-ephemeral-rtsp-ref-alerts.json` | ephemeral | 2 | intruder | Pre-registered alert configs |
| `07-ephemeral-rtsp-sns-integration.json` | ephemeral | 2 | weapon | SNS topic + crisis_go integration |
| `08-ephemeral-rtsp-max-cameras.json` | ephemeral | 48 | intruder | Boundary case at limit |
| `09-persistent-single-rtsp-intruder.json` | persistent | 1 | intruder@medium | Smallest persistent run |
| `10-persistent-multi-rtsp-full.json` | persistent | 8 | full product mix | Realistic persistent site config |
| `11-ephemeral-loitering-product.json` | ephemeral | 1 | loitering@high | Dwell-time semantics |

Every PR to the connector that touches `settings.json` parsing must keep all 11 fixtures green; the canary catches what merged anyway.

### What about post-merge drift in the translator itself?

The canary catches translator-vs-connector drift. To catch translator-vs-spec drift (translator wrote something the API should have rejected), the translator has its own unit-test corpus drawn from `~/work/settings-files/` real customer dumps. The test asserts: for each real customer settings.json, you can derive a `RunSpec` (or document why you can't — e.g., uses a feature run-service doesn't expose) that the translator round-trips back to a settings.json that's structurally equivalent (modulo bucket D run-service overrides).

This is a one-time manual derivation for the corpus, then automated thereafter. If a customer's real settings.json contains a field shape the translator can't produce, that's a flag to either extend the API or document the limitation.

### Alert thresholds

| Canary signal | Yellow | Red |
|---|---|---|
| Any fixture failing | 1+ for 1 cycle | 1+ for 3 cycles |
| Total runtime > 60s | yes | > 120s |
| Translator import failure | — | yes (immediate) |

Red status feeds the [[dashboard-check]] dashboard as a signal alongside operational health.

## Drift recovery — what happens when the canary fires

1. **Page** — PagerDuty + NR event.
2. **Triage** — which fixture failed? Diff the settings.json output between the last green run and now. Identify which connector field is the culprit.
3. **Root-cause** — usually one of:
   - Connector added a new required field → translator needs to set it (bucket B or D).
   - Connector renamed a field → translator's field name is stale.
   - Connector tightened validation on an existing field → translator's defaults need updating.
   - Model registry out of sync with inference layer → registry update.
   - Sensitivity preset's underlying numbers became invalid for a connector-side constraint → preset update.
4. **Fix** — translator change + new fixture (if a new field shape needs covering) + canary re-run.
5. **Postmortem note** — what changed, why we missed it pre-merge, fixture coverage gap. Logged to KB under `engineering-process/concepts/`.

If the canary is red for >24h, run-service should refuse new runs (return `503` with `service_degraded`) until green. Persistent runs that are already running keep running — they're not affected by a translator drift, only new spec submissions are.

## Translator code location

| Option | Pros | Cons |
|---|---|---|
| **A. New repo `run-service`** | Clean ownership, no coupling to existing repos | Adds a repo to maintain |
| **B. Sub-package of `actuate-libraries`** | Reuses existing CodeArtifact publish machinery; connector and translator can share types | Library change cycle is heavier than a service repo |
| **C. Sub-package of `vms-connector`** | Translator + connector parser live together (no drift between them by construction) | Couples public API surface to connector release cadence |

**Recommendation:** option **C**. The translator's correctness is defined by the connector's parser; co-locating them eliminates the drift class entirely (canary becomes a regression test of "did this PR forget to update the translator?"). The Lambda orchestrator becomes a small `run-service` repo that imports `vms_connector.run_service_translator` as a library.

Trade-off accepted: connector release cadence drives API release cadence. For a permanent control plane this is non-trivial — connector releases happen weekly, sometimes more often, and run-service consumers don't want to track every bump. Two mitigations:

- The **Lambda pins** the connector image tag at deploy time (so a connector release doesn't auto-affect the running translator until run-service redeploys).
- The **translator interface is stable** (add fields, don't remove) so Lambda → connector library compatibility doesn't break across minor connector versions.

## Open questions

1. **Vestigial top-level customer fields** — do `customer.server_ip`, `customer.username`, etc. need to be set when `cameras[]` is multi-camera? Highest-priority follow-up.
2. **`validate` subcommand** — does the connector image already have one, or is this a new ENG ticket?
3. **Defaults location** — in-code (recommended) vs S3 manifest. Tag for revisit if env-specific overrides become important.
4. **Translator code location** — picked C, but worth a sanity check from the connector team.
5. **Model registry hot-reload** — if the inference team stands up a new model, does the translator need a redeploy, or do we want a registry that hot-reloads from a config map / DynamoDB?
6. **Canary fixture corpus growth** — 11 fixtures at start; what's the discipline for keeping the set representative as the API grows?
7. **Sensitivity preset numeric calibration** — final numbers per product × preset need inference-team sign-off before launch.
8. **Sensitivity preset versioning policy** — pin existing runs vs migrate live? Default to pin; revisit per-tuning.
9. **Per-product sensitivity scales** — keep universal `low / medium / high`, or allow per-product scales (loitering's dwell-time, line-crossing's directionality)? Permissive registry today; canonicalize when usage clarifies.
10. **Disagreeing per-class thresholds across products on same camera** — translator picks looser; should we instead error and force the caller to disambiguate? Only matters if disagreement is common.
11. **Bucket D run-service vs admin-api split** — do `customer.demo`, `flex_schedule_id`, etc. have meaningful values for run-service runs, or are they always defaulted? Affects how cleanly run-service runs differ from admin-api runs in the data model.

## Cross-references

- [[_overview]] — project framing + schema-drift design
- [[api-contract]] — the input shape this layer translates from
- [[paradigm-c]] / [[paradigm-d]] / [[paradigm-e]] — the executors that consume the translated `settings.json`
- [[../../../engineering-process/notes/syntheses/2026-04-30_three-tier-routine-check-pattern|three-tier routine-check pattern]] — canary scaffolding
- [[vms-connector/_summary]] — the parser that's the source of truth
- [[settings-automation/_summary]] — adjacent settings.json work
