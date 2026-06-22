---
title: "Resolution: pre-endrun crashes investigation (2026-05-01)"
type: synthesis
topic: autopatrol
tags: [autopatrol, vms-connector, eagle-eye, ghost-cronjob, partial-fix, silent-failure, NameError, KeyError, TypeError, AttributeError]
jira: "CONNECTOR-164"
created: 2026-05-01
updated: 2026-05-01
author: kb-bot
incoming:
  - topics/personal-notes/notes/concepts/2026-05-01_pre-endrun-crashes-handoff.md
  - topics/personal-notes/notes/daily/2026-05-04.md
incoming_updated: 2026-05-27
---

# Resolution: pre-endrun crashes investigation

Closed-out investigation into 4 distinct pre-endrun crash modes affecting 37 autopatrol sites (plus 17 Eagle Eye sites). Only 2 of the 4 were actually autopatrol; the other 2 involved admin-side data corruption and Eagle Eye healthcheck containers. See [[2026-05-01_pre-endrun-crashes-handoff]] for the original scope.

## Scope correction: not all were autopatrol

The handoff framed all 4 as "autopatrol/VCH connector pre-endrun crashes." Investigation revealed:

| # | Exception | Sites | Fleet | Root Cause Category |
|---|-----------|-------|-------|---|
| 1 | NameError `cache_multiplier` | cid=35830 | autopatrol | Code regression in custom image |
| 2 | KeyError `YAM Slicing Microservice` | cid 44565, 41516, 27652, 40722 | chm-cronjob (data corruption) | Admin-side model misconfiguration |
| 3 | TypeError `integration doesn't exist` | cid=7493 | autopatrol (chm-cronjob) | Ghost cronjob (stale deployment) |
| 4 | AttributeError `NoneType.lower` | 17 distinct sites | Eagle Eye | Library defect + connector missing guard |

**Critical framing fix:** "chm-cronjob" container name does not mean "autopatrol customer." It's the generic CHM healthcheck cronjob. Many integration types run chm-cronjobs. Crashes #2 and #4 affected non-autopatrol sites; only #1 and #3 were actually autopatrol customers.

## Per-crash resolution

### 1. NameError cache_multiplier (cid=35830, autopatrol)

**Root cause:** Simplify refactor commit 88ceb533 dropped the local variable assignment `cache_multiplier = 2` while leaving the reference at line 51 of `autopatrol_camera.py`. Introduced ~3 weeks before discovery; regression was silent because the customer uses a custom image tag (`:s3alerts`).

**Fix:** Commit 41a88fe2 (`fix: NameError crash in AutoPatrolCamera + restore dev queue routing`) re-introduces the local. Authored Apr 15 but the push to `origin/s3alerts` + ECR rebuild didn't trigger until 2026-05-01 22:01 UTC.

**Status:** Resolved. The cid=35830 pod will pull the new `:s3alerts` image on next cronjob cycle.

**Lesson:** Merged fix ≠ deployed fix. Always verify the ECR image last-pushed timestamp matches expectations. For custom-tag images, check the registry directly rather than relying on git commit dates.

### 2. KeyError YAM Slicing Microservice (4+ sites, chm-cronjob / multi-integration)

**Root cause:** Admin-side bug wrote a non-existent AI model name (`'EKS to EKS dev YAM Slicing Microservice Intruder + vehicle'`) into customer settings rows. The connector's model lookup failed on every patrol cycle with KeyError.

**Initial fix:** Admin team regenerated settings for cid 44565, 41516, 27652, 40722.

**Discovery during investigation:** The fix was incomplete. NRQL FACET query showed 23+ distinct site IDs with the bad model name — the 4 fixed customers covered only 4 of 24+ affected sites. Post-fix timeseries showed a clear staircase: high plateau, one drop when the 4-customer fix landed, then a persistent floor of 10-98 events/30min continuing to query time. Classic partial-fix signature.

