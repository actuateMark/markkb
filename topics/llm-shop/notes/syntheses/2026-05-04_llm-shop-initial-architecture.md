---
title: "LLM Shop — Initial Architecture (2026-05-04)"
type: synthesis
topic: llm-shop
tags: [llm-shop, architecture, adr, ollama, openvino, fastapi, caddy, tailnet, npu-server, watchman]
jira: ""
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
status: draft
outgoing:
  - topics/compute-fleet/notes/entities/host-npu-server.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-04_https-via-tailscale-certs.md
  - topics/llm-shop/notes/concepts/2026-05-04_phase-1-installed.md
  - topics/llm-shop/notes/concepts/2026-05-04_status-dashboard-sketch.md
  - topics/llm-shop/notes/concepts/2026-05-05_ollama-vulkan-broken-on-meteor-lake.md
  - topics/llm-shop/notes/concepts/harness-pattern.md
  - topics/llm-shop/notes/syntheses/2026-05-04_phase-2-day-to-day-usage.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/compute-fleet/notes/entities/host-npu-server.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-04_https-via-tailscale-certs.md
  - topics/llm-shop/notes/concepts/2026-05-04_phase-1-installed.md
  - topics/llm-shop/notes/concepts/2026-05-04_status-dashboard-sketch.md
  - topics/llm-shop/notes/concepts/2026-05-05_ollama-vulkan-broken-on-meteor-lake.md
  - topics/llm-shop/notes/concepts/harness-pattern.md
  - topics/llm-shop/notes/syntheses/2026-05-04_phase-2-day-to-day-usage.md
  - topics/llm-shop/notes/syntheses/2026-05-07_kb-deep-intake-architecture.md
  - topics/llm-shop/notes/syntheses/2026-05-07_long-running-multi-agent-pattern.md
incoming_updated: 2026-05-08
---

# LLM Shop — Initial Architecture (2026-05-04)

ADR-style record of the design decisions made in the 2026-05-04 sketching session. Captures the *why* — install steps live in [[llm-shop/_summary|LLM Shop]] and the §24 workstream checklist in [[mark-todos]].

## Goals

1. Run a suite of local LLMs on the [[host-npu-server|company NPU box]] and expose each as a task-specific HTTP endpoint
2. Be a polite tenant — never starve the existing [[watchman-repo|Watchman]] service
3. Multi-purpose, multi-tenant — usable by Mark, by coworker tooling, and by Claude Code subagents
4. Closes the [[obsidian-clipper-evaluation|KB intake]] follow-up by providing a `/kb-intake` harness

## Non-goals

- **Not a Claude replacement.** Local 7B-32B models drop tools mid-conversation and mis-format JSON. The shop handles *discrete, well-scoped* tasks; agentic loops still go to Claude.
- **Not always-on for everyone.** Resources are capped; coworkers consume on-demand, no SLA.
- **Not internet-exposed.** Tailnet-only. No public listener.

## Decisions

### D1. Two-layer service: harnesses on top of model serving

Each harness is a small FastAPI app (~100-300 LOC) that owns:
- System prompt + few-shot examples
- Tool definitions (e.g. `kb-intake` exposes `fetch_url`, `readability_strip`, `pdf_to_text`)
- Output schema (Pydantic)
- Backing-model selection (per-task; can fall back across models)
- Validation + retry on malformed output

Underneath, two model-serving backends:
- **Ollama** for the bulk of inference (loopback `127.0.0.1:11434`, on-demand model loading, GGUF quantized)
- **OpenVINO + NPU** for always-on small models (1.5B triage, embeddings) that benefit from sub-second response and don't compete with [[watchman-repo|Watchman]] for the iGPU

**Why this split:** harnesses change frequently (new tasks, new prompts); model serving changes rarely. Decoupling makes harness contributions cheap (just fastapi + a model name) and model upgrades global (one config change, all harnesses benefit).

### D2. Caddy reverse proxy on `tailscale0` for HTTPS

