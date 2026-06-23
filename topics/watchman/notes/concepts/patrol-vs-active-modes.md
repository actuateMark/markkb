---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [watchman, modes, patrol, active-monitoring, site-supervisor]
incoming:
  - topics/autopatrol/notes/concepts/flex-ignore-zones.md
  - topics/watchman/notes/concepts/2026-06-02_frontend-sketch-ui.md
  - topics/watchman/notes/concepts/multi-agent-architecture.md
  - topics/watchman/notes/concepts/onboarding-wizard.md
incoming_updated: 2026-06-19
---

# Patrol vs Active Monitoring Modes

[[watchman/_summary|Actuate Watchman]] operates in two distinct modes that mirror how a human security operator would shift attention between routine scanning and incident response. The [[multi-agent-architecture|Site Supervisor Agent]] governs transitions between them.

## Patrol Mode

Patrol Mode is the default, low-activity state. The [[autopatrol/_summary|AutoPatrol (H1.2)]] sweeps cameras on adaptive 5-15 minute cycles, sampling each feed and looking for anomalies. The cycle frequency is not fixed -- it adapts based on the time of day, historical activity patterns from the [[multi-agent-architecture|Site Context Agent]], and recent event density.

During Patrol Mode the system is conservative with resources. Not every camera is analysed simultaneously; the Patrol Agent rotates through them, prioritising cameras that historically see more activity or that cover higher-value zones (as configured during the [[onboarding-wizard]] protection priorities step). Anomalies detected during patrol are flagged to the Assessment Agent for severity scoring, but the system does not yet commit to full real-time correlation across all cameras.

Key characteristics:
- Adaptive sweep intervals (5-15 min)
- Camera prioritisation based on site context and protection priorities
- Anomalies flagged but not yet correlated cross-camera at full fidelity
- Resource-efficient -- suitable for sustained 24/7 operation

## Active Monitoring Mode

Active Monitoring Mode is triggered when any camera flags a precursor event (via the YOLO filter gate) or a confirmed threat (via the full Actuate detection models). The system shifts from sequential sweeping to real-time multi-camera correlation.

In this mode, the Assessment Agent performs cross-camera compound severity scoring -- correlating events across multiple feeds to determine whether an anomaly on one camera is corroborated or contradicted by others. The Recommendation Agent generates response instructions, and the Escalation Agent is armed to dispatch notifications if severity thresholds are met.

Key characteristics:
- Triggered by precursor or confirmed threat detection
- Real-time analysis across all relevant cameras simultaneously
- Cross-camera correlation and compound severity scoring
- Escalation chains armed (CRITICAL / HIGH / MEDIUM tiers)
- Higher resource consumption -- sustained only while the event is active

## Transition Logic

The Site Supervisor Agent (PROD-147) manages mode switching. The transition from Patrol to Active is event-driven: any detection event that passes the Actuate Threat Agent's filter triggers the shift. The transition back to Patrol is based on activity decay -- when event counts drop below a threshold and no active threats remain, the Site Supervisor returns the system to Patrol Mode.

This two-mode design avoids the cost of running full real-time analysis 24/7 (which would be prohibitively expensive at scale) while ensuring the system can ramp up instantly when something happens. It is analogous to how a human guard alternates between walking rounds and responding to an alarm.

## Adaptive Frequency

The Patrol Agent's sweep frequency is not static. The Site Context Agent builds a rhythm model for each site -- learning when activity peaks occur, when the site is empty, and when transitions happen (opening hours, shift changes). Patrol cycles tighten during historically active periods and relax during quiet ones. This adaptive scheduling is an evolution of the scheduling logic already proven in [[autopatrol/_summary|AutoPatrol (H1.2)]].
