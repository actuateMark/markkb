---
title: "Local Sketches Plan — 5 software-architecture projects + dashboard"
type: synthesis
topic: software-architecture
tags: [sketch, prototype, dashboard, tech-debt, enforcement, metrics, tooling]
created: 2026-04-17
updated: 2026-04-23
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

## Shared substrate decisions (RESOLVED 2026-04-22)

All substrate decisions below are locked as of 2026-04-22 via the user interview in the `/daily-scope` task-2 execution. Prior "open" framing preserved at the end of this section for provenance.

### Decisions

- **Repo layout: one scratch repo, flat.** `~/work/software-arch-sketches/` containing all 5 sketches as sibling modules under a single Python package. Shared `pyproject.toml`, shared venv, cross-module imports allowed (dashboard can import directly from metrics/enforcement/debt modules). Tooling-landscape sketch lives in its own sub-module but still in the same repo.
- **Input repo: `vms-connector`** (at `/home/mork/work/vms-connector`). Pointed at via env var `SKETCH_INPUT_REPO` with a sensible default. Biggest + most real-world-messy Actuate repo → best signal for enforcement / metrics / debt sketches. If tooling-landscape wants a second repo for coverage, pick ad-hoc per-tool during that sketch.
- **Language: Python 3.12+.** No TypeScript. Dashboard is Flask or FastAPI + Jinja2 + Chart.js loaded from CDN — plain HTML, no build step.
- **Data format: JSON files on disk.** `data/` directory inside the repo; one JSON per sketch output plus a `data/tools/` subdirectory for tooling-landscape output. No database. No Redis. No S3.
- **Dashboard invocation: `make all`** runs collectors + renders dashboard JSON; `make serve` spins up a local Flask on `localhost:8000` rendering from the JSONs.
- **Package layout** (proposed, may evolve during sketch phase):
  ```
  ~/work/software-arch-sketches/
    pyproject.toml
    Makefile
    README.md
    src/software_arch_sketches/
      metrics/           # metrics collector
      enforcement/       # fitness-function checks
      debt/              # tech-debt agent
      tooling/           # third-party tool runners
      dashboard/         # Flask app + templates
    data/                # JSON outputs
      metrics.json
      violations.json
      debt-metrics.json
      debt-report.md
      tools/
    scripts/
      run_all.sh
  ```

### Rationale

- **One flat repo** beats per-sketch subdirs or per-sketch repos because the integration-point contract below *requires* cross-sketch composition. The dashboard's whole value is reading real output from the other 4; isolating them makes the contract synthetic. One repo with shared deps + cross-module imports keeps friction to zero.
- **vms-connector** beats inference-api / actuate-libraries / multi-repo on signal density. Enforcement fitness functions have obvious targets (camera/pipeline/observer layer rules), metrics have scale (12+ libraries worth of code), debt agent has real drift to find. The other candidates were cleaner but would yield less signal-per-sketch-hour.
- **Python-only** beats mixed because it keeps the substrate minimal and matches team default. Dashboard-UI ergonomics with TypeScript would be marginal for throwaway sketches.

### Provenance (open framing, pre-decision)

> Before starting, decide:
> - **One repo or many?** — easier to iterate in one sandbox repo vs. sprinkled across actual Actuate codebases. Probably: one scratch repo for code-health-dashboard + metrics-to-track + architecture-enforcement + tech-debt-agent, pointed at a *real* Actuate repo as its input.
> - **Language?** — Python matches the team default; TypeScript gives better dashboard-UI ergonomics. For sketches, Python for everything is fine — the dashboard can be a plain HTML + Chart.js page reading from a JSON produced by the Python tools.
> - **Where does the data live?** — JSON files on disk for the sketch phase. A database is premature.
> - **How is the dashboard invoked?** — `make` target that runs all 4 collectors then opens the dashboard locally.

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

## Scaffolding complete (2026-04-22)

Repo scaffolded at **`/home/mork/work/software-arch-sketches/`** per the substrate decisions above. What landed:

- Git-init'd on `main`; not yet pushed to a remote.
- `pyproject.toml` (hatchling build, Python 3.12+, deps: `click`, `flask`, `radon`; dev: `pytest`, `ruff`, `mypy`)
- `Makefile` with targets: `help`, `install`, `metrics`, `enforce`, `debt`, `tools`, `collect`, `dashboard`, `serve`, `all`, `test`, `lint`, `clean`
- `README.md` with run instructions + per-sketch status table
- `src/software_arch_sketches/` package tree:
  - `__init__.py` + `config.py` (input-repo + data-dir resolution)
  - `metrics/`, `enforcement/`, `debt/`, `tooling/`, `dashboard/` — all siblings, cross-module imports allowed
  - `dashboard/app.py` (Flask, `--render-only` / `--serve` modes, `/api/data` endpoint) + `templates/index.html` (Chart.js-from-CDN shell)
