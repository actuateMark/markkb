---
title: "home/ — start here (orientation packet)"
type: index
tags: [home, orientation, guides, moc, navigation]
updated: 2026-06-25
author: kb-bot
---

# `home/` — start here

**If you read only this folder, you should come away oriented to the whole knowledge base + the team's operational setup.** That's the goal of `home/`: a self-contained orientation packet. Everything here is either *general orientation* or a *cross-cutting operational guide* — the per-topic detail lives out in `topics/` (mapped from [[index]]).

Read roughly top-to-bottom; skip to what you need.

## 1 · Orientation (read these first)
| Note | What you'll learn |
|---|---|
| [[what-is-actuate]] | What the product is + the data-flow spine (frames in → detect → alerts out) |
| [[the-topic-landscape]] | The ~40 topics grouped into 9 domains + **"I want to learn X → go here"** |
| [[how-to-use-this-kb]] | Note types, the retrieval ladder, the `obsidian` CLI + `/kb-ask` & `/kb-lookup`, conventions |

## 2 · The operational footprint (what the team runs)
| Note | What it covers |
|---|---|
| [[2026-06-22_actuate-footprint-handoff]] | **"What runs where"** — firebat mini-PC, the dashboard, the llm-shop, the KB — and who owns what |
| [[2026-06-22_firebat-operations-runbook]] | Deep team-handoff runbook for the firebat automation host (timers, creds, recovery) |
| [[2026-06-22_dashboard-signals-catalog]] | Every operational-dashboard signal: what it means + its baseline |
| [[2026-06-22_npu-server-llm-shop-runbook]] | The local-LLM box (SYCL/NPU/Ollama serving) — operate + rebuild |
| [[2026-06-24_secrets-refresh-runbook]] | Rotating/refreshing every credential the automation depends on |
| [[2026-06-22_dead-mans-checklist]] | **If something breaks:** symptom → cause → fix |

## 3 · Set up your own instance
| Note | For |
|---|---|
| [[DEVBOX-BOOTSTRAP]] | Stand up the full KB + Claude-Code workflow on a fresh machine |
| [[SETUP]] | Just the KB (Obsidian vault + Quartz) |

## 4 · Offboarding (Mark → team handoff, June 2026)
Time-bound, but the handoffs double as ownership docs. Start at [[offboarding-overview]].
| Note | What it is |
|---|---|
| [[offboarding-overview]] | The offboarding topic summary / index |
| [[2026-06-22_offboarding-plan]] | The full plan (workstreams WS-0…WS-E, ENG-376) |
| [[2026-06-22_manual-action-checklist]] | §A–§I human/team-gated actions |
| [[2026-06-24_offboarding-asks]] | The concrete asks for the team |
| [[2026-06-23_watchman-fleet-handoff-paolo-mike]] | Watchman / fleet → Paolo + Mike |
| [[2026-06-23_autopatrol-handoff]] | AutoPatrol → Brad |
| [[2026-06-23_firebat-dashboard-ownership-handoff]] | Firebat + dashboard ownership |
| [[2026-06-23_local-repo-audit]] | Local-repo doc-gap audit |
| [[2026-06-24_firebat-kb-git-sync-task]] | Switching firebat KB sync to git-pull from the org repo |

---

**Where to next:** the full topic map is the wiki home **[[index]]**. For "where do I go to learn X?", **[[the-topic-landscape]]**.
