---
title: "Using the LLM Shop — Day-to-Day Reference"
type: synthesis
topic: llm-shop
tags: [llm-shop, pi-coding-agent, ollama, openai-compat, how-to, quick-reference, claude-code-subagent]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
outgoing:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-05_ollama-vulkan-broken-on-meteor-lake.md
  - topics/personal-notes/notes/daily/2026-05-05.md
incoming:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-05_ollama-vulkan-broken-on-meteor-lake.md
  - topics/llm-shop/notes/syntheses/2026-05-07_kb-deep-intake-architecture.md
  - topics/llm-shop/notes/syntheses/2026-05-07_long-running-multi-agent-pattern.md
  - topics/llm-shop/notes/syntheses/2026-05-07_overnight-batch-pattern.md
  - topics/personal-notes/notes/daily/2026-05-05.md
incoming_updated: 2026-05-08
---

# Using the LLM Shop — Day-to-Day Reference

A quick reference for how to actually USE the [[llm-shop/_summary|LLM shop]] day-to-day. The shop is the suite of locally-served LLMs running on [[host-npu-server]], reachable across the company tailnet at `npu-server.tail9b2a4e.ts.net`. **All consumption is free** (local compute, $0/token).


> **STATUS 2026-05-05 (evening): iGPU runtime is llama.cpp+SYCL on `:8200`, NOT Ollama+Vulkan.**
> Ollama's experimental Vulkan path produces garbage tokens on Meteor Lake (verified, see [[2026-05-05_ollama-vulkan-broken-on-meteor-lake]]). Ollama on `:11434` runs CPU-only as a fallback for models without a SYCL container.
> 
> **Default daily driver in Pi: `llm-shop-sycl` provider, model `qwen2.5-coder:14b-instruct-sycl`** at `http://npu-server.tail9b2a4e.ts.net:8200/v1`. Roughly 1.5 tok/s warm — slow per-token but real iGPU acceleration with correct output. Single iGPU container at a time (only ~5-9 GiB iGPU VRAM free after [[watchman-repo|Watchman]]); swap models by `systemctl --user disable/enable llm-shop-sycl-<size>.service`.
> 
> Harnesses point at `:8200` for Qwen-Coder work: `code-delegate` (`:8100`) and `kb-todo-research` (laptop CLI). `kb-intake` (`:8110`) still uses Ollama-CPU + `llama3.1:8b` because that model isn't on SYCL yet.

## Five surfaces

| # | How to call | When to use |
|---|---|---|
| 1 | **Browser**: `http://npu-server.tail9b2a4e.ts.net:8080/playground` | "Let me try a model on a specific prompt right now" — pick model, type, get streaming response. Try this first. |
| 2 | **Pi (terminal)**: `pi -p "..."` or `pi` interactive — see [[pi-dev-integration]] | One-shot questions while terminal-driven. Strong for quick code chats. Already configured: `~/.pi/agent/models.json` provider `llm-shop`. |
| 3 | **`~/bin/kb-intake <url>`** | URL → drafted source note in `_research-inbox/`. The article-into-KB pipeline (closes §23). |
| 4 | **`~/bin/kb-todo-research --target <X>`** | Broken-wikilink target → drafted stub in `_research-inbox/`. The KB-stub-from-context pipeline (Phase 2F). |
| 5 | **Claude Code subagent**: invoke `llm-shop-delegate` via the `Agent` tool | Inside a Claude Code session when you want to delegate a discrete code task without spending Anthropic tokens on grunt work. |

## Which model for which task

| Task shape | Model | Backend | Latency (warm) |
|---|---|---|---|
| "What does this regex do?" / quick triage / classify | `tinyllama-1.1b-int4-ov` | NPU (`:8090`) | sub-second to ~5s |
| Boilerplate, refactor, test-gen, code review | `qwen2.5-coder:14b-instruct` (default) | Ollama iGPU (`:11434`) | 30s-2min |
| Multi-file reasoning / harder review | `deepseek-coder-v2:16b` (MoE) | Ollama iGPU | 30s-2min |
| "Slow + smart, give me the best answer overnight" | `qwen2.5-coder:32b-instruct` | Ollama iGPU | 5-15min |
| URL summarization / topic classification / general prose | `llama3.1:8b` | Ollama iGPU | 30s-2min |
| Mid-size code chat | `qwen2.5-coder:7b-instruct` | Ollama iGPU | 15-60s |

Cold-load adds 5-90s the first time after a model has been evicted from RAM. To skip the cold-load when you know you're about to hit a model: `curl -X POST http://npu-server.tail9b2a4e.ts.net:8080/api/warm-up -d '{"model":"qwen2.5-coder:14b-instruct"}'`.

## Pi recipes

```bash
# One-shot — print mode
pi -p "explain this regex: ^[a-z]+(?:-[a-z0-9]+)*$" --provider llm-shop --model qwen2.5-coder:14b-instruct

# Pipe a file in
cat path/to/file.py | pi -p "review this code; flag bugs" --provider llm-shop --model qwen2.5-coder:14b-instruct

# Interactive — switch providers/models with /provider and /model
pi
# > /provider llm-shop
# > /model qwen2.5-coder:32b-instruct
# > <ask anything>

# JSON mode for scripting
pi -p "summarize: $(cat README.md)" --provider llm-shop --mode json | jq
```