- `tests/test_smoke.py` — 6 tests verifying each module imports + each stub emits its envelope
- `data/` directory + `data/tools/` with `.gitkeep`s

**Verification:** `make install` + `pytest -q` → 6 passed. Each stub runs via `python -m software_arch_sketches.<sketch>.<entry>` and writes its JSON. Dashboard `--render-only` confirms all 4 data sources are visible.

**Install note:** default PyPI index was CodeArtifact (auth expired); installed via public PyPI with `--index-url https://pypi.org/simple/ --index-strategy unsafe-best-match`. For durability either (a) refresh CodeArtifact auth when starting work, or (b) drop a local `uv.toml` pinning public PyPI. Not baked into the scaffold yet.

**Known minor noise:** 4 `datetime.utcnow()` DeprecationWarnings across the stub modules (Python 3.12+ prefers `datetime.now(datetime.UTC)`). Harmless for sketches; trivial 1-line fix per module when fleshing out.

**First commit is pending user approval** — repo is git-init'd but nothing committed yet.

## First commit + uv migration (2026-04-23)

Initial commit `6f80028` on `main` bundles the scaffold with the four deferred fixes flagged on 2026-04-22:

- **Remote decision** — local-only for now; no GitHub repo created. Plan to push once a sketch produces signal worth sharing. User directive: commit often regardless.
- **utcnow deprecation** — all four `datetime.utcnow()` sites (`metrics/collector.py`, `enforcement/rules.py`, `debt/patrol.py`, `tooling/runners.py`) migrated to `datetime.now(timezone.utc)`. Verified via `python -W error::DeprecationWarning` on every entry point.
- **Installer** — uv replaces pip. Makefile `install` target runs `uv sync --all-extras`; per-sketch / test / lint targets run via `uv run`.
- **Index persistence** — the previous install failure (CA auth expired → click/flask/radon unresolvable) was diagnosed down to the user's global `~/.config/uv/uv.toml` pinning CodeArtifact as the only index plus shell env vars `UV_INDEX` / `UV_INDEX_CODEARTIFACT_PASSWORD` overriding project-local config. Resolution:
  - Local `uv.toml` in the project declares two indexes: `pypi` (`default = true`) and `actuate-codeartifact` (`explicit = true`). Public PyPI is the baseline for sketches; CodeArtifact stays reachable for dev-version pulls of [[actuate-libraries|Actuate libraries]] via `[tool.uv.sources]` override.
  - Makefile `install` target runs `env -u UV_INDEX -u UV_INDEX_CODEARTIFACT_PASSWORD -u UV_INDEX_CODEARTIFACT_USERNAME uv sync --all-extras --no-config --default-index https://pypi.org/simple/` to bypass both env-var and global-config interference for the initial bootstrap.
  - `uv.lock` committed. After the first install, subsequent `uv sync` calls (including from the user's normal CA-default shell env) use the lockfile and never hit any index.
- **Dev-version workflow** — documented in README "Pulling dev versions of actuate-libraries": refresh CA auth with `aws codeartifact login`, add the dep under `[tool.uv.sources]` pointing at the `actuate-codeartifact` index, re-sync. Keeps drift-avoidance cheap without daily CA auth overhead for baseline work.

Tests: 6/6 green (`make test`). No DeprecationWarnings from stub entry points.

Unblocks [next concrete step #1](#next-concrete-steps-in-recommended-order) — first real sketch is the metrics collector (radon cc across `vms-connector`).

### Next concrete steps (in recommended order)

1. Fill in `metrics.collector` — `radon cc` across `vms-connector` Python files, write per-file + summary into `data/metrics.json`. ~2 hours.
2. Fill in `enforcement.rules` — pick 2-3 layer-import rules (e.g. `camera/` ↛ `sender/`), AST-parse imports, emit `data/violations.json`. ~3 hours.
3. Wire dashboard to render metrics + violations summary (scorecards, not just raw JSON). ~2 hours.
4. Fill in `debt.patrol` — TODO/FIXME grep, stale-file detection via `git log`, large-function heuristic. ~3 hours.
5. Pick 2 tools from the tooling-landscape catalog, write subprocess runners, capture install friction + output-quality findings. ~4 hours.
6. Consolidation synthesis at `topics/software-architecture/notes/syntheses/2026-XX-XX_sketch-findings-summary.md`.

## Related

- [[knowledgebase/topics/software-architecture/_summary]] — parent topic
- [[mark-todos]] §6 — workstream tracking
- Each synthesis this plan sketches: [[2026-04-16_code-health-dashboard]], [[2026-04-16_tooling-landscape]], [[2026-04-16_metrics-to-track]], [[2026-04-16_architecture-enforcement]], [[2026-04-16_tech-debt-agent]] — each has its own "Sketch status (2026-04-22)" block at the top
- [[fleet-architecture/_summary]] — separate R&D track (tracked as §5); don't confuse with this one
- [[core-repo-suite]] — `software-arch-sketches` added to the Local list 2026-04-22
