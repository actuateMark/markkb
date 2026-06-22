---
title: "Customer Model Dissection — Candidate Split Seams"
type: synthesis
topic: admin-api
tags: [admin-api, customer-model, architecture, refactor-candidate, actuate-admin, dissection]
jira: "AI-184"
created: 2026-05-13
updated: 2026-05-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/concepts/2026-05-13_handoff-deploy-branch-phase1.md
  - topics/actuate-platform/notes/concepts/2026-05-18_handoff-deploy-branch-phase1-resume.md
  - topics/admin-api/notes/syntheses/2026-05-20_deploy-branch-full-scope.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watchman-scheduling-brainstorm-correlation.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-migration-plan.md
  - topics/personal-notes/notes/daily/2026-05-13.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-30
---

# Customer Model Dissection — Candidate Split Seams

The Customer model is accreting complexity faster than the codebase can absorb. **2221 lines, 70+ fields, 12+ functional domains, and still growing.** Recent work pulls Mark into distributed edits across four new files for §29 alone; v8 intruder is about to add Sensitivity FKs that point at Customer; and committed regressions (e.g., `f1ad8fcb` — custom-tag breaks when deployment_phase flips to PROD) cluster around deployment-lifecycle state. This note maps the model's fault lines so the next session can execute a split before the entanglement becomes harder to unwind.

## Scale Crisis

- **customer_model.py:** 2221 lines, 70+ fields, 132 model field definitions (`= models.`), ~8 major method families
- **customer_view.py:** 1458 lines — admin UI wiring + duplicated logic (duplicate_site action, custom_deployment_validation, cluster-routing queries)
- **Growth trajectory:**
  - `51e494d2` — moved endpoint_stage + queue_stage from AutoPatrolSchedule onto Customer (consolidation in wrong direction)
  - AUTO-551 chain (5 commits, 27b2514c–0c1e200f) — added vlm_enabled + vlm_sample_rate fields
  - `f1ad8fcb` — custom-tag regression when deployment_phase flips to PROD (unintended coupling exposed)
  - §29 scaffolding — added 4 new files around Customer, plus image_tag_override_expires_at + pre_custom_deployment_phase fields still incoming
  - AI-184 v8 intruder — Sensitivity FK pointing at Customer for per-scope thresholds (inbound coupling)

## Field-Domain Inventory (70+ fields grouped by responsibility)

**Identity (7 fields):**
name, customer_id, deployment_id, notes, source, onboarding_integration, lead

**VMS/camera connection & integration-specific (60+ fields, 90% per-row unused):**
- Core: server_ip, server_port, username, password, integration_type FK, protocol
- Milestone: milestone_ssl_port, milestone_http_port, stream_port, alert_port, management_server FK, user_nonce, key
- OpenEye: openeye_nvr_id, openeye_use_ows, openeye_ows_username, openeye_ows_password, openeye_stream_type
- Star4Live: device_name, server_ip_star4live, password_star4live, username_star4live
- Eagle Eye: een_api, app_name, api_key
- [[hikcentral-components|Hikcentral]]: hikcentral_key, hikcentral_secret, hikcentral_alert_port
- DW NX: area_name, use_nx_proxy, nx_username, nx_password
- DW v5/Stages: cloud_system_id, use_v5, stages_account, signal_code, stages_address, stages_port (deprecated)
- Genetec: genetec_developer_suffix, server_id, return_url
- Clips: clips_token, destination_account_number
- YourSix: yoursix_site_id, yoursix_site_name
- [[ajax-components|Ajax]]: hub_name, hub_id

**Deployment & versioning (20+ fields):**
deployment_phase, connector_version FK, ecs_task_id, ecs_memory, ecs_cpu, ecs_cluster, ecs_nat, ecs_nat_instance, ecs_review_cpu, ecs_review_memory, eks_cluster, settings_deployment, settings_deployed, deployed_date, last_reboot_time, connector_deployment_id, association_id, new_relic_muting_rule_id, plus incoming image_tag_override_expires_at + pre_custom_deployment_phase

**Motion & signaling (10+ fields):**
use_motion, use_motion_envera, motion_choices, motion_interval, tcp_port, http_port, smtp_port, smtp_auth_port, read_filename, read_filename_expression

**Logging & retention (8 fields):**
log, log_group, demo, store_local, store_local_directory, store_samples_local, store_samples_local_directory, fps_and_processing_sample_period, record_motion_percentage, ttl_time, low_confidence_max (and related)

