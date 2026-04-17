---
title: "B2B2B vs B2B Go-to-Market"
type: synthesis
topic: product-roadmap
tags: [synthesis, cross-topic, b2b2b, b2b, watchman, immix, autopatrol, go-to-market, strategy]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# B2B2B vs B2B Go-to-Market

Actuate is running two go-to-market motions simultaneously. The B2B2B channel -- selling detection through monitoring center partners like [[integrations/immix|Immix]] -- generates current revenue (~$800K/12mo via VCH/AutoPatrol). The B2B direct channel -- [[watchman]] targeting commercial businesses with 4-30 cameras -- is the growth bet. This synthesis examines the tension between these models in feature prioritization, engineering bandwidth, and infrastructure divergence.

## B2B2B: The Immix-Anchored Revenue Engine

The current business operates as a detection layer embedded in monitoring center workflows. The commercial chain is **Actuate -> Partner (Immix, Sentinel, SureView, etc.) -> End Customer**. Actuate never touches the end customer. The Immix relationship is the dominant revenue driver, with 27 alarm senders in [[actuate-alarm-senders]] delivering alerts via SMTP, HTTP, and SQS to partner consoles.

[[autopatrol]] is the flagship B2B2B product: virtual patrols running on Immix Connect, generating clips, and dispatching alerts through the `AutoPatrolAlertSender` via the Immix Connect REST API (subscription key auth, `autopatrol.immixconnect.com`). The AutoPatrol initiative has 50+ open Jira issues and is the most active by issue count. Current workstreams include flex ignore zones (Brad Murphy, Tatiana, Victoria Peccia), VLM integration (Alena Prashkovich's Phase III prompt engineering, Jessica Bae's alerting frontend), Immix bounding boxes on clips (Mark Barbera, ready to deploy), and generic patrol mode (shipped April 2026).

The B2B2B model's strength is that Actuate controls the AI but delegates the expensive human layers -- monitoring, dispatch, escalation, customer relationship -- to the partner. Its weakness is that Actuate has no direct customer relationship and limited ability to differentiate on the operator experience.

## B2B Direct: Watchman's New Market

[[watchman]] flips the model to **Actuate -> Commercial Business (direct)**. It removes the monitoring center and owns the full stack: connectivity ([[actuate-wireguard]]), AI detection ([[vms-connector]] pipeline), threat assessment (multi-agent orchestration), escalation (push + SMS + phone call with auto-escalation), and operator engagement (triage gamification, terminal-style UI). Target customers are businesses with 4-30 cameras that cannot afford live remote video monitoring ($50-150+/camera/month).

Watchman reuses significant infrastructure: the connector pipeline, 41 [[actuate-libraries]] packages, AI models, WireGuard tunnels, VLM FP filter, and AutoPatrol scheduling. But it builds three genuinely new agents (Site Supervisor, Escalation, Learning), a self-service [[onboarding-wizard]], compound cross-camera severity scoring, multi-tier escalation, and a completely new UI paradigm. The MVP targets 10-20 beta sites.

## Feature Priority Conflicts

The two motions compete for the same engineering team's attention. Specific conflicts visible in the April 2026 roadmap:

**AutoPatrol (B2B2B) demands:**
- Flex ignore zones -- multiple IZ presets per camera, full API + frontend + settings generation (AUTO-446, 500, 424, 493)
- VLM alerting frontend -- surfacing VLM assessments in the Immix workflow (AUTO-420)
- Immix bounding boxes on clips -- visual enhancement for monitoring center operators (AUTO-351)
- AP Server/MS integration -- deployment infrastructure (AUTO-449)

**Watchman (B2B) demands:**
- Multi-agent orchestration -- Site Supervisor, Patrol, Threat, Assessment, Escalation, Learning agents (PROD-147, 152, 132, 157, 172, 209)
- Self-service onboarding -- 9-step wizard with ONVIF camera discovery (F-001)
- Escalation infrastructure -- push, SMS, phone call with auto-escalation tiers
- Terminal-style UI -- agentic-first design (Brad Murphy)
- Mobile app shell -- iOS + Android (PROD-239)

