---
title: "Long-running multi-agent orchestration pattern for the LLM shop"
type: synthesis
topic: llm-shop
tags: [llm-shop, multi-agent, orchestration, planner-worker-composer, harness-pattern, decomposition, pipeline, design-strategy]
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
status: design-locked
outgoing:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/syntheses/2026-05-07_kb-deep-intake-architecture.md
  - topics/personal-notes/notes/daily/2026-05-07.md
incoming:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/syntheses/2026-05-07_kb-deep-intake-architecture.md
  - topics/personal-notes/notes/daily/2026-05-07.md
  - topics/personal-notes/notes/daily/2026-05-08.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-09
---

# Long-running multi-agent orchestration pattern for the LLM shop

## What this is

A general-purpose pattern for solving non-trivial generative tasks on the [[host-npu-server|`npu-server`]] LLM shop by splitting one logical task across **multiple specialized LLM calls coordinated by a deterministic orchestrator**. The pattern emerged from building [[2026-05-07_kb-deep-intake-architecture|kb-deep-intake]] (URL → KB-quality multi-section markdown note); it generalizes to any task where the LLM shop's hardware constraints make a single LLM call infeasible.

This is not "multi-agent" in the autonomy sense (no agents picking each other's work). It's a **planner-worker-composer** decomposition where the orchestrator code defines the topology and each LLM call has a narrow, contract-bound role.

## Why this pattern, on this hardware

The LLM shop's two backends are both constrained:

| Backend | Context | Throughput | Strength |
|---|---|---|---|
| [[2026-05-05_ollama-vulkan-broken-on-meteor-lake|SYCL Qwen-14B]] (`:8200`) | 4096 tokens | ~1.5 tok/s warm (often slower under load — see "Lessons" below) | Quality on short structured output |
| Ollama llama3.1:8b CPU (`:11434`) | 16384 tokens | ~3 tok/s | Workhorse, predictable, never truncated |

Any single-call solution to a "generate a 1000-word multi-section structured artifact" task fails in at least one of three ways:

1. **Context window** — full source material plus full output won't fit on SYCL.
2. **Per-request budget** — a 1500-token output at 1.5 tok/s is ~17 min; long enough to time out on flaky network or to overlap with other requests in queue.
3. **Quality on long output** — the model degrades on long single-pass generations even when the budget fits, because it has to hold structure-decisions and prose-decisions in mind simultaneously.

The fix is to **cut the task into stages where each LLM call has a tight prompt and a tight output budget**, with deterministic orchestration code stitching the stages together. Time isn't the constraint once we have the [[2026-05-07_overnight-batch-pattern|overnight batch pattern]] — the box has all night for one item.

## The shape of the pattern

```
─────────────────────────────────────────────────────────────────────────
PARSE/EXTRACT       deterministic. Pull source data into a structured     no LLM
                     representation (sections, items, fields, whatever).

PLAN                short LLM call → structured plan JSON. Decides         1 LLM call
                     topology: what sub-tasks exist, their order, which   (quality model;
                     parts of the source feed each sub-task, what          short prompt,
                     "shape" the final artifact takes.                     short output)

WORKERS             one LLM call per planned sub-task. Each sees ONLY     N LLM calls
                     the source slice the plan cited, plus minimal       (workhorse model;
                     context. Output: sub-task result in structured       bigger context,
                     form (JSON wrapping markdown, or whatever).          tight per-call.)

COMPOSE             LLM call assembles final artifact from plan + worker   1 LLM call
                     outputs. Does NOT see the original source — forces  (quality model;
                     faithfulness to the worker summaries, keeps prompt   structured input,
                     compact and predictable.                              long output)

FINALIZE/LINK       deterministic. Mechanical post-processing —           no LLM
                     validation, link substitution, schema repair,
                     sanity caps, anything that doesn't need a model.
─────────────────────────────────────────────────────────────────────────
```

The exact phase names change per problem. The structure is what's load-bearing.

## Why structured contracts between phases

Every phase boundary is a **frozen JSON schema** ([[pydantic-as-contract|Pydantic models]] in our stack). Three benefits:

1. **The composer doesn't re-parse**. If the plan were freeform prose, the composer would have to re-derive every decision from the planner's text. Tokens spent there are tokens not spent on prose quality.
2. **Each phase is independently testable**. A standalone CLI per phase (e.g. `kb-deep-intake parse <url>`, `... plan ...`, `... worker ...`) lets you debug one stage at a time, pipe intermediate outputs between stages, swap a stage's implementation without disturbing others.
3. **Failures stay contained**. The orchestrator catches per-phase exceptions, records them in a phase log, and decides whether to fall back, retry, or abort.

The cost of structured contracts is small (Pydantic validation is cheap, the planner's structured output is short) and pays for itself at the composer step.

## Backend routing: pick the right tool per phase

| Phase | Output character | Backend | Why |
|---|---|---|---|
| Parse | structured data, no LLM | — | Determinism |
| Plan | short JSON (~600 tok) | SYCL Qwen-14B | Quality on structure, output is short so slow throughput tolerable |
| Worker | medium JSON wrapping prose (~400 tok per call) | Ollama llama3.1:8b | Bigger context, predictable, parallelizable in v2 |
| Compose | full artifact (~2000 tok) | SYCL Qwen-14B | Quality matters most here; structured input keeps prompt bounded |
| Finalize | deterministic | — | Determinism |

A useful **escape hatch**: support a backend-swap env var (`KB_DEEP_INTAKE_QUALITY_BACKEND=ollama`) that routes the "quality" backend through Ollama. Tested deeply during the deep-intake build when SYCL was degraded — the env override let the full pipeline run end-to-end with Ollama-everywhere in ~12 min, proving the code worked even though we couldn't validate at production quality. **Bake this in from day one** — when SYCL is sick or you're iterating fast, you'll need it.

## Failure handling — graceful degradation, not abort

Designed-in fallbacks per phase:

| Phase | Failure mode | Recovery |
|---|---|---|
| Parse | URL 404, fetch timeout, decode error | Hard fail — bubble up to the batch runner, mark item failed |
| Plan | Invalid JSON, schema mismatch | Retry once with stricter prompt; on second failure, fail item |
| Worker (per sub-task) | Times out, garbage output | Empty body placeholder for that sub-task only; mark `partial`; other workers continue |
| Compose | LLM error, malformed output | Templated fallback — deterministic Python assembly from plan + worker outputs. Marked `composer_fell_back` |
| Finalize | Should not fail; if it does | Write un-finalized output, log warning |

The orchestrator returns a `phase_log` — a list of `(phase, status, detail, elapsed_ms)` events — so the batch runner's manifest captures *which* phase failed for each item, not just success/failure. Helps post-hoc triage of an overnight batch.

A **templated compose fallback** is critical. The composer is the most expensive call; on a quality run it's ~10 min on SYCL. If it fails, you don't want the entire item lost. Deterministic assembly from plan + worker JSON gives you a coherent (if slightly stilted) artifact that's still useful — and surfaces the partial-failure status to the manifest.

## When to apply this pattern

Apply it when the task has **at least two of these traits**:

- **Output is structured and multi-part** (sections, fields, items) and would benefit from being assembled deliberately rather than generated as one blob.
- **Source material won't fit in the quality model's context** alongside a useful output budget.
- **A single-pass call has to balance two different cognitive loads** (e.g. "decide structure" + "write prose") and the output suffers.
- **Quality matters more than latency** — you're willing to spend 10× more wallclock for substantially better output. Especially true when paired with the [[2026-05-07_overnight-batch-pattern|overnight batch pattern]].
- **Some sub-tasks are independent enough** that even serial execution gains from focused-context per call (and v2 could parallelize across CPU+iGPU).

**Don't apply it when:**

- The task fits in one call comfortably (small input, short output, simple structure). One call is always cheaper than five.
- The task is genuinely sequential prose (e.g. translate this paragraph) — there's no useful decomposition.
- You need synchronous response under 1 minute. Multi-pass adds latency even on fast paths.
- The structure is unclear up-front and the planner would have to guess wildly. Bad plans break the rest of the pipeline.

## Implementation conventions worth keeping

These came directly from the deep-intake build and apply broadly:

### One Python module, no per-phase HTTP

The pipeline is a single Python module (`kb_deep_intake/`) with one public entry point (`run(item)`). The batch runner imports it directly. **No new HTTP harness for the orchestrator** — HTTP only at the LLM-backend boundary. Reduces moving parts; the only network hops are the laptop→box transport and the box→llama.cpp/ollama calls.

### Standalone CLI per phase

Each phase exposes its own argparse-driven CLI under one `bin/<tool>` dispatcher (e.g. `kb-deep-intake parse | plan | worker | compose | link | run`). Lets you:

- Cache parsed pages and skip re-fetching during prompt iteration
- Run only the cheap phases when debugging the linker
- Pipe a hand-edited plan into the worker stage to test prompt tuning
- Compare composer outputs across runs without re-running the full pipeline

This is gold during development. Build the CLI **before** the orchestrator, not after.

### Defensive JSON parsing

Models leak invalid JSON in two consistent ways. Sanitize for both:

1. **Raw control characters in string values** (e.g. literal newline inside `"body_markdown": "para 1\n\npara 2"`). Use `json.loads(text, strict=False)` to accept these.
2. **Invalid backslash escapes** (e.g. `\ ` from FFmpeg-style line continuations, `\!`, `\(`). Pre-process with a regex that converts `\X` (where X is not in `["\\, \\\\, /, b, f, n, r, t, u]`) to `\\X`:

   ```python
   _INVALID_ESCAPE_RE = re.compile(r'\\([^"\\/bfnrtu])')
   def _sanitize_json(s: str) -> str:
       return _INVALID_ESCAPE_RE.sub(r'\\\\\1', s)
   ```

3. **Fences and preamble**. Even when the system prompt says "no fences," models leak ` ```json` and trailing prose. Walk the response for the first `{`, count braces (skipping inside strings) to find the matching `}`, take the substring.

Apply all three in series before `model_validate`. We saw all three in real responses on day one.

### Prompt size discipline

Account for **prompt + output ≤ context** with margin:

- SYCL Qwen-14B: 4096 ctx. Reserve 100 tok safety margin → 3996 tok available. If output budget is 900, prompt budget is ~3000 tok ≈ 12000 chars. Stay well under that — 8000-char prompts.
- Ollama llama3.1:8b: 16384 ctx. Comfortable for worker calls with substantial source slices.

Estimate prompt tokens as `chars / 4` (English) or `chars / 3` (code-heavy). Print the prompt size in dev runs to catch regressions when prompts grow during iteration.

### Section detection on real-world HTML is a parser problem, not an LLM problem

Don't ask the planner to re-segment a flat blob — the parser should produce structured input. A few traps from the deep-intake parser:

- **`lxml` element `id()` is unstable** under iteration with large trees (memory address reuse after garbage collection). Don't dedupe via `set[int]` on element ids — track via custom walker that prunes block subtrees explicitly.
- **`text_content()` on nested blocks double-counts**. `<li><p>foo</p></li>` yields "foo" from both `<li>` and `<p>` if you visit each. Walk the tree with an explicit recursive function that doesn't descend into already-consumed block subtrees.
- **Readability extractors filter aggressively**. Sites like GitHub READMEs come back with most h2/h3 stripped. Accept this — let the planner handle "one giant section" gracefully.

## Lessons from the kb-deep-intake build (2026-05-07)

The first end-to-end run uncovered all of these in one session. Document them so future builds don't relearn:

1. **SYCL throughput degrades unpredictably.** Planning for "1.5 tok/s warm" is a best case. On the e2e build day, SYCL was hitting 0.5-0.7 tok/s — a 900-token request timed out at 20 min. The Ollama backend-swap escape hatch let the build proceed.
2. **The pattern survives sub-optimal hardware.** Ollama-everywhere e2e produced a coherent 4KB markdown draft in ~12 min wallclock. Quality ≠ production target, but the *structure* came out right. That's the proof point this pattern is worth.
3. **Worker output should never be the original source verbatim.** When the worker echoes the source instead of summarizing/cleaning, the composer produces a longer-than-target note. Worker prompts need explicit `target_words` AND a "summarize, don't echo" instruction.
4. **The composer wants structured input, not the article.** Tested both. Structured input keeps the composer prompt bounded (~1800 tok) and forces faithfulness to worker decisions. The article-as-input variant hits the context wall and produces drift.
5. **Phase-log telemetry pays for itself immediately.** Knowing `worker[0]` took 243s vs `worker[1]` 105s revealed that section 0 was 4x larger than section 1 — surfacing a parser-level imbalance the planner could've split. Without per-phase timing, that's invisible.

## Related notes

- [[2026-05-07_kb-deep-intake-architecture]] — the concrete instantiation of this pattern (URL → KB note)
- [[2026-05-07_overnight-batch-pattern]] — transport layer for running pipelines like this overnight
- [[2026-05-04_llm-shop-initial-architecture]] — where the simple-pass pattern lived; the limitation that drove this design
- [[2026-05-05_using-the-llm-shop]] — model/endpoint reference
- [[harness-pattern]] — narrowly-scoped per-purpose harnesses
- [[host-npu-server]] — the box this all runs on
- [[pydantic-as-contract]] — why JSON contracts between phases matter

## Future problems where this pattern likely fits

Hypotheses; not yet built:

- **Confluence page → KB synthesis** — parse page tree, plan section coverage, worker-summarize each child page, compose into one synthesis
- **Code review autopatrol report** — parse PR diff, plan review angles (security/style/perf), worker-review each angle, compose final report
- **Daily-wrap from raw notes** — parse daily note + closed-items list, plan summary structure, worker-summarize per workstream, compose end-of-day brief
- **Jira epic teardown** — parse epic + child tickets, plan timeline narrative, worker-summarize per phase, compose status doc

In each, the trigger is "the source is bigger than fits comfortably in one call AND the output has structure worth assembling deliberately."
