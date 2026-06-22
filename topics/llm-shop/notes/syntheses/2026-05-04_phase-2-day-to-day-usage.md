---
title: "LLM Shop — Phase 2 Design: day-to-day usage"
type: synthesis
topic: llm-shop
tags: [llm-shop, phase-2, design, dashboard, ide-integration, continue, aider, claude-code, subagent, openai-compat]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
status: sketch
incoming:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-04_phase-1-installed.md
  - topics/llm-shop/notes/concepts/2026-05-05_first-real-tasks-experiments.md
  - topics/llm-shop/notes/concepts/2026-05-05_phase-2-next-steps.md
  - topics/llm-shop/notes/concepts/2026-05-06_model-routed-proxy.md
  - topics/llm-shop/notes/entities/pi-dev-integration.md
  - topics/llm-shop/notes/syntheses/2026-05-05_using-the-llm-shop.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-07
---

# LLM Shop — Phase 2 Design: day-to-day usage

[[2026-05-04_phase-1-installed|Phase 1]] is done — models are running, hot-swap works. **Phase 2's question: how does Mark (and eventually coworkers) actually use this thing day-to-day?** Sketched here before building so we capture all the surfaces and don't paint into a corner.

## The four user surfaces

```
                                     ┌─────────────────────────────────────────┐
                                     │  npu-server.tail9b2a4e.ts.net           │
                                     │   port 8080: dashboard + harness routes │
                                     │   port 8090: NPU harness                │
                                     │   port 11434: Ollama (loopback only)    │
                                     └─────────────────────────────────────────┘
                                                       ▲
        ┌──────────────────────────────────────────────┼────────────────────────────────────┐
        │                              │               │                 │                   │
        ▼                              ▼               ▼                 ▼                   ▼
   ┌─────────┐               ┌──────────────┐    ┌──────────┐     ┌────────────┐     ┌─────────────┐
   │ Browser │               │ Claude Code  │    │ Continue │     │ Aider /    │     │ Coworker    │
   │ (Mark)  │               │ skill / agent│    │ in VSCode│     │ Cursor /   │     │ tooling     │
   │         │               │ subagent     │    │          │     │ pi.dev?    │     │ (federation)│
   └─────────┘               └──────────────┘    └──────────┘     └────────────┘     └─────────────┘
   chat UI,                  POST /code-delegate, OpenAI-compat   OpenAI-compat       /catalog,
   catalog,                  POST /kb-intake,     base_url to     base_url to         /federated-*,
   logs,                     etc. — Python        :11434/v1       :11434/v1           bearer tokens
   peer view                 helper module        (via Caddy)     (via Caddy)
```

Four distinct consumers. The shop should accommodate all four without each one needing bespoke plumbing.

## Surface 1 — Multi-page dashboard with nav

Current state: single-page status view at `/`. Phase 2: add pages, all served from the same FastAPI service with a shared top nav.

### Pages

| Path | Purpose | Data source |
|---|---|---|
| `/` | Status (current page) | `/api/status` polled every 10s |
| `/playground` | Inline chat — pick a model, type, get response | `POST /api/proxy/chat` (forwards to Ollama or NPU) |
| `/catalog` | All harnesses + all models, with curl examples and "best for X" notes | `/api/catalog` (static for now, harness-driven later) |
| `/logs` | Recent NDJSON request log entries | `/api/logs?limit=N&since=T` |
| `/peers` | Federated tailnet peers (when Phase 3 lands) | `/api/peers` |

### Nav layout

Top bar across all pages:

```
┌──────────────────────────────────────────────────────────────────────────┐
│  llm-shop · npu-server                                                    │
│  [Status] [Playground] [Catalog] [Logs] [Peers]   [Swagger ↗] [GitHub ↗] │
└──────────────────────────────────────────────────────────────────────────┘
```

- Active page highlighted
- Right-side: external links (Swagger UI for the API, future repo)
- Mobile: collapse to hamburger; not a priority for solo + couple-coworker use

### Implementation

