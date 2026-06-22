---
title: "ENG-247 Design Dig Follow-ups and Weakpoints"
type: synthesis
topic: data-access-control
tags: [eng-247, follow-ups, design-review, weakpoints, scripts]
jira: "ENG-247"
created: 2026-05-13
updated: 2026-05-13
author: kb-bot
status: open-followups
outgoing:
  - topics/actuate-platform/notes/concepts/2026-05-13_handoff-deploy-branch-phase1.md
  - topics/data-access-control/_summary.md
  - topics/data-access-control/notes/concepts/2026-05-11_admindao-call-site-inventory.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-db-access-hardening.md
  - topics/data-access-control/team-brief.md
  - topics/personal-notes/notes/daily/2026-05-13.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/actuate-platform/notes/concepts/2026-05-13_handoff-deploy-branch-phase1.md
  - topics/actuate-platform/notes/concepts/2026-05-18_handoff-deploy-branch-phase1-resume.md
  - topics/admin-api/notes/syntheses/2026-05-20_deploy-branch-full-scope.md
  - topics/data-access-control/_summary.md
  - topics/data-access-control/notes/concepts/2026-05-11_admindao-call-site-inventory.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-db-access-hardening.md
  - topics/data-access-control/team-brief.md
  - topics/personal-notes/notes/daily/2026-05-13.md
incoming_updated: 2026-05-27
---

Pressure-test run on the data-access-control proposal today (2026-05-13) exposed significant credibility issues with the headline inventory count, Phase 0 list incoherence, and gaps in operational design for Phase 2. Three scripts are addressing the enumeration side live; this note captures what's deferred and blind spots for the team session.

## Context

Today's session dug through the 6 anchor notes of the data-access-control topic to pressure-test the proposal before publishing to Confluence. Found significant credibility issues with the headline inventory count in [[2026-05-11_admindao-call-site-inventory]] (which had "*(2 more enumerated in agent report)*" as a literal placeholder row) and cohesion gaps across Phase 0 lists in [[2026-05-11_admin-incident-catalog]] and [[2026-05-11_admin-reliability-fix-plan]]. The proposal can't be published until the Phase 0 list is unified and the inventory count is verified live.

## Being addressed via scripts (today)

Three scripts being built in `/home/mork/work/scripts/data-access-control/`:

- **admindao-inventory.py** — re-runs the AdminDAO call-site audit rigorously and outputs CSV. Replaces [[2026-05-11_admindao-call-site-inventory]]'s manual table; corrects the headline "12 total" count. Initial verification today: at minimum **14 sites** (found `actuate-libraries/actuate-config/.../customer_config.py:48` and `queue_consumer/consumers/health/health_consumer.py:4,18` not enumerated). Four vms-connector `get_product_by_metrics` sites verified accurate.

- **postgres-direct-callers.py** — broader Q2 scan (psycopg2 + [[actuate-wireguard]] + raw connection strings + [[actuate-daos]] AdminDAO imports). The `actuate-wireguard` migration enumeration (committed-to but undesigned in [[2026-05-11_admin-db-access-hardening]] §"Residual direct-DB principals") falls out of this script's output as a candidate-endpoints table.

- **admin-api-surface.py** — walks [[actuate_admin]] URL conf + viewsets, outputs every endpoint with auth class, current required permission, model(s) touched. The supply side of Phase 2 — needed before scope-vocabulary assignment can begin.

All three addressed via [[2026-05-13_scripts-data-access-control]] script set.

## High-priority weakpoints in the proposal (un-addressed, still open)

**Phase 0 list incoherence.** Three different Phase 0 starter sets across the 6 notes don't compose:
- Synthesis §5 Phase 0: postmortem audit, release-gate hardening, read replica, per-token rate-limit policy, consumer-degradation reviews
- Incident catalog "Phase 0 starter set": CI query-count assertion, slow-query→NR alert, statement_timeout on read-replica, read replica, prod-snapshot dry-run migration
- Fix plan Tier 1: Fix 1A (GroupAdmin.sites() prefetch), Fix 2A (CustomerAdmin prefetches), Fix 1C statement_timeout, Fix 1D CI query-count, Fix 4C data-quality gates, verify slow-query log status, Terraformize parameter group

Additionally, Tier 1 includes Fix 1A and Fix 2A — code bug fixes ([[2026-05-11_admin-incident-catalog]] references BT-926 N+1 and missing CustomerAdmin prefetches) — framed as "reliability baseline." That's a stretch. **Action:** pick ONE Phase 0 list; demote the rest to "near-term reliability work" or a separate workstream. Reconciliation step required before Confluence.

