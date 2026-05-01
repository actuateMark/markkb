---
title: "R&D Agent Set Pilot — Learnings (frame-storage pilot, 2026-04-21)"
type: synthesis
topic: engineering-process
tags: [multi-agent, rd-agents, pilot-learnings, research-prospector, kb-scribe, synthesizer, agent-formalization]
jira: ""
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
---

# R&D Agent Set Pilot — Learnings (frame-storage pilot, 2026-04-21)

First pilot run of the proposed 3-role R&D agent pipeline: **research-prospector → source-reader → synthesizer**, with frame-storage for the fleet-architecture redesign as the pilot topic. This note captures what worked, what broke, and what should change before formalizing the agent definitions in `~/.claude/agents/`.

Parent task: [[mark-todos]] §Not-Yet-Prioritized "R&D agent set — formalize post-pilot" + "Frame-storage research workstream."

See also: [[2026-04-20_multi-agent-model-routing]] (framing note); `topics/fleet-architecture/_pilot-2026-04-21-staged.md` (earlier-today source-reader pilot on a different topic).

## Pilot setup (what was actually run)

Ran **two roles in parallel** (foreground, single batch of `Agent` tool calls):

1. **Archaeology via `connector-pipeline-expert`** (existing agent, read-only; investigated current frame-storage in [[vms-connector|VMS connector]] + actuate-libraries). This was the option-(b) piece — grounding the research with internal state before going external.
2. **Research prospector via `general-purpose` + custom prompt** (Sonnet 4.6; web-search-heavy role, no custom agent definition yet). This was the option-(c) piece — prospector role with ad-hoc prompt rather than formalized agent.

**Did NOT run yet** (pending for next session):
- `source-reader` batch on the prospector's 26-entry reading list
- `synthesizer` pass across the archaeology note + source notes

## Role-by-role findings

### Archaeology (connector-pipeline-expert)

**Worked well.** Output was a fully-formatted concept note, saved directly to [[frame-storage-current-state]] with only frontmatter adjustment. 10 structured sections with `file:line` citations throughout. Zero fabricated claims detected on spot-checks. Agent is already formalized and the prompt-template pattern (list of numbered questions, required citation format, section-per-question output shape) is the right instrumentation for any future "archaeology" task.

**No changes needed.** The existing agent + the prompt pattern already constitute a reusable "archaeology" role.

### Research-prospector (ad-hoc on general-purpose)

**Worked well — the overall pattern is viable.** Returned 26 ranked sources in ~14 min wall-clock. Quality was high: top sources were canonical (Axis engineering blog on [[av1-vp9-future|AV1]], [[aws-kvs-entity|AWS KVS]] architecture docs, [[ffmpeg-entity|FFmpeg]] official reference, Milestone white papers). Rejected sources were justified (paywalled, too old, redundant with KB).

**Agent self-reported struggles (direct quotes from self-assessment):**

- **PDF sources are opaque** — binary content breaks WebFetch. Milestone's 2023-09 storage architecture PDF returned unparseable content; had to fall back to search-result snippets. **Fix:** the agent definition should include a fallback rule ("if PDF → search for HTML summary / press-release version; if none, include the PDF anyway with a `*(pdf)*` tag").
- **Academic publisher 303 redirects** — Nature's DOI redirector couldn't be followed; the keyframe-extraction paper made the list based on search metadata alone. **Fix:** add explicit handling for redirects; allow agent to trust search-result abstracts as a secondary confidence tier.
- **Paywalled/form-gated content** — Verkada's [[h265-hevc-deep-dive|H.265]] whitepaper preview-only. Handled cleanly (noted `*(form-gated)*` in output), but the calibration isn't obvious from the prompt. **Fix:** add explicit tier to the type-tag vocabulary.
- **Quality-score calibration ambiguity** — where does a vendor product-features page sit between 3-4? Agent asked for a sharper boundary. **Fix:** formalize the rubric: 5 = primary spec or peer-reviewed paper; 4 = strong primary (vendor engineering blog, well-cited industry writeup); 3 = solid secondary; 2 = useful-but-tangential; 1 = keep-for-completeness.
- **"Storage costs blew up" post-mortems not findable** — targeted "engineering war story" search didn't surface much. The ClickHouse post from Flock Safety was the closest. **Fix:** add specific company-scoped search patterns (`site:engineering.{company}.com "storage"`) to the prompt toolkit.

**What the pilot didn't test (worth flagging for agent definition):**
- Whether the prospector can handle a very narrow topic (e.g. "only papers from 2023+") vs the broad-ish frame-storage topic.
- Whether the prospector correctly skips sources already in the KB (it did check, but the check was easy because the reading-list was 100% internal Confluence URLs).
- Whether parallel prospectors on orthogonal sub-topics would yield better coverage than one prospector across all three chunks.

