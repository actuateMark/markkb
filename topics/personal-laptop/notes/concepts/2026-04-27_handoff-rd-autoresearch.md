---
title: "Handoff — R&D auto-research surface (mark-todos #70)"
type: concept
topic: personal-laptop
tags: [handoff, dashboard, research, autoresearch, scheduling, kb-tooling]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
status: ready-to-pick-up
incoming:
  - topics/personal-laptop/notes/syntheses/2026-04-27_minipc-tooling-improvements.md
  - topics/personal-notes/notes/daily/2026-04-27.md
incoming_updated: 2026-05-01
---

# Handoff — R&D auto-research surface (#70)

A new dashboard screen for managing KB research-asks + reading-list entries + scheduling them to run during off-hours. **Read this first**, then [[2026-04-27_minipc-tooling-improvements]] for context.

## What the user wants

Direct quote, 2026-04-27:

> Should create a job that surfaces reasearch asks and reading lists from the KB as a task list that can be signed off on and scheduled to run. It should also surface permissions on this same "R&D autoresearch" screen and allow me to add research topics to the KB this way. Requires sync being on. Should allow me to feed it a URL that it then slots in to the most relevant topic and adds a job to wake up when we have useage and run. Should also be able to swap between modes for this autoresearch on the webpage. Ideally, we should be able to set "workload times" and useage amounts for this stuff. Something like "at 1am wake up and pick up some tasks from the reading list/research queue to add to the KB." This will help both use up some more token spend and use up usage at off hours.

## Capabilities (from the user's description)

1. **Surface research-asks + reading-lists from KB as a task list**
   - Sources: every topic's `reading-list.md`, the global `_dive-queue.md`, the `_research-inbox/` directory
   - Each surfaces as a row that can be: signed off (mark done) / scheduled (queue for run) / deferred / removed
