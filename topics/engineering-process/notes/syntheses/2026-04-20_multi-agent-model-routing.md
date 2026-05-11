---
title: "Multi-agent / multi-model routing for KB source research"
type: synthesis
topic: engineering-process
tags: [multi-agent, model-routing, kb-automation, r-and-d, plan]
jira: "ENG-147"
created: 2026-04-20
updated: 2026-04-20
author: kb-bot
outgoing:
  - topics/engineering-process/notes/syntheses/2026-04-21_rd-agent-pilot-learnings.md
  - topics/engineering-process/reading-list.md
  - topics/fleet-architecture/_pilot-2026-04-21-staged.md
  - topics/personal-laptop/notes/concepts/2026-04-27_handoff-rd-autoresearch.md
  - topics/personal-notes/notes/daily/2026-04-20.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/engineering-process/notes/syntheses/2026-04-21_rd-agent-pilot-learnings.md
  - topics/engineering-process/reading-list.md
  - topics/fleet-architecture/_pilot-2026-04-21-staged.md
  - topics/personal-laptop/notes/concepts/2026-04-27_handoff-rd-autoresearch.md
  - topics/personal-notes/notes/daily/2026-04-20.md
  - topics/personal-notes/notes/daily/2026-05-08.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-09
---

# Multi-agent / multi-model routing for KB source research

Claude Code sessions spend substantial tokens on high-volume, low-judgment KB work — `/kb-ingest` digesting raw URLs, `/kb-synthesise` cross-referencing sources, `/repo-scan` enumerating GitHub issues, `/kb-sync` re-reading Confluence. This token drain reduces budget available for actual coding and judgment-heavy synthesis. This note frames the problem, surveys options, and recommends a first pilot.

## Problem

**Token pressure.** Anthropic's Opus and Sonnet quota is finite per day. KB R&D tasks (ingest, summarization, repo enumeration) are token-heavy but judgment-light — they require reading ability more than reasoning. Meanwhile, complex coding tasks (refactors, bug investigation, design synthesis) need the full Claude reasoning power. Today, both run on the same model.

**Offload candidates exist.** Gemini 3.x Pro has long context windows and low cost. Codex excels at code understanding. Self-hosted Ollama offers privacy for sensitive ingest. Each has specific strengths.

