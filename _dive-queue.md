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
- [ ] ds-server-container (Rust YOLO inference server) internals deep dive
- [ ] Actuate Secure / On-Prem space (AO1) full review
- [ ] Fire Detection space (FD) full review
- [ ] Billing space full review
- [ ] Update all integration topic frontmatter to reflect new subfolder paths
