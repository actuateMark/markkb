---
title: "Agent: issue-auditor (proposed — not yet built)"
type: entity
topic: engineering-process
tags: [agent, issue-hygiene, github, backlog, proposed]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/software-architecture/_summary.md
  - topics/software-architecture/notes/syntheses/2026-04-17_issue-hygiene-plan.md
incoming_updated: 2026-05-01
---

# issue-auditor (proposed)

**Status:** ⚠️ **Proposed / not yet built.** This is a design outline. Build decision tracked in [[mark-todos]] §7.

Audits GitHub issues against the project's issue-creation standard. Classifies violations (missing labels, empty body, ambiguous title, no acceptance criteria, etc.) and proposes normalization edits. Read-only by default.

**Intended file:** `/home/mork/.claude/agents/issue-auditor.md` (when built)
**Model (planned):** sonnet — classification + summarization, no heavy reasoning
**Mode (planned):** read-only default; write mode via `--apply` with per-issue confirmation

## Why this exists (design rationale)

The [[2026-04-17_scan|2026-04-17 repo scan]] surfaced that [[skill-repo-scan]] scoring is blunted by poor issue hygiene — sparse labels, empty bodies, ambiguous titles. Several issues are agent-generated with inconsistent structure. Normalizing the backlog manually is slow and boring; periodic drift is inevitable.

This agent automates the *classification* and *normalization-suggestion* steps, while leaving the hard calls (close vs. keep, priority level) to the human. Full rationale: [[2026-04-17_issue-hygiene-plan]].

## When to invoke (when built)

- **Periodic sweep** — run monthly against each major repo, surface new hygiene regressions
- **Post-mass-creation** — after an agent or partner files a batch of issues, normalize them before they accrete drift
- **Pre-release backlog grooming** — audit the repo before a release-cut ceremony

## When NOT to invoke

- Repos with strict external ownership (partner-managed issue trackers) — the standard doesn't apply
- One-off issues (single issue fixes don't need an agent — just edit directly)
- When the standard itself is still in flux (agent enforces the standard; if the standard is moving, agent output is noise)

## Intended behavior

### Read-only mode (default)

1. Fetch open issues from one repo (same `gh issue list` pattern as [[skill-repo-scan]])
2. For each issue, classify against the standard from [[2026-04-17_issue-hygiene-plan]]:
   - Title outcome-oriented?
   - ≥ 2 labels present? (Type + Priority + Area desired)
   - Body has Context / Problem / Acceptance Criteria sections?
   - Links to related issues / PRs / Jira where relevant?
3. Produce a markdown review per violating issue:
   - Current state (what's there)
   - Proposed fix (what to change)
   - Suggested diff for title + labels + body
4. Return to the user for review

### Write mode (`--apply` flag)

For each proposed fix, ask the user via AskUserQuestion: apply / skip / close-instead.
- `apply` → `gh issue edit #NNN --add-label ... --remove-label ... --title ... --body ...`
- `skip` → move on
- `close-instead` → surface as a close-candidate; require explicit confirmation; then `gh issue close` with a standardized reason

**Never auto-close.** Closing is a human judgment call.

## Scope / Tools (planned)

| Tool | Purpose |
|------|---------|
| `Bash` (gh CLI) | Read + write GitHub issues; scoped to `aegissystems/*` repos |
| `Read`, `Grep` | Load the issue-hygiene standard from the KB, cross-reference repos |
| `AskUserQuestion` | Per-issue confirmation in write mode |

**Excluded tools:**
- Write/Edit on files outside the KB (no code-repo writes)
- NR / Jira MCP (out of scope — this is GitHub only)

## Reference standards

- [[2026-04-17_issue-hygiene-plan]] — the standard this agent enforces
- [[security-hardening-checklist]] — (not directly enforced, but `security`-labeled issues get cross-referenced)

## Relation to other agents / skills

| Tool | Relation |
|------|---------|
| [[skill-repo-scan]] | Complementary — scan surfaces *what's worth picking up*; audit surfaces *what's poorly specified* |
| [[agent-actuate-pr-reviewer]] | PR-side counterpart — reviews PRs against checklists; this agent reviews issues |
| [[skill-todos-add]] | If an audit surfaces an issue that should be a workstream, `/todos-add` scaffolds it in mark-todos |

## Build decision (open)

Not built yet. The [[2026-04-17_issue-hygiene-plan]] proposes building this *after* 1-2 manual sweeps have stabilized the standard. Early automation on a drifting standard is worse than manual.

Build trigger: when manual audit passes start producing *consistent* normalization decisions across issues (i.e. patterns are teachable).

## Metrics this agent would feed

When running, each pass should emit:
- # issues audited
- # violations found (by category: label, title, body, links)
- # fixes applied (if `--apply`)
- # issues flagged as close-candidates

These roll up into the [[2026-04-16_metrics-to-track|code-health metrics]] and potentially the [[2026-04-16_code-health-dashboard|dashboard]].

## Related

- [[agents-catalog]]
- [[2026-04-17_issue-hygiene-plan]] — full plan of attack
- [[mark-todos]] §7 — workstream tracking the build decision
- [[skill-repo-scan]] — the scan whose signal improves when this runs
- [[repo-backlog/_summary|repo-backlog]] — where scans persist