**Reference implementation shows the way.** The [openclaw-claude-code](https://github.com/Enderfga/openclaw-claude-code) project wraps multiple coding CLIs (Claude Code, Codex, Gemini, Cursor, custom) behind a unified `ISession` interface, enabling multi-engine sessions with consensus voting, cross-session messaging, and session-level prompt caching maximization.

## What we have today

All six current subagents ([[agents-catalog]]) run on Claude (Haiku, Sonnet, or Opus). They protect the parent context from specific high-volume tasks (NR queries, PR review, KB writes, release monitoring) but still consume Anthropic token budget. The KB skills that spawn them — `/kb-ingest`, `/kb-synthesise`, `/repo-scan`, `/kb-sync` — are the budget killers: they read widely, summarize loosely, and rarely need multi-turn reasoning.

## What we want

Offload token-heavy, judgment-light tasks to cheaper models while keeping Claude in the orchestrator role for:
- Final synthesis quality gates
- Multi-turn coding work
- Cross-service architecture decisions
- Configuration and secret handling

This preserves Opus/Sonnet budget for high-ROI work while unblocking more daily source research.

## Reference implementation — openclaw

The [openclaw-claude-code](https://github.com/Enderfga/openclaw-claude-code) project is worth studying for its features:

- **Multi-engine sessions** — unified `ISession` interface wraps Claude, OpenAI Codex, Gemini, Cursor, and custom engines. Code runs once; engine swaps at instantiation.
- **Multi-agent council** — multiple agents work in parallel on the same task with git worktree isolation, consensus voting, and two-phase (plan → execute) protocol.
- **Session inbox** — cross-session messaging; idle agents pick up messages immediately, busy agents queue them.
- **Ultraplan** — dedicated Opus planning session (~30 min explore → detailed plan) and **Ultrareview** (5–20 parallel bug-hunter agents in parallel).
- **OpenAI-compatible API** — drop-in for existing tooling; maximizes Anthropic prompt caching via stateful sessions.

Not all features are needed here, but the engine-abstraction and consensus patterns are directly applicable.

## Integration options

Three paths to implement multi-model routing:

### Option 1: Subagent-level routing

New agent definitions in `~/.claude/agents/` that shell out to a non-Claude model via `google-genai` SDK (Gemini), OpenAI SDK (Codex), or Ollama HTTP. Light on infrastructure, tight with Claude Code.

**Pros:** Minimal new surface area. Can be done today. Lives inside existing agent framework.

**Cons:** Breaks prompt-cache affinity on multi-turn work. Requires normalizing output from each model back to KB-shaped notes.

### Option 2: Adopt openclaw wholesale

Install the npm plugin, use its MCP tools (`claude_session_start`, `council_start`, `ultraplan_start`). Gets session inbox + council + ultraplan/ultrareview "for free".

**Pros:** Most feature-complete. Session inbox enables cross-session messaging. Council voting for high-stakes decisions.

**Cons:** New infrastructure dependency. npm plugin surface area. Requires npm availability in the session. Overkill for first pilot.

### Option 3: Hybrid (recommended for first pilot)

New `/kb-delegate` skill that shells to Gemini 3.x Pro for specific tasks, returns normalized Markdown with frontmatter. Claude-side `kb-scribe` agent finalizes. Minimum new surface, maximum portability.

**Pros:** Isolates delegation logic. Easy to test one task end-to-end. Can graduate to other models later without code rework. Preserves Claude context for orchestration.

**Cons:** Requires a Gemini API key in env. Output contract needs design upfront.

## Recommended first pilot

**Approach:** Option 3. Delegate one `/kb-ingest` run end-to-end to Gemini 3.x Pro with a structured output schema.

**Scope:** Pick a single, self-contained ingest task (e.g., summarize a Confluence article or GitHub issue URL). Run it twice — once via Claude (baseline), once via Gemini. Compare output quality, token spend, latency.

**Success criteria:**
- Gemini output is semantically equivalent to Claude (no hallucinations, factually correct).
- Gemini token spend is <40% of Claude.
- Latency is acceptable (<5 min round-trip).
- Output can be normalized to KB frontmatter format without manual rework.

**Next step:** If pilot succeeds, expand to `/kb-ingest` + `/repo-scan` tasks; design the output contract formally.

## Open questions

- **Which KB skills are offload candidates?** Inventory `/kb-ingest`, `/kb-synthesise`, `/kb-auto`, `/repo-scan`, `/kb-sync` and classify each by Claude-dependency (judgment-heavy vs. summarization-heavy).
- **Which models to route where?** Gemini 3.x Pro for long-context ingest; Codex for code-context tasks; self-hosted Ollama for privacy-sensitive ingest.
- **Output contract:** Markdown-with-frontmatter, structured JSON intermediate, or freeform-then-normalized?
- **Quality gate:** Spot-audit by Claude? Sample-N-per-topic? Self-score confidence?
- **Cost baseline:** How do we measure current token spend on KB ops before offloading begins?
- **Prompt caching strategy:** Anthropic's 5-min TTL rewards staying on Claude for multi-turn work. Cross-model routing breaks cache affinity. Acceptable for self-contained one-shots ("summarise this URL"); painful for multi-turn synthesis.
- **Observability:** If Gemini hallucinates a summary, how is that caught?

## Related

- [[mark-todos]] — §8 workstream (this note's source)
- [[agents-catalog]] — current subagent surface (all Claude-backed)
- [[engineering-process/_summary]] — topic overview
- [openclaw-claude-code GitHub](https://github.com/Enderfga/openclaw-claude-code) — reference implementation