**Per-service degradation questions unanswered.** Synthesis §5e lists per-service degradation options (cache last-known-good, read-replica fallback, fail fast, degraded mode) but the decision for vms-connector / queue-consumer / autopatrol-server is "answered in Phase 0 degradation reviews" — which haven't started. This is load-bearing for Phase 2 cutover; risk is declaring Phase 0 complete will slip if these aren't scheduled now.

**Token storage / per-pod-vs-shared / rotation mechanism not specified.** Synthesis §5 Phase 2 says "Per-service API tokens minted via ExternalApiSetUp, stored in Secrets Manager with per-service paths." Missing details: is each pod its own token (per-instance) or one shared per service? How does each pod fetch its token (IRSA? Secrets Store CSI driver? sidecar?)? Rotation cadence? These affect operational complexity and blast radius. Concrete operational design required before Phase 2 starts.

## Open-question pressure points (for the team session)

Blind spots in [[2026-05-11_open-question-vini-gateway]] and [[2026-05-11_open-question-developer-tokens]] that warrant team discussion:

**Vini gateway extend-or-parallel — blind spots in the "parallel-but-compatible" lean:**
- **Latency math may be wrong.** Note cites "20-30ms extra round-trip" per hop × 6 lookups per session = 180ms total. If vms-connector sessions are long-lived (hours), this is rounding error. Need session-lifetime data before treating latency as a deal-breaker.
- **"Decoupled delivery" assumes ENG-122 is slow.** The note's own Question 1 asks "What's ENG-122's realistic delivery timeline?" but doesn't answer it. Should *gate* the decision, not flavor it.
- **B's rebuild cost (rate limit + structured logs) isn't scoped.** Could be 1 week or 1 month.
- **Missing: AWS API Gateway per-request cost.** For high-volume east-west, this matters or doesn't — needs back-of-envelope math before deciding.

**Developer tokens composition pathway — blind spots in the "Option B + interim Option A" lean:**
- **"Today's pattern is 10 steps" is overstated.** Admin already has quick ad-hoc endpoints; the framing exaggerates current friction.
- **Option B requires `actuate-admin-api` parity.** Composition library on admin doesn't help unless typed methods also land in the consumer client. Doubles the scope.
- **Option D (audited break-glass cred) is undersold.** Dismissed on "discipline drift" grounds, which is a values argument. May actually be 90% safety at 5% cost; worth a serious comparison rather than a footnote.

## Other findings (defer or address as time allows)

- **Audit-log durable storage open** ([[2026-05-11_admin-db-access-hardening]] §6) but §5d already commits to "≥1-year retention" — pick a venue (Postgres audit table on admin DB, S3+Athena, dedicated audit DB) before the commitment is meaningful.
- **No DR / cross-region story for admin.** Once admin is the single API path for application traffic, its disaster-recovery story becomes critical. Synthesis doesn't address cross-region failover, RDS failover testing, backup/restore drill cadence.
- **Scope-vocabulary deferred** to "concept note to spin up next" — but every Phase 2 endpoint needs a scope; can't assign without the vocabulary. Should be a Phase 2 pre-req, not a parallel task.
- **`actuate-daos` library lifecycle.** Synthesis says `admin_dao.py` eventually "moves into admin's own source tree." But the library publishes via CodeArtifact; other consumers may still want `admin_dao.py` for fixtures/mocks. Migration path for the package itself isn't clear.
- **Library-side AdminDAO callers** ([[actuate-monitoring]], [[actuate-config]]) instantiate AdminDAO inside library code, not just service code. The synthesis's "only admin_dao.py needs migration" framing in [[2026-05-11_admin-db-access-hardening]] §2.4 is misleading — library import patterns also need rewriting. This will get cleaner once the admindao-inventory script enumerates them.

## Reading order if revising the proposal

1. This synthesis — what's deferred + what's scripted
2. Re-run script outputs (once committed) — replaces [[2026-05-11_admindao-call-site-inventory]]'s headline table
3. Pick ONE Phase 0 list, then update [[2026-05-11_admin-db-access-hardening]] §5 Phase 0 + [[2026-05-11_admin-incident-catalog]] starter set + [[2026-05-11_admin-reliability-fix-plan]] Tier 1 to align
4. Per-service degradation reviews — schedule before declaring Phase 2 cutover ready
5. Pressure-test the two open questions during the team session (use blind-spot bullets above as the framing)
6. Once revised, publish to Confluence with confidence

## Related

- [[2026-05-11_admin-db-access-hardening]] — parent synthesis (the proposal being tightened)
- [[2026-05-11_admindao-call-site-inventory]] — being replaced by script output
- [[2026-05-11_admin-incident-catalog]]
- [[2026-05-11_admin-reliability-fix-plan]]
- [[2026-05-11_open-question-vini-gateway]]
- [[2026-05-11_open-question-developer-tokens]]
- [[team-brief]]

---

**Status:** open follow-ups; revisit before publishing Confluence write-up.
