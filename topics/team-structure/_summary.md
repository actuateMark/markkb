---
title: Team Structure & Assignments
type: summary
topic: team-structure
tags: [team, people, assignments, org]
created: 2026-04-13
updated: 2026-04-16
author: kb-bot
---

# Team Structure & Assignments

No formal org chart exists in Confluence. Team composition inferred from Jira assignments, Confluence authorship, and git history.

## Personal TODO Trackers

| Person | Note |
|--------|------|
| Mark Barbera | [[mark-todos]] |

## Leadership

| Person | Role |
|--------|------|
| Brian Leary | Product lead (Watchman PRD, strategy, pricing) |
| Laura Reno | PM lead (MVP requirements, agent specs, release comms, integration docs) |
| Jacob Weiss | Engineering lead (infrastructure, security, WireGuard, Jira reorg author) |

## Engineering

| Person | Active Focus (April 2026) | Key Tickets |
|--------|--------------------------|-------------|
| Michael Aleksa | Inference batching/compilation (Highest), YAM connector, model accuracy | ENG-71, ENG-67, ENG-39 |
| Mark Barbera | EBUS Phase 1 (In Progress), Jira/Confluence docs sync, PyAV upgrade | ED-32, ENG-126, ENG-147, ENG-136 |
| Vinicius Flores | External API schedule endpoints (primary), arm/disarm | ENG-123, ENG-34, ENG-125 |
| Paolo Zilioti | YoursIx VMS, clips dev scaling | ENG-118, ENG-145, ENG-150 |
| Tatiana Hanazaki | Admin API core, line crossing separation, DB perf (BT-926 companion), AutoPatrol backend, BI scheduling | PROD-116, ENG-148, AUTO-500 |
| Brad Murphy | Frontend (flex IZ nearing deploy, AP schedules, operator logging) | AUTO-446, AUTO-427, CS3-300 |
| Aziz | WireGuard Phase 5A metrics (In Progress), VPN troubleshooting tool scoping | ENG-117, ENG-83 |
| Adam Kawczynski | Monitoring-api staging deploy, camera-admin routing | ENG-146 |
| Jessica Bae | Enhanced action logs (Ready for Testing), alert muting | ED-10, ED-12 |

## Data Science / AI

| Person | Active Focus | Key Tickets |
|--------|-------------|-------------|
| Uladzimir Sapeshka (Vlad) | YAM re-evaluation (Done), bbox normalization fix (Done), v8 vs v5 performance | AI-211, AI-221 |
| Zack Schmidt | YAM epic owner, weapon model decisions | AI-158 |
| Alena Prashkovich | VLM prompt eng Phase III (Done), pipeline improvements, UK camera screening | AUTO-538, AI-213 |
| Mladen Lukic | UK/EU bespoke model labeling/testing | AI-169, AI-160 |
| Otzar Jaffe | PPF pipeline, site classification, ignore zones, YOLOv8 entrance model | SA-177, AI-167-164 |
| Carlos Torres | Weapon model training, VLM FP filter, supervisor scenario eval | SA-171, PROD-282, PROD-283 |
| Clarissa Herman | AP Server/MS integration (Rev2 deployed to DEV), VLM inference server (QWEN3-VL), prompt module | AUTO-489, PROD-275 |

## Product

| Person | Focus |
|--------|-------|
| Laura Reno | Watchman MVP, VLM FP reduction MVP (SA-221), integration docs |
| Jessica Bae | AutoPatrol product, alerts, DS coordination |
| Thomas Kornfeld | Settings Recommender (epic owner, SA-7) |

## QA
- **Victoria Peccia** -- AutoPatrol QA (flex IZ), CHM (schedule disabling)

## Support
- **Gary Sylvester** -- Support Tracker owner
- **Jacob Weiss** -- Active in support tickets (BT-921, 923, 891, 911)

## Cross-Initiative Spread

Several people span multiple initiatives:
- **Brad Murphy:** AUTO + CS3 + Watchman UI
- **Alena Prashkovich:** AUTO + AI
- **Otzar Jaffe:** AI + SA + AUTO
- **Mark Barbera:** AUTO + CS3 + ENG (EBUS)
- **Laura Reno:** SA + AI + CS3 + Watchman
