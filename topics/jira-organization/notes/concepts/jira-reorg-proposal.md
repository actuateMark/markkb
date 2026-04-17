---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [jira, process, reorganization, tooling]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/CAJP/pages/426213378"
---

# Jira Reorganization Proposal

A draft proposal authored by [[jacob-weiss]] in March 2026 to consolidate Actuate's Jira instance from **39 projects down to 6 team-based projects**. The proposal is documented in the CAJP Confluence space.

## The Problem

Actuate's Jira instance has grown organically to 39 projects serving only 24 active users. The majority of these projects are dead, duplicated, or organized around time-bound initiatives (e.g., H1.1 CHM, H1.2 AutoPatrol, H1.3 Alerts Improvements) that either launched or stalled. As of April 2026, only about 8-10 projects see regular activity; the rest create noise, fragment search results, and make cross-team planning difficult.

Current visible projects include ENG, ED, AI, AUTO, CS3, SA, AIM, PROD, BT, BACK, MISS, UI, MAH, QETD, ERROR0, EMISC, DN, NED, ROB, plus dead template projects like SSP and LEARNJIRA. The initiative-based naming (H1.1, H1.2, etc.) ties project identity to a specific planning horizon, which means new projects get created each cycle while old ones linger.

## The Proposal

Consolidate to **6 team-based projects**: Engineering, AI, Product, Data Science, plus 2 TBD. The key design principles are:

### Capacity Bucketing
Instead of creating a new project per initiative, work is bucketed into **5 capacity streams** within each team project. This allows leadership to see how engineering time is distributed across maintenance, new features, integrations, infrastructure, and support without fragmenting the issue graph.

### GitHub + Jira + Slack Integration
The proposal calls for tight toolchain integration:
- **GitHub to Jira:** Automated PR-to-ticket transitions. When a PR referencing a ticket is merged, the ticket moves to "Done" or "In Review" automatically.
- **Jira to Slack:** Sprint notifications, assignment alerts, and blocker escalation posted to team channels.
- **Slack to Jira:** Quick-create tickets from Slack threads for support requests and bug reports.

### Long-Lived Epics
Replace per-sprint epics with long-lived epics that map to product initiatives (e.g., AutoPatrol, External API, Morphean). This preserves initiative tracking without requiring separate projects.

### Rollout Plan
A 6-week phased rollout: (1) create new projects and configure workflows, (2) migrate active tickets, (3) archive dead projects, (4) train team, (5) enable integrations, (6) retrospective and adjustment.

## Current Status

The proposal is in **draft status** as of April 2026. It has not yet been approved or scheduled for implementation.

## See Also

- [[jacob-weiss]] -- proposal author
- [[confluence-spaces-map]] -- the Confluence side of tooling organization
