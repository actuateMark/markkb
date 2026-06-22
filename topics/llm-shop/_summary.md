---
title: "LLM Shop"
type: summary
topic: llm-shop
tags: [llm-shop, local-models, ollama, openvino, harnesses, subagent, tailnet]
created: 2026-05-04
updated: 2026-05-06
author: kb-bot
status: scoping
---

# LLM Shop

An internal, Tailnet-only service that exposes a suite of locally-served LLMs as task-specific HTTP endpoints ("harnesses"). Designed to run on company-shared compute (currently planned for [[host-npu-server]]) without disturbing existing tenants. Callers — Claude Code subagents, KB-ingest skills, coworker tooling — hit the right harness for the task and get structured JSON back.

## What lives here

- **[[harness-pattern]]** — what a harness is, how to build one, contribution conventions
- **[[2026-05-04_llm-shop-initial-architecture]]** — architecture decision record (D1-D10)
- **[[2026-05-04_phase-1-installed]]** — Phase 1 install record + measurements + surprises (2026-05-04)
- **[[2026-05-04_phase-2-day-to-day-usage]]** — Phase 2 design: multi-page dashboard, IDE/Pi/etc. integration
- **[[2026-05-04_https-via-tailscale-certs]]** — HTTPS strategy (currently deferred — needs admin)
- **[[2026-05-04_status-dashboard-sketch]]** — original status-page sketch
- **[[pi-dev-integration]]** — Pi Coding Agent (pi.dev) integration via OpenAI-compat
- **[[2026-05-05_first-real-tasks-experiments]]** — first real-task experiments (Qwen-14B writes a FastAPI endpoint) + the broken-wikilink-research-agent direction
- **[[2026-05-05_using-the-llm-shop]]** — user-facing how-to (Pi recipes, OpenAI-compat snippets, harness curl examples, common workflows)
- **[[2026-05-05_ollama-vulkan-broken-on-meteor-lake]]** — Ollama 0.23 Vulkan produces garbage tokens on Meteor Lake iGPU. CPU-only is correct but slow. Migration path: llama.cpp+SYCL or IPEX-LLM.
- **[[2026-05-06_model-routed-proxy]]** — `/api/proxy/chat` rewritten to route by model name (drops `backend` field); SYCL container reachable from playground; first source-control checkpoint of `~/llm-shop/` to `local_network_scripts/files/llm-shop/`.
- **[[2026-05-07_kb-deep-intake-architecture]]** — multi-pass URL → KB-quality markdown pipeline. 5 phases: parser → planner → workers → composer → linker. Design-locked.
- **[[2026-05-07_overnight-batch-pattern]]** — transport plumbing for running pipelines like deep-intake overnight (laptop submits, box runs, laptop pulls).
- **[[2026-05-07_long-running-multi-agent-pattern]]** — generalized planner-worker-composer pattern for the LLM shop. Lessons + decision tree for applying to new problems.

## Why

Three concrete drivers prompted this:

1. **Local code-task delegation.** A subagent that completes boilerplate, refactors functions, writes tests, or summarizes diffs without burning Claude tokens. Useful for "discrete, well-scoped" tasks; not a Claude replacement.
2. **KB intake automation.** The [[obsidian-clipper-evaluation|Obsidian Web Clipper question]] — local-model summarization + topic classification + frontmatter generation closes the ingestion loop without paid LLM tokens. Run overnight on the `_dive-queue.md`.
3. **Coworker amplifier.** Other team members with tailnet boxes can both consume the shop and contribute harnesses. Federation pattern: `tailscale status` finds peer shops; each publishes a `/catalog` endpoint listing its harnesses.

## Architecture in one diagram

```
   Caller (Claude Code subagent / kb-* skill / coworker tool)
                            │
                            │  POST https://npu-server.<tailnet>.ts.net/<harness>
                            │  Authorization: Bearer <token>
                            ▼
   ┌─────────────────────────────────────────────────────────────┐
   │  npu-server  (one box; federation via Tailscale later)       │
   │                                                                │
   │  Caddy (TLS via tailscale cert) → routes by path              │
   │                                                                │
   │  Harness layer (FastAPI services, one per task):              │
   │   /code-delegate     /kb-intake     /code-review              │
   │   /code-explain      /pr-summarize  /doc-extract              │
   │   /triage-router     /catalog       /api/status                │
   │                                                                │
   │  Each harness owns: system prompt + tools + output schema     │
   │  + backing-model selection. Calls into:                        │
   │                                                                │
   │  Model serving layer:                                          │
   │   • Ollama       :11434 (loopback)  → main inference           │
   │   • OpenVINO+NPU                    → always-on small models   │
   │                                                                │
   │  Coexisting tenant: Watchman service (priority, undisturbed)  │
   └─────────────────────────────────────────────────────────────────┘
```

