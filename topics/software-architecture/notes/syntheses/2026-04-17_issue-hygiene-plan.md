---
title: "Issue Hygiene + Backlog Audit Plan"
type: synthesis
topic: software-architecture
tags: [issue-hygiene, github, backlog, automation, agent, standards]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
---

# Issue Hygiene + Backlog Audit Plan

Plan of attack for normalizing GitHub issue quality across major Actuate repos and establishing standards for new issues. Tracked as §7 in [[mark-todos]].

## The problem (what triggered this)

The [[2026-04-17_scan|2026-04-17 repo scan]] surveyed 137 open issues across 7 major repos and surfaced a structural problem: **low label and body hygiene**.

Signals:
- Most issues carry only `bug` or `enhancement` (or nothing) — no priority, no area, no scope label
- Several issues have empty or near-empty bodies
- Ambiguous titles are common (no verb, or verb-only, or overly abstract)
- Agent-created issues in particular show inconsistent structure — likely written by different agents at different times without a shared template

Consequence: [[skill-repo-scan]] scoring is blunt. Reaction counts and comments are thin signal; labels are the main dial; labels are underused. The scan surfaces *the most label-rich issues* rather than *the highest-impact issues* — which is a shadow of what the skill is supposed to do.

## Goals

1. **Issue-creation standard** — a short, canonical template every future issue (human- or agent-created) conforms to
2. **Audit existing backlog** — a one-shot sweep that normalizes open issues against the standard
3. **Automation option** — an agent outline ([[agent-issue-auditor]]) that periodically patrols and flags hygiene regressions

Non-goals (for this phase):
- Closing stale issues at scale (needs more judgment than a first-pass audit should make)
- Force-migration of labels (may break external tooling / queries)
- Fixing Jira issues (this is GitHub-scoped; Jira has its own discipline via [[automation-jira-sync]])

## Proposed issue-creation standard

**Title** (outcome-oriented, <80 chars):
- Verb + object + (optional qualifier)
- Good: "Fix 502 from create-video under N-camera concurrency"
- Bad: "create-video issue" / "502s" / "Bug in video pipeline sometimes"

**Labels** (minimum 2 per issue):
- **Type** (one): `bug`, `enhancement`, `chore`, `docs`, `test`, `refactor`, `security`, `incident`
- **Priority** (one): `p0`, `p1`, `p2`, `p3` — aim for `p2` default, `p0`/`p1` require justification in body
- **Area** (one or more, repo-dependent): e.g. `pipeline`, `puller`, `alerts`, `admin-ui`, `infra`, `ci`

**Body sections** (markdown):
```markdown
## Context
<why this issue exists — 1-3 sentences, link to NR/Sentry if an incident prompted it>

## Problem / Behavior
<what's wrong or what's missing>

## Acceptance Criteria
- [ ] Specific, testable outcome 1
- [ ] Specific, testable outcome 2

## Out of Scope
<explicit list of things NOT being done here — prevents scope creep>

## Links
- Related issue: #NNN
- Jira: ENG-XXX (if applicable)
- KB: [[some-concept]] (if relevant)
```

Empty body issues should be treated as un-scoped — either flesh out or close.

## Audit approach (one-shot sweep)

Scope tight, then widen. Proposed order:

1. **Pilot on `vms-connector`** — largest backlog (50+), clearest test of the standard. Tune the standard based on what fits.
2. **Expand to `actuate_admin`** — next-largest backlog; different shape (more bug-reports, fewer engineering tasks).
3. **Sweep the smaller repos** — `actuate-inference-api`, `actuate-libraries`, etc. — faster passes.

Per-issue decisions (in order):
1. **Close?** — if stale, duplicate, or clearly irrelevant → close with a brief note.
2. **Re-label?** — if the issue is real but under-labeled, apply type/priority/area.
3. **Re-title?** — if ambiguous, edit title to outcome-oriented form.
4. **Re-body?** — if empty or under-specified, add at least Context + Acceptance Criteria.
5. **Link?** — connect to other issues / PRs / Jira tickets if missing.

**Batching:** process 10-20 issues per sitting. Don't marathon — audit fatigue leads to bad judgment calls, especially on "close or not?".

## Automation path ([[agent-issue-auditor]])

Once manual passes stabilize the standard and reveal repeating patterns, an agent can take over the periodic maintenance. The agent outline is sketched in [[agent-issue-auditor]]. Expected scope:

- **Read-only by default** — classifies issues against the standard; flags violations; proposes edits; does not modify without explicit arg
- **Repo-scoped** — runs against one repo per invocation (keeps context small, easy to review suggestions)
- **Outputs a markdown review** — for each violating issue, a suggested diff (new labels, revised title, suggested body structure)
- **Human approves before apply** — even in write mode, each change requires per-issue confirmation

The agent doesn't replace human judgment on "close or keep?" — that call stays manual. The agent accelerates the *normalization* decisions once the issue is staying.

## Metrics to track

Before and after the pilot sweep, capture:
- % of open issues with ≥ 2 labels (baseline: likely ~30-40% from scan data)
- % with non-empty body (baseline: likely ~60-70%)
- % with outcome-oriented title (harder to measure; sample manually)
- Median hygiene-score uplift from [[skill-repo-scan]] (direct proof the scan has better signal)

These feed into the broader [[2026-04-16_metrics-to-track|metrics-to-track]] work — issue hygiene is a code-health signal worth the dashboard.

## Effort estimate

Not a commitment — rough shape:
- Draft standard + iterate: 2-3 hours
- Pilot audit of vms-connector (50 issues): 4-6 hours across 3-4 sittings
- Audit `actuate_admin`: 3-4 hours
- Smaller repos: 1-2 hours each
- Agent outline → build: separate effort, tracked in [[agent-issue-auditor]] — ~1 week of part-time work to get to read-only version

## Non-goals (restated)

- Not closing stale issues in bulk
- Not changing label vocabulary retroactively across repos (new standard applies going forward; retroactive mapping is for during the audit)
- Not touching Jira

## Related

- [[mark-todos]] §7 — workstream tracking
- [[agent-issue-auditor]] — proposed automation
- [[skill-repo-scan]] — the scan tool whose quality improves when hygiene improves
- [[repo-backlog/_summary|repo-backlog topic]] — where scans live
- [[2026-04-16_metrics-to-track]] — hygiene % is a candidate dashboard metric
- [[2026-04-16_code-health-dashboard]] — dashboard consumer of the metric
- [[automation-jira-sync]] — Jira counterpart (out of scope here)