- Each page is a static HTML file in `~/llm-shop/dashboard/`: `index.html`, `playground.html`, `catalog.html`, `logs.html`, `peers.html`
- Shared `nav.html` partial — included via simple template in the FastAPI route handlers, OR inlined into each page (simpler — JS or server-side templating both work)
- Shared `style.css` and a small `app.js` per page where needed
- FastAPI serves them via `FileResponse`; static assets via `StaticFiles`

No build system, no framework, no SPA. Plain HTML + JS + CSS. Open in any browser, works.

## Surface 2 — Playground page (inline chat)

The "I just want to try this thing" surface. Hit the page, pick a model, type a prompt, see the response stream.

### UX

```
┌─ Playground ────────────────────────────────────────────────────────┐
│ Backend: ◉ Ollama (iGPU)  ○ NPU harness                             │
│ Model:   [qwen2.5-coder:14b-instruct ▼]   ← populated from /api/status │
│                                                                      │
│ System prompt: [optional — empty by default]                        │
│                                                                      │
│ ┌──────────────────────────────────────────────────────────────────┐│
│ │ User: write a python function that ...                          ││
│ └──────────────────────────────────────────────────────────────────┘│
│ [Send]    [Clear]                                                    │
│                                                                      │
│ Response:                                                            │
│ ┌──────────────────────────────────────────────────────────────────┐│
│ │ def function_name():                                             ││
│ │     ...                                                          ││
│ └──────────────────────────────────────────────────────────────────┘│
│                                                                      │
│ Latency: 4.2s · Tokens: 124 · 29.5 tok/s                            │
└──────────────────────────────────────────────────────────────────────┘
```

### Mechanics

- Backend selector toggles between Ollama (most models) and NPU harness (TinyLlama only for now)
- Model dropdown populated dynamically from `/api/status` `ollama_installed` (when Ollama selected) or static (when NPU)
- Send → `POST /api/proxy/chat` (status service proxies to Ollama or NPU)
- Streaming response via SSE so tokens appear as they generate
- Latency + tok/s counter on the right

### Why proxy, not call Ollama directly from browser?

Ollama listens on loopback only — browser can't reach it. The status service is the natural proxy: it's already on the tailnet, it can reach loopback locally, and it can apply auth/rate-limiting per-user when we add those.

## Surface 3 — Catalog page

The "what's here, how do I call it" surface.

### Sections

1. **Harnesses** — each row: name, URL, input schema, output schema, copy-paste curl, link to Swagger UI
2. **Models** — installed Ollama models + NPU model. Per-row: name, size, suggested tasks, "best for X" notes from the [[harness-pattern|harness pattern]], last-used time
3. **OpenAI-compat endpoint** — show the base URL, snippets for popular consumers:
   - `openai` Python SDK config block
   - Continue.dev `config.json` excerpt
   - Aider command-line flags
   - Cursor settings JSON
4. **Tailnet auth** — currently single shared bearer token; per-user tokens come later

### Data driving the catalog

- Static for now: hand-edit `~/llm-shop/dashboard/catalog.html`
- Future: `/api/catalog` returns JSON describing each harness from a registry (`~/llm-shop/harnesses.yaml`) — the dashboard renders from that
- `kb-scribe`-equivalent pattern: each harness contributes its own row when added

## Surface 4 — Claude Code integration

Two patterns, used together:

### A. Direct skill calls

A skill that wants to delegate code work hits the harness URL directly:

```python
# Inside a skill's procedure (Python)
import urllib.request, json
def delegate_code(prompt: str) -> dict:
    req = urllib.request.Request(
        "http://npu-server.tail9b2a4e.ts.net:8080/code-delegate",
        data=json.dumps({"prompt": prompt}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)
```

Skill author writes ~5 lines, gets structured response. No Anthropic API spend.

### B. Subagent wrapper

A new subagent at `~/.claude/agents/llm-shop-delegate.md`:

