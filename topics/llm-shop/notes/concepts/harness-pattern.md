---
title: "Harness Pattern"
type: concept
topic: llm-shop
tags: [llm-shop, harness, fastapi, contribution-pattern, subagent]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
outgoing:
  - topics/engineering-process/notes/concepts/2026-05-05_open-questions-inbox-idea.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-04_phase-1-installed.md
  - topics/llm-shop/notes/concepts/2026-05-04_status-dashboard-sketch.md
  - topics/llm-shop/notes/concepts/2026-05-05_first-real-tasks-experiments.md
  - topics/llm-shop/notes/concepts/2026-05-05_phase-2-next-steps.md
  - topics/llm-shop/notes/syntheses/2026-05-04_llm-shop-initial-architecture.md
  - topics/llm-shop/notes/syntheses/2026-05-04_phase-2-day-to-day-usage.md
  - topics/llm-shop/notes/syntheses/2026-05-05_using-the-llm-shop.md
incoming:
  - home/operations/2026-06-22_npu-server-llm-shop-runbook.md
  - topics/engineering-process/notes/concepts/2026-05-05_open-questions-inbox-idea.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-04_phase-1-installed.md
  - topics/llm-shop/notes/concepts/2026-05-04_status-dashboard-sketch.md
  - topics/llm-shop/notes/concepts/2026-05-05_first-real-tasks-experiments.md
  - topics/llm-shop/notes/concepts/2026-05-05_phase-2-next-steps.md
  - topics/llm-shop/notes/syntheses/2026-05-04_llm-shop-initial-architecture.md
  - topics/llm-shop/notes/syntheses/2026-05-04_phase-2-day-to-day-usage.md
  - topics/llm-shop/notes/syntheses/2026-05-05_using-the-llm-shop.md
incoming_updated: 2026-06-25
---

# Harness Pattern

A **harness** is the [[llm-shop/_summary|LLM shop]]'s unit of contribution. It wraps one task ("complete this code", "summarize this URL", "review this diff") with the prompt engineering, tool definitions, output schema, and model selection that task needs. Callers hit a harness's HTTP endpoint and get structured JSON; they don't touch the model directly.

## Anatomy

Every harness is a directory under `~/llm-shop/harnesses/<name>/`:

```
harnesses/code-delegate/
├── server.py            # FastAPI app — ~100-300 LOC
├── system-prompt.md     # opinionated; checked in
├── few-shot.md          # 2-5 worked examples (optional)
├── tools.json           # tool definitions if the model uses them
├── schema.py            # Pydantic input/output models
├── tests/               # task-specific eval set
│   ├── golden.jsonl     # input → expected-output pairs
│   └── run.py           # runs the harness against goldens, reports pass rate
└── README.md            # one-line purpose, API contract, owner
```

Plus one shared helper module they all import:

```
shared/
├── ollama_client.py     # thin async wrapper around Ollama HTTP API
├── auth.py              # bearer token validation
├── logging.py           # NDJSON request log
└── observability.py     # /metrics, /health endpoints
```

## Lifecycle of a request

```
1. Caller: POST /code-delegate { "prompt": "...", "context": {...} }
2. Caddy (tailnet) → forwards to FastAPI on loopback
3. Harness:
   a. Validate bearer token (shared/auth.py)
   b. Validate input against Pydantic schema (rejects malformed)
   c. Compose final prompt (system-prompt.md + few-shot.md + caller input)
   d. Pick backing model (default: qwen2.5-coder:14b-instruct)
   e. Call shared/ollama_client.py
   f. Validate output against output schema; retry once if invalid
   g. Log NDJSON line (request, model, tokens, latency, status)
   h. Return structured JSON
```

Total round-trip target: warm model = 5-30 sec depending on task; cold model = +5-10 sec for first load.

## Naming convention

`<verb>-<object>` or `<domain>-<task>`:

| Good | Reason |
|---|---|
| `code-delegate` | clear scope: "delegate code-related task" |
| `kb-intake` | clear domain: "ingest into KB" |
| `pr-summarize` | clear: "summarize a PR" |
| `code-explain` | clear: "explain this code" |

| Avoid | Reason |
|---|---|
| `assistant` | too vague; no shape constraint |
| `chat` | no task; encourages agentic loops we want to avoid |
| `gpt` / `claude` / `llama` | model-named (couples harness to specific model) |

## Output schema discipline

**Every harness defines a Pydantic output schema.** The model returns JSON that conforms — and if it doesn't, we retry once with a "respond ONLY with valid JSON matching this schema" reminder, then 500.

This is the most important thing about the pattern. It means:
- Callers parse strongly-typed responses, not raw model output
- Harness owners change models without breaking callers
- Eval sets test the *schema* fidelity, not "did the prose feel right"

Example for `kb-intake`:

```python
class KBIntakeOutput(BaseModel):
    proposed_topic: str = Field(..., description="Best-fit existing topic slug")
    proposed_title: str
    summary: str = Field(..., max_length=2000)
    proposed_tags: list[str] = Field(..., max_items=10)
    proposed_path: str  # e.g. "topics/X/sources/2026-05-04-my-source.md"
    proposed_concept_stubs: list[str]  # zero or more concept slugs to create
    confidence: float = Field(..., ge=0.0, le=1.0)
```

