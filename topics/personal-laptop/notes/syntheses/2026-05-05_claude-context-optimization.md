---
title: "Claude Code Context Optimization — 2026-05-05"
type: synthesis
topic: personal-laptop
tags: [claude-code, context, optimization, skills, mcp, mark-todos]
created: 2026-05-05
updated: 2026-05-05
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-05-05.md
incoming_updated: 2026-05-06
---

# Claude Code Context Optimization — 2026-05-05

A scoping + execution session triggered by hitting context limits during an Actuate-context session ($2.39 / 1.4M cache reads in 14 min wall-clock). Identified the always-loaded payload, ranked the easy wins, and executed five passes:

1. **CLAUDE.md trim** (-65%, ~5,000 tokens/session)
2. **Skill description trim** (28 skills, ~1,150 tokens/session)
3. **MCP cleanup** (1 server removed, 8 user-action pending)
4. **Heavy skill body refactor** (4 skills, ~10,560 tokens when invoked)
5. **`/todos-audit` follow-ups** — ghost stub removal + 4 oversized §N sections factored into KB synthesis notes (~400 tokens/session, plus durability win)

Total banked: **~6,550 tokens per session start** + **~10,560 tokens when heavy skills run**.

## Always-loaded budget (before)

| Source | Tokens |
|---|---|
| Claude Code base system prompt | ~10K |
| Global `~/.claude/CLAUDE.md` (32.6 KB) | ~8.1K |
| Skill descriptions (28 skills) | ~10K |
| Subagent definitions (8 agents, 40 KB) | ~10K |
| Deferred tools list (~110 names) | ~2-3K |
| Memory + project state | ~1-2K |
| **Total** | **~42-44K tokens / turn before any conversation** |

In a 14-turn session, that's **~580K cache reads from session boilerplate alone** — ~40% of the 1.4M observed.

## What got cut

### 1. Global CLAUDE.md trim (32.6 → 12.7 KB; ~5,000 tokens/session)

Backup: `~/.claude/CLAUDE.md.bak-20260505-143748`. Final size includes a "Mark-todos discipline" section added back during the session (intentional).

Cuts (preserved every concrete behavioral rule; cut rationale, duplication, elaboration):

- **Three-Tier Pattern section** — full rationale + retrofit guide moved to KB. Skill kept the rule + Tier-1/2/3 description in 6 lines instead of 50.
- **KB Integration "Cost-ordered ladder" table** — duplicates `/kb-lookup` and `/kb-ask` skill behavior. Dropped; one-line pointer.
- **Subagent Routing table** — each agent's `description` already specifies when to invoke it. Dropped redundant table.
- **Operational Dashboard "Reading the Data"** — moved to `/dashboard-check` skill body.
- **Post-Push Audit + Skill Post-Run Review** — tightened from ~2 KB each to ~400 chars without losing rules.
- **Task Completion Ritual** — kept the 4-step rule, dropped the 1219-line history rationale.

### 2. Skill description trim (28 skills, ~1,150 tokens/session)

`/tmp/trim-skills.py` ran the batch. Cut trigger-phrase noise (some descriptions had 5-8 phrases), keep WHAT + WHEN + 2-3 strongest triggers. Average: 330 → 165 bytes.

Backup: `/tmp/skills.bak-20260505-143804`.

### 3. Heavy skill body refactor (~10,560 tokens when invoked)

Heavy skills carried long prose explanations, dated incident annotations ("user preference 2026-04-23"), and rationale that belongs in KB notes or in the canonical script source.

| Skill | Before | After | Saved |
|---|---|---|---|
| `kb-relink` | 28.4 KB | 11.0 KB | 17.3 KB |
| `daily-scope` | 22.2 KB | 12.3 KB | 9.9 KB |
| `autopatrol-cleanup-lambda-check` | 21.2 KB | 13.8 KB | 7.4 KB |
| `daily-wrap` | 16.3 KB | 8.7 KB | 7.5 KB |
| **Total** | 88.1 KB | 45.8 KB | **42.2 KB / ~10.6K tokens** |