**Monitoring & health (7 fields + related CustomerMonitoring inline):**
connector_monitoring, cpu, memory, disable_alarms_on_stop, topic_arn, health_monitoring_email, video_loss_email

**AutoPatrol / Immix / [[sentinel-components|Sentinel]] (6 fields):**
immix_site_id, sentinel_site_id, endpoint_stage, queue_stage (recently moved here per `51e494d2`), group FK, tenant_id

**VLM filtering (2 fields):**
vlm_enabled, vlm_sample_rate (AUTO-551 addition)

**Scheduling & lifecycle (7 fields):**
schedule (text reference only), timezone, run_time, current_schedule_override_start, current_schedule_override_end, active, __original_active (dirty-tracking sentinel)

**Soft-delete & audit (3 fields + signal infrastructure):**
is_deleted, deleted_date, history (HistoricalRecords)

**US Monitoring (1 field):**
us_monitoring_cid

**Network/VPN (2 fields):**
vpn, wireguard FK

## Method Inventory: 8 Functional Families

**Save orchestration (1 method, 60+ lines):**
- `save()` at line 906 — IS_NEW branch recursively calls self.save() after setting customer_id; else branch orchestrates delete_zombies + propagate_changes_to_cameras + handle_schedule_changes + handle_chm_only + healthcheck.handle_healthcheck_cronjob
- Dirty-tracking: __original_active, __original_deployment_phase, __original_container_name, __original_server_ip, __original_motion_choices

**Deployment lifecycle (4 methods, 40+ lines):**
- `get_image_tag()` at 1833 — phase-gated on CUSTOM; load-bearing for §29
- `delete_deployment()` at 990 — makes HTTP POST to EKS ingress (violates model purity), handles phase-to-stage mapping (PROD→prod, DEV→dev, REARCH→rearch, REARCHDEV→rearchdev, STAGE→staging)
- `set_deployed()`, `set_undeployed()`

**Motion configuration & rules (2 methods, 40 lines):**
- `configure_motion()` at 822 — validates SMTP motion vs. integration.is_smtp, applies motion_interval floor/reset rules
- `set_nat_option()` at 894 — validates mutual exclusivity of ecs_nat + ecs_nat_instance

**Schedule queries (6+ methods, ~200 lines total):**
- `get_current_schedule()` at 1135 — 42 lines, override + weekday + flex branching, try/except swallows exceptions
- `get_timing()` at 1324 — state machine: always_on / has_pre_start / is_running branches
- `find_next_start_datetime()` at 1290 — 7-day loop, midnight-prestart special case
- `has_override_today()` at 1350
- `can_arm()` at 1538 — ONE_DAY window, manual_stop > manual_start logic
- `can_disarm()` at 1572 — mirrors can_arm logic
- Properties: `timing`, `current_schedule`, `next_schedule`, `has_flex_schedule` (at 1620, reads on model directly from customer_view.py)

**Status mutation (3 methods, 40 lines):**
- `set_arming_disarming_status()` at 1626 — mutates CustomerStatus, records timestamps + manual action flags
- `reset_manual_actions()`
- `trigger_status_update()`

**Settings export & integration (7+ methods, 200+ lines):**
- `get_settings()` at 1991 — 43 lines orchestrating _get_motion_settings + _get_integration_settings + _get_admin_feature_settings + _get_camera_status_settings + _get_additional_settings; builds large nested config dict for connector
- `get_monitoring_settings()` at 2036 — special-cases heartbeat + no_motion_email, traverses customer_monitoring.all()
- `_get_motion_settings()` — splits to _get_container_motion_settings() + _get_vm_motion_settings() depending on is_container
- `_get_integration_settings()` — builds 60-field integration config blob keyed by integration_type

**Status auto-create & queries (3+ methods, 50 lines):**
- `get_status()` — auto-creates if missing, **has critical deduplication logic at 2164-2171** that callers rely on
- `get_is_arming()` at 1474, `get_is_disarming()` at 1502 — 10-minute windows on last_arm_time / last_disarm_time

**Identity helpers (3 methods, 20 lines):**
- `make_customer_id()` at 778 — builds connector-id with locale/stage prefix
- `configure_camera_status()` at 790 — bulk-adds default alarm status to cameras
- `connector_id` property at 1386, `container_name` property at 1753

## Critical Boundary Violations

**HTTP from model** — `delete_deployment()` at customer_model.py:1015-1019 posts to {INGRESS_URL}/connector/deploy/delete — model violates its boundary by talking to the network. This is supposed to be orchestrated by a service layer.