### Source-reader (not run yet)

Earlier-today's 3-subagent fan-out on the fleet-architecture K8s reading list proved the shape: batches of 2-3 URLs per subagent, structured proposal output, main agent merges. No new learnings from this pilot for this role.

### Synthesizer (not run yet)

Pending the source-reader pass on the 26-entry frame-storage reading list. Will be the first test.

## Proposed `~/.claude/agents/` definitions (draft — NOT YET APPLIED)

When formalizing, create three files:

1. **`research-prospector.md`**
   - **Tools:** `WebSearch`, `WebFetch`, `Read`, `Grep`, `Glob`. **No Edit/Write.**
   - **System prompt:** should codify the rubric (quality scoring), PDF fallback rule, redirect handling, existing-KB-check step, self-assessment section in output.
   - **Output format:** match today's pilot (search log → ranked sources grouped by topic-chunk → considered-and-rejected → self-assessment → budget report).
   - **Model routing:** default Sonnet; Gemini / Haiku acceptable once routing wired.
   - **Budget:** ~15 min wall-clock, ~15 WebSearch calls, ~15 WebFetch calls.

2. **`source-reader.md`**
   - **Tools:** `WebFetch`, `Read`, `Grep`. **No Edit/Write.**
   - **System prompt:** frontmatter template + required section headings + "Relevance to {project-plan proposals}" section (configurable per-topic).
   - **Output format:** structured proposals (source notes + concept proposals + cross-refs + open questions). Matches today's K8s pilot.
   - **Model routing:** default Sonnet; Gemini candidate for long-source ingestion.
   - **Batch size:** 2-3 URLs per agent invocation; more than 3 risks context-overrun per source.

3. **`synthesizer.md`**
   - **Tools:** `Read`, `Grep`, `Glob`; optionally `Write` for synthesis notes + `Edit` for project-plan deltas. More permissive than the other two.
   - **System prompt:** take a set of source-note paths + a project-plan context doc; produce a synthesis note + delta-proposal list.
   - **Model:** Opus. This role requires the most cross-source judgment.
   - **Batch size:** 5-15 source notes per invocation.

## Open questions for the formalization pass

- **Where do the three agents live?** `~/.claude/agents/` globally, or per-project? The prospector is project-agnostic; the synthesizer's project-plan-delta output is fleet-architecture-specific. Consider a `research-prospector` (global) + per-topic `{topic}-synthesizer` variants.
- **How does the synthesizer discover source notes?** Via `Glob` on a directory, or via explicit file-list in the prompt? The prompt route is safer; the glob route is more autonomous.
- **Should source-reader be called from inside prospector?** No — keep them separate. Prospector returns a reading-list; main agent decides what to spawn from it.
- **Model routing for each role**, once Gemini is wired ([[mark-todos]] §kb-starter catch-up task) — prospector + source-reader can route to Gemini; synthesizer stays Opus.
- **Output schemas** — should we introduce a JSON-schema-like definition per role (for deterministic parsing), or keep freeform markdown (more flexible)? Today's pilots parsed cleanly from structured markdown; probably good enough.

## Recommended next steps (in order)

1. Run the **source-reader batch** on the prospector's reading-list (pick ~9 highest-quality entries across chunks 5/6/7, 3 subagents × 3 entries; pattern is proven).
2. Run the **synthesizer** on the archaeology note + the new source notes + each fleet proposal (A-E) to produce a "frame-storage design-delta per proposal" synthesis. This will be the first test of the synthesizer role.
3. After synthesizer runs, **formalize the three agents** in `~/.claude/agents/` per the drafts above, revised with synthesizer-pilot learnings.
4. **Wire Gemini routing** (tracked separately under [[mark-todos]] §kb-starter catch-up).

## Related

- [[2026-04-20_multi-agent-model-routing]] — parent framing
- [[agents-catalog]] — where new agents get registered
- [[skill-kb-scribe]] and [[agent-kb-scribe]] — existing source-reader analogue
- [[connector-pipeline-expert]] — archaeology agent pattern that worked
- `topics/fleet-architecture/notes/concepts/frame-storage-current-state.md` — archaeology output from this pilot
- `topics/fleet-architecture/reading-list.md` §"Frame Storage — 2026-04-21 Prospector Pilot" — prospector output
- `topics/fleet-architecture/_pilot-2026-04-21-staged.md` — earlier-today source-reader pilot staging (different topic, same pattern)