2. **Surface permissions / budget on the same screen**
   - Anthropic features in use, %-remaining quota (ties to mark-todos #66 follow-up)
   - Current token-allocation policy
3. **URL ingestion form**
   - User pastes a URL → backend auto-classifies into the most relevant KB topic (compare URL content with topic `_summary.md` fingerprints) → enqueues a research-job that wakes up next time we have budget
4. **Mode toggle** for auto-research:
   - quick prospector (find + rank sources, no reads)
   - source-reader (read individual sources, write source notes)
   - synthesizer (cross-reference existing source notes, write synthesis)
   - Match the existing R&D agent set — see [[research-prospector]], [[source-reader]], (synthesizer agent file pending)
5. **Workload-time scheduling**
   - "At 1am wake up, pick up N tasks from queue, run them, write results, stop"
   - Configurable per-window: time, max tasks, max tokens, mode
   - Enforces budget — can't run a $50 batch overnight if monthly budget is $20
6. **Off-hours optimization**
   - Burn unused token allowance in cheap windows instead of leaving it on the table
   - The user's framing: "use up some more token spend and use up usage at off hours"

## Existing infra to build on

- **R&D agent set already formalized**: `~/.claude/agents/research-prospector.md`, `~/.claude/agents/source-reader.md`. Synthesizer agent still pending — first synthesizer pilot (see [[2026-04-21_rd-agent-pilot-learnings]]) was the trigger to formalize. Probably worth writing it before Phase 2 of this work.
- **Reading-list pattern**: every topic has a `reading-list.md`. Pattern documented in [[reading-list-conventions]] (if exists; if not, scrape from existing samples in `topics/fleet-architecture/reading-list.md`, `topics/watchman/reading-list.md`).
- **Dive-queue pattern**: `_dive-queue.md` at vault root + per-topic deep-research candidates.
- **Research-inbox**: `_research-inbox/` is where the `kb-ingest` flow stages content awaiting review.
- **`/kb-auto` skill** — already exists for "headless autonomous ingestion from the dive queue." Some of what we need to build is automation around invoking `/kb-auto` on a schedule with budget guards.
- **`/app/claude/` page** — already shows today/week token usage. The R&D autoresearch page should sit alongside (or under) it as a full-screen tool.

## Gates / dependencies

Before this work starts:

1. **Obsidian Sync must be working on minipc** — required for the page to read fresh reading-lists / dive-queue. Confirmed working as of 2026-04-27 (vault-path fix in [[2026-04-27_minipc-tooling-improvements]]).
2. **Anthropic auth on minipc must work** — required for headless `claude -p` invocation. Confirmed working (the existing `kb_query.py` route already invokes `claude -p` for `/kb-ask`).
3. **% remaining usage indicator** (mark-todos #66 follow-up) — *should* land before this. Without a real budget number, "use up off-hours allowance" is vibes-based. **Likely needs Anthropic API key** (not just subscription) for true programmatic budget tracking, since `/usage` slash command returns prose. Or accept a configurable `~/.config/claude/budget.json` that the user updates manually each subscription period.
4. **Synthesizer agent definition** — formalize before scheduled runs in `synthesizer` mode are reliable. Currently there's only an ad-hoc pilot.

## Architecture sketch (proposed — confirm with user)

### Backend (FastAPI extension to `minipc-app/`)

- New route `routes/research.py`:
  - `GET /app/api/research/queue` — current reading-list + dive-queue + inbox items, classified
  - `POST /app/api/research/url` — accept URL, enqueue
  - `POST /app/api/research/schedule/{slot}` — configure a workload-time slot
  - `POST /app/api/research/task/{id}/sign-off` — mark a task done
  - `GET /app/api/research/budget` — current usage + remaining (consumes usage indicator)

- A backing systemd timer `research-runner.timer` that fires at the configured workload windows:
  - Reads queue
  - Picks N tasks (oldest, OR user-pinned, OR randomly weighted by topic-staleness)
  - Invokes the appropriate agent (prospector / source-reader / synthesizer) via `claude -p`
  - Writes results to KB through existing kb-ingest flow
  - Stops when token budget for this slot is hit OR queue is empty

### Frontend

- New page `/app/research/` (11ty, generated by `prebuild.js` `genResearch()`)
- OR extend `/app/claude/` with a tab/section
- Recommend: separate page, link from `/app/claude/` and home page tile
- Form: URL ingestion, mode toggle, workload-time editor, sign-off-able task list
- Live data: hit the new API endpoints

### Storage

- Workload-time config: `~/.config/minipc-research/schedule.json`
- Task queue: `~/.local/state/minipc-research/queue.jsonl` (append-only; sign-off writes a tombstone row)
- Budget config: `~/.config/claude/budget.json` (until %-remaining task lands)

## Concrete first session steps (recommended)

1. **Read this handoff + [[2026-04-27_minipc-tooling-improvements]]** for context.
2. **Confirm scope with user** — separate page or extend `/app/claude/`? Are mode-toggles and workload-time scheduling MVP or follow-up?
3. **Inventory existing reading-lists / dive-queues** — `find ~/Documents/worklog/knowledgebase/topics -name 'reading-list.md' | xargs wc -l` to see how big the surface area is. Some `reading-list.md` files have 30+ entries; the autoresearch surface needs to handle volume.
4. **Sketch the queue model** — how do reading-list entries map to "tasks"? Each line a task? Or only the un-checked ones (`- [ ]` items)?
5. **Define mode → agent mapping** — quick mode = prospector, deep mode = source-reader, etc.
6. **MVP first: URL-ingestion + view-only queue**. Defer scheduling + budget gates to Phase 2 once the queue model is stable.
7. **Write the FastAPI route** — start with `GET /app/api/research/queue`. Walk vault for `reading-list.md` files, parse `- [ ]` items, return as JSON.
8. **Write a simple HTML page** at `/app/research/` that consumes the API. No JS framework; vanilla fetch + table.
9. **Add URL ingestion** — POST endpoint, classify topic by simple keyword overlap with topic `_summary.md`, return suggested topic for user to confirm.
10. **Wire scheduling later** when the basic queue UX feels right.

## Open decisions to discuss with user

- Should this surface allow EDITING a reading-list entry (move it between topics, mark priority)? Or read-only with sign-off?
- Mode-toggle: should it be a per-task choice (each task labelled with its preferred mode), or a per-run choice (the schedule says "synthesizer mode tonight")?
- Budget enforcement: hard cap (refuse to run if it would exceed) or soft warning (run and notify)?
- Queue ordering: oldest-first, priority-tagged, or random within a topic? Probably hybrid — user-pinned + oldest-first within priority.
- Off-hours window: Mark says "1am" — is that a one-shot or recurring? Recurring weekday schedule probably; weekends could be different.
- If a research-job fails (e.g. URL 404, NRQL error, etc.), retry policy? Probably 1 retry with exponential backoff, then mark task as `error` for manual review.

## Related

- [[2026-04-27_minipc-tooling-improvements]] — surrounding architecture
- [[2026-04-21_rd-agent-pilot-learnings]] — the R&D agent pilot that motivated formalizing prospector/source-reader/synthesizer
- [[2026-04-20_multi-agent-model-routing]] — model-routing considerations (synthesizer needs Opus, prospector can use cheaper)
- [[research-prospector]], [[source-reader]] — the agent definitions to invoke
- [[skill-kb-auto]] — existing autonomous-ingestion skill that we'll likely orchestrate from here
- [[skill-kb-ingest]], [[skill-kb-synthesise]] — for individual-task invocation
- mark-todos #66 (claude-usage indicator with % remaining) — gate
- mark-todos #70 — task tracker entry
