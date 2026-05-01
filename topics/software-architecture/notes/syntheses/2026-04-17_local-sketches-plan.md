---
title: "Local Sketches Plan — 5 software-architecture projects + dashboard"
type: synthesis
topic: software-architecture
tags: [sketch, prototype, dashboard, tech-debt, enforcement, metrics, tooling]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/software-architecture/_summary.md
  - topics/software-architecture/notes/concepts/2026-04-23_sketch-findings-metrics.md
  - topics/software-architecture/reading-list.md
incoming_updated: 2026-05-01
---

# Local Sketches Plan

Lightweight local prototyping pass for the 5 software-architecture projects/designs drafted 2026-04-16. **Goal: build intuition, surface integration points, and prioritize — not to ship production tooling.**

Tracked in [[mark-todos]] §6.

## What's getting sketched

The [[knowledgebase/topics/software-architecture/_summary|topic]] defines 5 syntheses. Each gets a minimal local sketch:

| Project | Synthesis | Sketch scope |
|---------|-----------|--------------|
| Code health dashboard | [[2026-04-16_code-health-dashboard]] | Minimal web UI or CLI that reads metrics from the other 4 sketches and shows one page. Could be a single HTML file + JSON input or a tiny Flask/FastAPI. |
| Tooling landscape | [[2026-04-16_tooling-landscape]] | Pick 2-3 tools from the catalog and actually run them on one Actuate repo — capture installation friction, output quality, false-positive rate |
| Metrics to track | [[2026-04-16_metrics-to-track]] | Write a minimal collector script for 1-2 key metrics (e.g., complexity + coverage) on one repo. Output a JSON the dashboard can consume. |
| Architecture enforcement | [[2026-04-16_architecture-enforcement]] | Prototype one fitness function (e.g., "no layer X imports from layer Y") as a test or CI gate. Something executable. |
| Tech debt agent | [[2026-04-16_tech-debt-agent]] | Minimal patrol-and-report pass — a script (or headless Claude invocation) that scans one repo and emits a debt report in a format the dashboard can render. |

## Why "sketch" and not "PoC"

These are paper designs. A PoC implies a committed investment in direction. A sketch is cheaper: it's for *learning*, not committing. Specifically, sketches help:

- **Find integration points** — the dashboard can't just be mock data; making it render real output from the metrics collector + tech-debt agent forces the contract to be real
- **Surface unexpected complexity** — picking up 2 tools from the tooling landscape and running them will reveal install/config friction that the synthesis couldn't anticipate
- **Prioritize** — some of the 5 may turn out to be a-day-of-work and others a-quarter-of-work; the sketch is the cheapest way to learn which is which

## Shared substrate decisions (open)

Before starting, decide:

- **One repo or many?** — easier to iterate in one sandbox repo vs. sprinkled across actual Actuate codebases. Probably: one scratch repo for code-health-dashboard + metrics-to-track + architecture-enforcement + tech-debt-agent, pointed at a *real* Actuate repo as its input.
- **Language?** — Python matches the team default; TypeScript gives better dashboard-UI ergonomics. For sketches, Python for everything is fine — the dashboard can be a plain HTML + Chart.js page reading from a JSON produced by the Python tools.
- **Where does the data live?** — JSON files on disk for the sketch phase. A database is premature.
- **How is the dashboard invoked?** — `make` target that runs all 4 collectors then opens the dashboard locally.

## Integration-point contract (the important bit)

For the sketches to be useful, the interfaces between them have to be real. Draft contract:

```
Metrics collector  -> metrics.json    (per-repo, per-commit)
Enforcement check  -> violations.json (per-repo, per-run)
Tech debt agent    -> debt-report.md + debt-metrics.json (per-repo, per-scan)
Tooling outputs    -> tools/<name>.json (per-tool, whatever shape the tool emits)

Dashboard reads all of the above, renders a single page with:
  - Health scorecard (aggregated from metrics.json + violations.json)
  - Tech debt summary (from debt-metrics.json; links to debt-report.md)
  - Per-tool output viewer (from tools/*.json)
  - Trend lines if multiple runs are present
```

This contract is aspirational for the sketch — don't over-engineer it. Simple JSON blobs matching rough shapes are fine.

## Per-sketch notes

For each sketch, write `software-architecture/notes/concepts/2026-XX-XX_sketch-findings-<name>.md` capturing:
- What was surprisingly easy
- What was surprisingly hard
- Concrete numbers (lines of code, runtime, false-positive rate if applicable)
- What it implies for a real implementation: day-of-work? week-of-work? month-of-work?
- Whether the paper design's assumptions held up

## Consolidation

After all 5 sketches, write `software-architecture/notes/syntheses/2026-XX-XX_sketch-findings-summary.md`:
- Cross-sketch comparison
- Updated integration-point contract based on what actually worked
- Prioritized order: which to invest in first, which to defer, which to abandon
- Input to whichever ADR or ticket set graduates from the sketch phase

## Non-goals

- **Production-ready anything.** This is a throwaway sandbox.
- **All 5 tools from the tooling landscape.** Pick 2-3 and learn deeply, don't try to cover everything.
- **Dashboard visual polish.** Plain HTML + Chart.js with defaults is fine.
- **CI integration.** Local only for the sketch phase.

## Timeline ballpark

Rough, not a commitment:
- Shared substrate setup + integration-contract sketch: 0.5-1 day
- Each sketch: 0.5-1 day
- Dashboard wiring: 0.5-1 day
- Per-sketch notes: parallel with sketch work
- Consolidation synthesis: 0.5 day
- **Total sketch phase:** ~1 week of focused time (or distributed across 2-3 weeks of part-time)

## Related

- [[knowledgebase/topics/software-architecture/_summary]] — parent topic
- [[mark-todos]] §6 — workstream tracking
- Each synthesis this plan sketches: [[2026-04-16_code-health-dashboard]], [[2026-04-16_tooling-landscape]], [[2026-04-16_metrics-to-track]], [[2026-04-16_architecture-enforcement]], [[2026-04-16_tech-debt-agent]]
- [[fleet-architecture/_summary]] — separate R&D track (tracked as §5); don't confuse with this one
