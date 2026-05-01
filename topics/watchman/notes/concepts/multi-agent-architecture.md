---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [watchman, agents, architecture, orchestration, multi-agent]
incoming:
  - topics/actuate-platform/notes/syntheses/camera-onboarding-end-to-end.md
  - topics/alerts-improvements/notes/concepts/alert-muting.md
  - topics/alerts-improvements/notes/concepts/immix-dispatch.md
  - topics/autopatrol/notes/concepts/flex-ignore-zones.md
  - topics/settings-automation/notes/concepts/vlm-fp-reduction.md
  - topics/team-structure/notes/entities/brad-murphy.md
  - topics/team-structure/notes/entities/brian-leary.md
  - topics/team-structure/notes/entities/laura-reno.md
  - topics/watchman/notes/concepts/onboarding-wizard.md
  - topics/watchman/notes/concepts/patrol-vs-active-modes.md
incoming_updated: 2026-05-01
---

# Multi-Agent Architecture

[[watchman/_summary|Actuate Watchman]] is built around a hierarchy of nine specialised agents that collectively replace the role of a human security operator. The architecture is layered: a connectivity foundation, an AI detection middle tier, and an agentic orchestration layer on top. Each agent has a clearly scoped responsibility and communicates through well-defined inter-agent channels.

## The Nine Agents

### Infrastructure Layer
- **Connectivity Agent** (PROD-120) -- Manages secure camera-to-cloud links via [[WireGuard]] tunnels on Teltonika RUT241 routers or the Actuate Secure App. Adapted from the existing Actuate Secure product. It is the foundation everything else depends on.

### Detection Layer
- **Actuate Threat Agent** (PROD-132) -- Dual-track routing system. A YOLO precursor classifier acts as a high-throughput filter gate; events that pass are forwarded to the full Actuate threat detection models (firearms, intrusion, loitering, crowd, fire, slip-and-fall). This two-track design is new to [[watchman-repo|Watchman]] and separates low-confidence precursors from confirmed threats.

### Orchestration Layer
- **Site Supervisor Agent** (PROD-147) -- Top-level orchestrator. Owns mode transitions between [[patrol-vs-active-modes|Patrol and Active Monitoring modes]], decides when to escalate from passive sweeping to real-time correlation. Entirely new for [[watchman-repo|Watchman]].
- **Patrol Agent** (PROD-152) -- Performs adaptive camera sweeping on 5-15 minute cycles. Adapted from [[autopatrol/_summary|AutoPatrol (H1.2)]]. Flags anomalies to the Assessment Agent.
- **Assessment Agent** (PROD-157) -- Cross-camera compound severity scoring. This is described as the **core differentiator** of [[watchman-repo|Watchman]]. It correlates events across multiple cameras to produce a unified threat assessment rather than per-camera point alerts. Partially exists from AUTO-110 work.
- **Site Context Agent** (PROD-167) -- Maintains a site rhythm model: learned activity patterns, time-of-day baselines, schedule awareness. Provides contextual signals to the Assessment and Recommendation agents so scoring reflects what is normal for a given site and time.
- **Recommendation Agent** (PROD-162) -- Generates human-readable response instructions for the operator. Adapted from AUTO-124. Tells the operator what to do, not just what happened.
- **Escalation Agent** (PROD-172) -- Manages multi-tier notification chains: CRITICAL (push + SMS + phone, auto-escalate after 60 seconds), HIGH (push + SMS), MEDIUM (push only). Entirely new.
- **Learning Agent** (PROD-209) -- Closes the feedback loop. Tracks triage outcomes and accuracy over time, feeding into the [[triage-gamification]] system. Entirely new.

## Communication Flow

The typical flow during an event: Patrol Agent flags an anomaly to the Actuate Threat Agent for classification. Confirmed events are passed to the Assessment Agent, which queries the Site Context Agent for baseline context and produces a severity score. The Recommendation Agent translates that score into operator instructions. If severity warrants, the Escalation Agent dispatches notifications according to the tiered escalation policy. The Site Supervisor Agent oversees this entire pipeline, transitioning the system from patrol to active monitoring when event density crosses thresholds.

## Build Status

Three agents are entirely new (Site Supervisor, Escalation, Learning). Three are adapted from existing products (Connectivity, Patrol, Threat). Three are partial or adapted (Assessment, Site Context, Recommendation). The mix of reuse and new development is central to [[watchman-repo|Watchman]]'s feasibility at an accelerated timeline.