```yaml
---
name: llm-shop-delegate
description: Delegate a discrete code task (boilerplate, refactor, test gen, summarize diff) to a local model on npu-server. Use when the task is well-scoped and Claude-grade reasoning isn't needed. Saves API tokens.
tools: Bash, Read
model: haiku
---

You delegate the user's code task to a harness on the LLM shop.

Routing:
- "explain this" / "what does this do" → POST :8090/api/generate (NPU TinyLlama, fast)
- "refactor / boilerplate / write tests" → POST :8080/code-delegate (Ollama 14B coding)
- "review this diff" → POST :8080/code-review (Ollama DSV2-Lite, when available)
- "summarize this PR" → POST :8080/pr-summarize (Ollama 7B, when available)

Format the prompt with relevant context, call the harness, validate the response, return to parent. Never agentic-loop on the local model — one shot per task.
```

When parent Claude Code session needs delegation, it invokes the subagent via the Agent tool. The subagent's narrower context handles the formatting/curl/parsing without bloating parent context. This complements `kb-scribe` for write-side; this is for code-task delegation.

### When to use which

- **Direct call**: a skill that already knows exactly which harness it wants. Lightweight.
- **Subagent**: the parent doesn't know which harness fits, OR has many tasks to batch, OR wants the parent context kept lean while structured calls happen.

## Surface 5 — External IDE tool integration

**pi.dev** is [Pi Coding Agent](https://pi.dev/) — a minimal terminal harness by Mario Zechner. MIT-licensed, supports OpenAI-compatible providers via `~/.pi/agent/models.json`. Mark has it installed locally. Full integration detail at [[pi-dev-integration]].

Other candidates we should support (same OpenAI-compat surface):

| Candidate | What it is | Fit |
|---|---|---|
| **Pi (pi.dev)** | Minimal terminal coding harness, MIT, custom OpenAI providers | **Primary consumer** — see [[pi-dev-integration]] |
| **Continue.dev** | Open-source IDE assistant for VSCode + JetBrains. OpenAI-compat or Ollama-direct. | Strong fit |
| **Aider** | Terminal AI pair programmer. OpenAI-compat. | Strong fit |
| **Cursor** | Closed-source AI IDE. OpenAI-compat for "OpenAI compatible" backend. | Works but less open |
| **Codeium / Cody** | OpenAI-compat backends supported with config | Works |
| **Plain `openai` Python SDK** | Direct API calls from scripts | Works |

All of these speak `/v1/chat/completions` (OpenAI-compat). Ollama provides this natively — once we expose it on the tailnet (Phase 2B), every one of them is one config block away from working.

### What we need to expose

Ollama already provides an **OpenAI-compatible endpoint** at `/v1/chat/completions`. Currently bound to `127.0.0.1:11434` (loopback). To make IDEs reach it from the laptop:

**Option A (interim, simplest):** bind Ollama to `0.0.0.0:11434`. Same model as status + NPU harness — tailnet-only via the office firewall. IDEs configure `base_url=http://npu-server.tail9b2a4e.ts.net:11434/v1`.

**Option B (proper):** Caddy reverse proxy on port 8080 routes `/v1/*` → loopback Ollama. Lets us add bearer-token auth at the proxy layer when needed. Same URL as the dashboard, just a different path.

Option A is the 2-minute migration. Option B is the 30-minute one once we want auth.

### Per-IDE config snippets to ship in `/catalog`

**Pi (`~/.pi/agent/models.json`):**

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
        { "id": "qwen2.5-coder:14b-instruct", "name": "Qwen 2.5 Coder 14B" },
        { "id": "qwen2.5-coder:32b-instruct", "name": "Qwen 2.5 Coder 32B (slow + smart)" }
      ]
    }
  ]
}
```

Then: `pi` interactive, `pi -p "<prompt>"` one-shot, `cat file.py | pi -p "summarize" --mode json` scripted.

**Continue.dev (`~/.continue/config.json`):**

```json
{
  "models": [
    {
      "title": "Qwen 14B (npu-server)",
      "provider": "openai",
      "model": "qwen2.5-coder:14b-instruct",
      "apiBase": "http://npu-server.tail9b2a4e.ts.net:11434/v1",
      "apiKey": "ollama"
    }
  ]
}
```

**Aider:**

```bash
aider --openai-api-base http://npu-server.tail9b2a4e.ts.net:11434/v1 \
      --openai-api-key ollama \
      --model qwen2.5-coder:14b-instruct
