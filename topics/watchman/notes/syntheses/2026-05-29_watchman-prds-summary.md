---
title: Watchman PRDs Summary — What v2 + Agent Specs Actually Say
author: kb-bot
created: 2026-05-29
updated: 2026-05-29
topic: watchman
type: synthesis
tags: [watchman, fleet-architecture, manager-service, prd, agent-specs]
related:
  - "[[topics/watchman/_summary]]"
  - "[[2026-05-28_watch-management-service-index]]"
  - "[[2026-05-29_site-supervisor-vs-watch-manager]]"
confluence_prd: "https://actuate-team.atlassian.net/wiki/spaces/PM/pages/478019585"
confluence_agents: "https://actuate-team.atlassian.net/wiki/spaces/PM/pages/482344961"
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/concepts/2026-06-01_terminology-conflict-watchman-ambiguity.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_fleet-rearch-briefing-overview.md
  - topics/fleet-architecture/notes/syntheses/2026-05-28_watch-management-service-design.md
  - topics/fleet-architecture/notes/syntheses/2026-06-01_adr-watchman-mvp-slim-connector.md
  - topics/watchman/_summary.md
  - topics/watchman/notes/concepts/watch-entity.md
  - topics/watchman/notes/syntheses/2026-05-28_watch-management-service-index.md
  - topics/watchman/notes/syntheses/2026-05-29_site-supervisor-vs-watch-manager.md
  - topics/watchman/notes/syntheses/2026-05-29_watchman-judge-backend-io-contract.md
incoming_updated: 2026-06-02
---

# Watchman PRDs Summary — What v2 + Agent Specs Actually Say

Captures the two canonical [[watchman-repo|Watchman]] Confluence docs so we don't re-read for cross-referencing. Both were "unread in KB" as of the May 28 brainstorm-correlation note.

## PM/478019585 — Watchman PRD v2 (2026-03-03, Brian / Product)

Cloud-native BYOD virtual security operator. $25–35/cam/mo target.

**Three architectural layers:**

