---
title: "home/ — start here (orientation packet)"
type: index
tags: [home, orientation, guides, moc, navigation]
updated: 2026-06-25
author: kb-bot
---

# `home/` — start here

**Read just this folder and you should be oriented to the whole knowledge base and the team's setup.** That's the job of `home/`: a self-contained orientation packet. The *detail* for any subsystem lives out in `topics/` (mapped from [[index]]) — `home/` is the hub that tells you what exists and where to go.

**New here?** Read **§1** top-to-bottom (≈20 min) and you'll know what Actuate is, how it's built, how to navigate the KB, and how to start. **§2–§4** are reference: pull them up when you're installing, operating, or picking up an owned system — not required reading to feel oriented.

**Folder layout:** the two must-reads ([[what-is-actuate]], [[the-topic-landscape]]) + this README sit at the top level; everything else is grouped into `orientation/` · `operations/` · `setup/` · `offboarding/` (mirroring §1–§4 below).

---

## §1 · Orientation — *evergreen, read first*
| Note | What you'll learn |
|---|---|
| [[what-is-actuate]] | What the product is + the data-flow spine (frames in → detect → alerts out) |
| [[system-architecture]] | The layers end-to-end (ingest → connector → inference → dispatch → fleet → observability) + how code ships |
| [[the-topic-landscape]] | The ~40 topics grouped into 9 domains + **"I want to learn X → go here"** |
| [[how-to-use-this-kb]] | Note types, the retrieval ladder, the `obsidian` CLI + `/kb-ask` & `/kb-lookup`, conventions |
| [[first-steps]] | Day one: where's the code (repos), dev setup, who owns what, where work is tracked |

## §2 · Set up your own instance — *reference*
| Note | For |
|---|---|
| [[DEVBOX-BOOTSTRAP]] | Stand up the full KB + Claude-Code workflow on a fresh machine |
| [[SETUP]] | Just the KB (Obsidian vault + Quartz) |

## §3 · Operational footprint — *what the team runs (reference)*
| Note | What it covers |
|---|---|
| [[2026-06-22_actuate-footprint-handoff]] | **"What runs where"** — firebat mini-PC, the dashboard, the llm-shop, the KB — and who owns what |
| [[2026-06-22_firebat-operations-runbook]] | Deep team-handoff runbook for the firebat automation host (timers, creds, recovery) |
| [[2026-06-22_dashboard-signals-catalog]] | Every operational-dashboard signal: what it means + its baseline |
| [[2026-06-22_npu-server-llm-shop-runbook]] | The local-LLM box (SYCL/NPU/Ollama serving) — operate + rebuild |
| [[2026-06-24_secrets-refresh-runbook]] | Rotating/refreshing every credential the automation depends on |
| [[2026-06-22_dead-mans-checklist]] | **If the automation breaks:** symptom → cause → fix |

## §4 · Offboarding handoff — *time-bound (Mark → team, June 2026)*
History/reference once complete, but the handoffs double as the ownership docs for the systems in §3. Start at [[offboarding-overview]].
| Note | What it is |
|---|---|
| [[offboarding-overview]] | The offboarding summary / index |
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