**Global event bus** — model emits site_onboarded / site_restored / site_deleted via event_library.py:43 AdminEventLibrary.send_event(). Couples model to event infrastructure.

**Global heartbeats singleton** — heartbeats.py:31 called from save() at 947 + trigger_status_update at 1060. Model depends on global state.

**ScheduleProcessor threaded through save()** — request parameter forked to handle_schedule_changes + handle_chm_only for connector messaging. Model receives HTTP request context, violating layer boundaries.

## Logic in the Wrong File (customer_view.py)

**custom_deployment_validation (1245-1255)** — duplicates get_image_tag() logic; should call the model instead.

**duplicate_site action (501-527)** — deep-copies fields/monitoring/servers/admin_features; should be Customer.duplicate() classmethod.

**update_cluster_*_action (663-696)** — computes ecs_cluster from group ancestry; should be Customer.get_ecs_cluster().

**get_queryset annotations** — CustomerStatus runtime fields (bandwidth_usage, motion_percentage, last_alert_time) via Subquery — data-warehouse pattern in admin, belongs on CustomerStatus.get_latest() or a view model.

**customer_menu.py nav layer** — reaches into customer.integration.is_autopatrol — business logic leaks into navigation.

## Candidate Split Seams (ranked by payoff/effort, all included — parent picks)

**A. Deployment configuration model** (20+ fields, load-bearing for §29 + AI-184)
- Scope: deployment_phase, connector_version FK, ECS sizing (ecs_*), settings_deployed, deployed_date, new_relic_muting_rule_id, plus incoming image_tag_override_expires_at + pre_custom_deployment_phase
- Methods: get_image_tag(), set_deployed(), set_undeployed(), delete_deployment()
- Payoff: HIGH — §29 custom-branch, AI-184 Sensitivity FKs, recent regressions all cluster here. Unblocks independent iteration on deployment lifecycle without touching identity/integrations.
- Risk: Queries that JOIN on Customer.deployment_phase; FK migration (plan: Customer.deployment_config_id FK); settings_export needs to traverse relation. Highest-leverage first cut.

**B. Motion & signaling configuration model** (10+ fields + 2 methods)
- Scope: use_motion, use_motion_envera, motion_choices, motion_interval, tcp_port, http_port, smtp_port, smtp_auth_port, read_filename, read_filename_expression
- Methods: configure_motion(), get_external_ports(), get_internal_ports(), _get_container_motion_settings(), _get_vm_motion_settings()
- Payoff: MEDIUM — clean single-vendor boundary, used by motion subsystem only. Safe to extract.
- Risk: form widget exclusions in customer_form.py; settings export needs to traverse.

**C. Integration-specific configuration** (60+ nullable fields, ~90% per-row unused)
- Scope: The 12 vendor-specific blocks (Milestone, OpenEye, Star4Live, Eagle Eye, [[hikcentral-components|Hikcentral]], NX, Stages, Genetec, Clips, YourSix, [[ajax-components|Ajax]], Enviara)
- Pattern: Create discrete sub-models keyed off integration_type; migrate fields to IntegrationConfig(integration_type FK, config_json or per-vendor models)
- Payoff: VERY HIGH — biggest LOC reduction, schema clarity, per-vendor testability. But riskiest.
- Risk: Every integration onboarding workflow + form rendering + customer_view's _get_integration_settings() logic needs rework. Migration is complex (unpack vendor fields → repack into new tables/JSONField).

**D. Lifecycle/state-machine service layer** (no schema change, all behavioral)
- Scope: save() orchestration, dirty-tracking (__original_*), soft_delete_logic, delete_zombies, propagate_changes_to_cameras, handle_schedule_changes, handle_chm_only, healthcheck orchestration
- Pattern: Extract to CustomerLifecycleService; save() becomes thin wrapper; __original_* attrs become DirtyTracker instance; side-effect fan-out becomes explicit service methods
- Payoff: HIGH — kills recursive save() call, eliminates dirty-tracking sentinel attrs, makes save-time orchestration testable in isolation. No schema change = low migration risk.
- Risk: ScheduleProcessor + healthcheck + event bus still need to receive request context; need clean dependency-injection pattern so model stays pure. Signal receivers still coupled to old save() signature.

