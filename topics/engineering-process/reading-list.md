# Reading List: Engineering Process

Sources informing KB tooling, skill design, multi-agent/multi-model routing, and engineering workflow patterns. This topic covers the meta-layer: how we work, not the what.

Convention: `- [ ] [Title](url) -- short description`. Check off as read + extract notes into concept/synthesis/entity notes.

---

## KB Tooling — Upstream & References

- [ ] [sbuffkin/kb-starter — upstream updates since init commit](https://github.com/sbuffkin/kb-starter) -- **HIGH PRIORITY.** We based our KB structure on the initial commit; repo has had major enhancements since. Diff against current state; triage each improvement; fold applicable changes into `/kb-ingest`, `/kb-synthesise`, `/kb-queue`, `/kb-lookup`, `/kb-auto` skills. See [[mark-todos#KB tooling — catch up with upstream kb-starter]] for the follow-up task.
- [ ] [Enderfga/openclaw-claude-code](https://github.com/Enderfga/openclaw-claude-code) -- Multi-engine CLI harness wrapping Claude Code, Codex, Gemini, Cursor behind a unified `ISession` interface. Reference for multi-agent-council, session-inbox messaging, two-phase plan→execute, worktree-isolated parallel agents. Already studied in [[2026-04-20_multi-agent-model-routing]].

## Multi-Agent & Multi-Model Routing

- [ ] [Anthropic's subagents docs](https://docs.anthropic.com/en/docs/claude-code/sub-agents) -- Official guidance on subagent design, system-prompt separation, tool scoping. Calibrate our `agents-catalog` against upstream recommendations.
- [ ] [Google's `genai` SDK (Gemini API)](https://ai.google.dev/gemini-api/docs) -- Primary route for offloading token-heavy KB ingest work from Claude. Key questions: long-context pricing, structured-output support for returning KB-shaped proposals, tool-use parity with Claude for agentic flows.
- [ ] *(seed)* OpenAI function-calling / structured output — for parity-comparison with Anthropic tool-use when designing cross-model agent interfaces
- [ ] *(seed)* Ollama API docs — local model hosting for privacy-sensitive ingest

## Skills & Agents Design

- [ ] *(seed)* Claude Code's SKILL.md convention + frontmatter — official docs
- [ ] *(seed)* Community skill examples — awesome-claude-code-skills or similar collections
- [ ] Internal: `[[agents-catalog]]` — our current agent roster and routing conventions

## Knowledge Base Workflow

- [ ] [Obsidian docs — Bases](https://help.obsidian.md/bases) -- Native YAML-based data views; we use these instead of Dataview. Relevant to `/kb-lint`, `/kb-sync`, and any new automation skills.
- [ ] *(seed)* Obsidian Canvas + link-graph patterns — for visual synthesis of large topics
- [ ] *(seed)* Zettelkasten principles applied to technical KBs — find a recent writeup on dense-linking tradeoffs

## Session-Level Patterns

- [ ] *(seed)* Prompt caching economics — deep dive on cache-hit-rate optimization at the Claude Code session level
- [ ] *(seed)* Tool-use loop patterns — avoiding single-query-per-turn inefficiency
- [ ] Internal: `[[2026-04-20_multi-agent-model-routing]]` — framing note for KB-source-research token pressure

## AI Assistant Tooling Landscape

- [ ] *(seed)* Cursor AI / Zed AI / Cody — compare agentic coding IDEs to calibrate what's baseline vs novel
- [ ] *(seed)* Aider + Claude Dev + similar project-local agentic coding tools
- [ ] *(seed)* Continue.dev — open-source alternative; useful reference for hooks + settings architecture

## Writing & Documentation

- [ ] *(seed)* Diátaxis framework — tutorial/how-to/reference/explanation decomposition; applicable to how we structure KB notes vs external docs
- [ ] *(seed)* "Docs as code" pipelines — we have Confluence sync; compare with industry patterns

---

## How to use this file

1. Items marked `*(seed)*` need URL resolution before reading.
2. When an item is read, tick `[x]` and extract findings into `engineering-process/notes/concepts/`, `/syntheses/`, or `/entities/`.
3. New sources surfacing during skill/agent work → add here under the right section.
4. Cross-pollinate with `fleet-architecture/reading-list.md` — autoscaling and placement patterns inform both topics.
