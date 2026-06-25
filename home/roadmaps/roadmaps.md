---
title: "Roadmaps — where the team is headed next"
type: index
tags: [roadmap, home, handoff, navigation]
updated: 2026-06-25
author: kb-bot
---

# Roadmaps — where the team is headed next

Forward-looking overviews of the **high-leverage initiatives** the team is picking up, written to get a successor productive fast. Each links down into the deep design record in `topics/`. (Status/ownership of *all* workstreams is in [[2026-06-22_offboarding-plan]]; Jira handoff comments are posted on the open tickets.)

## The big ones
- **[[watchman-fleet-architecture|Watchman + Fleet Architecture]]** — the flagship. The VMS-connector redesign (Proposal E) + the new [[watchman-repo|Watchman]] product built on its Phase 0 shape; monotonic growth `Phase 0 → E → v10 (~100k cameras)`. Owners: **Mike (ENG-300)** + **Paolo (ENG-383)**.
- **[[actuate-integration-tools|AIT (Actuate Integration Tools)]]** — the `ait` testing/inspection toolkit (config inspection + "brain-in-jar" replay + Hypothesis QA). Strong forward vector: its primitives fit the upcoming [[watch-entity|Watch]] Manager test surface. Owner: **TBD** (first task: fix the local path-pins + assign ownership).

## Other in-flight workstreams (detail in the offboarding plan)
- **AutoPatrol** (§3/§14) — handoff in [[2026-06-23_autopatrol-handoff]]; topic [[autopatrol/_summary]].
- **Billing event pipeline** (§28) — [[billing/_summary]].
- **RDS extended-support upgrades** (§33) — [[runbooks/_summary]] + the RDS upgrade runbook.
- **Connector / [[pyav-entity|PyAV]] decode** (§15) — [[vms-connector/_summary]] + [[video-processing/_summary]].
- **Firebat automation + the operational dashboard** — the most uniquely Mark-built layer; runs unattended but needs an owner to maintain/extend it. See [[2026-06-23_firebat-dashboard-ownership-handoff]] + [[2026-06-22_firebat-operations-runbook]].

## How to use this
Read the relevant roadmap top-to-bottom for the lay of the land + the open decisions, then follow its ranked "Read next" into the topic syntheses. For the product/architecture context first, see [[what-is-actuate]] + [[system-architecture]].
