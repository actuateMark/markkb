---
title: "LLM Shop — Phase 1 Installed (2026-05-04)"
type: concept
topic: llm-shop
tags: [llm-shop, phase-1, install-record, ollama, openvino, npu, hot-swap, measurements]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
outgoing:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-05_first-real-tasks-experiments.md
  - topics/llm-shop/notes/concepts/2026-05-05_ollama-vulkan-broken-on-meteor-lake.md
  - topics/llm-shop/notes/concepts/2026-05-05_phase-2-next-steps.md
  - topics/llm-shop/notes/syntheses/2026-05-04_phase-2-day-to-day-usage.md
  - topics/llm-shop/notes/syntheses/2026-05-05_using-the-llm-shop.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/actuate-platform/notes/concepts/2026-06-22_npu-server-llm-shop-runbook.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-05_first-real-tasks-experiments.md
  - topics/llm-shop/notes/concepts/2026-05-05_ollama-vulkan-broken-on-meteor-lake.md
  - topics/llm-shop/notes/concepts/2026-05-05_phase-2-next-steps.md
  - topics/llm-shop/notes/concepts/2026-05-06_model-routed-proxy.md
  - topics/llm-shop/notes/syntheses/2026-05-04_phase-2-day-to-day-usage.md
  - topics/llm-shop/notes/syntheses/2026-05-05_using-the-llm-shop.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-24
---

# LLM Shop — Phase 1 Installed (2026-05-04)

What actually got built and measured during the 2026-05-04 install session. Captures the deltas vs the design ([[2026-05-04_llm-shop-initial-architecture|architecture ADR]]) — specifically what worked, what surprised us, what we punted to Phase 2.

## What's running

| Service | Port (loopback / tailnet) | Backing | Status |
|---|---|---|---|
| `llm-shop-status` | `:8080` (0.0.0.0, tailnet-reachable) | FastAPI + uv venv, `MemoryMax=512M` | up |
| `llm-shop-ollama` | `:11434` (loopback) | Ollama 0.23.0 user-mode at `~/llm-shop/bin/ollama`, `MemoryMax=14G`, `MAX_LOADED_MODELS=2`, `KEEP_ALIVE=10m` | up |
| `llm-shop-pull-models` | (one-shot) | Sequential `ollama pull` for 6 models | running in background; 3/6 done at session end |
| `llm-shop-npu` | `:8090` (0.0.0.0, tailnet-reachable) | OpenVINO genai pipeline pinned to `NPU` device, `MemoryMax=3G` | up |

All three serve via systemd `--user` units in `~/.config/systemd/user/llm-shop-*`. Uninstall is `systemctl --user disable --now llm-shop-* && rm -rf ~/llm-shop ~/.config/systemd/user/llm-shop-*`.

## Models on disk

iGPU side (Ollama, in `~/llm-shop/models/`):

| Model | Size | Status |
|---|---|---|
| `qwen2.5-coder:1.5b` | 986 MB | pulled |
| `qwen2.5-coder:7b-instruct` | 4.7 GB | pulled |
| `qwen2.5-coder:14b-instruct` | 9.0 GB | pulled |
| `qwen2.5-coder:32b-instruct` | 19 GB | pulled |
| `llama3.1:8b` | 4.9 GB | pulled (2026-05-05 — see "Tag-name correction" below) |
| `deepseek-coder-v2:16b` | 8.9 GB | pulled (2026-05-05 — see "Tag-name correction" below) |

NPU side (OpenVINO IR, in `~/llm-shop/models-ov/`):

| Model | Format | Status |
|---|---|---|
| `tinyllama-1.1b-int4-ov` (`OpenVINO/TinyLlama-1.1B-Chat-v1.0-int4-ov`) | OV-IR INT4 (Intel-published) | loaded on NPU; serves `/api/generate` |
| `qwen-1.5b` (self-converted `Qwen/Qwen2.5-Coder-1.5B-Instruct`) | OV-IR INT4 | converted but NPU-incompatible (see below); kept as CPU fallback |

## Measured performance (hot-swap proof, 2026-05-04)

Hot-swap test, three Ollama models in sequence with `MAX_LOADED_MODELS=2`:

| # | Model | Cold? | Latency for 1-token reply | Warm set after |
|---|---|---|---|---|
| 1 | `qwen2.5-coder:1.5b` | yes | 2.36 s (load + 1 tok) | `[1.5b]` |
| 2 | `qwen2.5-coder:7b-instruct` | yes | 10.94 s (load + 1 tok, 1.5b stays warm) | `[7b, 1.5b]` |
| 3 | `qwen2.5-coder:14b-instruct` | yes | 28.60 s (load + 1 tok, **1.5b evicted as LRU**) | `[14b, 7b]` |

LRU eviction confirmed working. Cold-load times match expectations for Ollama+Vulkan on Arc Xe-LPG (~9 GB shuffled across PCIe + tokenizer setup).

NPU performance (TinyLlama-1.1B-int4-ov, 30 tokens):

| Test | Latency | Throughput |
|---|---|---|
| First generate (after model warm) | 3.62 s | ~8.3 tok/s |

This is on the actual Intel NPU 3720, not CPU fallback. CPU side-by-side for the same model would likely run faster (~30-50 tok/s) — the NPU is slow per-token but **uses zero iGPU time**, so it's pure win when other workloads want the iGPU.