**E. Status & monitoring service** (3+ methods, 50 lines)
- Scope: get_status() (with deduplication logic), get_is_arming(), get_is_disarming(), can_arm(), can_disarm(), set_arming_disarming_status(), connector_monitoring config, CPU/memory toggles
- Methods: Move to CustomerStatusService; get_status() deduplication logic becomes the heart of it
- Payoff: MEDIUM — separates status-state-machine from configuration. Clean boundary.
- Risk: **get_status() deduplication logic at 2164-2171 is relied on by external callers**; need to preserve guarantees. property access patterns from admin views (is_arming, is_disarming) still read on model; might need proxy properties.

**F. Scheduling query service** (6+ methods, 200 lines)
- Scope: get_current_schedule(), get_timing(), find_next_start_datetime(), has_override_today(), list_active_flex_schedules(), list_regular_schedules(), has_flex_schedule property, timezone-dependent cached_property calculations
- Methods: Move to ScheduleQueryService; timezone tz-aware queries become its responsibility
- Payoff: MEDIUM-HIGH — removes timezone-dependent query complexity from model. Schedule state-machine isolated from deployment/motion logic.
- Risk: customer_view.py has_flex_schedule reads on the model directly; cached_property lru pattern needs to move to service. Flex schedule deduplication at line 1303-1305 stays correct.

## Cross-File Logic Duplication

| Logic | customer_model.py | customer_view.py | Recommendation |
|-------|-------------------|------------------|---|
| custom-deployment validation (image_tag + phase gate) | get_image_tag() at 1833 | custom_deployment_validation() at 1245 | consolidate to model; view calls it |
| cluster routing (group ancestry) | (missing) | update_cluster_*_action() at 663-696 | extract to Customer.get_ecs_cluster_from_group() |
| site duplication | (missing) | duplicate_site() at 501-527 | make it Customer.duplicate() classmethod |
| runtime status fields | (calls get_status) | annotates via Subquery in get_queryset() | move annotation to CustomerStatus.get_latest() |

## Pre-Existing Context: Regression Signals

- **`f1ad8fcb`** — fix custom-tag regression when deployment_phase flips to PROD (March 2026); direct consequence of deployment config being scattered across the model
- **`51e494d2`** — refactor moved endpoint_stage + queue_stage FROM AutoPatrolSchedule onto Customer (consolidation in the wrong direction; should have stayed isolated)
- **AUTO-551 chain** — 5 commits adding vlm_enabled + vlm_sample_rate per-camera flags; model-side fields added without decomposition
- **`b56c0343`** — simple-history support for soft-deleted Customer; audit infrastructure now fully coupled to model

## Open Questions

1. **Which split seam to pilot first?** Seam A (deployment config) is highest-leverage for near-term blockers (§29, AI-184), but Seams D/E/F (service layers) are lower-risk stepping stones that don't require migration. Recommend: start with D (lifecycle service), then unblock A once pattern is established.

2. **Is there an existing [[actuate_admin]] refactor ADR template to follow?** Check if BACK-604 Django upgrade or BACK-623 [[database-performance|database performance]] work captured refactoring patterns.

3. **Do we coordinate with v8 intruder's AI-184 Sensitivity FK addition, or land it before?** If Sensitivity.customer FK lands before we split deployment config, the migration becomes harder. Suggest: block AI-184 on §29 completion, OR land AI-184 with the FK pointing at the old Customer model, then refactor after v8 merge to reroute it through the new relation.

4. **Should integration-specific fields migrate to a JSONField (IntegrationConfig.config_json) or discrete sub-models per vendor?** JSONField is faster to ship but less queryable; sub-models are cleaner long-term. Recommend JSONField for Phase 1 if vendor-specific queries are rare.

## Related

- **ENG-247** — Research ticket: "move away from raw SQL access to postgres in non-admin contexts" (Security epic ENG-4, due 2026-05-22). This dissection feeds the model-side inventory that ticket needs: what's exposed today, what should sit behind an API surface, what split seams ease the transition.
- [[mark-todos#29-internal-test-deploy-lane--custom-branch-wiring-via-admin-api]] — the §29 workstream that exposed deployment-config scattering; worked example of the ENG-247 pattern
- [[2026-05-12_internal-test-deploy-lane]] — §29 design surface
- [[2026-05-13_v8-release-postgres-context]] — sibling synthesis; AI-184 Sensitivity FK will point at Customer
- [[admin-api/_summary]] — parent topic; documents current focus on AutoPatrol dev settings + [[database-performance|database performance]]
- [[2026-04-30_autopatrol-state-audit.md]] — related investigation that uncovered lead_implies_dev heuristic on Customer model