Per skill:

- **kb-relink** — implementation detail (anchor inventory build, slug heuristics, scan logic) was duplicated in SKILL.md *and* in the canonical `relink.py` driver. Removed from SKILL.md; kept WHAT/HOW-TO-INVOKE/decision-rules/report-format/self-review.
- **daily-scope** — Steps 2b/2ba/2bb/2c had long "Why" paragraphs and rationale-as-prose. Compressed to imperative form; preserved the cache-first protocol, preflight check table, and fan-out behavior.
- **autopatrol-cleanup-lambda-check** — kept every bash command (those ARE the runbook); cut explanatory paragraphs; consolidated dated incident annotations into single-line parentheticals or KB pointer.
- **daily-wrap** — long prose explanations of Step 1.5, Step 2.7, Step 5.5 compressed without dropping rules.

### 4. MCP cleanup (partial)

- **`claude mcp remove newrelic-eu`** succeeded — duplicate of working `newrelic` server. ~25 deferred tool names removed.
- **8 `claude.ai *` connectors** (Figma, Calendar, Drive, Gmail, Canva, NR, Slack, HubSpot) cannot be removed via CLI — they're org-level discoverable resources cached at `~/.claude/mcp-needs-auth-cache.json`. Each contributes 2 deferred tool names (`authenticate` + `complete_authentication`) = ~16 total. User confirmed claude.ai → Settings → Connectors panel shows none enabled, but the cache repopulates from claude.ai's API on each session — these are likely org-admin-controlled discoveries, not per-user opt-ins. **Treat as a wash; minimal cost.**

### 5. `/todos-audit` follow-ups (mark-todos.md hygiene; ~400 tokens/session)

mark-todos.md is read at every session start (Session Start Ritual). Bloat costs every conversation. Audit found:

**A. Ghost stubs** — §16 + §22 archived 2026-05-04 in the Archive table but stub headings + `> ARCHIVED` callouts left behind. Removed (12 lines).

**B. Oversized §N sections** — 4 over the 60-line ceiling. Each had verbose architecture context, decision histories, and inline tables that belong in KB synthesis notes. Spawned 4 parallel subagents; each:
1. Read its §N from mark-todos
2. Wrote a KB synthesis note in the appropriate topic with the factored content
3. Edited mark-todos to replace inline content with a slim version + wikilink to the synthesis

| §N | Before | After | KB note |
|---|---|---|---|
| §5 Fleet Architecture | 83 | 59 | `topics/fleet-architecture/.../2026-05-05_fleet-architecture-workstream-context.md` |
| §9 Operational Dashboard | 89 | 38 | `topics/operational-health/.../2026-05-05_operational-dashboard-context.md` |
| §10 Laptop-config + DR | 78 | **29** ✅ | `topics/personal-laptop/.../2026-05-05_laptop-config-portability-context.md` |
| §11 Firebat minipc | 69 | 44 | `topics/personal-laptop/.../2026-05-05_firebat-minipc-followups-context.md` |

§5/9/11 hover above the 30-line target — that's the structural floor for sections with 32 / 20 / 20 mandatory `[ ]` checkboxes respectively. **All 4 are now under the 60-line ceiling.**

Net mark-todos shrink: **1,339 → 1,178 lines (-161 / -12%)**. Backup: `mark-todos.md.bak-20260505-151051`.

## Net savings

| Bucket | Per session start | When invoked |
|---|---|---|
| CLAUDE.md trim | **~5,000 tokens** | — |
| Skill descriptions | **~965 tokens** | — |
| Agent descriptions (added 2026-05-05 PM) | **~326 tokens** | — |
| MCP `newrelic-eu` | ~25 deferred tool names | — |
| mark-todos audit (A + B) | — | **~400 tokens when `/daily-scope` reads it** |
| Heavy skill bodies | — | **~10,560 tokens** |
| **Total** | **~6,291 tokens / session start** | **~10,560 tokens / heavy-skill invocation** |