**Handoff status:** Expanded site list passed back to admin team: 45188, 40243, 43682, 43680, 34767, 32463, 19105, 39986, 43628, 45993, 38507, 38008, 38091, 37585, 38414, 37437, 12611, 35185, 38418, 37181 (plus the original 4, which were still firing post-fix).

**Lesson:** When fixing data corruption, audit the full blast radius before declaring done. One bad write to a settings table almost never affects only the customer who reported it. Pull `FACET by site_id` for the same error pattern; the timeseries staircase immediately reveals a partial fix.

### 3. TypeError integration doesn't exist (cid=7493, autopatrol)

**Surface:** Code raises `TypeError("integration doesn't exist")` at `vms-connector/connector_factories/shared/factory.py:107` when `integration_type` doesn't match any case. cid=7493 hit this ~720 times / 7d.

**Investigation:** Customer was marked inactive in admin, but the chm-cronjob was still running in k8s and hitting the factory every cycle. The code is correct; the bug is a stale cronjob that should have been torn down.

**Direct fix:** User manually deleted the cronjob: `kubectl delete cronjob connector-7493-chm-cronjob -n rearchitecture`. Symptom resolved.

**Root cause (deeper):** `actuate_admin/inframap/sites/health/healthcheck_model.py:226` — when admin marks a customer inactive, it calls `requests.delete(f"{INGRESS_URL}/connector/deploy/chm/{name}")` to tear down the cronjob. That call was wrapped in `try: ... except Exception as e: logger.warning(...)`. No response capture, no status check. A 5xx from the deployer (e.g., transient k8s API failure) was treated identically to a 200. The cronjob never actually got deleted.

**Systemic fix (PR in flight):** https://github.com/aegissystems/actuate_admin/pull/2399 (`fix/healthcheck-deploy-loud-log`, base `staging`). Captures response, calls `raise_for_status()`, switches to `logger.exception()` with full traceback, distinguishes create vs delete in the message, includes a `kubectl delete cronjob ...` cleanup hint for oncall.

**Diagnostic improvement (PR in flight):** https://github.com/aegissystems/vms-connector/pull/1665 (`fix/factory-typeerror-include-integration-type`, base `stage`). Changes error to `TypeError(f"integration doesn't exist: integration_type={integration_type!r}")` so future occurrences immediately show what value triggered the crash.

**Follow-up:** Same silent-failure pattern exists in `inframap/sites/autopatrol/autopatrol_schedule_model.py:477/509/526` for AutoPatrol schedule deploys/undeploys. Tracked as a follow-up PR after #2399 lands.

**Status:** Resolved (one-off cleanup) + systemic source has PRs in flight.

### 4. AttributeError NoneType.lower (17 Eagle Eye sites, not autopatrol)

**Affected fleet:** 17 Eagle Eye chm-cronjob healthcheck sites. Top 3 by event volume: cid 40261 (672 events), 17322 (168), 40982 (97). All 17 were 100% silent for their cameras (no Snowflake row, no Immix alert, no S3 frame).

**Crash site:** `actuate-libraries/actuate-pullers/src/actuate_pullers/url/av_url_puller.py:522` — the snapshot-mode generator expression `any(indicator in self.url.lower() for indicator in snapshot_indicators)` doesn't guard for `self.url is None`. Note: line 500 in the same file already has the guard (`bool(self.url and ...)`); line 522 was simply missed.

**Upstream call site:** `vms-connector/camera/eagle_eye/eagle_eye_healthcheck_camera.py:115` — `self._create_puller(camera, stream_url)` was being called with `stream_url=None`. Three upstream paths produce None: explicit assignment at L91 when EE V3 access token / base URL missing, `get_url_v3()` returning `Union[str, None]`, `get_url()` returning `Union[str, None]`. Importantly, `init_dummy_pullers()` at L61 already created a `DummyPuller` for every camera, so a missing stream_url should mean "keep the dummy" — not "crash the whole site."

