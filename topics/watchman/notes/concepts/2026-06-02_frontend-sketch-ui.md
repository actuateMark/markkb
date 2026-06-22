---
title: "Watchman Frontend Sketch (2026-06-02 demo)"
type: concept
topic: watchman
tags: [watchman, ui, frontend, sketch, design]
jira: null
confluence: null
created: 2026-06-02
updated: 2026-06-02
author: kb-bot
---

Look-and-feel prototype of the Watchman cloud product UX. Auth-gated demo at demo.watchmansecurity.ai. Validates the agentic-first, terminal-style conversational design already outlined in [[watchman-repo|Watchman]] architecture docs. Not functional; conveys visual direction and interaction flow.

## Dashboard / Home View

![Dashboard home view](../assets/2026-06-02_watchman-ui-dashboard-home.png)

Centered greeting ("Good morning, Laura") with the Watchman logo—three curved orange triangular segments—and tagline "AI-powered security you can trust."

Three ghost-tile stat counters in a row:
- **6 Attention** (red, location-pin icon)
- **6 Activity** (orange, sparkle icon)
- **7 Sites** (teal, monitor icon)

These are the always-visible KPIs from the designed dashboard layout, giving the operator a glanceable summary of system state.

**Elevated Threat Mode** banner button (shield icon) surfaces the Patrol↔Active mode toggle at eye level. Currently reads: "heightened monitoring across all sites."

An embedded terminal panel repeats the conversational interface (see below), showing a recent search. Top-right light/dark theme toggle; bottom "Mobile App Preview" button hints at a companion mobile app design direction.

## Terminal / Forensic-Search View

![Terminal search interface](../assets/2026-06-02_watchman-ui-terminal-search.png)

Dark terminal titled "watchman". Header: "Watchman v1.0 · 28 cameras across 7 sites · type 'help' for commands".

**Conversational flow:**
1. User types `$ intruders` (a natural-language query).
2. System clarifies intent and suggests forensic searches ("vehicles at sports rental", "loitering after hours") or commands (alerts · timeline · live · help).
3. User refines: `$ vehicles at sports rental`.
4. System echoes the resolved plan: `> Plan: Sports Rental · last 30d · vehicle`.
5. Results: `5 detections found:` with a horizontal carousel of detection cards.

**Detection cards** show:
- Camera thumbnail (parking lots, driveways, labeled vehicles, some with colored bounding boxes).
- Camera label ("Sports Rental") + per-camera name.
- Relative timestamp ("23h ago").
- Confidence or severity label.
- Two triage actions: **Open** (view full detail) and **Pivot** (cross-camera correlation / drill-down).

**Filter chips** at top (`Sports Rental ×`, `last 30d`, `vehicle`) allow refinement; "clear" resets the search. Bottom input bar prompts: "Try a search like 'vehicles at sports rental' or type a command…".

## Design Implications

- **Ghost-tile dashboard** confirms the always-visible stat pattern for at-a-glance operator situational awareness.
- **Terminal conversational command bar** validates the agentic-first UX pillar—natural-language intent resolution with suggested disambiguations.
- **Forensic natural-language search** over historical detections implies a queryable event/detection store; aligns with the phase-0 ingest pipeline emitting structured, searchable signals.
- **Pivot action** signals cross-camera threat correlation and severity re-scoring—the Assessment Agent's comparative drill-down capability.
- **Elevated Threat Mode banner** is the user-facing surface of the [[patrol-vs-active-modes|Site Supervisor Agent's mode transition]]; confirms the Patrol (passive monitoring) vs. Active (heightened thresholds) dichotomy.
- **28 cameras across 7 sites** indicates a multi-site, multi-camera queryable index—constrains the shape of the ingest and alert pipeline.

**Auth-gated demo note:** The screenshots are the durable record; the live demo at demo.watchmansecurity.ai may evolve. Refer to these images for the 2026-06-02 snapshot.

---

## Related

- [[watchman-repo]] — Watchman backend/platform repo
- [[patrol-vs-active-modes]] — Patrol monitoring vs. Active heightened-alertness mode
- [[multi-agent-architecture]] — Site Supervisor, Assessment, Judge agents
- [[triage-gamification]] — Detection triage workflows
- [[onboarding-wizard]] — New-customer setup flow
- [[2026-06-02_watchman-phase0-fleet-fit]] — Phase 0 fleet ingest pipeline fit (planning, unresolved link OK)
