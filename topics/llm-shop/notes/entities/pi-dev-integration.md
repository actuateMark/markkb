---
title: "pi.dev (Pi Coding Agent) — local-models integration"
type: entity
topic: llm-shop
tags: [llm-shop, pi-dev, pi-coding-agent, openai-compatible, ide-integration, terminal, models-json]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
incoming:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/syntheses/2026-05-04_phase-2-day-to-day-usage.md
  - topics/llm-shop/notes/syntheses/2026-05-05_using-the-llm-shop.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-06
---

# pi.dev (Pi Coding Agent)

[Pi](https://pi.dev/) is a minimal terminal coding harness by Mario Zechner ([@mariozechner](https://github.com/mariozechner), [`badlogic/pi-mono`](https://github.com/badlogic/pi-mono)). MIT-licensed. Mark has it installed locally on the laptop.

The relevant fact for us: **Pi accepts custom OpenAI-compatible providers via `~/.pi/agent/models.json`**, which means our [[llm-shop/_summary|LLM shop]]'s Ollama (port 11434) is a one-config-block away from being a Pi backend.

## Install reference

| Method | Command |
|---|---|
| curl | `curl -fsSL https://pi.dev/install.sh | sh` |
| npm | `npm install -g @mariozechner/pi-coding-agent` |
| bun / pnpm | `bun add -g @mariozechner/pi-coding-agent` |

## Modes

| Mode | Invocation | Use |
|---|---|---|
| Interactive | `pi` | Terminal REPL |
| Print | `pi -p "<prompt>"` | One-shot, prints answer, exits |
| JSON | `pi -p "..." --mode json` | Streams events as JSON lines (script integration) |
| Pipe | `cat file \| pi -p "summarize"` | Stdin as input |
| RPC / SDK | (per docs) | Programmatic integration |

The print + JSON modes mean Pi is itself harness-able from shell scripts and Claude Code skills — same way we'd shell out to `curl`, but with all of Pi's harness surface (system prompts, tool calling, session state via `AGENTS.md`/`SYSTEM.md`).

## Config: pointing Pi at our local-models shop

Add to `~/.pi/agent/models.json` on the laptop:

```json
{
  "providers": [
    {
      "id": "llm-shop",
      "name": "LLM Shop (npu-server)",
      "type": "openai-compatible",
      "baseUrl": "http://npu-server.tail9b2a4e.ts.net:11434/v1",
      "apiKey": "ollama",
      "models": [
        { "id": "qwen2.5-coder:14b-instruct",         "name": "Qwen 2.5 Coder 14B (default)" },
        { "id": "qwen2.5-coder:7b-instruct",          "name": "Qwen 2.5 Coder 7B" },
        { "id": "qwen2.5-coder:1.5b",                 "name": "Qwen 2.5 Coder 1.5B (fast)" },
        { "id": "qwen2.5-coder:32b-instruct",         "name": "Qwen 2.5 Coder 32B (slow + smart)" },
        { "id": "deepseek-coder-v2:16b","name": "DeepSeek Coder V2 Lite (MoE 16B-A2.4B)" },
        { "id": "llama3.1:8b",               "name": "Llama 3.1 8B (general)" }
      ]
    }
  ]
}
```

Notes:
- `apiKey: "ollama"` — Ollama's OpenAI-compat layer doesn't validate the key; any non-empty string passes
- `baseUrl` requires Ollama to be reachable from the laptop. Currently bound to `127.0.0.1:11434` (loopback). **Phase 2B flips this to `0.0.0.0:11434`** so tailnet peers can reach it.
- Model `id` is the Ollama tag (what `ollama list` shows). When new models are pulled, add an entry; when retired, remove.

## Why this matters

Pi is **not the primary use case** for the shop — Claude Code subagents (`/code-delegate`, `/kb-intake`) are. But:

1. Pi is already on the laptop. Zero new install effort to consume the shop.
2. The OpenAI-compat surface that makes Pi work also makes Continue.dev, Aider, Cursor, and the plain `openai` Python SDK work. Configure once, all consumers benefit.
3. Pi's print/JSON mode + system-prompt support means the shop's models can be invoked from shell scripts as a "smarter cat":
   ```bash
   cat path/to/file.py | pi -p "what does this do" --mode print
   ```
4. For an interactive "I want to chat with Qwen-32B from my terminal" surface, Pi is faster to launch than a full IDE.

## Catalog dashboard surface

The forthcoming `/catalog` page on the dashboard should ship a copy-paste config block for Pi alongside the Continue / Aider / Cursor / `openai` SDK snippets. Mark's first pass at the catalog needs a Pi block; coworkers consuming the shop later get it for free.

## Cross-references

- [[llm-shop/_summary|LLM Shop topic]]
- [[2026-05-04_phase-2-day-to-day-usage|Phase 2 design note]] — pi.dev is one of the listed consumers
- [Pi GitHub repo](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent)
- [Pi homepage](https://pi.dev/)

## Open work

- [ ] Phase 2B: bind Ollama to `0.0.0.0:11434` so the laptop can reach it
- [ ] Add Pi config block to the catalog dashboard page
- [ ] Test `pi -p "..."` against Qwen 14B end-to-end and capture latency notes here
- [ ] Document any quirks Pi exposes (e.g., does it stream Ollama responses correctly? Tool-use compatibility?)
