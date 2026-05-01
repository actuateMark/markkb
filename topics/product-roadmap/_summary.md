---
title: Product Roadmap & Initiatives
type: summary
topic: product-roadmap
tags: [roadmap, product, initiatives, revenue]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/PR/overview"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Product Roadmap & Initiatives

## Revenue Drivers

- **VCH / AutoPatrol via Immix:** ~$800K in 12 months (current primary)
- **Morphean / VIDEOR:** 30 countries, 170+ resellers (one integration = many customers)
- **[[watchman-repo|Watchman]]:** New market category (direct B2B to 4-30 camera businesses)

## Active Initiatives (H1.x)

| Initiative | Project | Status | Key Metric |
|-----------|---------|--------|------------|
| [[camera-health-monitoring/_summary|Camera Health Monitoring (H1.1)]] (H1.1) | CS3 | Maintenance mode | Launched, scene change differentiator |
| [[autopatrol/_summary|AutoPatrol (H1.2)]] (H1.2) | AUTO | Active (50+ issues) | Flex IZ dominant, VLM next wave |
| [[alerts-improvements/_summary|Alerts Improvements (H1.3)]] (H1.3) | AIM | Stalled (25/29 unassigned) | Low staffing |
| [[settings-automation/_summary|Settings Automation (H1.4)]] (H1.4) | SA | Planning (VLM MVP defining) | PPF active, recommender planned |

## Major Product Tracks

| Product | Status | Key Facts |
|---------|--------|-----------|
| [[watchman/_summary|Actuate Watchman]] | ASAP priority | AI-powered virtual security operator, multi-agent, 10-20 beta sites |
| [[external-api/_summary|External API Initiative]] | In progress | 6 workstreams (detection, scheduling, image ingestion, arm/disarm) |
| Fire Detection | In progress | Standalone/add-on. [[laura-reno|Laura Reno]] leading launch plan. |
| Line Crossing | Near-GA | Beta complete (86-98% alert reduction). Separating from intruder (PROD-116). |
| Loitering | Rework draft | [[botsort-tracking|BoTSORT tracking]] improvement completed |
| Actuate Secure / On-Prem | Phase 4 (RMS) | WireGuard VPN, Teltonika router onboarding |
| EU Model Development | Active | Generalist model deployed; bespoke continuing |
| [[integrations/morphean/_summary|Morphean]] | Draft | Cloud-to-cloud + edge hardware tracks |

## Upcoming Product Work

- **PROD-272** -- VLM Version 2.0 (new supervisor models + linker updates)
- **PROD-98** -- Weapon YOLOv8 deployment
- **PROD-267** -- Automatic recorded footage pulling
- **PROD-269** -- Sliced detections support
- **PROD-270** -- High-resolution image performance
- **PROD-239** -- [[watchman-repo|Watchman]] mobile app shell (iOS + Android)

## Jira Reorganization (CAJP)

Proposal to consolidate from **39 Jira projects to 6 team-based projects** ([[jacob-weiss|Jacob Weiss]]):
- Engineering, AI, Product, Data Science, + 2 TBD
- Capacity bucketing across 5 work streams
- GitHub + Jira + Slack integration
- 6-week rollout plan (draft status)

## Key Risks (April 2026)

1. **4 Highest-priority unowned ENG tickets** (schedule race condition, EKS upgrade, VPA, thundering herd)
2. **EBUS v5 API still "To Do"** on ENG side -- [[mark-barbera|Mark Barbera]]'s review queue must clear first
3. **[[database-performance|Database performance]]** -- recursive CTE causing Aurora CPU spikes (BT-926 / BACK-623)
4. **AIM initiative stalled** -- 25/29 issues unassigned
5. **Multiple integration failures in support queue** ([[evalink-components|Evalink]], Patriot, DW, Immix)