The harness's `server.py` calls Ollama with `format="json"` and the schema serialized into the prompt; validates the response with Pydantic; retries once on validation failure.

## Eval set discipline

Every harness has `tests/golden.jsonl` — a small set of `{input, expected_output_shape}` pairs. `tests/run.py` runs the harness against them and reports pass rate.

This is **not a benchmark** — pass rate isn't optimized for. It's a **regression check**. When you swap models or update the system prompt, run the eval. If pass rate drops noticeably, decide whether the change is worth it.

Goldens are checked in. Coworkers contribute new ones with a PR. The harness is "done" enough to ship at ~10 goldens; gold-standard at ~50.

## Contribution flow

To add a new harness:

1. Pick a verb-object name
2. `cp -r harnesses/_template harnesses/<your-name>`
3. Edit `server.py`, `system-prompt.md`, `schema.py`
4. Add 5+ goldens to `tests/golden.jsonl`, run `python tests/run.py`
5. Add a systemd unit at `~/.config/systemd/user/llm-shop-<your-name>.service` (template provided)
6. Add a Caddy route line for `/<your-name>`
7. `systemctl --user daemon-reload && systemctl --user enable --now llm-shop-<your-name>`
8. Verify `https://npu-server.<tailnet>.ts.net/<your-name>/health` returns OK
9. Add an entry to `/catalog`'s harness list (config-driven)
10. Update [[llm-shop/_summary]] to mention the new harness

A harness is owned by whoever wrote it. They commit their goldens, monitor their NDJSON log, and decide on model upgrades.

## What harnesses do NOT do

- **Long agentic loops.** If a task needs >3 model turns, it's a Claude problem, not a shop problem.
- **Persistent state.** Harnesses are stateless request-handlers. State (conversation history, RAG index) lives in the caller or in shared infra (a vector DB, etc.) — not in the harness.
- **Cross-harness orchestration.** A "router" harness (`/triage-router`) can decide which other harness to recommend, but it doesn't *call* them — the original caller does.
- **Tools the model can't actually use.** Most local models <14B do tool-use poorly. Harnesses that need tools should pick a model with strong tool-use training (Qwen2.5-Coder, DSV2-Lite) and validate every tool call output.

## Per-harness routing table (locked 2026-05-04)

| Harness | Backend | Model | Why |
|---|---|---|---|
| `code-explain` | OpenVINO NPU | `qwen2.5-coder-1.5b-int4-ov` | Sub-second; "what does this do" doesn't need 14B |
| `triage-router` | OpenVINO NPU | `qwen2.5-coder-1.5b-int4-ov` | Picks which harness handles a task |
| `embeddings` | OpenVINO NPU (or CPU) | `bge-large-en-v1.5` (later) | RAG / code-search vectors |
| `code-delegate` | Ollama iGPU | `qwen2.5-coder:14b-instruct` | Default coding workhorse |
| `code-review` | Ollama iGPU | `deepseek-coder-v2:16b` | MoE handles longer context, multi-file reasoning |
| `code-batch` | Ollama iGPU | `qwen2.5-coder:32b-instruct` | Slow but Sonnet-tier; queue-only |
| `pr-summarize` | Ollama iGPU | `qwen2.5-coder:7b-instruct` | Diff → description; 7B plenty |
| `kb-intake` | Ollama iGPU | `llama3.1:8b` | General summarizer + topic classifier |

The model name in each harness's `server.py` should be **a config constant**, not hardcoded across the request handlers — so swapping a harness's backing model is a one-line config change. Caller never sees the model name.

## Initial harness backlog (status as of 2026-05-04)

| Harness | Status | Notes |
|---|---|---|
| `_status` | **Phase 1 — DONE** | Status page service (Phase 1 first deliverable; not a model harness — see also [[2026-05-04_status-dashboard-sketch]]) |
| `code-delegate` | Phase 1 | First proving harness with a model — Ollama backend |
| `kb-intake` | Phase 1 | Closes [[obsidian-clipper-evaluation]] — Ollama backend |
| `code-explain` | Phase 2 | NPU sub-second response |
| `pr-summarize` | Phase 2 | git-diff context |
| `code-review` | Phase 2 | Multi-file context, MoE model |
| `code-batch` | Phase 2 | Slow + smart 32B for overnight quality runs |
| `triage-router` | Phase 3 | Recommend which harness fits a task |
| `embeddings` | Phase 3 | Code search / RAG |
| `kb-relink-helper` | Phase 3 | Tag/link proposals for `/kb-relink` |
| `doc-extract` | Phase 3 | Q&A over PDFs |

Phase 1 = first proven pattern + flagship use cases, Phase 2 = team-useful, Phase 3 = power-user.

## Related

- [[llm-shop/_summary]] — service overview
- [[2026-05-04_llm-shop-initial-architecture]] — design ADR
- [[host-npu-server]] — the host
