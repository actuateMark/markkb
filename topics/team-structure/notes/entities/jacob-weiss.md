---
type: entity
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [person, engineering, leadership, infrastructure, security]
---

# Jacob Weiss

Jacob Weiss is the **Engineering Lead** at Actuate, responsible for infrastructure, security, and engineering process. He is also the author of the [[jira-reorg-proposal]], a significant organizational initiative to consolidate Jira from 39 projects down to 6.

## Leadership Role

As engineering lead, Jacob's responsibilities span technical architecture, security posture, and team process. Unlike a pure people-manager role, he remains hands-on -- actively participating in support tickets (BT-921, BT-923, BT-891, BT-911) and infrastructure work. He appears in both the Leadership and Support sections of the team roster, reflecting his dual role.

## Infrastructure Focus

Jacob's infrastructure work centers on Actuate's AWS environment:

- **WireGuard VPN** -- Part of the Actuate Secure / On-Prem product (Phase 4, RMS). WireGuard provides secure connectivity between on-premises camera infrastructure and Actuate's cloud platform. [[aziz]] completed Phase 5A observability for WireGuard (ENG-117), indicating this is a multi-phase effort with Jacob providing architectural oversight.
- **Security posture** -- Responsible for the overall security of the platform, including network segmentation, access control, and compliance requirements (particularly relevant for the EU deployment in eu-west-1 for GDPR).
- **EKS orchestration** -- The platform runs on Amazon EKS with [[argocd|ArgoCD]] GitOps for deployment. Infrastructure decisions around multi-AZ hosting (project MAH), VPA (Vertical Pod Autoscaler), and EKS upgrades fall under Jacob's purview.

## Jira Reorganization

Jacob authored the March 2026 draft proposal to consolidate Actuate's Jira instance from **39 projects to 6 team-based projects** (see [[jira-reorg-proposal]]). The proposal addresses a real pain point: 39 projects for only 24 active users, with most projects dead, duplicated, or organized around time-bound initiatives that have ended. The proposed structure introduces capacity bucketing across 5 work streams, tight GitHub + Jira + Slack integration, and automated PR-to-ticket transitions.

## Key Risks Under His Purview

Several of the highest-priority risks in the [[active-risks]] note fall within Jacob's domain:

- **4 unowned Highest-priority ENG tickets** -- schedule race condition, EKS upgrade, VPA configuration, and thundering herd. These are infrastructure-level issues that need assignment.
- **Multi-AZ hosting** (MAH project) -- low activity but strategically important for reliability.

## See Also

- [[jira-reorg-proposal]] -- his organizational consolidation plan
- [[multi-region-deployment]] -- infrastructure he oversees
- [[active-risks]] -- unowned infrastructure tickets
