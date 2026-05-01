---
title: Actuate Watchman
type: summary
topic: watchman
tags: [watchman, product, agentic, multi-agent, b2b, security-operator]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/PM/pages/478019585"
jira: "PROD-118"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Actuate Watchman

**AI-Powered Virtual Security Operator Platform** -- the next major product. A fully cloud-based system that closes the gap between passive surveillance (cameras record but nobody watches) and prohibitively expensive live monitoring ($50-150+/camera/month).

**Classification:** Internal -- Confidential
**Target release:** ASAP
**MVP target:** 10-20 beta sites with live camera feeds

## Market Thesis

- Global video surveillance market: $56-74B (2024)
- Less than 1% of surveillance video is monitored live
- RVM services cost $50-150+/camera/month -- inaccessible to most businesses
- [[watchman-repo|Watchman]] creates a **new market category**: affordable proactive monitoring for businesses with 4-30 cameras
- **Go-to-market pivot:** from B2B2B (via Immix/monitoring centers) to **B2B direct** to commercial businesses

## Architecture -- Three Layers

1. **Secure Connectivity Layer** (Actuate Secure) -- WireGuard VPN tunnels via Teltonika RUT241 routers or Actuate Secure App
2. **AI Detection Layer** -- Dual-layer: YOLO precursor classification (high-throughput filter gate) + Actuate threat detection (firearms, intrusion, loitering, crowd, fire, slip-and-fall)
3. **Agentic Orchestration Layer** -- Multi-agent AI system

## Agent Architecture

| Agent | JIRA | Role | Build Status |
|-------|------|------|-------------|
| Connectivity Agent | PROD-120 | Secure camera-to-cloud connection | EXISTS (adapt from Actuate Secure) |
| Site Supervisor Agent | PROD-147 | Top-level orchestrator, mode transitions | NEW |
| Patrol Agent | PROD-152 | Adaptive camera sweeping (5-15 min cycles) | EXISTS (adapt from AutoPatrol) |
| Actuate Threat Agent | PROD-132 | Integration with existing AI models | EXISTS (adapt, add two-track routing) |
| Assessment Agent | PROD-157 | Cross-camera severity scoring -- **core differentiator** | PARTIAL (extend from AUTO-110) |
| Site Context Agent | PROD-167 | Site rhythm model, learned patterns, schedule awareness | PARTIAL (adapt) |
| Recommendation Agent | PROD-162 | Human-readable response instructions | EXISTS (adapt from AUTO-124) |
| Escalation Agent | PROD-172 | Multi-tier notification chains, auto-escalation | NEW |
| Learning Agent | PROD-209 | Triage feedback loop, accuracy tracking | NEW |

## Operating Modes

1. **Patrol Mode:** Low-activity. Patrol Agent sweeps cameras adaptively. Anomalies flagged to Assessment Agent.
2. **Active Monitoring Mode:** Triggered when any camera flags a precursor or active threat. Real-time multi-camera correlation.
3. **Transition:** Site Supervisor manages mode switching based on event counts and activity levels.

## UI Design

**Agentic-first design philosophy** -- terminal-style conversational interface:
- Ghost tile dashboard (always-visible stats)
- Terminal input bar (chat-style commands)
- Camera & Site Management panel
- Triage workflow with XP/streak gamification
- Daily AI-generated digest

## Onboarding -- 9-Step Wizard (F-001)

1. Deployment type selection
2. WireGuard tunnel setup
3. WiFi configuration
4. Camera discovery (ONVIF/[[rtsp-deep-dive|RTSP]])
5. Site type classification
6. Camera selection + naming/zone assignment
7. Emergency contacts (up to 5)
8. Protection priorities
9. Go Live (animated deployment sequence)

## Escalation Tiers

- **CRITICAL:** Simultaneous push + SMS + phone call. Auto-escalate after 60s non-acknowledgment.
- **HIGH:** Push + SMS
- **MEDIUM:** Push only

## Success Metrics

| KPI | Target |
|-----|--------|
| Triage engagement | >70% events triaged within 1 hour |
| Onboarding time | <10 minutes |
| Detection-to-notification | <10s (p95) |

## What's Genuinely New vs Reused

**Reused:** WireGuard tunnels, connector pipeline, AI models, AutoPatrol scheduling, VLM FP filter, CHM patterns
**New:** Multi-agent orchestration, two-track precursor/threat routing, compound cross-camera severity scoring, multi-tier escalation with auto-escalation, [[triage-gamification|triage gamification]], terminal-style UI, BYOD self-service onboarding

## Team

- **[[brian-leary|Brian Leary]]** -- Product lead, PRD author
- **[[laura-reno|Laura Reno]]** -- Document owner, MVP Requirements + Agent Specs
- **[[jacob-weiss|Jacob Weiss]]** -- Engineering (infrastructure, security)
- **[[brad-murphy|Brad Murphy]]** -- Frontend
- **Tatiana** -- Engineering
- **[[michael-aleksa|Michael Aleksa]]** -- Engineering
- **Jagadish** -- AI/ML