**Connector fix (PR in flight):** https://github.com/aegissystems/vms-connector/pull/1664 (`fix/eagle-eye-skip-none-url`, base `stage`). Adds `if not stream_url: log warning + continue` guard before `_create_puller`. CI checks green; ready to merge.

**Library defense-in-depth fix (PR in flight):** https://github.com/aegissystems/actuate-libraries/pull/342 (`fix/av-url-puller-none-guard`, base `main`). Adds `bool(self.url) and` prefix matching the line 500 pattern. **Held for Monday merge** to avoid Friday-evening stable publish + connector pin bump.

**Status:** Resolved (two-PR approach) + library fix held for Monday.

## Patterns & systemic lessons

1. **"Pre-endrun crash" is too coarse.** A traceback-by-traceback slice reveals crashes at different layers (library, factory, admin-side data, integration-specific path). Don't assume common root; investigate per exception type first.

2. **Partial-fix pattern is the silent tax.** When fixing a user-reported bug, fix the class of bug, not just the reported cases. For data corruption, always `FACET by site_id` and compare the full affected set to what was fixed. Staircase timeseries (plateau → drop → new floor) immediately reveals incomplete fixes.

3. **Silent deploy failures create ghost cronjobs.** Any `try: requests.X(...) except Exception: logger.warning(...)` around a mutation is a future ghost deployment. Template for systemic fix: capture response, `raise_for_status()`, use `logger.exception()` with traceback, surface a cleanup hint to oncall. Apply uniformly to all admin deploy/undeploy paths.

4. **Merged fix ≠ deployed fix.** Custom-tag images (`arm_connector_rearch:s3alerts`) require explicit ECR rebuild, not just a git merge. Check the registry's last-pushed timestamp; don't rely on commit dates. For main-track images, CI auto-rebuilds, but verify the tag hit ECR.

5. **Lying error messages are future investigator tax.** Include the triggering value in the exception message (factory.py:107). Distinguish related-but-different actions in a single try block (admin create cronjob vs delete cronjob). Future debugging session will thank you.

6. **None-guards must be exhaustive.** When a field can be None upstream, every downstream reference needs a guard. The library had a None-guard at line 500 but missed it at line 522; the connector didn't guard for None before passing to the puller. Both need fixing.

## PRs shipped this session

- **vms-connector [#1664](https://github.com/aegissystems/vms-connector/pull/1664)** — Eagle Eye None-skip (CI green, ready to merge to stage)
- **vms-connector [#1665](https://github.com/aegissystems/vms-connector/pull/1665)** — factory.py diagnostic improvement (CI pending)
- **actuate-libraries [#342](https://github.com/aegissystems/actuate-libraries/pull/342)** — av_url_puller None guard (CI pending; held for Monday merge)
- **[[actuate_admin]] [#2399](https://github.com/aegissystems/actuate_admin/pull/2399)** — loud-log CHM cronjob deploy failures (CI pending)

## Open follow-ups

- **Monday:** merge actuate-libraries #342, then bump [[actuate-pullers]] pin in vms-connector
- **After #2399 lands:** apply same loud-log pattern to `inframap/sites/autopatrol/autopatrol_schedule_model.py:477/509/526`
- **Admin team:** 24+ sites with bad YAM Slicing model name in their settings still require fixes (expanded list above)
- **Audit:** other admin mutation paths for same `try/except Exception/logger.warning` pattern; convert all to `logger.exception` + `raise_for_status` + cleanup hint

## Cross-references

- [[2026-05-01_pre-endrun-crashes-handoff]] — original scope & diagnostic queries
- [[2026-05-01_silent-cameras-diagnosis]] — the fleet-silence investigation that surfaced these crashes
- [[autopatrol-onboarder]] — entity
- [[autopatrol-cleanup-lambda]] — sibling cleanup Lambda (overlapping ghost-cronjob semantics)
- [[2026-04-30_data-model-cascade-semantics]] — admin cascade semantics (relevant for #3)
