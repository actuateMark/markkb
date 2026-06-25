---
title: "LLM Shop — model-routed /api/proxy/chat + source-control sync (2026-05-06)"
type: concept
topic: llm-shop
tags: [llm-shop, proxy, sycl, model-routing, playground, source-control, phase-2e]
created: 2026-05-06
updated: 2026-05-06
author: kb-bot
incoming:
  - home/operations/2026-06-22_npu-server-llm-shop-runbook.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-05_phase-2-next-steps.md
  - topics/personal-notes/notes/daily/2026-05-06.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-25
---

# LLM Shop — model-routed `/api/proxy/chat` + source-control sync

Two-part enhancement to the dashboard's chat proxy:

1. **Proxy now routes by model name** instead of an explicit `backend` field. Caller picks a model; the server picks the upstream (`:8200` SYCL container, `:8090` NPU harness, `:11434` Ollama) and translates the protocol.
2. **First source-control checkpoint** for `~/llm-shop/` — the entire deployed tree is now mirrored at `local_network_scripts/files/llm-shop/`. Future edits flow laptop → git → npu-server.

## Why

Previously `/api/proxy/chat` knew about Ollama and the NPU harness. The SYCL container on `:8200` (added 2026-05-05; see [[2026-05-05_ollama-vulkan-broken-on-meteor-lake]]) was reachable directly via OpenAI-compat but **not from the playground** — the dashboard's only client. So the iGPU-accelerated model was effectively invisible to the in-shop UI.

The pasted Phase-2 follow-ups list flagged this:

> Rewrite /api/proxy/chat to route by model name → right port (14b-instruct-sycl → :8200, 1.5b → :11434, etc.)

Combined with the simultaneous "we should also have the actual files in git" realization — staging at `/tmp/llm-shop-staging/` was ephemeral, and the deployed tree on npu-server was the only durable copy — both got addressed in one session.

## Routing table

Centralized in `harnesses/_status/server.py`:

```python
SYCL_PORTS = {
    "qwen2.5-coder:14b-instruct-sycl": 8200,
    "qwen2.5-coder:7b-instruct-sycl": 8201,    # placeholder — service unit not yet shipped
    "llama3.1:8b-sycl": 8202,                  # placeholder — service unit not yet shipped
}
NPU_PORT = 8090
OLLAMA_PORT = 11434

def _route_model(model: str) -> tuple[str, str]:
    if model in SYCL_PORTS:
        return ("sycl", f"http://127.0.0.1:{SYCL_PORTS[model]}")
    if "int4-ov" in model or model.startswith("tinyllama"):
        return ("npu", f"http://127.0.0.1:{NPU_PORT}")
    return ("ollama", f"http://127.0.0.1:{OLLAMA_PORT}")
```

The 7b/8b entries are pre-wired so the next session can ship the service units without touching the proxy. Adding a new SYCL model = one row in `SYCL_PORTS` + one new systemd unit.

A new `GET /api/proxy/routes` endpoint exposes this table (sans logic) so the playground UI doesn't carry a duplicate routing table client-side. Schema:

```json
{
  "sycl_ports": {"qwen2.5-coder:14b-instruct-sycl": 8200, ...},
  "npu_port": 8090,
  "ollama_port": 11434
}
```

## Wire format

Request schema simplified — `backend` field removed:

```json
{ "model": "qwen2.5-coder:14b-instruct-sycl",
  "messages": [{"role":"user","content":"..."}],
  "max_tokens": 512 }
```

Response is unchanged: NDJSON over HTTP body, one of `{token: ...}`, `{done: true, ...}`, `{error: ...}`. The server normalizes three different upstream protocols into this single wire format:

| Upstream | Protocol | Adapter |
|---|---|---|
| Ollama `/api/chat` | NDJSON, one JSON object per line | passthrough — extract `message.content` per chunk, `done` from final chunk |
| llama.cpp+SYCL `/v1/chat/completions` | OpenAI SSE (`data: {...}\n\n`) | `_stream_sycl` — strip `data:` prefix, drop `[DONE]` sentinel, extract `choices[0].delta.content` per chunk; pull `predicted_per_second` from final stats chunk |
| NPU `/api/generate` | one-shot JSON (no streaming) | `_stream_npu` — flatten messages into a `[SYSTEM]/[USER]/[ASSISTANT]` prompt, emit response as one big token |

`predicted_per_second` from the SYCL stream's `timings` block bubbles up to the playground stats line ("done — 5 tok · 6.5s · 0.8 tok/s · sycl (server: 3.8 tok/s)"), making the LPDDR5x bandwidth ceiling visible to the user.