1. **Actuate Secure** — WireGuard mesh from customer edge.
2. **AI Detection** — Actuate threat engine + YOLO precursor pipeline (today's connector).
3. **Agentic Orchestration** — the new layer; ten agents listed in PM/482344961.

**Two Operating Modes** (the headline UX):

- **Patrol Mode** — default state when activity ≤ baseline. **Patrol Agent (PROD-152)** drives structured camera sweeps every 5/15 min. Adaptive frequency from rhythm model.
- **Active Monitoring Mode** — engaged when a precursor or threat fires above patrol-severity threshold. Site-wide cross-camera correlation, compound severity, escalation chain push→SMS→phone→email with 60s ack timeout.

**Mode transition rule (§8.3):** "Any precursor/threat above patrol-severity threshold → Active; all events resolved + activity below baseline → Patrol."

**Modes are site-level orchestration state managed by Site Supervisor Agent (PROD-147), NOT [[watch-entity|Watch]] attributes.** This is the load-bearing fact that resolves the "Operating Modes vs. [[watch-entity|Watch]]" open question across the May 28 syntheses.

**Other PRD facts that touch our fleet-arch design:**

- Sub-2s [[webrtc-deep-dive|WebRTC]] live view requirement.
- Sub-10s detection-to-notification SLA.
- §11 mentions AWS Local Zones for latency.
- §13 Enterprise tier mentions RBAC / SSO / SCIM (relevant for [[2026-05-29_watch-manager-rbac|manager RBAC]]).
- §17 mentions EU residency (relevant for [[2026-05-29_watch-manager-multiregion|multi-region]]).

## PM/482344961 — Watchman Agent Specifications v3 (2026-04-20)

Ten agents, each with goal / inputs / outputs / build-status. Below: only the agents that materially affect [[watch-entity|Watch]] Management Service design.

| Agent | Ticket | Role | Status |
|---|---|---|---|
| **Site Supervisor Agent** | PROD-147 | Per-site **Mode state machine** + agent coordinator + resource allocator. Owns the orchestration loop that decides when to transition between Patrol and Active. | Net-new across the board |
| **Site Context Agent** | PROD-167, PROD-135 | Owns the **site rhythm model**, real-time per-camera state cache, and **schedule-aware context** (business hours, shifts, closures, after-hours exceptions). Reuses Project Cactus (AUTO-90), site classification (AUTO-117), heuristic baselines (AUTO-78). | Reuses existing pieces |
| **Patrol Agent** | PROD-152 | Cloud-side patrol orchestration; **adapts AUTO-77 (Autopatrol microservice)** + AUTO-78 + AUTO-107. Adaptive sweep frequency from rhythm model — currently fixed/Immix-driven in code. | Adapts AUTO-77 |
| **Connectivity Agent** | PROD-120/122/123/125 | Stream health monitoring + **NVR-playback fallback** when live drops >10s. Tags frames with `source_type="recorded_playback"` so downstream Assessment uses capture-time, not arrival-time. | Net-new |
| **Escalation Agent** | PROD-172/178/183 | Direct-to-operator push / SMS / phone / email. **NOT Immix.** | Net-new |
| **Threat Agent** | PROD-?? | (Not detailed in this digest) | |
| **Assessment Agent** | PROD-?? | Cross-camera correlation, compound severity (drives Mode transitions) | |
| **Learning Agent** | PROD-?? | (Not detailed) | |
| **Recommendations Agent** | (in `Watchman/agents/recommendations_agent.py`) | Hourly batch LLM over Postgres rows | Only PRD agent that exists in code today |

**Infrastructure assumptions in the agent specs:**

- **Kafka** is the inter-agent bus. Manager touchpoint T17 ("SQS `site_product_started/ended` is the manager's oracle") needs a bridging migration to Kafka.
- **DynamoDB** for site rhythm, event timeline, project-cactus-descriptions.
- **Redis** for real-time site state (different from today's Redis `MotionStatus`).
- **S3** for clips.

## Implications for Watch Management Service design

In rough order of impact. Cross-referenced from [[2026-05-28_watch-management-service-design]] and the six per-proposal addenda:

1. **Modes ≠ [[watch-entity|Watch]].** Operating Modes are site-level Site-Supervisor-managed state derived from live events; Watches are armed-surveillance units. Orthogonal. Update master design's "Open questions" and the index. Resolved in [[2026-05-29_site-supervisor-vs-watch-manager]].
2. **Site Supervisor ↔ Manager relationship is the missing first-order decision.** Both are continuous, per-site (or fleet-wide), reconciler-shaped daemons. Three options: manager IS the Site Supervisor substrate, Site Supervisor IS a tenant inside the manager, or they're separate pods sharing state. See [[2026-05-29_site-supervisor-vs-watch-manager]].
3. **Constraint #8 (connector owns `start_patrol/end_patrol`) is temporary.** Under [[watchman-repo|Watchman]], Patrol Agent absorbs AP scheduling. Manager must coordinate the deprecation, not just preserve the constraint. Update master design.
4. **Constraint #3 (no settings-reload path) must be relaxed under [[watchman-repo|Watchman]].** Site Supervisor's "allocate resources on mode change" (e.g. bump FPS during Active mode) requires the connector to accept hot-reconfigure. Net-new requirement; flag as Watchman-driven. Update master design.
5. **VCH/AP runtime-model decision is partly pre-resolved.** Briefing question 4 — Patrol Agent absorbs AP scheduling; VCH overlaps Connectivity Agent + CHM. Both lose "separate CronJob" identity in the target state.
6. **Kafka, not SQS** for inter-agent transport. Bridging migration story needed for T17.
7. **Escalation is direct-to-operator.** Alarmwatch / StarFM / Crosbies / Patriot remain compatible but become secondary delivery channels, not primary. Update brainstorm-correlation's partner-impact framing.
8. **NVR-playback fallback affects billing semantics.** Connectivity Agent's `source_type="recorded_playback"` flag plus original capture-time means billing must use capture-time, not arrival-time. Constraint addition.

## Watchman repo state — context for design

Two repos exist; **neither implements PRD entities** (see [[topics/watchman/notes/entities/watchman-repo]]):

- `actuate-watchman-internal` is an unrelated on-premise line-crossing product (name collision).
- `Watchman` (the agentic repo) is a 2-commit prototype with hourly-batch LLM analysis (Analysis/Judge/Recommendations agents over self-contained Postgres). No camera management, no schedules, no [[watch-entity|Watch]] entity. FastAPI + Bedrock + Postgres wired up.

The manager-service work is fully **greenfield in code**; nothing constrains or contradicts the May 28 syntheses. Optional choice: extend `Watchman/api.py` (existing FastAPI scaffold) or stand up a new service.

## Cross-references

- Brainstorm: [PM/601686018](https://actuate-team.atlassian.net/wiki/spaces/PM/pages/601686018)
- PRD v2: [PM/478019585](https://actuate-team.atlassian.net/wiki/spaces/PM/pages/478019585)
- Agent Specs: [PM/482344961](https://actuate-team.atlassian.net/wiki/spaces/PM/pages/482344961)
- Brainstorm correlation: [[2026-05-28_watchman-scheduling-brainstorm-correlation]]
- Master [[watch-entity|Watch]] Manager design: [[2026-05-28_watch-management-service-design]]
- [[watch-entity|Watch]] Manager index: [[2026-05-28_watch-management-service-index]]
- Site Supervisor vs Manager decision: [[2026-05-29_site-supervisor-vs-watch-manager]]
- Briefing overview: [[2026-05-28_fleet-rearch-briefing-overview]]
