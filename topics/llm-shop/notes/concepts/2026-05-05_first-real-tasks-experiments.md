---
title: "LLM Shop — first real-task experiments + KB-todo-research direction"
type: concept
topic: llm-shop
tags: [llm-shop, experiment, qwen-14b, kb-relink, kb-research-agent, broken-wikilinks, chm]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
outgoing:
  - topics/camera-health-monitoring/_research-inbox/blur-handler-v2.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-05_phase-2-next-steps.md
  - topics/llm-shop/notes/syntheses/2026-05-05_using-the-llm-shop.md
  - topics/personal-notes/notes/daily/2026-05-05.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-05_phase-2-next-steps.md
  - topics/llm-shop/notes/syntheses/2026-05-05_using-the-llm-shop.md
  - topics/personal-notes/notes/daily/2026-05-05.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-19
---

# LLM Shop — first real-task experiments + KB-todo-research direction

Captures (a) the first time we used the [[llm-shop/_summary|shop]] for real coding output, (b) the direction Mark surfaced in the same session for a much higher-leverage application: turning broken-wikilink targets into a reading queue an agent can drive against the local models.

## Experiment 1 — Qwen2.5-Coder-14B writes a `/api/warm-up` endpoint

**Setup**: hit `http://npu-server.tail9b2a4e.ts.net:11434/v1/chat/completions` from the laptop via curl. System prompt: "code only, no markdown, no preamble." User prompt: full spec for a small FastAPI endpoint (Pydantic body, httpx call to Ollama, error handling). `temperature=0.2`, `max_tokens=600`.

**Result**: usable code in **~1m58s** (cold-load + generation; iGPU+Vulkan path). Model emitted ~25 lines of clean FastAPI, structurally correct, would work after fixing two minor issues:

| Issue | Severity | Notes |
|---|---|---|
| Wrapped output in ` ```python ... ``` ` markdown fence despite system-prompt explicitly asking for no markdown | cosmetic | One sed strip |
| Used `httpx.NetworkError` exception (doesn't exist in httpx) | bug | Should be `httpx.RequestError` (network) and/or `httpx.HTTPStatusError` (raise_for_status). Would crash on first network failure. |

**Verdict**: 14B-on-iGPU is **good enough for "delegated-but-reviewed" code work**. Outcome with one human review pass = ship-quality. Without review = silent-bug-shipped (the `httpx.NetworkError` would have looked plausible to a non-Python eye).

**Latency takeaway**: the ~2 min cold-load is dominated by model load (it had been evicted). Subsequent requests to the same model would be ~5-15s for similar output sizes. Good for "fire and let cook" patterns; not for inline-completion.

## Experiment 2 (proposed, larger scope) — broken-wikilink reading queue + research agent

Mark surfaced a much higher-leverage use case during the same session.

### The observation

KB notes accumulate **outbound wikilinks to anchors that don't exist yet** — implicit "TO-DO: write this note." Example: [[../../camera-health-monitoring/notes/syntheses/chm-end-to-end-flow|chm-end-to-end-flow]] (186 lines, dense with class/concept references) has dozens of broken wikilinks like:

```
[[ActiveCamHealthcheckRunner]]    [[HealthcheckConfig]]    [[BlurHandler]]
[[ConnectivityHealthcheckRunner]] [[DWDiagnostics]]        [[chm-diagnostics-architecture]]
[[BaseDiagnostics]]               [[ExacqDiagnostics]]     [[chm-phase1-network-probe]]
[[DiagnosticRunner]]              [[MilestoneDiagnostics]] [[chm-diagnostics-gap-analysis]]
…
```

Each one represents real work: read the codebase, understand what the thing does, write a 200-800-word KB stub. Today these accumulate forever — they're discovered organically, addressed sporadically, and tracked nowhere.

`obsidian unresolved` reports **165 unresolved wikilink targets across the vault** as of 2026-05-05. Most are not equally important — some are typos, some are placeholder anchors, some are real TODOs.

### The pipeline (sketch)

```
┌─────────────────────────────────────────────────────────────────────┐
│  Tier 1 — Scanner script (~/bin/kb-todo-scan)                        │
│   - obsidian unresolved → list of broken targets                     │
│   - For each target: obsidian backlinks file=<target>                │
│   - For each (target, source-note): grep context (3 lines around)    │
│   - Score by # of references + topic frequency                       │
│   - Write JSON queue: ~/.local/state/kb-todo/<YYYY-MM-DD>.jsonl      │
│   - Also writes a markdown digest (top 20) for daily-scope to read   │
└─────────────────────────────────────────────────────────────────────┘
                                ↓
┌─────────────────────────────────────────────────────────────────────┐
│  Reading queue                                                       │
│   - JSONL records: {target, references[{file, line, context}], score}│
│   - User can prune / re-order before running the agent               │
└─────────────────────────────────────────────────────────────────────┘
                                ↓
┌─────────────────────────────────────────────────────────────────────┐
│  Agent — kb-todo-researcher (Claude Code subagent or harness)        │
│   For each queued target:                                            │
│     1. Read all source-note contexts                                 │
│     2. Classify: code reference vs concept vs entity                 │
│     3. If code reference (e.g. ClassName ending in 'Runner'):        │
│        - Search codebase (rg) for the symbol                         │
│        - Read top-N matches                                          │
│        - Hand to local LLM with structured prompt                    │
│     4. If concept/entity:                                            │
│        - Search source-notes (`obsidian search`) for prior mentions  │
│        - Hand to local LLM with context bundle                       │
│     5. LLM emits draft note (frontmatter + body)                     │
│     6. Write to topics/<topic>/_research-inbox/<slug>.md             │
│        for human review (Rule 1: kb-bot authorship guard ✓)          │
│     7. NDJSON log: target, model, tokens, accepted-or-rejected       │
└─────────────────────────────────────────────────────────────────────┘
```

### Why the LLM shop fits

- **Volume**: 165 broken targets × ~1500 tokens of context each × ~600 tokens output = ~350K tokens of API spend if done via Claude. With local models = $0.
- **Repeated, structured**: same prompt template per target. No need for Claude-grade reasoning.
- **Quality bar is "draft note for human review"**, not "ship-ready synthesis." Local 14B is fine.
- **Code-aware tasks**: Qwen2.5-Coder-14B is *literally trained for this*. Better fit than Llama-3.1-8B for the code-reference subset.

### Per-target routing (proposed)

| Target shape | Model | Why |
|---|---|---|
| Class-named (e.g. `ActiveCamHealthcheckRunner`, `BlurHandler`) | `qwen2.5-coder:14b-instruct` | Code-trained, knows OOP |
| Concept-slug (e.g. `chm-diagnostics-architecture`) | `llama3.1:8b` | Generalist summarizer |
| Synthesis-named (date-prefixed) | `llama3.1:8b` | Same |
| Quick triage / "is this even a real TODO?" | NPU TinyLlama | Sub-second filter |

### What the scanner shouldn't do

- Don't auto-create the KB notes. Drafts go to `_research-inbox/` for review.
- Don't re-research targets that are in the inbox already (idempotency by anchor name).
- Don't research targets in `sources/*` paths (those are immutable per kb-starter Rule 11).
- Don't flag things that are intentional anchors-without-files (some `_summary` paths use a path-form like `[[admin-api/_summary|...]]` which `obsidian unresolved` may flag wrongly — needs filter).

### What's needed to implement

1. **Scanner script** (~150 LOC Python): `~/bin/kb-todo-scan`, sister to `kb-relink` and `kb-recap`. Reads CLI + greps for context. Tier 1 candidate (no LLM in scanner).
2. **Researcher agent** (~250 LOC): could be a Claude Code subagent at `~/.claude/agents/kb-todo-researcher.md`, OR a FastAPI harness on the shop. **Subagent first** — leverages Claude Code's existing file-read + grep tools without re-implementing them. Harness can come later for headless overnight runs.
3. **`_research-inbox/`** convention per topic: `topics/<topic>/_research-inbox/<slug>.md` for drafts. Distinct from kb-starter's `sources/`.
4. Wire the scanner into `/daily-scope` so the morning view surfaces "N stub-worthy wikilinks queued."

### Probable hits in the chm topic alone (sampled 2026-05-05)

From `chm-end-to-end-flow.md` — sample of broken targets that look like high-value research candidates:

- **Class-named** (search [[watchman-repo|Watchman]] codebase): `ActiveCamHealthcheckRunner`, `ConnectivityHealthcheckRunner`, `ServerHealthcheckRunner`, `SceneChangeHealthcheckRunner`, `MotionStatusHealthcheckRunner`, `RecordingHealthcheckRunner`, `StreamQualityHealthcheckRunner`, `BaseDiagnostics`, `DWDiagnostics`, `ExacqDiagnostics`, `MilestoneDiagnostics`, `RTSPDiagnostics`, `AvigilonDiagnostics`, `DummyDiagnostics`, `DiagnosticRunner`, `BlurHandler`, `IntegratedSACDetectorBank`, `LRUImageCache`, `HealthcheckConfig`, `HealthcheckAggregator`, `HealthcheckDataPacket`, `ConnectivityPacket`, `StreamQualityPacket`, `SceneChangePacket`, `MotionStatusPacket`, `RecordingPacket`, `ServerStatusPacket`, `DummyAlertGenerator`, `AlertDataPacket`
- **Concept** (search KB + codebase): `chm-diagnostics-architecture`, `chm-diagnostics-gap-analysis`, `chm-phase1-network-probe`, `chm-phase2-stream-probe`, `rtsp-deep-dive`, `autopatrol-integration-components`, `vch-components`, `milestone-components`, `new-relic`

**~30 broken targets in one note.** A morning's work for the agent. Result would be a complete stub set for the chm topic ready for human review.

## Decisions to lock before next session

1. **Scanner location**: Tier 1 (`~/bin/kb-todo-scan` on firebat, output served at `/logs/`)? Tier 2 (laptop only)? Both? Recommendation: laptop first (Tier 2-only), promote to Tier 1 firebat-cron once the format stabilizes.
2. **Agent shape**: Claude Code subagent OR llm-shop harness? Recommendation: subagent first (`~/.claude/agents/kb-todo-researcher.md`) — gets Read/Grep/Bash tools for free. Harness comes later for headless `/loop`.
3. **Output destination**: `_research-inbox/` per topic, OR a single global queue, OR direct to `notes/concepts/`? Recommendation: per-topic `_research-inbox/`. Mirrors kb-starter's `clippings/` convention spiritually.
4. **Authorship marker**: drafts get `author: kb-bot` + `status: research-draft` so human review can flip to `status: review` → `final` after acceptance.
5. **Scope filter**: should the scanner skip targets in `sources/*` paths (immutable) and known path-form anchors (`<topic>/_summary`)? Yes.

## Open questions

- **How does the agent decide "this is a code reference, search codebase" vs "this is a concept, search KB"?** Heuristic: `[A-Z][a-zA-Z]+([A-Z][a-zA-Z]+)+` (camelCase classes) → code; `[a-z]+(-[a-z]+)+` (slug) → concept; date-prefixed (`YYYY-MM-DD_*`) → synthesis. Can be a 1.5B NPU triage call too.
- **Where does the codebase live?** `~/work/<repo>/` per Mark's setup. The [[watchman-repo|Watchman]] codebase isn't currently cloned to the laptop — the agent might need to delegate to `npu-server` (which has it at `~/actuate-watchman/`). But that violates the "do not disturb" rule on that dir. Cleaner: ensure relevant repos are cloned to `~/work/` on the laptop before running.
- **Quality bar for draft notes**: 200-300 words minimum? Frontmatter required? `related:` array populated? Define in the agent's system prompt.
- **Dedup with existing relink work**: `kb-relink/aliases.yaml` is the source of truth for which anchor slugs exist. The scanner should filter against it — don't research an anchor that's just an aliasing miss.

## Experiment 3 — Qwen2.5-Coder-14B writes `kb-todo-scan` v1 (2026-05-05)

**Setup**: well-formed spec sent to `qwen2.5-coder:14b-instruct` via `/v1/chat/completions`. ~150-line spec, structured constraints (stdlib only, 3.10+, JSON output schema specified). `temperature=0.2`, `max_tokens=1500`.

**Result**: ~4m32s round-trip cold (model was evicted). 82 lines of clean Python. Then **6 fix-ups** before it ran:

| # | Issue | Source | Severity |
|---|---|---|---|
| 1 | Output wrapped in ` ```python ... ``` ` markdown fence (despite system prompt forbidding it) | model (cosmetic) | minor |
| 2 | `OBSIDIAN_CLI = '~/.local/bin/obsidian'` — literal tilde, subprocess won't expand | model | bug |
| 3 | Multi-word command passed as single argv: `[bin, 'backlinks file=X']` instead of `[bin, 'backlinks', 'file=X']` | model | bug |
| 4 | Missing `import sys` (used 3 times) | model | bug |
| 5 | Filter `'_' in target` killed all `synthesis`-form targets (which contain `_`). Should be `target.startswith('_')`. | model — partial: ambiguous in spec | bug |
| 6 | Regex `\[\[{target}\]` only matched `[[X]]`, missed `[[X|display]]` | model | bug |

**Then it ran and emitted `[]`** — empty result. Cause: **`obsidian backlinks file=<X>` only works for files that EXIST.** For unresolved targets (the whole point), the CLI returns "not found." This was a bug in MY prompt, not the model's output. The model implemented the spec faithfully.

**Iteration 2 (hand-rewritten)**: switched to single-pass `Path.rglob('*.md')` over `topics/`, building a global `target → [refs]` index, then intersecting with `obsidian unresolved`. O(N_files) not O(N_files × N_targets). 90 LOC.

**Iteration 2 result on the live KB:**

```
=== 139 broken-wikilink targets with references ===
by category: {'concept': 89, 'synthesis': 16, 'class': 34}

top 15 by ref_count:
   18  [  concept]  actuate-filters
   16  [synthesis]  2026-05-01_silent-cameras-diagnosis
   15  [  concept]  actuate-pipeline-objects
   15  [  concept]  connector-library-deployment-lifecycle
   14  [synthesis]  2026-04-28_tenant-status-sync-gap
   13  [synthesis]  2026-04-23_immix-api-error-patterns
   12  [synthesis]  2026-04-29_immix-zombie-tenants
   12  [  concept]  obsidian-clipper-evaluation         <- false positive (file exists, sync lag)
   10  [  concept]  actuate-image-cache
    9  [synthesis]  2026-05-04_silent-camera-diagnosis
    9  [  concept]  actuate-math
    9  [  concept]  actuate-pipeline
    8  [  concept]  feature-development-lifecycle
    8  [  concept]  feedback_fail_fast_guards
    7  [synthesis]  2026-04-24_stale-schedule-cleanup-investigation
```

The top results are exactly the targets a human would prioritize manually: high-frequency concepts that have built up canonical-anchor expectations across many notes. **Output is directly useful** as a research backlog.

The script lives at `~/bin/kb-todo-scan`. Re-runnable any time, idempotent.

**Verdict on "shop-as-coding-tool" loop**: works, but the human still needs to (a) write a precise spec, (b) review the output for plausible-looking bugs, (c) actually run it. Six bug-fixes on 82 LOC means ~7% line-level edit rate. That's the "delegated-but-reviewed" sweet spot — model saves the typing, human catches the bugs. For pure typing: ~5x faster than writing it from scratch. With review: ~2x faster. Not a Claude replacement; a typing accelerator.

**Lessons for next iteration:**
- The model honors output structure (Python script, JSON shape) but ignores prosaic instructions ("no markdown fences"). Pre-strip fences in the post-processor — don't argue with the model.
- For CLI-using scripts, **send the model accurate CLI behavior in the prompt**. The `obsidian backlinks` quirk would have saved 4m32s if I'd included it.
- Two-iteration loop is realistic: first iteration draft + fixes, second iteration if structural rework needed (in our case the rework was replacing `obsidian backlinks` with rglob, but I did it by hand because the model already had limited budget left).

## Experiment 4 — End-to-end Phase 2F: kb-todo-research drafts a real KB stub (2026-05-05)

After the scanner shipped, wrote the second half by hand: `~/bin/kb-todo-research`. ~200 LOC. Reads the scanner JSON, picks a target (or top N by ref_count), bundles all in-KB reference contexts into a prompt, calls Qwen-14B over the OpenAI-compat endpoint, strips markdown fences from the response, writes to `topics/<topic>/_research-inbox/<slug>.md`.

Topic detection: most-referencing source note's `topics/<X>/...` path component wins. Slug rule: CamelCase → camel-case, lowercase, hyphenate.

**First real run: `BlurHandler`** (3 refs across 2 files in `camera-health-monitoring`).

Stats:
- Prompt: 681 tokens (system + structured user with all 3 contexts inline)
- Completion: 556 tokens
- Elapsed: 166.9s warm (cold would be ~+90s for the 9GB model load)
- Throughput: ~3.3 tok/s (Qwen-14B on Arc Xe-LPG via Ollama+Vulkan)
- Output: 2897 chars → `topics/camera-health-monitoring/_research-inbox/blur-handler.md`

**Quality assessment of the draft** (one human read):

What it got right:
- Frontmatter format perfect (type, topic, tags, status: research-draft, author: kb-bot)
- Correctly identified the two techniques (FFT blur + Shannon entropy) from context
- Captured the lifecycle hint ("deleted from `blur_analyzers`")
- "Open questions" surfaced real follow-ups (codebase impl, threshold semantics, perf)

What it got wrong (factual inversion / mild hallucination):
- **Reversed the entropy interpretation**: source says "below 1.5 means blank/black frame" (low entropy = blank), draft says "high entropy values suggest blurriness." That's directionally wrong. The 14B bridges context inference but **flips directionality on technical claims** it doesn't have ground truth for.
- "FFT analysis...removing center frequencies, which are typically associated with sharp images" — actually high frequencies are associated with sharpness; the model overcorrected the explanation.
- Tags: `[camera, health monitoring, blur detection]` — used a space in `health monitoring` (should be `health-monitoring`).

What this means for the workflow:

1. **The pipeline works.** Scanner → research → inbox loop is real, end-to-end, producing notes that look right and cite their evidence.
2. **Drafts are not gospel.** The author-review step is non-optional. The "Open questions" pattern is the right disclosure but isn't a substitute for catching factual inversions.
3. **Quality probably improves with**: (a) a second-pass review by Qwen-32B that re-reads the draft + same context and suggests corrections, (b) including the actual code for class-named targets (the implementation would have made the entropy direction unambiguous), (c) a "factual claim flagging" prompt asking the model to mark what it inferred-vs-directly-quoted.
4. **Cost**: $0 (local LLM). Time: ~3 min/draft warm for 14B. With 139 targets in queue, full sweep is ~7 hours of overnight compute. Free.

Without this pipeline, the only artifact for `BlurHandler` was a wikilink target in 3 prose paragraphs. Now there's a 2897-char structured stub with frontmatter, body, and explicit gaps. **Even if the human throws away half of the prose, the scaffold + open-questions list are the win.**

Promotion path: `_research-inbox/<slug>.md` → human edits → moves to `notes/entities/<slug>.md` (for `class` category) or `notes/concepts/<slug>.md` (for `concept`). Status flips `research-draft` → `review` → `final`.

## Files shipped this session

| Path | Role |
|---|---|
| `~/bin/kb-todo-scan` | Scanner — broken wikilinks → JSON queue. ~90 LOC. Stdlib only. |
| `~/bin/kb-todo-research` | Researcher — JSON queue → draft notes via LLM shop. **v2 with code-search + optional review pass.** ~340 LOC. Stdlib + urllib. |
| `~/work/local_network_scripts/files/{kb-todo-scan,kb-todo-research}` | Source-controlled copies. Untracked at end of session; ready for `git add` in the next round. |
| `topics/camera-health-monitoring/_research-inbox/blur-handler.md` | First draft (v1 — Qwen-14B without code search). Has the entropy inversion. |
| `topics/camera-health-monitoring/_research-inbox/blur-handler-v2.md` | Second draft (v2 — Qwen-14B WITH code search). No inversion. Hyphenated tags. Tighter (1981 vs 2897 chars). |

## Experiment 5 — kb-todo-research v2: code search + optional review (2026-05-05)

Followed up Experiment 4 with two upgrades to address the quality gaps:

### v2.1 — Code search for `class`-category targets

When the target matches the `class` regex (`^[A-Z][a-zA-Z0-9]+$`), the researcher now runs a `grep -rnE` over `~/work/*` for the symbol with these inclusions/exclusions:

- `--include=*.py *.ts *.tsx *.js *.go *.rs`
- `--exclude-dir=.git .venv node_modules __pycache__ dist build target .pytest_cache`
- Pattern: `(\b(class|def)\s+<symbol>\b|\b<symbol>\b)` — matches both definitions and usages, sorted with definitions first

The matched code lines (up to 8 hits, max 2 usages per file) are bundled into the prompt as a "CODEBASE EVIDENCE" section, with system-prompt instruction not to invert directionality.

**Result on `BlurHandler`** (3 KB refs + 8 code hits, 1 def):

| Metric | v1 (no code) | v2 (with code) |
|---|---|---|
| Prompt tokens | 681 | 1044 |
| Completion tokens | 556 | 416 |
| Elapsed (warm) | 167s | 130s |
| Body chars | 2897 | 1981 |
| Tag format | `[camera, health monitoring, blur detection]` ❌ space | `[camera-analysis, blur-detection, health-monitoring]` ✓ |
| Entropy directional inversion | YES ("high entropy = blurry") | NO (avoided the claim entirely) |
| References to wikilinks | implicit | explicit `[[chm-end-to-end-flow]]` |

The model with code in-context produced **tighter, less speculative, factually safer** output. Counterintuitively also **faster** — perhaps because grounded prompts produce shorter, more confident outputs (fewer "perhaps", "might suggest" hedge phrases). 

**Ripgrep wasn't installed on the laptop**, so the script falls back to plain `grep`. Robust + portable. Worth installing rg later for speed but not required.

### v2.2 — Optional review pass with `--review` (Qwen-32B re-reads draft + context)

Added a second-pass review mode behind `--review`. Flow:

1. Draft generated by `qwen2.5-coder:14b-instruct` (default)
2. If `--review`: send the draft + original contexts + code block to `qwen2.5-coder:32b-instruct` with a prompt asking it to identify factual claims unsupported by context, directional inversions, or overreach — and emit a corrected version
3. Strip fences from the result; that's what's written to inbox

Cost: review adds **~5-15 min** depending on cold/warm 32B state and prompt size. **Not run as part of v2 demo** — v2.1's code-search alone fixed the BlurHandler-class issues. Reserved for harder targets where the draft still smells off after one pass.

### Open polish for Phase 2F (deferred)

- [ ] Wire `kb-todo-scan` digest into `/daily-scope` morning view ("N stub-worthy wikilinks queued")
- [ ] Add a `--review-mode` that re-reads existing inbox drafts (not just new ones) — useful for upgrading earlier batches
- [ ] Topic-aware code-root selection: a `class`-target referenced from `topics/autopatrol/` should bias search toward `~/work/autopatrol_*` repos, not all of `~/work/*`. Reduces false-positive hits.
- [ ] Persist run logs (NDJSON) so we can track quality trends over time
- [ ] Frontmatter validator: ensure tags hyphenate, type matches category, etc. — already mostly works but a deterministic post-processor would catch the rare miss

## Cross-references

- [[2026-05-04_phase-1-installed]] — what was running by the time of these experiments
- [[2026-05-04_phase-2-day-to-day-usage]] — Phase 2 design (the warm-up endpoint was a Phase 2E backlog item)
- [[harness-pattern]] — "harness vs subagent" decision rubric
- [[obsidian-cli|Obsidian CLI]] — the `obsidian unresolved` + `obsidian backlinks` primitives the scanner uses
- [[obsidian-clipper-evaluation]] — sibling KB-ingestion idea (external sources vs internal broken links)
- `topics/camera-health-monitoring/notes/syntheses/chm-end-to-end-flow.md` — the canonical "test case" for the new pipeline