**Shared dependencies where priority is ambiguous:**
- VLM FP reduction (SA-221 / PROD-2) -- both products benefit, but Watchman's two-track routing formalizes it as an architectural requirement while AutoPatrol treats it as an enhancement
- EKS upgrade 1.32 -> 1.35 (ENG-79) and VPA fixes (ENG-78) -- both products need these, but Watchman's many-small-sites model makes them urgent
- Weapon v8 deployment (PROD-98) -- benefits both channels
- [[settings-automation]] -- AutoPatrol needs it for reducing manual tuning; Watchman needs it for zero-touch onboarding

## The AIM Signal

The [[alerts-improvements]] initiative (H1.3) is the canary for bandwidth constraints. Of its 29 issues, **25 are unassigned**. AIM represents cross-cutting improvements to alert quality that benefit both go-to-market channels. Its stalled state suggests the team does not have capacity beyond the two primary product tracks. If AIM cannot get staffing, smaller-scope improvements to alert delivery, false positive reduction, and operator experience will accumulate as technical debt affecting both channels.

Similarly, 4 of the highest-priority ENG tickets remain unassigned: the schedule race condition (ENG-96), VPA over-provisioning (ENG-78), event-listener thundering herd (ENG-66), and EKS upgrade (ENG-79). These are infrastructure issues that affect both products equally but compete with feature work for engineering time.

## Infrastructure Divergence

The two models share the same AWS account, EKS clusters, model servers, DynamoDB tables, and S3 storage. But they diverge in important ways:

| Dimension | B2B2B (Current) | B2B (Watchman) |
|---|---|---|
| **Alert routing** | SQS FIFO -> partner console (SMTP/HTTP) | Multi-tier escalation (push/SMS/call) -> business owner |
| **Deployment trigger** | Admin API manual request -> [[connector-deployer]] | Self-service wizard -> automated deployment |
| **Site profile** | Large sites (50+ cameras common) | Small sites (4-30 cameras) |
| **Scaling concern** | Per-site compute (sharding cost) | Per-cluster management (many small deployments) |
| **UI integration** | Embedded in partner platforms | Own terminal-style UI |
| **Config complexity** | 150+ field [[settings-files]] per site | Inferred from site type + protection priorities |

The risk of infrastructure divergence is that shared library changes affect both products but are tested against different assumptions. A performance optimization that helps large sites (raising shard size) may not matter for Watchman's small sites. A VPA fix validated on 50-camera deployments may behave differently on 4-camera pods with lower baseline resource usage.

## Bandwidth Allocation Reality

Looking at the named team members across both tracks:

- **Brad Murphy**: AutoPatrol frontend (flex IZ, bulk updates) AND Watchman UI
- **Tatiana**: Admin API backend AND AutoPatrol flex IZ API
- **Mark Barbera**: Immix bounding boxes AND generic patrol mode AND EBUS v5 review queue
- **Jacob Weiss**: Watchman infrastructure/security AND Jira reorganization AND ENG tickets
- **Carlos Torres**: VLM FP filter (shared) AND weapon model training AND model routing
- **Laura Reno**: Watchman document owner AND VLM MVP definition AND fire detection launch

Many engineers serve both tracks. The practical effect is context-switching overhead and the risk that neither track moves as fast as its standalone priority would suggest. The Watchman PRD's "ASAP" priority designation competes directly with AutoPatrol's ~$800K revenue obligation.

## Strategic Tension

The fundamental question is sequencing. The B2B2B channel generates current revenue and has committed partner relationships (Immix's 27 alarm senders, Morphean's 30-country network). Underinvesting in it risks the revenue base. The B2B channel is the growth bet -- but Watchman's 10-20 beta site MVP target is deliberately small, designed to validate without disrupting. The tension becomes acute when shared infrastructure work (EKS upgrade, VPA fix, VLM deployment) must be prioritized: does it get done on the B2B2B timeline (steady, operational) or the Watchman timeline (ASAP)?

The Jira reorganization proposal (CAJP, 39 projects to 6 team-based projects with capacity bucketing across 5 work streams) is implicitly an attempt to make this allocation visible and explicit. Until that reorganization lands, the two go-to-market motions compete informally through individual engineers' task lists.
