---
title: "Feature Request: Ad-Hoc Connector Pod Redeploy via API"
type: concept
topic: product-roadmap
tags: [feature-request, connector, admin-api, devops, backlog, autopatrol]
status: backlog
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
incoming:
  - topics/autopatrol/notes/concepts/2026-04-23_cleanup-rollout-day.md
  - topics/autopatrol/notes/entities/autopatrol-cleanup-lambda.md
incoming_updated: 2026-05-01
---

# Feature Request — Ad-Hoc Connector Pod Redeploy via API

## Ask

An API endpoint (admin-side) that triggers a targeted redeploy of connector pods:
- **Per-site** (specific `deployment_id`)
- **Per-integration** (all AutoPatrol pods, all VCH pods, etc.)
- **Per-config-change** (redeploy all pods that need the latest env var / settings.json)
- **Fleet-wide** (emergency / new feature rollout)

Possibly paired with a dry-run mode that lists affected pods without doing the redeploy.

## Motivating context

Surfaced 2026-04-23 during the AutoPatrol stale-schedule cleanup rollout ([[2026-04-17_stale-schedule-cleanup-design]]). Step F — "opt in prod connector pods to emit cleanup signals to SQS" — requires setting `AUTOPATROL_EMIT_CLEANUP_SIGNALS=true` on prod pods. Today:

- Prod pods are per-site CronJobs dynamically spawned from `connector_deployer` into the `Connector-EKS` cluster
- Each pod's env and `settings.json` are baked at spawn time
- Changing an env var / setting requires the pod to be **redeployed** to pick it up
- There's no lightweight API to do a targeted redeploy — you either wait for natural reconciliation or do it one-by-one through admin UI actions

This has been a recurring pain. Mark (2026-04-23): *"I have been seeing a need for such a 'ad-hoc deployment via api' feature for a while now as well."*

## Why it's worth building

1. **Phased feature rollout**: turning on a new feature gated by env/settings without waiting days for natural reconciliation
2. **Config-change propagation**: fleet-wide config update that needs to actually hit pods in a bounded time
3. **Emergency kill-switch re-asserting**: if an ENV-var kill-switch needs to propagate fast (incident mitigation)
4. **Ops hygiene**: today "I need to redeploy site X to get the new setting live" is a fiddly manual process
5. **Canary rollouts**: redeploy 5%, watch, redeploy another 20%, etc. — currently blocked by lack of granular control

## Approach sketch (not a plan yet)

Candidates for where it lives:
- **Admin API** — new endpoint like `POST /api/deployments/redeploy` with body `{scope: "site|integration|config|fleet", filter: {...}, dry_run: bool}`
- **Claude Code skill** — `/connector-redeploy` that wraps the above
- **connector_deployer gRPC** — if the deployer already exposes an RPC, extend it

Bookkeeping needed:
- Audit trail (who/when/what)
- Rate limiting (don't redeploy the fleet by accident)
- RBAC (only admins can trigger)
- Dry-run mode mandatory before full fleet actions

Related to:
- [[autopatrol-onboarder]] — which uses cron to reconcile new customer sites, but doesn't handle config changes
- [[connector-library-deployment-lifecycle]] — existing multi-repo deployment pattern
- [[2026-04-23_release-acceptance-criteria]] — config-surface drift rule (§5) — an ad-hoc redeploy API is the forcing function to close drift windows

## Status

- [ ] Scope as a proper initiative (interview, plan, decide: admin-API vs deployer-RPC)
- [ ] Jira ticket
- [ ] Not currently blocking any workstream; just recurring pain

## Related

- [[mark-todos]] §3 (autopatrol cleanup rollout) — Step F blocked-ish on this
- [[connector-library-deployment-lifecycle]]
- [[core-repo-suite]] — `connector_deployer` is where pod spawning lives