mark-todos is **not** in the always-loaded prefix — only the `<!-- BEGIN-SESSION-CLAIMS -->` block is surfaced via the SessionStart hook. The full file loads only when `/daily-scope` (or a manual Read) pulls it in. Earlier draft of this table double-counted those 400 tokens in the per-session-start column; corrected 2026-05-05 after verification.

A typical 14-turn session paid 1.4M cache reads pre-optimization. Same session shape post-optimization should pay roughly **1.4M − (5,965 × 14) = 1.32M cache reads** — a **~5.8% reduction on cache reads**, or ~$0.13-0.18/session at current pricing. On days when `/daily-scope` + `/daily-wrap` run, additional ~10K tokens × 14 turns ≈ ~140K more cache reads saved.

## Patterns used (apply to future skills)

1. **CLAUDE.md is hot.** Loaded every session. Anything in there that's:
   - Reference material → move to KB
   - Duplicated by a skill or agent description → drop
   - Rationale/history → cut to one line + KB pointer
   - Per-system implementation detail → move to that system's skill

2. **Skill description = WHAT + WHEN + 2-3 strongest triggers.** Trigger phrase lists past 3 entries are noise.

3. **Skill body should be:**
   - The decision rules and command sequences (the runbook)
   - NOT prose explanations of WHY each rule exists
   - NOT historical incident annotations as inline paragraphs (collapse to parentheticals or wikilinks)
   - NOT logic that's already in the canonical script

4. **Tier-1-fallback skills should be lean.** When a skill's canonical execution is a Firebat/laptop script, SKILL.md is fallback runbook + diagnostic obligation — not a re-derivation of the script's logic.

5. **mark-todos is hot too.** Read every session start. Per-§N target ~30 lines, ceiling 60 lines. Verbose context belongs in KB synthesis notes; mark-todos cross-links to them via wikilinks. Closed `[x]` items must be swept by `/daily-wrap` Step 2.7, never accumulate in-place.

6. **Cache reads counter ≠ wastefulness.** It's `context_size × turn_count`. Long sessions look expensive but cache-read pricing is ~10% of input price; without caching the same session would cost 10× more. The metric to optimize is per-turn context size.

## Verification — how to check whether this actually moved the needle

Run these checks to confirm savings landed:

### Check 1 — Per-session-start budget (most important)

**Critical:** `/clear` resets the conversation but **NOT** the billing counter on a `claude code` process — fresh Check 1 measurement requires a brand-new `claude code` invocation, not just `/clear`. And `/usage` is a local read; it doesn't trigger an API turn, so running `/usage` as the first input produces all zeros.

**Protocol:**
1. Quit any running `claude code` (Ctrl-D / `/exit`).
2. `cd /home/mork/work/vms-connector` (or any Actuate context with CLAUDE.md present).
3. Launch `claude` fresh.
4. Send any tiny substantive prompt (e.g., `hi`).
5. Run `/usage`. The first-turn `cache write` + `cache read` together = the always-loaded prefix.

