---
title: Jira Organization
type: summary
topic: jira-organization
tags: [jira, projects, reorganization, process, autopatrol]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/CAJP/pages/426213378"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Jira Organization

## Current State: 21 Visible Projects

| Key | Name | Purpose | Active? |
|-----|------|---------|---------|
| **ENG** | Engineering | Core engineering, external API, infrastructure | Yes |
| **ED** | EU Deployment | EU work: EBUS, Monitex, action logs, [[alert-muting|alert muting]] | Yes |
| **AI** | AI Team | ML model development and evaluation | Yes |
| **AUTO** | H1.2 - Autopatrol | AutoPatrol product | Yes (50+ issues) |
| **CS3** | H1.1 - CHM | Camera Health Monitoring | Maintenance |
| **SA** | H1.4 Settings Automation | Settings automation, VLM FP | Planning |
| **AIM** | H1.3 Alerts Improvements | Alerts pipeline | Stalled |
| **PROD** | Product Initiatives | [[watchman-repo|Watchman]], cost estimation, VLM | Yes |
| **BT** | Support Tracker | Customer support tickets | Yes |
| **BACK** | Product Backlog | Feature requests, tech debt | Yes |
| **MISS** | Miss Tracker | Missed detection tracking | Low activity |
| **UI** | UI Improvements | Frontend work | Low activity |
| **MAH** | Multi-AZ Hosting | AWS infra | Low activity |
| **QETD** | QA Engineering & Tech Debt | QA and tech debt | Low activity |
| **ERROR0** | Error Logs | Error tracking | Low activity |
| **EMISC** | ENG-Miscellaneous | Misc engineering | Low activity |
| **DN** | DMP-NLSS | DMP/NLSS integration | Low activity |
| **NED** | Network Expansion Device | Network devices | Low activity |
| **ROB** | RoboMladen | Experimental | Low activity |
| **SSP** | Sample Scrum Project | Template | Dead |
| **LEARNJIRA** | Learn Jira | Onboarding | Dead |

## Reorganization Proposal (Draft, March 2026)

**Author:** [[jacob-weiss|Jacob Weiss]]
**Problem:** 39 projects for 24 active users. Most dead, duplicated, or organized around time-bound initiatives.

**Proposed:** Consolidate to **6 team-based projects** with:
- Capacity bucketing across 5 work streams
- Tight GitHub + Jira + Slack integration
- Automated PR -> ticket transitions
- Long-lived epics (not per-sprint)
- 6-week rollout plan

**Proposed projects:** Engineering, AI, Product, Data Science, + 2 TBD

## Confluence Spaces (by activity)

| Space | Pages | Purpose |
|-------|-------|---------|
| kb | 200 | Primary engineering knowledge base |
| EDOCS | 78 | Auto-synced GitHub docs (created Apr 9, 2026) |
| DS | 33 | Data Science models, evaluation, methodology |
| PM | 20 | Product Management ([[watchman-repo|Watchman]], infrastructure) |
| Integratio | 11 | Integration partner docs (EBUS, Morphean, [[evalink-components|Evalink]]) |
| CAJP | 10 | Jira/Confluence process |
| PR | 4 | Product Roadmap |
| Others | Various | AO1 (Actuate Secure), FD (Fire), IA (AutoPatrol), SAS (Settings), etc. |
