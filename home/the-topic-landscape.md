---
title: "The topic landscape — where to go to learn what"
type: synthesis
tags: [orientation, map, topics, navigation, home]
updated: 2026-06-25
author: kb-bot
incoming:
  - home/README.md
  - home/orientation/first-steps.md
  - home/orientation/how-to-use-this-kb.md
  - home/orientation/system-architecture.md
  - home/what-is-actuate.md
  - index.md
incoming_updated: 2026-06-25
---

# The topic landscape — where to go to learn what

The KB has ~40 topics. This page groups them into **domains** and answers *"I want to understand X — where do I start?"*. The live, counted topic index is on the wiki home [[index]]; this page is the **reasoned tour**.

## The 9 domains at a glance

| Domain | Topics | What it covers |
|---|---|---|
| **Platform & core** | [[actuate-platform/_summary\|actuate-platform]], [[vms-connector/_summary\|vms-connector]], [[actuate-libraries/_summary\|actuate-libraries]], [[admin-api/_summary\|admin-api]] | The services + shared libraries that *are* the product |
| **APIs** | [[inference-api/_summary\|inference-api]], [[external-api/_summary\|external-api]] | Model-serving + the public v5 contract |
| **Products & initiatives** | [[autopatrol/_summary\|autopatrol]], [[camera-health-monitoring/_summary\|camera-health-monitoring]], [[watchman/_summary\|watchman]], [[alerts-improvements/_summary\|alerts]], [[settings-automation/_summary\|settings]], [[product-roadmap/_summary\|roadmap]] | What's shipped on top of the spine |
| **Integrations** | [[integrations/_summary\|integrations]] (sub-topic per VMS / monitoring-center / partner) | How video gets IN and alerts go OUT |
| **AI models & data science** | [[models/_summary\|models]], [[ai-models/_summary\|ai-models]], [[data-science/_summary\|data-science]] | The detectors + the ML/eval methodology |
| **Infra · fleet · cost · perf** | [[fleet-architecture/_summary\|fleet-architecture]], [[infrastructure/_summary\|infrastructure]], [[compute-fleet/_summary\|compute-fleet]], [[aws-cost/_summary\|aws-cost]], [[profiling-and-performance/_summary\|profiling]], [[new-relic/_summary\|new-relic]] | Running it at scale, economically, observably |
| **Video & media** | [[video-processing/_summary\|video-processing]], [[webrtc-deep-dive/_summary\|webrtc]] | Decode, frame transport, streaming |
| **Engineering & process** | [[engineering-process/_summary\|engineering-process]], [[runbooks/_summary\|runbooks]], [[releases/_summary\|releases]], [[repo-backlog/_summary\|repo-backlog]], [[software-architecture/_summary\|software-architecture]], [[team-structure/_summary\|team-structure]], [[data-access-control/_summary\|data-access-control]], [[billing/_summary\|billing]], [[local-test-stack/_summary\|local-test-stack]], [[jira-organization/_summary\|jira]] | How the team builds, ships, and governs |
| **KB · tooling · ops** | [[operational-health/_summary\|operational-health]], [[personal-notes/_summary\|personal-notes]], [[personal-laptop/_summary\|personal-laptop]], [[llm-shop/_summary\|llm-shop]], [[obsidian/_summary\|obsidian]] | The KB, the automation, the [[dev-environment|dev environment]] |

## "I want to learn…" → go here

- **…what Actuate does** → [[what-is-actuate]], then [[actuate-platform/_summary]].
- **…how video gets ingested** → [[vms-connector/_summary]] (the pipeline) + [[integrations/_summary]] (per-VMS specifics: Milestone, Avigilon, Genetec, [[kvs-components|KVS]], [[rtsp-deep-dive|RTSP]]…).
- **…how detection works** → [[models/_summary]] ("what does line-crossing/weapon/fire do?") vs [[ai-models/_summary]] ("how do we evaluate a candidate model?"). Serving: [[inference-api/_summary]].
- **…how alerts reach a monitoring center** → [[integrations/_summary]] (monitoring centers: Immix, [[sentinel-components|Sentinel]], [[bold-components|Bold]]…) + [[alerts-improvements/_summary]] + [[autopatrol/_summary]].
- **…the connector internals** (filter/observer/sender/puller, AIMD back-pressure, config threading) → [[vms-connector/_summary]] + [[actuate-libraries/_summary]]. (There's a `connector-pipeline-expert` subagent for deep Q&A.)
- **…running the fleet at scale / cost** → [[fleet-architecture/_summary]] (the redesign), [[compute-fleet/_summary]], [[aws-cost/_summary]], [[profiling-and-performance/_summary]].
- **…the public API** → [[external-api/_summary]] (v5), with [[inference-api/_summary]] underneath.
- **…how the team works** (CI, release chain, branch semantics, library publishing) → [[engineering-process/_summary]] + [[releases/_summary]]. Ops fix-its → [[runbooks/_summary]].
- **…production health / monitoring** → [[operational-health/_summary]] + [[new-relic/_summary]] (query rules + dashboards).
- **…the AutoPatrol product** → [[autopatrol/_summary]] (the biggest product topic).
- **…video decode / streaming / [[webrtc-deep-dive|WebRTC]]** → [[video-processing/_summary]] + [[webrtc-deep-dive/_summary]].
- **…who owns what / team layout** → [[team-structure/_summary]].
- **…the automation + dev [[SETUP|setup]]** (firebat, dashboard, llm-shop, this KB) → the operational map [[2026-06-22_actuate-footprint-handoff]], and the runbooks in this folder.

## How the spine maps onto topics
Reading the [[what-is-actuate]] data-flow left-to-right, each stage is a topic cluster:
**integrations → vms-connector → inference-api/models → integrations (senders)**, all running on **fleet-architecture/infrastructure**, observed via **operational-health/new-relic**, built per **engineering-process**.

## Also in this `home/` folder
Operational handoffs + runbooks (firebat, dashboard, llm-shop, secrets) and the full offboarding suite — see [[README]] for the ordered reading list and [[offboarding-overview]] for that context.