**Measured 2026-05-05** (this synthesis's verification run):
- First-turn `cache write`: **25.3K**
- First-turn `cache read`: **17.7K** (system-prompt sub-prefix warm from prior session in 5-min cache)
- **Total always-loaded prefix: 43K tokens**
- First-turn cost: **$0.17**

The 43K sits at the bottom of the synthesis's pre-opt *estimate* range (42-44K). Because we never had a measured pre-opt baseline, Check 1 alone doesn't crisply prove "≥6K savings landed" — the trim could have landed against an actual pre-opt baseline of ~49K, OR savings could be smaller than estimated. File-level evidence (CLAUDE.md −5K tokens, skill descriptions −965 tokens) is the unambiguous side; **going forward, treat 43K as the new measured baseline**.

If a future re-measurement shows >43K, something re-bloated. Likely culprits:
- A linter/Obsidian-Sync re-bloated CLAUDE.md (compare `wc -c ~/.claude/CLAUDE.md` against ~12,700)
- A skill's frontmatter description got rewritten (spot-check `head -8 ~/.claude/skills/{kb-recap,daily-scope}/SKILL.md`)
- Backup/scratch dirs accidentally became loaded (check no new `.md` in `~/.claude/skills/`)

### Check 2 — Cache reads on a 10-15 turn session

Run a typical workflow (e.g., open a PR, run a few greps, do an edit). After ~10-15 turns, run `/usage`.

**Expected:**
- **Before:** ~1.0-1.4M cache reads for a 10-15 turn session of similar complexity
- **After:** ~6-7% lower (the per-turn savings × turn count)

This is harder to control for — turn complexity varies a lot — but a clear directional improvement should be visible.

### Check 3 — Heavy skill invocation cost

In a fresh session (after Check 1), invoke a trimmed skill and Ctrl-C at the first tool call. Then `/usage`. The `cache write` increase from turn 1 to turn 2 is the skill body load + small overhead from the user message and the skill's first response.

**Measured 2026-05-05 — `/kb-relink`:**
- Turn 1 (`hi`) cache write: 25.3K
- Turn 2 (`/kb-relink` + Ctrl-C at first bash) cache write: 30.2K
- **Delta: +4.9K** (≈ ~3.7K skill body + ~1.2K conversation overhead from 658 output tokens + slash-command system reminder)
- Cost delta: **+$0.07** for the invocation turn

Pre-opt body was 28.7 KB ≈ 7.1K tokens; post-opt body is 11.0 KB ≈ 2.8K tokens. Had the body still been pre-opt size, the cache-write delta would have been ~9.2K, not 4.9K. **Trim landed on the wire for kb-relink.** File-level evidence on the other 3 skills (daily-scope, daily-wrap, autopatrol-cleanup-lambda-check) is identical in pattern, so the same conclusion extrapolates without re-measurement.

**Targets for the other 3 skills** (file-level math, not yet wire-measured):
- `/daily-scope` invocation should add ~3K tokens of skill body (was ~5.5K before)
- `/daily-wrap` invocation: ~2.2K (was ~4K)
- `/autopatrol-cleanup-lambda-check`: ~3.5K (was ~5.3K)
- `/kb-relink`: ~2.8K (was ~7.1K)

### Check 4 — Behavior regressions (the cost side of trims)

Trim risks behavior loss. [[watch-entity|Watch]] for:

- **Skills not triggering when expected.** If you say "kb relink" or "let's do an enrichment pass" and the skill *doesn't* invoke, the description is too tight. Re-add a trigger phrase to that skill's `description:`.
- **Workflow rules getting skipped.** Specifically [[watch-entity|watch]]:
  - **Post-Push Audit** still runs after every push (now ~400 chars instead of 2 KB — the rule itself is intact)
  - **Skill Post-Run Review** still happens after every skill (same)
  - **Three-Tier Pattern** still followed (the global rule is preserved; the rationale was moved to KB but the rule itself is in CLAUDE.md)
- **Mark-todos `[x]` accreting again.** If `/daily-scope` reads a §N tomorrow and finds `[x]` rows inside, Step 2.7 of `/daily-wrap` got skipped. Not caused by this optimization but worth watching.
- **Subagent routing.** Without the routing table in CLAUDE.md, Claude relies on each agent's description. [[watch-entity|Watch]] for cases where a delegate-able task gets done in parent context instead — if so, the agent's description needs sharpening.

### Check 5 — `/usage` $/session trend

Track 3-5 representative sessions over the next week. Compare to recent pre-optimization sessions of similar length.

**Expected:**
- Light session (5-7 turns, no heavy skills): ~$0.05-0.10 cheaper than before
- Medium session (10-15 turns, one or two heavy skill invocations): ~$0.20-0.40 cheaper
- Heavy session (20+ turns, multiple `/daily-*` skill invocations): ~$0.50-1.00 cheaper

If you don't see a clear cost drop after 5 sessions, something didn't land. Re-run Check 1.

## Operational concerns surfaced during the work

1. **The Stop hook (`session-claims-heartbeat.py`) touches mark-todos.md on every Claude turn.** Multiple subagents working in parallel hit "File has been modified since read" Edit failures. They retried successfully, but if you script bulk edits to mark-todos in future, the hook may need a guard or a manual-lock window. Consider a `.claude-bulk-edit-lock` sentinel or a `--quiet-period` flag on the hook.
2. **`claude.ai *` MCPs are org-level.** The local cache `~/.claude/mcp-needs-auth-cache.json` re-populates from the claude.ai API on each session. Even with no connectors enabled in the user's claude.ai settings, the discovered list re-appears. Cost is minimal (~16 deferred tool names) but they can't be cleanly removed without org-admin action.
3. **CLAUDE.md may be edited by other tools mid-session.** A "Mark-todos discipline" section appeared in CLAUDE.md after the trim landed (intentional, kept). If automation rewrites parts of CLAUDE.md, future trims need to be aware that not all sections are user-controlled.

## Remaining easy wins (deferred, ranked)

| Win | Estimated savings | Effort |
|---|---|---|
| Trim 5 largest KB `_summary.md` files (>5 KB each) | ~1-1.5K tokens *per `/kb-lookup` of that topic* | medium — content review |
| Trim `_index.md` (8.2 KB) | ~2K tokens *when /kb-lookup runs* | medium |
| Refactor next-tier skill bodies: `repo-scan` (13.9 KB), `cost-check` (12.4 KB) | ~1-1.7K tokens per invocation of each | low-medium — but low practical leverage (skills run rarely) |
| Trim agent **bodies** (47.6 KB across 9 agents) | ~1-2K tokens per subagent invocation | low — same pattern as heavy-skill body trim |
| ~~Trim agent **descriptions**~~ | ~~up to ~2K tokens / session start~~ | **DONE 2026-05-05 PM — saved ~326 tokens (synthesis row in Net savings)** |
| ~~Mark-todos: address remaining 30-60 line §N~~ | — | **N/A — re-audit 2026-05-05 confirms all §N under 60-line ceiling** |

## Process notes

- **Backups before edit.** `cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak-<ts>` and `cp -r ~/.claude/skills /tmp/skills.bak-<ts>` ahead of each batch. Cheap insurance.
- **Verify after batch.** Bash `wc -c` confirms each trim landed; sample `Read` on 2-3 trimmed files verifies frontmatter still parses.
- **Live system reminder updated mid-session** — after the skill-description trim, the next turn's "skills available" reminder showed the new descriptions. Confirmed the change had landed without restart.
- **Parallel subagents for §N trim worked well** despite shared-file concurrent-write risk. The Edit tool's "file modified since read" guard caught it; agents retried + succeeded. For scripted automation, sequence the edits or hold a lock.

## Backups (rollback if needed)

- `~/.claude/CLAUDE.md.bak-20260505-143748`
- `/tmp/skills.bak-20260505-143804/` (full skills tree before description trim)
- `~/.claude/skills/{autopatrol-cleanup-lambda-check,daily-wrap,daily-scope,kb-relink}/SKILL.md` — no per-skill backups; restore from `/tmp/skills.bak-*` if needed
- `mark-todos.md.bak-20260505-151051`

## Related

- [[2026-04-30_firebat-script-conversion-candidates]] — adjacent Tier-1-script work that further reduces LLM calls
- [[2026-04-30_three-tier-routine-check-pattern]] — pattern under which heavy skill bodies are deliberately small
- [[2026-04-24_skills-audit-script-candidates]] — earlier audit of skill bloat
- [[2026-05-05_operational-dashboard-context]] — factored §9 content
- [[2026-05-05_fleet-architecture-workstream-context]] — factored §5 content
- [[2026-05-05_laptop-config-portability-context]] — factored §10 content
- [[2026-05-05_firebat-minipc-followups-context]] — factored §11 content
