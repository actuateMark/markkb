---
title: "Source: Rollout Runbook"
type: source
topic: actuate-platform
tags: [worklog, rollout, deployment, rollback, new-relic, runbook]
ingested: 2026-04-14
author: kb-bot
---

# Rollout Runbook

Worklog notes defining the standard operating procedure for rolling out changes across the Actuate site fleet. This is a staggered deployment process with monitoring and rollback provisions.

## Rollout Script (Admin)

1. **Filter** -- exclude sites that should not receive the changes.
2. **Defer writes** -- do not call `.save()` until all filters are validated.
3. **Check for reboot needs** -- determine if running sites need a restart to pick up changes.
4. **Stagger deployment** -- deploy in batches of 100-500 sites, with a timer/pause between batches to allow monitoring.

## Rollback Script

- Symmetrical to the rollout script but with a **looser filter** (acceptable to be less precise when reverting).
- **No staggering** -- rollback immediately to all affected sites, no timer between batches.

## Monitoring Dashboard

Create a New Relic dashboard with queries and graphs to monitor for issues in running sites. Example dashboards referenced:
- `https://onenr.io/0nQxrGVodRV`
- `https://onenr.io/08wor47nYQx`
- `https://onenr.io/0nQxrGVmaRV`

## Process Checklist

1. Get signoff on rollout script, rollback script, and dashboard from team members.
2. Schedule a review call with at least two other team members for script review and "pushing the button."
3. After running the script, actively monitor the dashboard.
4. Perform spot checks on individual sites.
5. Execute spot rollbacks if any issues are detected.

## Key Design Decisions

- Writes are deferred until filtering is complete to prevent partial/incorrect rollouts.
- Rollbacks are intentionally fast (no stagger) because speed matters when reverting a bad change.
- Human oversight is required at every stage -- no fully automated rollout.

## See Also

- [[rollout-process]] -- synthesized concept note
