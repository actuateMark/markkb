---
title: "kb-deep-intake — multi-pass pipeline for KB-quality source notes"
type: synthesis
topic: llm-shop
tags: [llm-shop, kb-intake, multi-agent, harness-pattern, decomposition, overnight, planner-worker-composer]
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
status: design-locked
supersedes: kb-intake-single-pass-harness (still exists for ad-hoc one-offs)
outgoing:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/syntheses/2026-05-07_long-running-multi-agent-pattern.md
  - topics/llm-shop/notes/syntheses/2026-05-07_overnight-batch-pattern.md
  - topics/personal-notes/notes/daily/2026-05-07.md
incoming:
  - home/operations/2026-06-22_npu-server-llm-shop-runbook.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/syntheses/2026-05-07_long-running-multi-agent-pattern.md
  - topics/llm-shop/notes/syntheses/2026-05-07_overnight-batch-pattern.md
  - topics/personal-notes/notes/daily/2026-05-07.md
  - topics/personal-notes/notes/daily/2026-05-08.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-25
---

# kb-deep-intake — multi-pass pipeline for KB-quality source notes

## Why this exists

The single-pass [[2026-05-04_llm-shop-initial-architecture|kb-intake]] harness drafts a note from a URL with one LLM call: `fetch → readability → one prompt → one response`. That call has to fit the whole article *and* the whole output inside a single context window — and it has to come back inside whatever per-request timeout the caller imposes.

Two things break that on this hardware:

1. **Context window** on the [[2026-05-05_ollama-vulkan-broken-on-meteor-lake|SYCL Qwen-14B]] backend is 4096 tokens. A truncated 4000-char article ≈ 1000 prompt tokens; topic list + anchor list eats more; that leaves only ~1000 tokens for output. Capping output at 800 tokens to fit produces one short paragraph per article — the opposite of "KB-quality."
2. **Throughput** on SYCL is ~1.5 tok/s warm. Even a capped 800-token output blows past the 600s laptop-side budget once the long prompt is counted, so most calls time out without returning anything at all.

Bigger model + bigger output is the right move (we want 800-1500 word notes with multiple sections, comparable to `[[ffmpeg-libav-libraries|FFmpeg libav* libraries]]`). Time isn't the constraint once we have the [[2026-05-07_overnight-batch-pattern|overnight batch pattern]] — the box has all night. **But a single LLM call can't produce a richly-structured multi-section note with this hardware regardless of how patient the caller is.** Splitting the work into stages lets each call run with a tight prompt and an output budget that fits, and lets the structure of the final note be assembled deliberately rather than generated as one undifferentiated blob.

Inspired by the way Obsidian Web Clipper-style tools section a page before processing it.

## Pipeline overview

```
─────────────────────────────────────────────────────────────────────────────────
Phase 1   FETCH + PARSE          fetch URL, readability strip, heading       no LLM
                                  detection. Output: structured page
                                  representation { title, byline, sections[] }

Phase 2   PLANNER                page metadata + section list →              1 LLM call
                                  structured plan JSON: which sections to    Qwen-14B SYCL
                                  process, target topic, note structure,     (quality > speed
                                   suggested anchors                          for short output)

Phase 3   SECTION WORKERS        for each planned section: section text +    N LLM calls
                                  context (page title, plan, sibling         llama3.1:8b CPU
                                  sections) → ~200-word section summary +    (16K context;
                                  key claims                                  workhorse)

Phase 4   COMPOSER               page metadata + plan + section summaries →  1 LLM call
                                  full multi-section markdown note with      Qwen-14B SYCL
                                  frontmatter, lede, section bodies,         (quality prose)
                                  Key claims, Open questions

Phase 5   LINKER                 walk anchor index for the note's topic;     no LLM
                                  substitute [[anchor]] wikilinks for known
                                  inline mentions; repair frontmatter;
                                  validate schema
─────────────────────────────────────────────────────────────────────────────────
```

Output target per article: **800-1500 words, 4-7 sections**. Wallclock budget per article ~25-40 min (planner ~3 min + 4-6 sections × 4-5 min serial + composer ~10 min + linker negligible). Fits inside a sleep window for batches of 20-30 articles via the [[2026-05-07_overnight-batch-pattern|overnight batch]].

## Why JSON for the plan (and not freeform)

