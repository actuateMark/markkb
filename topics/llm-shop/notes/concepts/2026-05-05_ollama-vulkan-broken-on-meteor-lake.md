---
title: "Ollama 0.23 Vulkan broken on Intel Meteor Lake iGPU — diagnosis + fix"
type: concept
topic: llm-shop
tags: [llm-shop, ollama, vulkan, intel, meteor-lake, npu-server, gotcha, runtime]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
outgoing:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-06_model-routed-proxy.md
  - topics/llm-shop/notes/syntheses/2026-05-05_using-the-llm-shop.md
incoming:
  - topics/actuate-platform/notes/concepts/2026-06-22_npu-server-llm-shop-runbook.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-06_model-routed-proxy.md
  - topics/llm-shop/notes/syntheses/2026-05-05_using-the-llm-shop.md
  - topics/llm-shop/notes/syntheses/2026-05-07_kb-deep-intake-architecture.md
  - topics/llm-shop/notes/syntheses/2026-05-07_overnight-batch-pattern.md
incoming_updated: 2026-06-24
---

# Ollama 0.23 Vulkan broken on Intel Meteor Lake iGPU

The `OLLAMA_VULKAN=1` flag enables Ollama's experimental Vulkan iGPU path on Intel hardware. On the [[host-npu-server|`npu-server`]] (Intel Core Ultra 7 155H, Arc Xe-LPG iGPU), this path **produces garbage tokens** — verified across qwen2.5-coder 1.5b/7b/14b/32b and llama3.1:8b 2026-05-05.

## Symptoms

When `OLLAMA_VULKAN=1`:

- Model loads to iGPU successfully (`/api/ps` reports `size_vram > 0`, journal logs `offloaded N/N layers to GPU`)
- Inference completes in plausible time (seconds, not minutes)
- **Output is nonsense tokens.** Examples observed:
  - 1.5B: `"..\\..\\..\\..\\..\\..\nThe time has moved.\n```\n"`
  - 7B: `" liquid containing about the general Pell\\'\\ For all\ndouble\naP re or other of you you or an of."`
  - 14B: `"0000000000000000000000000000000"`

Pi clients see this as "no response" because the streaming output is junk text.

## Cause (probable)

Ollama 0.23's Vulkan backend is marked experimental in Ollama's own startup log: `experimental Vulkan support disabled. To enable, set OLLAMA_VULKAN=1`. The experimental Vulkan kernels appear to have **numerical-precision or quantization-mismatch issues** on Intel Meteor Lake's Arc Xe-LPG iGPU — output values are corrupted before token sampling.

Not specific to one model family or quantization (Q4_K_M failed across all sizes). Not a memory issue (we observed it under both 14G and 18G cgroup caps). Not driver-only (the `xe` driver loads cleanly; `intel_gpu_top` reports normal state).

## Default behavior (without OLLAMA_VULKAN=1)

Ollama falls back to **pure CPU inference**. This is correct but slow. Measured 2026-05-05:

| Model | Cold load | "Say hello" warm | Realistic interactive | Realistic batch |
|---|---|---|---|---|
| qwen2.5-coder:1.5b | ~5s | ~2s | ✓ daily driver | ✓ |
| qwen2.5-coder:7b-instruct | ~15s | ~8-15s | ✓ tolerable | ✓ |
| qwen2.5-coder:14b-instruct | ~60s | ~30-60s for short, 2-5min for normal | ⚠ slow | ✓ |
| qwen2.5-coder:32b-instruct | ~3min | ~5-15min | ✗ too slow | ✓ overnight only |
| deepseek-coder-v2:16b | ~30s | ~20-40s | ⚠ slow | ✓ |
| llama3.1:8b | ~15s | ~10-20s | ✓ tolerable | ✓ |

CPU only is the **correct stopgap**. Pi + Continue + Aider all work fine; just slower than the iGPU-accelerated story we'd planned.

## Practical recommendations (interim)