## OpenAI-compat consumers (Continue, Aider, Cursor, openai SDK)

Base URL: `http://npu-server.tail9b2a4e.ts.net:11434/v1`. API key: any non-empty string (use `"ollama"`). Full config snippets on the [`/catalog`](http://npu-server.tail9b2a4e.ts.net:8080/catalog) page.

```python
from openai import OpenAI
client = OpenAI(base_url="http://npu-server.tail9b2a4e.ts.net:11434/v1", api_key="ollama")
resp = client.chat.completions.create(
    model="qwen2.5-coder:14b-instruct",
    messages=[{"role": "user", "content": "hi"}],
)
```

## Harnesses (structured task endpoints)

The dashboard's `/catalog` page lists curl examples for each. Quick reference:

```bash
# Code-delegate (qwen-14b with task_type-aware system prompt)
curl -sS -X POST http://npu-server.tail9b2a4e.ts.net:8100/code-delegate \
  -H 'Content-Type: application/json' \
  -d '{"task":"refactor this", "context":"<code>", "task_type":"refactor"}'

# kb-intake (URL → drafted source note)
curl -sS -X POST http://npu-server.tail9b2a4e.ts.net:8110/kb-intake \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://...", "topics":["topic-a","topic-b"], "hint_topic":"topic-a"}'

# NPU TinyLlama (always-warm small model)
curl -sS -X POST http://npu-server.tail9b2a4e.ts.net:8090/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"def fib(n):", "max_new_tokens":64}'
```

## Lessons from first real use

(See [[2026-05-05_first-real-tasks-experiments]] for full detail.)

- **Qwen-14B is "delegated-but-reviewed" quality.** Produces structurally correct output, but **flips directionality on technical claims** it doesn't have ground truth for (entropy direction got inverted in the first BlurHandler draft). Rule: pass actual code into the prompt as context for class-named targets — `kb-todo-research` does this automatically via `--no-code` to disable.
- **Code-grounded prompts are *tighter and faster*.** Counterintuitive: when the model has source-of-truth code, it hedges less. v2 of BlurHandler was 1981 chars in 130s. v1 (no code) was 2897 chars in 167s. Less hedging = more confident, shorter, more accurate.
- **Models always wrap output in markdown fences** even when system-prompt forbids it. Strip them in your post-processor — don't argue with the model.
- **Frontmatter often missing closing `---`.** Both `kb-intake` and `kb-todo-research` have a `repair_frontmatter()` post-processor.

## Common workflows

### "I'm reading and want to save this article into the KB"

```bash
~/bin/kb-intake https://example.com/article --hint <topic-slug> --anchors-from <topic-slug>
# → wrote: topics/<topic>/_research-inbox/<date>-<slug>.md
# Review the draft in Obsidian, polish, promote to topics/<topic>/sources/.
```

### "I want a quick stub for a class I see referenced in many notes"

```bash
~/bin/kb-todo-scan | jq '.[0:5]'                       # see what's worth researching
~/bin/kb-todo-research --target BlurHandler            # draft via code-delegate
~/bin/kb-todo-research --top 3 --review                # batch with second-pass review (slow)
```

### "Quick code question while in a terminal"

```bash
pi -p "what's the difference between asyncio.gather and asyncio.wait" --provider llm-shop --model qwen2.5-coder:14b-instruct
```

### "Inside a Claude Code session, delegate a refactor without spending tokens"

Invoke the `llm-shop-delegate` subagent via the `Agent` tool. It routes between NPU triage and 14B code-delegate based on task complexity. See `~/.claude/agents/llm-shop-delegate.md` for the full routing rubric.

## Status + observability

- Dashboard: [`http://npu-server.tail9b2a4e.ts.net:8080/`](http://npu-server.tail9b2a4e.ts.net:8080/)
- Logs: `ssh npu-server "journalctl --user -u llm-shop-* -f"`
- Health: `curl http://npu-server.tail9b2a4e.ts.net:8080/api/status | jq`

## Cost discipline

- Compute is free, but iGPU is shared with the [Watchman test service](http://host-npu-server) on the same box. The shop is RAM-capped (`MemoryMax=18G` aggregate) and CPU-yielding (`CPUWeight=50`) so it never starves [[watchman-repo|Watchman]]. Don't pin huge workloads to the shop during [[watchman-repo|Watchman]] benchmark windows; you'll just both throttle.
- Latency budget per request is real. **Don't agentic-loop on local models** — they're not Claude. Single-shot tasks with structured output are the sweet spot.

## Cross-references

- [[llm-shop/_summary]] — service overview
- [[2026-05-04_phase-1-installed]] — what's running
- [[2026-05-04_phase-2-day-to-day-usage]] — Phase 2 design ADR
- [[2026-05-05_first-real-tasks-experiments]] — Qwen-14B in action, lessons learned
- [[pi-dev-integration]] — Pi specifically
- [[harness-pattern]] — how harnesses are structured
- [[host-npu-server]] — the host