The composer is the most token-expensive call. Anything that lets it skip re-interpretation is worth the small cost of structured output upstream.

- **Freeform plan** — composer would have to re-parse the planner's prose, infer the section list, re-derive topic, etc. More prompt tokens, more variance, more failure modes.
- **Structured plan** — composer reads JSON deterministically; prompt template is fixed; output shape is predictable.

The planner pays a small cost to emit JSON (Qwen-14B is fine at this), the composer pays a much larger cost on every section's text — favoring the small upfront cost is the right trade. Same logic that drives [[pydantic-as-contract]] in the broader codebase.

## Phase details

### Phase 1 — Fetch + parse (no LLM)

Existing `harnesses/kb_intake/server.py:fetch_url` already does fetch + readability. Extend it:

- Detect `<h1>`, `<h2>`, `<h3>` boundaries from the readability-extracted HTML *before* the tag-strip pass.
- Output: `{ title, byline, source_url, sections: [{ heading: str, level: int, text: str, char_count: int }] }`
- If the page has no headings at all (a flat blog post): emit one synthetic section `{ heading: "(body)", level: 0, text: <full body> }` and let the planner decide whether to subdivide it by paragraph.

No LLM. ~1-3 s per page.

### Phase 2 — Planner

**Model:** Qwen-14B SYCL (`http://127.0.0.1:8200/v1/chat/completions`). Quality > speed; plan is short.

**Input prompt:** page title + byline + per-section heading + per-section first 200 chars + first 80 chars of each later paragraph + existing topic list + existing anchors. Estimated: ~1500 tokens prompt.

**Output schema (locked):**

```json
{
  "title": "Human-readable note title",
  "topic": "video-processing",
  "tags": ["ffmpeg", "python-bindings", "library"],
  "note_kind": "concept|entity|integration|reference",
  "lede": "One-sentence summary of what this article is about — used as note opening line.",
  "sections": [
    {
      "section_index": 0,
      "heading_in_note": "What it is",
      "source_section_idxs": [0, 1],
      "guidance": "Explain the project's purpose and the relationship to FFmpeg the binary.",
      "target_words": 180
    },
    {
      "section_index": 1,
      "heading_in_note": "API ergonomics",
      "source_section_idxs": [2],
      "guidance": "Describe the chained-builder API style; contrast with PyAV.",
      "target_words": 220
    }
  ],
  "skip_source_idxs": [3, 4],
  "skip_reason": "Sections 3-4 are install instructions and changelog — not KB-relevant.",
  "open_question_seeds": [
    "Does ffmpeg-python expose hardware-accel decoders the same way PyAV does?",
    "How does it handle filtergraph errors compared to subprocess.run?"
  ]
}
```

**Output budget:** ~600 tokens. Comfortable inside the 4096 context window after the prompt.

Planner is also responsible for **picking the topic** from the existing topic list (or signaling a new slug if none fit). And for telling the composer which existing anchors are likely matches (composer doesn't re-derive these).

### Phase 3 — Section workers

**Model:** llama3.1:8b on Ollama-CPU (`http://127.0.0.1:11434/v1/chat/completions`). 16K context — never truncated. Slow per token but the workhorse role: predictable, parallel-with-SYCL hardware (different silicon, so we *could* run a section worker on CPU concurrently with the planner/composer on iGPU; v2 nicety, not v1).

**Input per section:**

- Page title + byline (8 lines of context)
- The plan's `lede` (so worker knows the note's thesis)
- This section's `heading_in_note` + `guidance` + `target_words`
- The text of all `source_section_idxs` for this plan section, concatenated (typically 500-2000 chars)
- A "no-fabrication" rule: cite only what's in the source text; flag uncertainty as `(per the article)` or omit.

**Output schema (locked):**

```json
{
  "section_index": 0,
  "heading_in_note": "What it is",
  "body_markdown": "FFmpeg-python is a thin Python wrapper around the FFmpeg CLI…",
  "key_claims": [
    "Builds shell commands as Python expressions; does NOT bind libavformat.",
    "Last release 2023-10; project is in maintenance mode."
  ]
}
```

**Output budget:** ~400 tokens per section. With 4-6 sections that's 1600-2400 tokens of section content total — well above the 800-token cap that gimped the single-pass version.

### Phase 4 — Composer