- **Default model in Pi for daily driver: `qwen2.5-coder:7b-instruct`**, not 14B. 7B on 16C CPU is genuinely usable interactively (~8-15s for short answers); 14B isn't.
- For "I'll wait for quality" tasks: 14B still works, just batch-only. `pi -p "..."` with the 14B is fine if you accept 30-60s per response.
- **Don't bother with 32B until we migrate the runtime.** Pure-CPU 32B is overnight territory.
- **NPU TinyLlama-1.1B harness on `:8090` is unaffected** (different runtime — OpenVINO genai). Still sub-second for what it does.

## Migration paths (next session)

To get real iGPU acceleration on Meteor Lake, three options:

### Option B — llama.cpp with SYCL backend

Build llama.cpp from source with `LLAMA_SYCL=ON`. Intel SYCL/oneAPI is the Intel-blessed parallel framework; the SYCL backend in llama.cpp targets Intel iGPUs natively. Expected throughput: ~10-20 tok/s on 14B (rough estimate based on community reports — needs measurement).

Trade-off: lose Ollama's hot-swap UX. Each model = one `llama-server` process on its own port. Manage multiple processes manually OR write a thin router. GGUF format unchanged so the existing model files in `~/llm-shop/models/` work directly.

### Option C — IPEX-LLM (Intel-native)

Intel's purpose-built LLM runtime. Best Intel iGPU performance. Expected throughput: ~20-30 tok/s on 14B (measured by Intel for similar HW). Provides an OpenAI-compatible HTTP server via `ipex-llm[serving]`.

Trade-off: heavier deps (PyTorch + Intel oneAPI), different model format (HuggingFace native + Intel quantization, not GGUF). One-time conversion per model.

### Option D — Pin Ollama to an older version

Ollama 0.4-0.6 had a `LLAMA_CUDA` / non-experimental GPU offload path that may work on Intel via OpenCL. **Untested.** Has its own limitations.

## Recommendation for next session

**Try llama.cpp+SYCL first** as the simplest perf upgrade — keeps GGUF, reuses our existing model files, just swaps the runtime. Run alongside Ollama (different ports), gradually migrate harnesses to point at it.

If SYCL also has precision issues on Meteor Lake (possible — same hardware), fall back to IPEX-LLM. The harness contract (URL + model name) doesn't change; only the upstream URL.

## Workaround DEPLOYED 2026-05-05 — llama.cpp+SYCL via Docker