```

**Cursor:** Settings → Models → "OpenAI Compatible" → Base URL: `http://npu-server.tail9b2a4e.ts.net:11434/v1`, API key: `ollama` (any non-empty value, Ollama doesn't check), Model name: `qwen2.5-coder:14b-instruct`.

**`openai` Python SDK:**

```python
from openai import OpenAI
client = OpenAI(
    base_url="http://npu-server.tail9b2a4e.ts.net:11434/v1",
    api_key="ollama",
)
resp = client.chat.completions.create(
    model="qwen2.5-coder:14b-instruct",
    messages=[{"role": "user", "content": "hi"}],
)
```

The catalog page renders all of these as copy-paste blocks. Drop-in for any user.

## Surface 6 — Coworker federation (Phase 3, not Phase 2)

Out of scope for this design — but the dashboard's `/peers` page needs to exist as a stub now so the routing is right. Empty until other shops come online.

## Open questions

1. ~~What does `pi.dev` refer to?~~ Resolved 2026-05-05 — Pi Coding Agent. See [[pi-dev-integration]].
2. **OpenAI-compat: bind Ollama to 0.0.0.0 or proxy via Caddy?** Recommendation: 0.0.0.0 now (Phase 2B), Caddy proxy when we add auth (Phase 2C+).
3. **Per-user auth tokens — when?** Single shared bearer for now. Per-user when 2+ coworkers actively consume.
4. **Streaming responses in playground — Server-Sent Events or WebSocket?** SSE is simpler; let's default to SSE.
5. **Should the playground default to `/code-delegate` (the harness) or raw `/v1/chat/completions` (Ollama direct)?** Lean: harness, because the harness has the system prompt baked in and outputs structured JSON. Raw chat is for "freeform" mode.
6. **Should we expose Ollama's iGPU memory / NPU usage as graphs?** Phase 2.5 — Grafana-lite via the NDJSON request log + a tiny SVG sparkline lib. Not critical now.

## Phase 2 implementation plan (proposed)

Once user nods on this design + clarifies `pi.dev`:

### Phase 2A — Multi-page + playground (1 session, ~2 hours)
1. Refactor dashboard HTML to share a top-nav partial across pages
2. Add `/playground.html` + `/api/proxy/chat` SSE endpoint
3. Add `/catalog.html` with hand-written content (harness list + IDE snippets)
4. Add `/logs.html` (tail of NDJSON request log)
5. Add `/peers.html` (stub for Phase 3)
6. Update status page to be just the "Status" tab in the new layout

### Phase 2B — IDE / OpenAI-compat exposure (15 min)
1. Bind Ollama to `0.0.0.0:11434` via systemd unit env
2. Add IDE config snippets to catalog page
3. Test `openai` SDK call from laptop, Continue.dev plugin, etc.

### Phase 2C — Claude Code subagent (1 hour)
1. Write `~/.claude/agents/llm-shop-delegate.md` subagent definition
2. Test with a sample delegation from a parent Claude Code session
3. Document in [[harness-pattern]] under "Calling from Claude Code"

### Phase 2D — `code-delegate` and `kb-intake` harnesses (1-2 sessions)
The actual model harnesses we promised in Phase 1 but haven't built yet. Now that the pattern (status + NPU) is proven, follow the same shape: FastAPI service on its own port, Pydantic in/out schema, Ollama backend call, NDJSON log line per request.

## Cross-references

- [[2026-05-04_llm-shop-initial-architecture]] — D2 (Caddy on tailscale interface — currently using port-direct, will move to Caddy in Phase 2B)
- [[2026-05-04_phase-1-installed]] — what's running today
- [[harness-pattern]] — harness template; needs an "external consumer" section added when Phase 2 lands
- [[host-npu-server]] — host entity
- [[obsidian-clipper-evaluation]] (§23) — `kb-intake` harness closes this; sequenced as Phase 2D
- [[mark-todos]] — §24 workstream
