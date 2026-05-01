# Dive Queue

Sources and topics queued for future ingestion.

## Priority: Integration Summaries (agents hit usage limit)

- [ ] Write _summary.md for all 29 integration topics (immix, milestone, sentinel, bold, patriot, etc.)
- [ ] Read alarm sender source code for each integration
- [ ] Read puller source code for each integration
- [ ] Cross-reference with connector factory in vms-connector

## Priority: Model Summaries (agents hit usage limit)

- [ ] Write _summary.md for all 13 model topics (intruder-v5, intruder-v8, weapon-v8, fire, etc.)
- [ ] Read model config from actuate-config for confidence thresholds
- [ ] Cross-reference with pipeline steps and observers

## Priority: Synthesis Notes (agents hit usage limit)

- [ ] How a frame becomes an alert (end-to-end trace)
- [ ] Integration landscape (all 27+ integrations mapped)
- [ ] Library-connector dependency map
- [ ] Watchman vs current platform comparison
- [ ] Model lifecycle (training to production)

## Queued

- [ ] kb Confluence space deep dive (200 pages, only overview scanned)
- [ ] Individual actuate-library README files from GitHub (41 packages)
- [ ] shadow-test-eval repo documentation
- [ ] **[high — blocks fleet-architecture]** `kubernetes-deployments` repo deep dive — how are sites launched today? One deployment-per-site? Shared? Per-integration? Needed to resolve site-connectivity gaps in [[fleet-architecture/notes/concepts/customer-site-connectivity]]
- [ ] **[high — blocks fleet-architecture]** `connector_deployer` architecture deep dive — how does it route to NAT / VPN / public sites? What per-site auth/session state exists? Feeds puller fleet design for every proposal (A-E)
- [ ] Map the distribution: fraction of sites using public / WireGuard / customer-VPN / NAT-out connectivity (needed to size puller fleets)
- [ ] ds-server-container (Rust YOLO inference server) internals deep dive < bump this up priority to help with intruder v8 deployment
- [ ] Actuate Secure / On-Prem space (AO1) full review
- [ ] Fire Detection space (FD) full review
- [ ] Billing space full review
- [ ] Update all integration topic frontmatter to reflect new subfolder paths

## Missing entity articles (surfaced 2026-05-01 via `obsidian unresolved`)

Auto-discovered from unresolved `[[wikilinks]]` — files that other notes try to link to but which don't exist. Each represents a real entity that prose already references; creating the entity article would close the link gap and fix orphans.

### actuate-libraries (referenced from prose, no entity article exists)

These are internal Python packages from `aegissystems/actuate-libraries`. Each should get an entity note in `topics/actuate-libraries/notes/entities/<slug>.md` with a brief description of the package's purpose, public API surface, primary consumers (vms-connector, autopatrol-server, inference-api), and Confluence/repo link.

- [ ] actuate-filters
- [ ] actuate-frames
- [ ] actuate-image-cache
- [ ] actuate-math
- [ ] actuate-pipeline
- [ ] actuate-pipeline-objects
- [ ] actuate-platform
- [ ] actuate-threadpool

### Date-prefixed unresolved references (likely typo or filename drift)

These are `[[YYYY-MM-DD_<slug>]]` references that don't resolve. Some may exist with a slightly different slug (typo); others may have been planned but never written. `/kb-lint` should surface the source files for triage.

- 11 date-prefixed unresolved refs (see `obsidian unresolved` for full list)

### Reference patterns that need a different fix (not ingestion)

- **Bare topic-name wikilinks** like `[[admin-api]]`, `[[autopatrol]]`, `[[aws-cost]]` — should be rewritten to `[[<topic>/_summary|<Topic Name>]]`. ~30 cases. Candidate for a one-off bulk find+replace, NOT an entity-creation task.
- **Python class names** like `[[ActiveCamHealthcheckRunner]]`, `[[BlurHandler]]`, `[[AvigilonDiagnostics]]` — class names referenced via wikilinks. Decision: either (a) drop the wikilinks (these are code identifiers, not KB entities) or (b) create a `class-docs/` synthesis note per repo. Default: (a) — strip the wikilinks.
- **Skill-name shorthand** like `[[api-endpoint-development]]`, `[[autopatrol-cleanup-lambda-check]]` — meant to refer to skill entities. Skill entities live at `topics/engineering-process/notes/entities/skill-<name>.md`. Fix: rewrite as `[[skill-<name>|/<name>]]`.