llama.cpp's SYCL backend produces **correct output** on Meteor Lake's iGPU (verified — no precision issues, unlike Ollama's experimental Vulkan path). Deployed end-to-end this same session.

### Docker image

`ghcr.io/ggml-org/llama.cpp:server-intel` — official llama.cpp project's Intel-SYCL build, ships with Intel Level Zero / oneAPI runtime baked in. The host already has `intel-level-zero-gpu` installed ([[watchman-repo|Watchman]] uses it) so `--device /dev/dri` is enough; no extra deps.

### Single iGPU container approach

Only ONE llama.cpp+SYCL container at a time on this hardware: the iGPU's available VRAM (after [[watchman-repo|Watchman]]) is ~5-9 GB depending on [[watchman-repo|Watchman]]'s current load, which fits one 7B-14B Q4 model with KV cache. Running 7B and 14B simultaneously OOMs the iGPU.

Pattern: one systemd unit per swappable model, only one enabled at a time. Currently shipping 14B as the default daily-driver iGPU model. Swap by `systemctl --user disable --now llm-shop-sycl-14b && systemctl --user enable --now llm-shop-sycl-7b`.

### systemd `--user` Docker quirk

`systemd --user` instances do NOT inherit the user's supplementary groups (specifically `docker`). So `ExecStart=/usr/bin/docker run …` fails with `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`. Workaround: wrap in `sg docker -c '…'`:

```ini
ExecStart=/usr/bin/sg docker -c '/usr/bin/docker run --rm --name %N --device /dev/dri ...'
```

`sg <group> -c <cmd>` re-execs the command with the named group active. The user is already a member of `docker`, so no password prompt.

### Measured perf (warm)

| Model | Container | iGPU VRAM | Cold load | tok/s (warm gen) |
|---|---|---|---|---|
| qwen2.5-coder:7b-instruct (Q4_K_M, c=8192) | `ghcr.io/ggml-org/llama.cpp:server-intel` | ~4.6 GiB | ~50s | ~6 tok/s |
| qwen2.5-coder:14b-instruct (Q4_K_M, c=4096) | same | ~9 GiB | ~70s | ~1.5 tok/s |

14B on iGPU is slower than 7B per-token because (a) the model is 2x bigger, (b) iGPU VRAM bandwidth is the bottleneck on Meteor Lake (LPDDR5x shared with system, not dedicated GDDR), (c) [[watchman-repo|Watchman]] shares the same iGPU memory pool. Expect 14B to remain in the 1-2 tok/s range; for 5+ tok/s on a model that big you'd need IPEX-LLM (Intel-native) or different hardware.

For interactive Pi use: 14B at 1.5 tok/s gives ~30s for a 50-token answer, ~2min for 200 tokens. Tolerable for "delegate a code task" but not for streaming chat.

### Migration of harnesses to SYCL endpoint

- `code-delegate` (`:8100`) — env updated: `OLLAMA_URL=http://127.0.0.1:8200`, `CODE_DELEGATE_MODEL=qwen2.5-coder:14b-instruct-sycl`. Health probe now uses `/v1/models` (works for both Ollama and llama.cpp).
- `kb-todo-research` (laptop CLI) — defaults updated: `LLM_SHOP_BASE=http://npu-server.tail9b2a4e.ts.net:8200`, `LLM_SHOP_MODEL=qwen2.5-coder:14b-instruct-sycl`.
- `kb-intake` (`:8110`) — kept on Ollama-CPU (`llama3.1:8b`); summary work is bulk overnight, CPU is fine. Switch when an 8B SYCL container is added.
- Status server `/api/proxy/chat` — still hits Ollama; will route per-model in a future polish pass.

### Open follow-ups

- [ ] Add a SYCL container per model (7b, 8b, 14b, 32b) under separate systemd units, only one enabled at a time. Document the swap procedure.
- [ ] Make `/api/proxy/chat` model-aware (route by model name to the right port).
- [ ] Try IPEX-LLM as a fastpath for 14B/32B perf — should beat llama.cpp+SYCL on Intel hardware. Bigger setup cost; deferred.
- [ ] Once 32B SYCL is up, set `LLM_SHOP_REVIEW_MODEL=qwen2.5-coder:32b-instruct-sycl` for kb-todo-research's review pass.

## See also

- [[2026-05-05_using-the-llm-shop]] — user-facing how-to, updated with SYCL as the iGPU path
- [[host-npu-server]] — hardware

## Configuration as of 2026-05-05

`~/llm-shop/systemd/llm-shop-ollama.service`:

```ini
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=%h/llm-shop/models"
Environment="OLLAMA_MAX_LOADED_MODELS=2"
Environment="OLLAMA_KEEP_ALIVE=10m"
Environment="OLLAMA_CONTEXT_LENGTH=16384"
# Environment="OLLAMA_VULKAN=1"  # DISABLED — produces garbage on Meteor Lake iGPU
MemoryMax=18G
MemoryHigh=15G
```

The `OLLAMA_VULKAN=1` line is intentionally commented out with a warning. Re-enable only after a future Ollama release confirms Meteor Lake support, OR if you're testing it specifically.

## Cross-references

- [[host-npu-server]] — Hardware specs (Intel Meteor Lake)
- [[2026-05-04_phase-1-installed]] — Original install notes (we believed iGPU was working then; turns out we were misled by /api/ps reporting size_vram > 0 without checking output correctness)
- [[2026-05-05_using-the-llm-shop]] — User-facing how-to (now updated with realistic CPU-side latency)
- [[2026-05-04_llm-shop-initial-architecture]] — Phase 2 architecture; D10 Ollama choice was based on assumed iGPU acceleration via Vulkan. Re-evaluate D10 with this constraint in mind.
