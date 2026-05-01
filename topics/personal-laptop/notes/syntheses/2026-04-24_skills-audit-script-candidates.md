---
title: "Skills audit — script-able vs LLM-required"
type: synthesis
topic: personal-laptop
tags: [skills, claude-code, automation, minipc, audit]
created: 2026-04-24
updated: 2026-04-24
author: kb-bot
---

# Skills audit — script-able vs LLM-required

## Why this audit

`/kb-recap` was ported to `~/bin/kb-recap` (pure Python, 250 LoC) on 2026-04-24 and wired into the minipc's `prebuild.js` so `/app/today/` refreshes every 5 min without spinning up a headless Claude session. That freed two systemd units (`run-kb-recap.{service,timer}`) and ~8s + one billed Claude invocation per tick. The motivating user question: **"no real need to run this through claude right?"**

This note triages the remaining 25 skills in `~/.claude/skills/` for the same pivot, so the minipc dashboards can run them as cron scripts where feasible and keep the Claude-only ones as skills.

## Tiering rubric

| Tier | Definition | Rule of thumb |
|---|---|---|
| **T1 — scriptable** | Pure find / fetch / transform / emit. No interpretation, no interviewing. | "A Python script with pyyaml + requests could do this end-to-end." |
| **T2 — mixed** | Mechanical data-pull + thin LLM summary/commentary. The LLM pass is small (1–2 paragraphs). | "I could script the fetch; the LLM just writes the narrative header." |
| **T3 — LLM-required** | Reasoning, judgment, interviewing, or free-form writing dominates the skill's value. | "The LLM is doing the work; scripting it would delete the point." |

## Classification (26 skills)

### T1 — scriptable (priority conversions)

| Skill | What it does | Why scriptable | Port sketch |
|---|---|---|---|
| `kb-recap` ✓ | Categorize today's KB changes | Pure find + classify + emit | **Done 2026-04-24** → `~/bin/kb-recap` (Python, 250 LoC) |
| `kb-lint` | Structural KB validator (broken wikilinks, missing frontmatter, stale notes, orphans) | Every check is rule-based; no interpretation needed | Python + pyyaml; walk `topics/`, build wikilink graph, emit tiered report (errors/warnings/info). ~400 LoC. Run nightly, expose at `/app/kb-lint/` |
| `recap` (session-state) | Summarize Today's Scope + session claims + TaskList + closed items | Mechanical reads; three file parses + a tasks API query | Small Python script; could render as `/app/session/` live page |
| `claim` / `release` / `claims` | Mutate the `BEGIN-SESSION-CLAIMS` table in mark-todos | Already scripted via `session-claims-*.py` hooks; skills are thin wrappers | Promote existing `~/.claude/hooks/session-claims-*.py` to a `~/bin/claims` CLI with `claim <label> <scope>` / `release [label]` / `list` subcommands. Low ROI but trivially easy |

### T2 — mixed (partial conversions / keep skill as orchestrator)

| Skill | Mechanical part | LLM part | Recommended split |
|---|---|---|---|
| `dashboard-check` | Signal catalog eval, NRQL queries, threshold classification, HTML rendering, sink JSONL append | "What's notable today?" narrative header | Already mostly scripted (`signals/*.py`, `render.py`, `backfill.py`). The headless `claude -p` invocation just writes a 2–3 line summary. Option: strip the LLM pass entirely on minipc runs — the HTML itself tells the story. Keep skill only for "explain this red signal to me" drill-down |
| `cost-check` | AWS CE queries with aggregation rules | Interpretation + surprising-findings commentary | Script the queries as a CLI (`~/bin/cost-check --window 30d --facet service`); skill orchestrates + commentary |
| `repo-scan` | `curate.py` (already scripted) — refreshes per-repo concept files | "Top candidates" ranking + cluster narrative | Already mostly scripted. Add a bare `~/bin/repo-scan-refresh` cron that just runs `curate.py` for the per-repo refresh without the skill's interview/narrative layer — keep skill for the "walk me through top candidates" mode |
| `autopatrol-cleanup-lambda-check` | NR + CloudWatch + DDB queries, pass/fail classification | State narrative + anomaly notes | Script the probes; emit JSON; keep skill for narrative synthesis. Minipc runs the probe-script as a timer, pages only on RED |
| `autopatrol-overnight-check` | Same profile | Narrative synthesis is the product | Keep as skill; probes already run inside. Not worth fragmenting |
| `kb-sync` | Confluence / Jira scrape | Summarize + decide what's stale | Keep as skill; the Confluence API exposure already runs under MCP, the decision layer matters |

### T3 — LLM-required (keep as skill, do not script)

| Skill | Why LLM is load-bearing |
|---|---|
| `kb-ask` | Free-form Q&A over the vault; the reasoning is the point |
| `kb-ingest` | Web research + concept-note writing |
| `kb-synthesise` | Cross-reference sources; write synthesis notes |
| `kb-auto` | Autonomous loop over the dive queue; decision-heavy |
| `kb-lookup` | Surface *relevant* KB context for a coding task — ranking + relevance |
| `kb-queue` | Per-item review + interactive approval |
| `daily-scope` / `daily-wrap` | Interview-driven; judgment about priorities and closure |
| `todos-audit` / `todos-add` | Judgment about duplication, drift, priority |
| `stage-release` | Orchestration with guard-rail prompts at each step |
| `generate-project-docs` / `write-external-docs` / `api-endpoint-development` | Doc + code generation |

## Recommended execution order

1. **`kb-lint` → `~/bin/kb-lint`** (Python). Highest ROI among remaining T1 candidates: it's a read-only validator, it produces a clean tiered report, and running it nightly surfaces wikilink rot and stale-frontmatter debt without human triggering. Add a `/app/kb-lint/` dashboard page rendering yesterday's report.
2. **`recap` (session state) → `~/bin/session-recap`**. Small script (~80 LoC). Not critical but nice to have as a browser-accessible status surface at `/app/session/`.
3. **`dashboard-check` — strip the LLM narrative pass on minipc runs.** Half the motivation for wiring `run-dashboard-check.timer` through `claude -p` today is the headline — but the HTML already speaks for itself. Rewrite the timer's wrapper to invoke the skill's internal Python modules directly, not via `claude -p`. Bigger win than it sounds: removes the MCP-allowlist dependency that's been flaking on cron (see [[automation-overnight-check]]).
4. **`claims` CLI.** Tiny; mostly done in hooks already. Low-priority.
5. **`repo-scan` refresh-only cron.** Skill stays; add a `curate.py`-only cron for the per-repo concept file refresh so those stay fresh even on days the user doesn't run the skill interactively.

## Deliberate non-goals

- **Don't port `kb-ingest` / `kb-synthesise` / `kb-auto`.** The reasoning is the product.
- **Don't port `daily-scope` / `daily-wrap`.** The interview is the product.
- **Don't try to fully de-LLM `dashboard-check`.** Strip the narrative layer on cron runs, but keep the skill for ad-hoc drill-down.
- **Don't build one mega-script.** Each T1 conversion stays a single-purpose script. The minipc timer catalog is the orchestrator.

## Related

- [[2026-04-24_minipc-dashboard-static-gen-refactor]] — the dashboard refactor that motivated the question
- [[skill-kb-recap]] — original skill, now superseded by `~/bin/kb-recap`
- [[automation-overnight-check]] — MCP-allowlist flakiness that motivated point #3 above
- [[firebat-minipc-as-claude-dev-box]] — the minipc this audit is pointed at