## Playground UI changes

`dashboard/playground.html`:
- Backend dropdown removed
- Model dropdown is grouped: `<optgroup label="iGPU (SYCL) | NPU | CPU (Ollama)">`
- Sub-label under selector shows route hint (`→ SYCL container :8200 (iGPU, ~3-7 tok/s)`)

`dashboard/playground.js`:
- Pulls `/api/proxy/routes` on load; uses it for client-side group/route lookup
- Sends `{model, messages, max_tokens}` (no backend field)
- Surfaces server-reported `predicted_per_second` in the post-completion stats line

## Smoke tests (deployed, all via `:8080/api/proxy/chat`)

| Route | Model | Wall time | Result |
|---|---|---|---|
| ollama | `qwen2.5-coder:1.5b` | 2.0s | "ack" ✓ |
| sycl | `qwen2.5-coder:14b-instruct-sycl` | 5.5s | "ack" + 5.46 tok/s server ✓ |
| npu | `tinyllama-1.1b-int4-ov` | 2.6s | response ✓ |
| sycl streaming | 14b-sycl listing 3 colors | 6.5s | tokens emitted individually (`Red`, `\n`, `Blue`, `\n`, `Green`) ✓ |

Token-by-token streaming proven on SYCL (5 separate token events for the colors test) — confirms the SSE→NDJSON adapter is wire-correct.

## Source-control sync (Phase B)

`/home/mork/work/local_network_scripts/files/llm-shop/` now mirrors the deployed `~/llm-shop/` tree on npu-server. 28 files copied:

```
files/llm-shop/
├── README.md
├── pyproject.toml
├── pi-models.json                            # ~/.pi/agent/models.json snapshot
├── bin/{install.sh,install-ollama.sh,install-openvino.sh,pull-models.sh,probe-npu-models.sh}
├── harnesses/
│   ├── _status/server.py                     # the file edited today
│   ├── _npu/{__init__.py, server.py}
│   ├── code_delegate/{__init__.py, server.py}
│   └── kb_intake/{__init__.py, server.py}
├── dashboard/{index,playground,catalog,peers}.html
├── dashboard/{playground,app}.js
├── dashboard/style.css
└── systemd/llm-shop-{status,ollama,npu,code-delegate,kb-intake,pull-models,sycl-14b}.service
```

Pre-sync verification: every file in `/tmp/llm-shop-staging/` was diffed against `actuate@npu-server:~/llm-shop/` — all matched. Staging was a faithful copy, so the source-of-truth move is loss-less. Excluded from sync: `.venv/`, `models/`, `models-ov/`, `uv.lock` (machine-specific build artifacts), `dashboard/server.py` (stale duplicate of `harnesses/_status/server.py` from an earlier deployment iteration; the systemd unit imports from `harnesses._status.server:app`).

Future deploy convention: edit `local_network_scripts/files/llm-shop/...`, scp the changed file(s) to `actuate@npu-server.tail9b2a4e.ts.net:~/llm-shop/...`, restart the relevant `systemctl --user` unit. No automated `rsync -a --delete` script yet — single-file scp is fine while the surface is small.

## What's NOT done (carries forward)

- `llm-shop-sycl-7b.service` (port 8201, qwen2.5-coder:7b-instruct gguf) and `llm-shop-sycl-8b.service` (port 8202, llama3.1:8b gguf) — proxy ports already reserved; need the actual systemd units + model gguf paths. Mutual exclusion via `Conflicts=` on the unit so only one runs at a time (single iGPU).
- Phase 2E status page UX polish (warm-up button, model live state, NDJSON log viewer, iGPU/NPU util banner).
- IPEX-LLM evaluation as a faster alternative to llama.cpp+SYCL.
- `eval_count` is `null` on SYCL `done` events — llama.cpp's stats chunk shape doesn't always carry `usage.completion_tokens` where I look for it. `predicted_per_second` works; cosmetic.

## Cross-references

- [[knowledgebase/topics/billing/_summary|llm-shop/_summary]] — topic summary (refresh status row)
- [[2026-05-04_phase-1-installed]] — Phase 1 install record
- [[2026-05-04_phase-2-day-to-day-usage]] — Phase 2 design ADR (multi-page dashboard, IDE integration)
- [[2026-05-05_ollama-vulkan-broken-on-meteor-lake]] — why we have a SYCL container in the first place
- [[2026-05-05_phase-2-next-steps]] — the menu this work picked from
- [[host-npu-server]] — the host
- [[mark-todos]] §24 — workstream tracker
