---
title: "Immix marks `end_patrol(Finished)` as Failed when no raise_patrol_alert occurred"
type: synthesis
topic: autopatrol
tags: [autopatrol, immix, integration, regression, bug-report-draft]
created: 2026-05-22
updated: 2026-05-22
author: mark
incoming:
  - topics/personal-notes/notes/daily/2026-05-22.md
incoming_updated: 2026-05-27
---

# Immix marks `end_patrol(Finished)` as Failed when no raise occurred

## Problem statement

Per the Actuate-side AutoPatrol design (post vms-connector PR #1709 + autopatrol-server PR #28, both 2026-05-21), `raise_patrol_alert` is only called for real detections / model-driven CHM issues. Healthcheck-style patrols that produce no detections should reach `Finished` status via the connector's `update_patrol(Finished)` call without any prior `raise`.

**Observed behavior**: Immix's response to `PUT /Patrols/{id}` with body `{"patrolStatus":"Finished"}` returns `patrolStatus="Failed"` in the response body whenever no `raise_patrol_alert` was called during the patrol's Started lifetime. This appears to be the rule documented in vms-connector autopatrol code as: *"Without at least one raise_patrol_alert call, Immix's API returns patrolStatus=Failed in the response to update_patrol(Finished), regardless of whether the patrol actually succeeded on our side."*

The autopatrol-server's prior PATROL_SUMMARY-raise hack (PR #28's deleted code) existed solely to satisfy this Immix rule. The disable plan removed the hack on the assumption that the rule was either lifted or wouldn't matter; in practice it's still active and produces customer-visible `Failed` patrol status.

## Evidence

### Timeline — schedule 55a93d4b (tenant `dfda7621-f1d3-4469-b6df-dea988fd81a9`, site 10012 "McCall"), patrol `ee865b11-5971-4f7c-b457-08deb106c9cf` at 2026-05-22 19:15 UTC

```
19:15:00.949  connector  PUT /Patrols/ee865b11        body: {"patrolStatus":"Started"}
              ← Immix HTTP 200 — response body: {"patrolStatus":"Started",...}

19:15:00-34   connector  (33 s camera run, 5 cameras, NO raise_patrol_alert calls)

19:15:34.356  connector  PUT /Patrols/ee865b11        body: {"patrolStatus":"Finished"}
              ← Immix HTTP 200 — response body: {"patrolStatus":"Failed",...}     ← THIS IS THE BUG
              connector logs `end_patrol succeeded on attempt 1/3` (succeeded HTTP-wise; body returned Failed)

19:15:36+     autopatrol-server  POST /Patrols/ee865b11/raise
              ← Immix HTTP 400 — body: "Patrol id ee865b11 with status Failed is not in the expected status of Started"
              (this is autopatrol-server's pre-disable code firing — to be removed by PR #28, will not be relevant post-deploy)
```

### Tenant + schedule context

| Field | Value |
|---|---|
| Tenant ID | `dfda7621-f1d3-4469-b6df-dea988fd81a9` |
| Tenant name | Immix.Hedrick |
| Schedule ID | `55a93d4b-feee-4920-3669-08deb1143883` |
| Schedule title | test fire |
| Patrol type | AutoPatrol |
| Cron | `*/15 * * * *` (every 15 min) |
| Tier | 0 (default / standard) |

Reproduces on every cron tick. Multiple patrol IDs observed transitioning Started → Failed identically: `64ccd6bb` (19:00), `ee865b11` (19:15), `459be9e6` (19:30), `f1b6b270` (20:00 onward).

## Questions for Immix

1. **Is the "Finished requires ≥ 1 raise" rule intentional and still in effect?** If yes, was that the case historically and we built around it with a per-camera dummy alert workaround?
2. **Is there an alternative API path** for healthcheck-style patrols that legitimately produce no detections (e.g. a `/healthcheck-complete` endpoint, a `patrolType: Healthcheck` discriminator on the schedule, or a tenant-level flag) that allows `Finished` without a raise?
3. **Has this rule changed recently?** Internal design discussions assumed it would not apply post-transition; observed behavior contradicts that assumption.
4. If the rule is intentional and there's no alternative path, what's the recommended way to mark a no-detection patrol as successfully completed without producing a customer-visible alert from the workaround raise?

## Internal state on our side

- vms-connector PR #1709 (`fa29ed566`, merged 2026-05-21): connector now calls `update_patrol(Finished)` itself before SQS handoff, replacing autopatrol-server's previous responsibility. Deployed to 91%+ of fleet on `arm_connector_rearch:latest` as of 2026-05-22 20:00 UTC.
- autopatrol-server PR #28 (`641e4eb`, merged 2026-05-21): disables the per-camera `raise_patrol_alert(PATROL_SUMMARY)` loop + keepalives + server-side `end_patrol`. **Deployed to prod us-west-2 at 2026-05-22 20:11:28 UTC** as version `0.1.26` ([[kubernetes-deployments]] PR #392).
- Pre-disable behavior: autopatrol-server's PATROL_SUMMARY raise loop happened to satisfy Immix's "needs at least one raise" rule, producing `Finished` correctly but generating one customer-visible HEALTHCHECK-tier alert per camera per patrol. Business decision to remove this.
- Post-disable behavior (current state, ~2026-05-22 20:11 UTC onward): connector calls `Finished`, no raises occur, Immix marks patrol `Failed`. Customer sees "Timeout/Period Lapsed" or equivalent.

## Cross-references

- [[2026-05-22_autopatrol-onboarding-silent-deploy-failure]] — original incident where this gap was discovered
- vms-connector PR #1709 (cross-repo Part 1)
- autopatrol-server PR #28 (cross-repo Part 2)
- [[kubernetes-deployments]] PR #392 (deploy of 0.1.26)
