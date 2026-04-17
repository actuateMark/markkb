---
type: concept
author: kb-bot
created: 2026-04-14
updated: 2026-04-14
tags: [rollout, deployment, rollback, new-relic, operations, runbook]
---

# Rollout Process

The standard operating procedure for deploying changes across the Actuate site fleet. Designed for safety at scale -- the fleet can include thousands of sites, so changes are staggered with monitoring at every step.

## Rollout

A rollout script on Admin applies changes in controlled batches:

1. **Filter** the site list to exclude anything that should not receive the change. This filtering must complete before any writes happen -- `.save()` is not called until all filters pass.
2. **Check reboot requirements** -- determine if running sites need a restart to pick up changes.
3. **Stagger deployment** in batches of 100-500 sites with a wait period between batches. This allows monitoring to detect issues before the blast radius expands.

## Rollback

The rollback script is structurally symmetrical to the rollout but differs in two critical ways:

- **Looser filter** -- when reverting a bad change, it is acceptable to be less precise about which sites to touch.
- **No stagger, no timer** -- rollback happens as fast as possible to all affected sites simultaneously. Speed of recovery outweighs the controlled-pace benefit.

## Monitoring

A dedicated New Relic dashboard is created for each rollout with queries and graphs tracking site health metrics. This dashboard is the primary tool for validating the rollout in real time.

## Human Process

The rollout process is explicitly not fully automated. It requires:

1. Signoff from team members on the rollout script, rollback script, and monitoring dashboard.
2. A scheduled review call with at least two other team members to review scripts and "push the button" together.
3. Active monitoring of the dashboard after execution, with spot checks on individual sites.
4. Spot rollbacks for any sites showing issues, without waiting for a full rollback decision.

## Design Philosophy

The asymmetry between rollout (slow, staggered, strict filters) and rollback (fast, unstaggered, loose filters) reflects the operational reality: deploying a change requires confidence at each step, but reverting a bad change requires speed above all else.

## See Also

- [[worklog-rollout-process]] -- original runbook notes
- [[multi-region-deployment]] -- infrastructure context for where rollouts target