Caddy 2 with the [`caddy-tailscale`](https://github.com/tailscale/caddy-tailscale) plugin binds to the tailnet interface only and uses Tailscale-issued Let's Encrypt certs for `npu-server.<tailnet>.ts.net`. Browser-trusted, auto-renewing, never publicly listening. See [[2026-05-04_https-via-tailscale-certs]].

### D3. Resource isolation via systemd cgroups

```
llm-shop.slice
├── MemoryMax=18G               # hard cap; never starves Watchman
├── MemoryHigh=15G              # soft cap; throttles before OOM
├── CPUWeight=50                # Watchman gets default 100, so prioritized
└── (per-harness sub-units inherit the slice's caps)
```

**Why:** [[watchman-repo|Watchman]] has continuous CPU/RAM/iGPU activity (not benchmark-burst). Trying to detect "[[watchman-repo|Watchman]] busy" and dynamically pause is fragile. Trusting the kernel scheduler to share fairly under cgroup constraints is simpler and works.

A *fallback* hook (read [[watchman-repo|Watchman]] benchmark scripts from `~/actuate-watchman/`, `pgrep` for them, route to CPU-only when matched) is documented as a Phase-2 enhancement if real-world testing shows iGPU contention.

### D4. iGPU on-demand, NPU always-on

| Workload | Hardware | Why |
|---|---|---|
| Always-on triage / embeddings | NPU (`/dev/accel/accel0`) | Separate silicon from iGPU — never competes with [[watchman-repo|Watchman]] |
| Main coding model | iGPU (`xe` driver) | 14B+ models need iGPU compute. Loaded on-demand, evicted after `OLLAMA_KEEP_ALIVE=10m` |
| Heavy batch inference | iGPU | 32B model for "give me the smartest answer, I'll wait" tasks |
| CPU fallback | 16C of 155H | Used when iGPU contention detected |

### D5. Multi-tenant auth: bearer tokens at the harness layer, tailnet ACL outside

Two-layer auth:
1. **Tailnet ACL** (outer) — only devices tagged `tag:llm-shop-user` can reach the host on port 443
2. **Bearer token** (inner) — per-user / per-team scope, used by the harness for quotas, request logs, and cost attribution

For now (single user, sketch phase): single shared token. Multi-user issuance becomes a real project once 2+ coworkers actively consume the shop.

### D6. Observability: NDJSON request logs + small status dashboard

Every harness logs one NDJSON line per request to `~/llm-shop/logs/requests-<date>.ndjson`:

```json
{"ts":"2026-05-04T10:23:14Z","harness":"kb-intake","model":"llama-3.1-8b","user":"mark","tokens_in":1240,"tokens_out":380,"latency_ms":4218,"status":"ok"}
```

A static HTML dashboard at `https://npu-server.<tailnet>.ts.net/` shows uptime, RAM, loaded models, recent request rates, and [[watchman-repo|Watchman]] activity. See [[2026-05-04_status-dashboard-sketch]].

### D7. Federation via Tailscale tags

Coworker boxes are discovered through `tailscale status --json` filtered by `tag:llm-shop`. Each shop publishes its harness inventory at `/catalog`. A future `/federated-catalog` aggregates across the fleet. **Not built now** — the plumbing is documented so future-shop-runners follow the same pattern.

### D8. Foothold: `~/llm-shop/` only

Everything we install lives in `~/llm-shop/` on the host. No system-wide writes (except the unavoidable `tailscale` install). User-mode Python venv, user-mode systemd units, Ollama models in `~/llm-shop/models/`. Uninstall is `systemctl --user disable llm-shop-* && rm -rf ~/llm-shop ~/.config/systemd/user/llm-shop-*`. Nothing in `~/actuate-watchman/`, `~/intel/`, `~/venvs/`, or `~/model_cache/` is touched.

### D9. Build harness pattern first, model selection second

We commit to **two harnesses (`code-delegate`, `kb-intake`)** as the proving pattern. They cover the two axes of the use case:
- `code-delegate`: tool-use + structured output + iGPU model + warm
- `kb-intake`: web fetch + readability + classification + write-side workflow

If both work end-to-end, the pattern scales. If they don't, the architecture has an issue — find it before building the long tail.

### D10. Hot-swap is a hard requirement → hybrid Ollama (iGPU) + OpenVINO (NPU)

**Locked 2026-05-04 after a re-evaluation pass.** Earlier draft of D10 deferred model selection. The hot-swap requirement collapses the choice space:

- **iGPU side: Ollama.** Of the four candidate runtimes (Ollama, llama.cpp+SYCL, IPEX-LLM, OpenVINO Model Server), only Ollama and OVMS have native multi-model hot-swap. Ollama wins on ergonomics: GGUF catalog (no per-model conversion), `OLLAMA_MAX_LOADED_MODELS=N` + `OLLAMA_KEEP_ALIVE=10m` give us LRU-evict for free, model name in the request body switches between models. OVMS is enterprise-grade but each model needs OV-IR conversion — too heavy for a fast-iterating shop.
- **NPU side: OpenVINO genai.** The NPU is *separate silicon* from the iGPU; running a small model there has zero contention with [[watchman-repo|Watchman]] or with Ollama's iGPU work. OpenVINO is the only real path to NPU compute. One model (Qwen2.5-Coder-1.5B INT4) lives there always-on for sub-second triage / embeddings.

**Perf trade-off accepted.** Ollama is ~30% slower on Intel iGPU than IPEX-LLM (which uses Intel oneAPI directly). For Qwen2.5-Coder-14B Q4_K_M that's roughly 10-15 tok/s vs 20-30 tok/s. Both are fine for "delegate a coding task," neither is fit for "real-time IDE completion." The hot-swap UX wins.

**Migration is not a one-way door.** Each harness calls a URL+model. If perf becomes the bottleneck, the iGPU layer can be replaced with llama.cpp+SYCL (multi-server pattern) or IPEX-LLM without changing harness code. Just URL points elsewhere.

#### iGPU model catalog (Ollama, in `~/llm-shop/models/`)

| Slot | Model | Q4 size | Use |
|---|---|---|---|
| Default coding | `qwen2.5-coder:14b-instruct` | ~9 GB | `/code-delegate` |
| MoE A/B | `deepseek-coder-v2:16b` | ~9 GB | `/code-review` (multi-file context) |
| Slow + smart | `qwen2.5-coder:32b-instruct` | ~20 GB | `/code-batch` (queue-only, overnight quality) |
| Mid | `qwen2.5-coder:7b-instruct` | ~4.5 GB | `/pr-summarize` |
| Generalist | `llama3.1:8b` | ~5 GB | `/kb-intake` |
| Triage GGUF (optional, fallback for NPU) | `qwen2.5-coder:1.5b` | ~1.2 GB | fallback if NPU unavailable |

#### NPU model catalog (OpenVINO genai, in `~/llm-shop/models-ov/`)

| Slot | Model | Format | Use |
|---|---|---|---|
| Always-on triage | `qwen2.5-coder-1.5b-int4-ov` | OV-IR INT4 | `/code-explain`, `/triage-router` |
| Embeddings (later) | `bge-large-en-v1.5` or `nomic-embed-text` | OV-IR | `/embeddings` for code-search / RAG |

#### Hot-swap configuration

```
OLLAMA_MAX_LOADED_MODELS=2    # tune by RAM headroom
OLLAMA_KEEP_ALIVE=10m         # warm models stay 10 min after last use
OLLAMA_HOST=127.0.0.1:11434   # loopback only (Caddy proxy comes later)
OLLAMA_MODELS=~/llm-shop/models
```

RAM budget under steady state with `MAX_LOADED_MODELS=2`:
- NPU (OpenVINO): always 1.2 GB
- Ollama iGPU (peak 2 models loaded): up to ~14-18 GB
- [[watchman-repo|Watchman]]: ~10 GB
- System: ~2 GB
- **Total peak: ~28-31 GB** on a 30 GB box. Tight when 32B is loaded; can swap at startup. Adjust `MAX_LOADED_MODELS=1` for batch jobs.

## Alternatives considered (rejected)

| Alternative | Why rejected |
|---|---|
| **vLLM as the only serving layer** | Always-loaded model = wastes RAM when idle. Ollama's auto-evict is better fit for "many models, mostly idle." |
| **Docker Compose** for harnesses | Adds setup overhead. systemd `--user` is simpler for solo / small-team start. Migrate later if multiple coworkers contribute. |
| **No harness layer; expose Ollama directly** | Loses task-specific prompts, output schemas, tool definitions. Each caller would re-implement. |
| **LangChain / CrewAI / Letta** | Heavyweight. Each harness is ~150 LOC of FastAPI; a framework would 10x the dependency surface. |
| **Internal CA + step-ca** | More setup. Tailscale-issued LE certs are zero-config. |
| **Always-loaded models on iGPU** | Defeats GPU-on-demand discipline. [[watchman-repo|Watchman]] would compete continuously. |
| **Detecting "[[watchman-repo|Watchman]] benchmarking" via repo state** | [[watchman-repo|Watchman]] is continuous service, not benchmark-burst. cgroup CPUWeight handles this naturally. (Pgrep fallback documented as Phase-2 enhancement.) |

## Open questions (deferred to next session)

1. Tailnet auth key — Mark to acquire from Tailscale admin console
2. Sudo password coordination — needed for Tailscale install + cert issuance
3. Caddy + caddy-tailscale plugin: does the tailnet ACL allow the cert issuance flow? (test once on tailnet)
4. NPU model conversion path — OpenVINO IR via `optimum-intel`? Or direct `intel/neural-compressor`? Confirm during install.
5. Watchman-busy fallback hook: implement Phase-1 (CPU-only) or skip until contention is observed?

## Related

- [[host-npu-server]] — the host running the shop
- [[harness-pattern]] — how to build a harness
- [[2026-05-04_https-via-tailscale-certs]] — TLS strategy
- [[2026-05-04_status-dashboard-sketch]] — visibility frontend
- [[obsidian-clipper-evaluation]] — KB intake use case (flagship harness)
- [[mark-todos]] — §24 workstream tracking