**Model:** Qwen-14B SYCL again. Composing prose from structured input is where Qwen's quality matters.

**Input:** plan JSON + section summaries JSON + page metadata. **Not** the original article (per the locked design decision — keeps prompt bounded and forces faithfulness to the section workers' summaries).

**Output:** complete markdown file content, starting with the YAML frontmatter delimiter. Format:

```
---
title: <plan.title>
type: <plan.note_kind, mapped to source>
topic: <plan.topic>
tags: <plan.tags>
created: <today>
updated: <today>
author: kb-bot
status: research-draft
origin: <source_url>
---

# <plan.title>

<plan.lede>

<for each section in plan.sections, in order:>
## <section.heading_in_note>

<section worker's body_markdown for that section>

<after all sections:>
## Key claims

<dedupe + flatten section workers' key_claims into 5-9 bullets>

## Open questions

<plan.open_question_seeds, lightly polished>
```

**Output budget:** ~2000 tokens. Tight inside 4096 context after a ~1800-token prompt — but achievable because the composer's input is structured and compact (no original article, no anchor list — those are linker's job).

The composer is constrained to **rearrange and stitch, not invent.** All factual claims must trace back to a section summary. The system prompt states this explicitly.

### Phase 5 — Linker (no LLM)

After the composer emits the markdown:

1. **Anchor index walk** — load the topic's existing anchor list (every `*.md` filename in `topics/<topic>/notes/{concepts,entities,syntheses}/`).
2. **Inline match** — for each anchor, find case-insensitive whole-word matches in the body. Wrap the first occurrence per section in `[[anchor|<original-text>]]`. Skip anchors already present as wikilinks.
3. **Frontmatter repair** — if the closing `---` is missing (recurring LLM failure mode per [[2026-05-05_using-the-llm-shop|using the LLM shop synthesis]]), insert it.
4. **Schema validate** — required fields (`title`, `type`, `topic`, `tags`, `created`, `updated`, `author`, `status`) present. If missing: fill from the plan or fail the item.
5. **Sanity caps** — body ≤ 2500 words; ≤ 12 sections; ≤ 12 key claims. If exceeded: log a warning, leave as-is for human review.

No LLM. ~50ms per note. Pure mechanical post-processing — same kind of work `kb-relink` and `kb-lint` already do, just baked into the pipeline.

## Failure handling

| Phase | Failure mode | Recovery |
|---|---|---|
| 1 (fetch) | URL 404, fetch timeout, decode error | Mark item `failed` in batch manifest; skip to next URL |
| 2 (planner) | Invalid JSON output, schema mismatch | One retry with stricter prompt; if still bad, mark `failed_planner`, dump raw output to log |
| 3 (worker) | Worker times out or returns garbage | Leave that section's body empty with a `(section worker failed — see log)` placeholder; continue to other sections; mark item as `partial_section_failure` in manifest |
| 4 (composer) | Invalid markdown, missing frontmatter | One retry; on second failure, fall back to a *templated* assembly: just concatenate section summaries under their headings with hand-built frontmatter from the plan. Mark `composer_fell_back` in manifest. |
| 5 (linker) | Should never fail; if it does, write the un-linkered markdown and log | Mark `linker_failed` |

The whole pipeline runs in a single Python process per article — no inter-process state. Failures bubble up to the batch runner, which records them in `manifest.json` and proceeds.

## How it composes with the overnight batch pattern

The [[2026-05-07_overnight-batch-pattern|overnight batch]] is unchanged in transport: `kb-batch-submit` → input.json → systemd unit → manifest.json → `kb-batch-pull`. Only the **worker** changes:

- **Before:** batch runner called the existing single-pass `POST /kb-intake` endpoint per item.
- **After:** batch runner imports `kb_deep_intake.run(item)` directly. No HTTP boundary inside the worker; the local LLM calls go to the same `:8200` and `:11434` endpoints the planner/worker/composer pick.

The single-pass `POST /kb-intake` endpoint stays for ad-hoc laptop one-offs — there's still a use case for "I want to ingest this one URL right now and look at the result in a minute." Just not at KB-quality and not for batch.

## Wallclock budget per article

