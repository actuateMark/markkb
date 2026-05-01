# Reading List: Software Architecture

Sources informing the 5 sketches tracked in [[mark-todos]] §6 and the strategic topics in `software-architecture/_summary.md`: fitness functions, code-health metrics, tech-debt quantification, architecture enforcement, and the tooling landscape. Biased toward things usable in the sketch phase (Python / FastAPI / UV monorepo stack); long-form theory is seeded for later.

Convention: `- [ ] [Title](url) -- short description`. Items marked `*(seed)*` need URL resolution before reading. Check off with `[x]` as read + extract findings into `software-architecture/notes/concepts/` or `/syntheses/`.

---

## Fitness Functions & Architecture Enforcement

- [ ] [Building Evolutionary Architectures, 2nd ed. (Ford, Parsons, Kua)](https://www.oreilly.com/library/view/building-evolutionary-architectures/9781492097532/) -- **HIGH PRIORITY.** The canonical source for the fitness-function framing our [[2026-04-16_architecture-enforcement]] synthesis builds on. Ch. 2-4 for atomic vs. holistic vs. triggered functions; Ch. 5 for case studies. Direct input to the `enforcement` sketch.
- [ ] [import-linter — GitHub](https://github.com/seddonym/import-linter) -- **HIGH PRIORITY.** Python-native tool for enforcing layered / forbidden / independence import contracts. Likely the canonical implementation for the `camera/ ↛ sender/` style rules in the `enforcement` sketch. Study config format + check what Actuate codebases already do (if anything).
- [ ] [Archunit (Java) — arc unit tests](https://www.archunit.org/) -- Reference-only (not Python) but the best-documented architecture-as-tests library; patterns translate. Useful framing for what we want import-linter + our own fitness functions to eventually cover.
- [ ] *(seed)* "Evolutionary Architecture with Fitness Functions" -- ThoughtWorks tech-radar entries + conference talks; pragmatic case studies
- [ ] *(seed)* Pattern: CI gate for cyclic-dependency detection -- look for write-ups on integrating with pydeps / tach / import-linter in a real monorepo

## Code Health Metrics

- [ ] [Cyclomatic Complexity — radon docs](https://radon.readthedocs.io/) -- **Already a dep** in the sketch repo. Read the CC + MI + raw-metrics pages before writing the `metrics` collector. Particularly: what do "A/B/C/D/E/F" rank thresholds actually mean, and what's a reasonable cutoff for Actuate code?
- [ ] *(seed)* Software engineering metrics: A discipline survey -- find a recent (post-2020) survey paper on what metrics actually predict defect rates; too much folklore in this space
- [ ] [SonarQube Quality Gate docs](https://docs.sonarsource.com/sonarqube-server/latest/user-guide/quality-gates/) -- Even if we don't adopt SonarQube, their quality-gate taxonomy (reliability / security / maintainability / coverage / duplication) is the de-facto industry shape for code-health scorecards. Reference for dashboard card design.
- [ ] *(seed)* Cognitive Complexity (SonarSource whitepaper) -- the competitor metric to cyclomatic; argues cyclomatic undercounts nested-conditional difficulty. Decide whether to expose both in the `metrics` sketch.
- [ ] *(seed)* Halstead metrics -- classic but contested; skim for context, don't adopt blindly

## Tech Debt — Research & Practice

- [ ] [Martin Fowler — Technical Debt Quadrant](https://martinfowler.com/bliki/TechnicalDebtQuadrant.html) -- **HIGH PRIORITY.** Short, foundational. The "deliberate/prudent/reckless × prudent/inadvertent" framing informs how the `debt` sketch categorizes findings — not all debt is equal, and the agent should surface *why* not just *what*.
- [ ] *(seed)* "Managing Technical Debt" (SEI report, Kruchten / Nord / Ozkaya) -- longer treatment; read after Fowler's piece for depth
- [ ] *(seed)* Adam Tornhill's "Your Code as a Crime Scene" (code-maat, hotspot analysis) -- directly relevant to the `debt` sketch's stale-file + churn-vs-complexity heuristic. The tool is dormant but the ideas are live; several Python ports exist.
- [ ] *(seed)* GitHub blog post on "Code Scanning" rollout -- reference for what large organizations actually flag as debt at scale
- [ ] more of a follow up task, but we should create a task/script that can scan through all our repos for useage of the actuate libraries so that we can ensure versions are pinned. I think the main one for this is actuate-libraries itself, which should do a better job throughout of pinning the inter-library dependencies so that they can be imported together and so that we retain good posture about making sure libraries don't break each other.

## Python Static-Analysis Tooling (candidates for the `tooling` sketch)

Pick **2-3** to actually wire up. Keep the rest as seed entries for later.

- [ ] [ruff — docs](https://docs.astral.sh/ruff/) -- Already team-default. For the `tooling` sketch, the question isn't "should we use ruff" but "what ruleset does vms-connector fail, and what's the signal/noise ratio?" Write a runner that captures current violation count + top-10 rules fired.
- [ ] [radon — GitHub](https://github.com/rubik/radon) -- Complexity + maintainability index + raw metrics. **Already a dep.** Used by both `metrics` and `tooling` sketches.
- [ ] [vulture — dead code detection](https://github.com/jendrikseipp/vulture) -- Static dead-code finder. False-positive rate on dynamic Python is the main question the sketch should answer. Candidate tool #1 to actually run.
- [ ] [bandit — security linter](https://github.com/PyCQA/bandit) -- Security issue detection (hardcoded secrets, shell injection, unsafe deserialization, etc.). Low false-positive historically; good value-per-friction. Candidate tool #2.
- [ ] [pydeps — dependency graph](https://github.com/thebjorn/pydeps) -- Generates module-level import graphs; produces SVG/PNG. Useful for visualizing vms-connector's layer structure before writing enforcement rules. Candidate tool #3 or a visualization input for the dashboard.
- [ ] [tach — Python module boundary enforcement](https://github.com/gauge-sh/tach) -- Younger than import-linter but actively developed; compare both for the `enforcement` sketch.
- [ ] *(seed)* mypy / pyright -- type-checking; too heavy for first-pass tooling sketch but worth a later dedicated run against one library
- [ ] *(seed)* coverage.py + pytest-cov -- coverage collection for the `metrics` sketch; format is already `coverage.xml`, parse is trivial

## Dashboard & Visualization Patterns

- [ ] *(seed)* Grafana dashboard design principles -- sparkline density, panel hierarchy, trend-vs-snapshot. Applicable even though we're building a Flask sketch, not Grafana.
- [ ] [Chart.js — docs](https://www.chartjs.org/docs/latest/) -- Pinned from CDN in the dashboard sketch. Read the "Responsive" + "Performance" sections before adding more than 3-4 charts.
- [ ] *(seed)* "Effective monitoring dashboards" -- find a recent post-mortem-style writeup; ops community has written a lot on this, engineering-metrics dashboards inherit most principles
- [ ] *(seed)* Datadog / CodeClimate / SonarQube screenshots -- visual reference for how each handles multi-repo code-health views
- [ ] Look into hosting all of this on a new page on the miniPC. For all major repos, it should have a job that checks daily for updates/pushes and then runs all of these tools on the local instances it has of these repos for code health and quality. We want a nice clean view that shows all of the data we gather on these topics.

## Monorepo Governance

- [ ] *(seed)* Bazel / Nx / Pants -- how large monorepos enforce module boundaries mechanically. Reference only; we're not adopting any of these, but their boundary-enforcement patterns inform our fitness-function design.
- [ ] [Google's monorepo engineering practices (Potvin & Levenberg 2016)](https://cacm.acm.org/research/why-google-stores-billions-of-lines-of-code-in-a-single-repository/) -- High-level but cited constantly; worth the 20 minutes. `actuate-libraries` is a 41-package UV monorepo and some of this applies.
- [ ] *(seed)* "Living with monorepos" -- find a recent blog series or conference talk on medium-scale Python monorepo experience; Actuate is closer to Instagram/Dropbox scale than Google

## Industry Reports & Benchmarks

- [ ] *(seed)* Stack Overflow Developer Survey — tooling section -- annual; useful for "what do teams actually adopt" grounding vs. "what's hip"
- [ ] *(seed)* State of DevOps report (DORA) -- deploy frequency / MTTR / change-fail / lead-time; adjacent to code health but informs what metrics matter
- [ ] *(seed)* ThoughtWorks Tech Radar -- quarterly; filter for architecture + tooling entries

---

## How to use this file

1. Items marked `*(seed)*` need URL resolution before reading — first-pass prospector-agent run.
2. When an item is read, tick `[x]` and extract findings into `software-architecture/notes/concepts/` (single-topic capture) or `/syntheses/` (cross-source synthesis).
3. New sources surfacing during sketch work → add here under the right section.
4. Cross-pollinate with [[engineering-process/reading-list]] (KB tooling overlaps) and [[fleet-architecture/reading-list]] (K8s + autoscaling patterns that inform fitness-function design for a distributed system).

## Related

- [[software-architecture/_summary]] — parent topic
- [[mark-todos]] §6 — the sketches workstream this reading list feeds
- [[2026-04-17_local-sketches-plan]] — sketch plan with substrate decisions
- Each of the 5 sketch syntheses: [[2026-04-16_code-health-dashboard]], [[2026-04-16_tooling-landscape]], [[2026-04-16_metrics-to-track]], [[2026-04-16_architecture-enforcement]], [[2026-04-16_tech-debt-agent]]
- [[engineering-process/reading-list]] -- adjacent topic
- [[fleet-architecture/reading-list]] -- adjacent topic (K8s + distributed-system patterns)