## Status

| Area | State |
|---|---|
| Architecture | Locked — see [[2026-05-04_llm-shop-initial-architecture]] (D10: Ollama+OpenVINO hybrid) |
| Host onboarding | **Done** — `npu-server.tail9b2a4e.ts.net` joined company tailnet 2026-05-04 |
| Status dashboard | **Live** at `http://npu-server.tail9b2a4e.ts.net:8080/` |
| Ollama install | **Done** — v0.23.0 user-mode in `~/llm-shop/bin/`, hot-swap proven, bound `0.0.0.0:11434` for IDE/Pi |
| Ollama model pulls | **Done** — all 6 models on disk (1.5b/7b/14b/32b qwen-coder, llama3.1:8b, deepseek-coder-v2:16b) |
| OpenVINO genai + NPU | **Live** — TinyLlama-1.1B INT4 on NPU, ~8 tok/s |
| Multi-page dashboard | **Done** — Status / Playground / Catalog / Peers tabs, top nav, /api/proxy/chat streaming |
| Model-routed proxy | **Done 2026-05-06** — `/api/proxy/chat` routes by model name (SYCL/NPU/Ollama) with SSE→NDJSON adapter for SYCL container. See [[2026-05-06_model-routed-proxy]]. |
| Source-control checkpoint | **Done 2026-05-06** — `~/llm-shop/` mirrored to `local_network_scripts/files/llm-shop/` (28 files); pi config snapshotted. |
| IDE / Pi integration | **Done** — OpenAI-compat reachable at `http://npu-server.tail9b2a4e.ts.net:11434/v1`. Config snippets on `/catalog` page for Pi, Continue.dev, Aider, Cursor, openai SDK. |
| SYCL 14B service | **Live** on `:8200` — qwen2.5-coder:14b-instruct-sycl, ~3.4 tok/s output / 5.4 tok/s prompt on iGPU |
| SYCL 7B / 8B services | Not started — proxy port reservations exist (8201/8202); need systemd units with `Conflicts=` (single-iGPU mutual exclusion) |
| Self-converted Qwen on NPU | Failed compile (vpux); kept on disk as CPU fallback. See Phase 1 note. |
| HTTPS | Deferred — needs tailnet admin |
| Tailnet tags (`tag:llm-shop` etc.) | Deferred — needs tailnet admin |
| Phase 2 design (multi-page dashboard, IDE integration, Claude Code subagent) | Implemented — see [[2026-05-04_phase-2-day-to-day-usage]] |
| First harness (`code-delegate`) | **Shipped** on `:8100` — task_type-aware system prompts |
| Second harness (`kb-intake`) | **Shipped** 2026-05-05 — `~/bin/kb-intake` CLI (URL → readability → llama3.1:8b → draft to `_research-inbox/`). Closes [[obsidian-clipper-evaluation]]. |
| `llm-shop-delegate` Claude Code subagent | **Shipped** at `~/.claude/agents/` |
| `kb-todo-{scan,research}` agent | **Shipped** at `~/bin/kb-todo-*`, source-controlled |

Tracked as `§24` in [[mark-todos]].

## Phase 1 lessons (captured 2026-05-04)

See [[2026-05-04_phase-1-installed]] for full detail. Key items:
- `/tmp` permissions on `npu-server` were broken (`drwxr-xr-x` instead of `1777`); needed `sudo chmod 1777 /tmp` before any apt operation worked. Likely affects [[watchman-repo|Watchman]] dev too.
- Ollama's `https://ollama.com/download/...` redirect alias is stale (still points at deprecated `.tgz`). Use the GitHub release URL directly with `.tar.zst`.
- Self-quantized Qwen2.5-Coder-1.5B failed NPU compile with a dynamic-shape op error. Intel-published OV-IR variants (`OpenVINO/TinyLlama-1.1B-Chat-v1.0-int4-ov`) loaded on NPU first try.
- NPU first-load takes ~5 seconds (graph compile); subsequent loads use cache.
- Ollama pulls saturate office bandwidth; pause pulls before running `uv sync` for unrelated deps.

## Cross-references

- [[host-npu-server]] — the host
- [[compute-fleet/_summary]] — host catalog
- [[obsidian-clipper-evaluation]] — KB intake use-case driver
- [[engineering-process/_summary]] — three-tier pattern, broader engineering conventions
