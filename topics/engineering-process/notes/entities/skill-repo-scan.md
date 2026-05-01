---
title: "Skill: /repo-scan"
type: entity
topic: engineering-process
tags: [skill, github, opportunity, personal-workflow]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
---

# /repo-scan

Cross-repo GitHub issue scan — surfaces high-impact work and low-hanging fruit across major Actuate repos that isn't already in [[mark-todos]] or assigned to Mark. Read-only digest, not full issue bodies.

**Installed at:** `/home/mork/.claude/skills/repo-scan/SKILL.md`

## Why this exists

The [[automation-jira-sync]] job only covers Jira tickets assigned to Mark. GitHub issues that are:
- Assigned to someone else (or nobody)
- In a repo Mark doesn't touch daily
- Filed recently by partners or users

…are invisible to the existing daily flow. This skill fills that gap.

## When to trigger

- Periodic "what else is happening" sweep (weekly or ad-hoc)
- When the current workstreams feel light on concrete execution work
- Via `/daily-scope --with-repo-scan` during morning planning
- When hunting for a quick win between larger work chunks

Trigger phrases: `/repo-scan`, "repo scan", "scan repos", "low hanging fruit", "what should I pick up".

## Output shape

Two categorized buckets:

| Bucket | Signal |
|--------|--------|
| 🔥 High Impact | P0/P1/critical/priority/urgent labels, bug/production/incident/security labels, high reaction/comment counts, recent activity |
| 🧹 Low-Hanging Fruit | `good-first-issue`, `chore`, `docs`, `refactor`, `cleanup`, `test` labels; no assignee; tight scope; clear body |

Down-ranked by default: assigned issues (pass `--include-assigned` to see them too), epic/complex/spike labels.

## Default repo set

`vms-connector`, `actuate-libraries`, `actuate-inference-api`, `actuate_admin`, `autopatrol_onboarder`, `autopatrol-server`, `camera-ui`.

Override via `--repos a,b,c`.

## Caching

Raw `gh` response cached to `~/.cache/repo-scan/<YYYY-MM-DD>.json` so re-runs within a day are free. `--refresh` forces re-fetch.

## KB persistence

Every scan writes a dated note to `topics/repo-backlog/notes/scans/<YYYY-MM-DD>_scan.md`:

- Two tables (high-impact + LHF), each with direct GitHub URLs in the title column
- Picked-up tracker at the bottom (manual or `/todos-add`-driven)
- Overwrites within the same day (latest snapshot wins); past days are immutable

The parent topic's `_summary.md` lists all scan dates, so trends over time are easy to see.

## Relation to other skills

| Skill | Role |
|-------|------|
| [[skill-daily-scope]] | Can invoke /repo-scan via `--with-repo-scan` to fold GH issues into the scope interview |
| [[automation-jira-sync]] | Covers Jira-assigned tickets; /repo-scan covers GitHub issues regardless of assignee (complementary) |
| [[skill-todos-add]] | After /repo-scan surfaces something worth pursuing, /todos-add scaffolds the workstream |

## Scoring caveats

- **Don't infer priority from title keywords.** "Critical" in a title isn't signal; a `critical` label is.
- **Assigned issues are down-ranked, not hidden.** Someone else being on it lowers the "pick this up" score but doesn't zero it — sometimes a stalled assignee's work is a good place to help out.
- **Body length is a heuristic for ease.** A long body with checkboxes usually = well-specified, picker-friendly. An empty body usually = needs re-scoping before it's fruit.

## Related

- [[skill-daily-scope]] — invokes /repo-scan via `--with-repo-scan`
- [[mark-todos]] — destination for any picked-up issues
- [[automation-jira-sync]] — complementary Jira-side sync