Steady-state RAM at end of session: ~14 GB used ([[watchman-repo|Watchman]] ~10 GB + OpenVINO/NPU harness ~1.5 GB + status service + system).

## Surprises + gotchas

### The `/tmp` permissions bug
First `apt update` on `npu-server` failed catastrophically because `/tmp` was `drwxr-xr-x` instead of the standard `drwxrwxrwt` (1777). apt drops privileges to `_apt` for downloads, which then can't write GPG temp files. **Fixed with `sudo chmod 1777 /tmp`**, but the same issue probably hits other users of the box. Already noted in [[host-npu-server]] and §24 learnings.

### Ollama download URL stale
`https://ollama.com/download/ollama-linux-amd64.tgz` returns 404 — Ollama renamed assets to `.tar.zst` in v0.23 but didn't update their CDN alias. Fix: pin to `https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tar.zst` and use `tar --zstd -xf`. Captured in `bin/install-ollama.sh`.

### Self-converted Qwen2.5-Coder-1.5B failed NPU compile
We exported `Qwen/Qwen2.5-Coder-1.5B-Instruct` to OV-IR INT4 successfully via `optimum-cli export openvino`. Loading on NPU triggered a `vpux-compiler` abort:

```
Channels count of input tensor shape and filter shape must be the same: 0 != 12
"IE.Convolution"(...) : (tensor<1x0x1x1xf16>, tensor<1x12x1x1xf16>) -> ( ??? )
```

The `0` dimension is a dynamic-shape op the NPU's compiler can't resolve. The crash is fatal — Python `try/except` doesn't catch it because it's a SIGABRT in the C++ runtime.

**Workaround:** switched to `OpenVINO/TinyLlama-1.1B-Chat-v1.0-int4-ov` from HuggingFace (Intel-published, NPU-tested). Loaded on NPU first try.

**Open question for Phase 2:** can we re-export Qwen with `--disable-stateful` or static-shape config to make it NPU-friendly? Or are NPU-tested OV-IR variants of Qwen-Coder available? Tracked in §24 Phase 2 design questions.

### NPU first-load is slow
`ov_genai.LLMPipeline(path, "NPU")` takes ~5 sec the first time after a service restart — it's compiling the model graph for the NPU. Subsequent loads use the cache. Means systemd `sleep` between `restart` and `curl /api/health` needs to be ≥5 sec, not 2-3.

### Bandwidth contention paused us
Mid-install, `uv sync` for the OpenVINO deps timed out against pypi.org while Ollama was actively pulling the 50 GB model set. Sequential isn't enough — we had to **stop the pulls service**, run uv sync, **then resume**. The pulls are systemd-driven so this is just `systemctl --user stop` + `... start` again. Future installs should sync deps before kicking off the pull marathon.

## Status page enhancements added this session

- **NPU harness card** — model name, device (NPU vs CPU vs degraded), warm state. Probes `http://localhost:8090/api/health` per refresh.
- **Ollama "loaded" vs "installed" split** — "loaded" hits `/api/ps` (warm models); "installed" hits `/api/tags` (everything in `OLLAMA_MODELS` dir). User asked for the installed list since hot-swap means most models are cold most of the time.
- **API specs card** — links to `/docs` (Swagger), `/redoc`, `/openapi.json` for both the status service (port 8080) and NPU harness (port 8090). The NPU harness is bound to `0.0.0.0:8090` so its docs are reachable from tailnet peers.

## Outstanding Phase 1 work — closed 2026-05-05

- ✅ Ollama pulls for `qwen2.5-coder:32b-instruct` — completed
- ⚠️ Ollama pulls for `llama3.1:8b-instruct` and `deepseek-coder-v2:16b-lite-instruct` — **failed** (wrong tag names; see "Tag-name correction" below). Re-pulled with corrected tags 2026-05-05.

### Tag-name correction (2026-05-05)

The original `pull-models.sh` had wrong tags. Ollama's library doesn't always expose an `-instruct` suffix — some model families use the bare size tag as the instruct variant.

| Tried (failed) | Correct tag | Notes |
|---|---|---|
| `llama3.1:8b-instruct` | `llama3.1:8b` | The bare 8B IS the instruct model |
| `deepseek-coder-v2:16b-lite-instruct` | `deepseek-coder-v2:16b` | `:latest` is an alias to same digest |

`bin/pull-models.sh` updated with corrected tags and a comment explaining the convention. Future re-pulls work as-is.

## Phase 2 next steps

Sketched in [[2026-05-04_phase-2-day-to-day-usage|Phase 2 design note]]:
- Multi-page dashboard with nav (status / playground / catalog / peers)
- Inline chat/query UI hitting the harnesses directly from the browser
- Claude Code skill + subagent integration patterns
- External IDE tool integration (Continue.dev, Aider, Cursor — and clarify "pi.dev")

## Cross-references

- [[2026-05-04_llm-shop-initial-architecture]] — original ADR; D10 locked Ollama+OpenVINO hybrid before this session
- [[harness-pattern]] — per-harness routing table
- [[host-npu-server]] — host entity (now `on-tailnet`)
- [[2026-05-04_status-dashboard-sketch]] — status-page sketch (delta: now also serves at `/docs` + has installed-models panel)
- [[2026-05-04_https-via-tailscale-certs]] — currently deferred (admin needed)
- [[mark-todos]] — §24 workstream