| Phase | Calls | Per-call | Total |
|---|---|---|---|
| 1 fetch+parse | 0 | — | 1-3 s |
| 2 planner | 1 | ~3 min | ~3 min |
| 3 workers | 4-6 (serial) | ~4 min | 16-24 min |
| 4 composer | 1 | ~10 min | ~10 min |
| 5 linker | 0 | — | <1 s |
| **Total** | | | **~30-40 min/article** |

For 30 URLs: ~15-20 hours wallclock — covers a long sleep window. For 10 URLs: ~5-7 hours. Calibrate batch sizes accordingly.

## Components to build

| Where | File | Purpose |
|---|---|---|
| Box | `~/llm-shop/harnesses/kb_deep_intake/parser.py` | Phase 1 — fetch + readability + heading detection. Returns parsed page object. |
| Box | `~/llm-shop/harnesses/kb_deep_intake/planner.py` | Phase 2 — Qwen-14B call, returns plan JSON (validated against schema). |
| Box | `~/llm-shop/harnesses/kb_deep_intake/worker.py` | Phase 3 — llama3.1:8b call per section, returns section summary JSON. |
| Box | `~/llm-shop/harnesses/kb_deep_intake/composer.py` | Phase 4 — Qwen-14B call, returns full markdown. |
| Box | `~/llm-shop/harnesses/kb_deep_intake/linker.py` | Phase 5 — anchor substitution, frontmatter repair, schema validation. |
| Box | `~/llm-shop/harnesses/kb_deep_intake/__init__.py` | `run(item) -> DraftResult` — orchestrates phases, handles per-phase failures, returns the assembled draft + per-phase log. |
| Box | `~/llm-shop/bin/kb-batch-runner.py` | Already in [[2026-05-07_overnight-batch-pattern|batch design]]. Calls `kb_deep_intake.run(item)` per item. |

No new HTTP harness for kb-deep-intake. It's a Python module the batch runner imports. Keeps things simple — HTTP only at the LLM-backend boundary.

## Followups (out of v1)

- **CPU/iGPU parallelism** — run a section worker on CPU concurrently with the planner/composer on iGPU. ~2x throughput on most articles. Adds a queue + coordination layer.
- **Composer review pass** — after composer emits, ask Qwen-14B (or a future 32B SYCL) to flag factual inversions or unsupported claims, then patch them. Same pattern as `kb-todo-research --review`.
- **Section-summary cache** — if the same URL is re-ingested (e.g. resubmit after a partial-run), reuse cached section summaries.
- **Multi-URL aware planner** — for cases like "ingest these 3 URLs that all describe the same project," have a meta-planner merge them into a single note. Out of scope for first build.
- **Domain-specific worker prompts** — section workers for code-heavy docs (worker preserves code blocks verbatim) vs prose docs (worker compresses).
- **Web view of run** — surface plan JSON + per-section summaries + composer output side-by-side at `:8080/runs/<run-id>/<slug>` for debugging quality regressions.

## Build sequencing (resequenced)

The simple-pass quality-tuning round is dropped — the architecture was wrong for the goal. New order:

1. Build **kb-deep-intake** module on the box (parser → planner → worker → composer → linker, in that order; standalone CLI for testing each phase).
2. End-to-end test: one URL through all 5 phases, eyeball the output.
3. Iterate planner / worker / composer prompts until output quality is on par with hand-written concept notes.
4. Build the **overnight batch** plumbing per [[2026-05-07_overnight-batch-pattern|the batch design]], pointing at `kb_deep_intake.run`.
5. First overnight run on `video-processing` reading-list (~10 URLs).
6. Review pulled drafts; iterate.
7. Add followup niceties from §"Followups" as needed.

## Related

- [[2026-05-07_long-running-multi-agent-pattern]] — the generalized pattern this is one instance of (when to apply, lessons, anti-patterns)
- [[2026-05-07_overnight-batch-pattern]] — the transport layer this pipeline plugs into
- [[2026-05-04_llm-shop-initial-architecture]] — the original simple kb-intake harness
- [[2026-05-05_using-the-llm-shop]] — current model/endpoint reference
- [[2026-05-05_ollama-vulkan-broken-on-meteor-lake]] — why kb-intake routes to SYCL
- [[harness-pattern]] — why harnesses stay narrowly-scoped
- [[host-npu-server]] — the box this all runs on
- [[obsidian-clipper-evaluation]] — the original "structured page ingestion" idea this pipeline operationalizes
