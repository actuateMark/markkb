---
title: "2026-06-16 Watchman Pipeline & Backend Architecture Meeting"
type: synthesis
topic: watchman
tags: [watchman, architecture, pipeline, backend, meeting, fleet-architecture, lambda, storage, aws]
jira: null
confluence: "https://actuate-team.atlassian.net/wiki/spaces/PM/pages/629112838"
created: 2026-06-16
updated: 2026-06-17
author: kb-bot
related:
  - "[[2026-06-02_watchman-phase0-fleet-fit]]"
  - "[[2026-05-29_watchman-judge-backend-io-contract]]"
  - "[[2026-05-29_watchman-prds-summary]]"
  - "[[2026-06-02_frontend-sketch-ui]]"
  - "[[topics/fleet-architecture/_summary]]"
---

# 2026-06-16 Watchman Pipeline & Backend Architecture Meeting

Planning output from Valeri's pipeline review and backend architecture kickoff. **Captured what is NEW since [[2026-06-02_watchman-phase0-fleet-fit]], what is NOW DECIDED, and what remains OPEN.**

## Current Pipeline State

**Version:** v2 with re-identification variant implemented. Alert ID naming scheme needs cleanup; alert grouping rules ("grouped by x?") are unspecified.

**Parity question:** Pipeline output has NOT yet been apples-to-apples compared against the [[vms-connector]]. The connector can supply motion blobs, frames, and all upstream signals the pipeline needs. Before backend plumbing, validate that pipeline output matches connector capability and that there are no missing inputs.

**Key artifact:** Confluence JSON schema pages define the concrete output contract: "Watchman WS /events/stream — v1 schema" (page 600637443) and detection-output schema. Pipeline output must conform to these objects.

## Backend Architecture Direction

**Start point:** Doubletake-pattern Lambda, invoked *during* the connector run (not post-hoc), writes pipeline results to a window-id table or other backing store — same infrastructure shape as [[doubletake]].

**Storage layer — OPEN DECISION (three options being evaluated):**
- **Postgres** — traditional; familiar ops.
- **OpenSearch** — Jagadish's suggestion; simplifies integration to the current Actuate stack (already in use elsewhere).
- **S3 vector search** — Otzar has prior experience; decouples storage from index.

**API layer:** After Watchman operators label site/alert/event metadata, engineering builds the REST/GraphQL API on top of the chosen store to feed Brad's [[2026-06-02_frontend-sketch-ui|UI]].

**Forensic search backend:** Separate track. Requires GPUs, sentence-transformers, vector DBs for the conversational "find vehicles at sports rental" UX.

## Operational & AWS Decisions

**AWS account:** NO new account for now. Terraform on the **dev account is acceptable** for pipeline + backend development. Cost is lower; avoiding a new account sidesteps the overhead of a separate New Relic account + GDPR setup.

**Gotcha:** Before dev pushes code, add a **cleanup + documentation step** to the task. Frame it as a security-hardening opportunity (tear down test infra, document what was temporary, archive results).

**Trade:** Dev account infra is not customer-facing; do not assume persistence or production-grade availability.

## Next Steps & Work Split

**~End of week:** Split into two tracks:
- **Connector component:** Valeri to implement the connector-side Lambda (see open question below).
- **Backend & API:** Team to prototype storage layer evaluation and stand up the API skeleton.

**Action items:**
1. Valeri: implement connector-side Lambda invocation + window-id table writes.
2. Eng: evaluate storage options (Postgres vs OpenSearch vs S3) with prototype perf/cost/integration tests.
3. Ops: document cleanup checklist for dev account teardown (logging, Terraform modules, data retention).

## Open Questions (carry into implementation)

1. **Lambda invocation point:** Where exactly in the connector's run lifecycle should the Lambda fire? (Post-detection? Post-window-confirmation? Per-camera or per-site aggregation?) — Valeri and eng to pair on trigger semantics.

2. **Alert ID / grouping cleanup:** Current naming needs refinement. What defines an "alert group"? Is it per-camera, per-window, per-incident? Needed before backend schema stabilizes.

3. **Pipeline-vs-connector parity:** Formal comparison of pipeline input assumptions against connector-supplied signals. If inputs diverge, backfill or pivot the pipeline.

4. **Storage choice impact:** Each option (Postgres / OpenSearch / S3) has different query patterns, cost curves, and Watchman-integration complexity. Prototype results will drive the pick; no commitment until perf data is in hand.

5. **Schema versioning:** How should backend handle future pipeline schema changes? Versioning strategy for rolling deploys.

## Integration with Phase 0 Plan

This meeting **refines and extends** [[2026-06-02_watchman-phase0-fleet-fit]] in two ways:

**NEW from phase-0 plan:**
- Concrete Lambda backend shape (phase-0 was abstract about storage; this makes it real).
- Forensic search backend as a separate track (not in phase-0 MVP scope, but necessary for Brad's UI).
- Storage evaluation as a decision gate (phase-0 left "WMS state store" open; now it's concrete options).

**DECIDED from phase-0 unknowns:**
- AWS dev account for prototyping (vs. hesitation about infra sprawl).
- Doubletake-pattern Lambda as the starter (vs. other possible architectures).
- No new AWS account (keeps ops lean during pilot).

**STILL OPEN from phase-0:**
- Backend storage choice (Postgres vs OpenSearch vs S3).
- Lambda invocation point in the connector lifecycle.
- Full Watch entity schema integration (phase-0 defers this; now part of backend API design).

**Unchanged from phase-0:**
- Stateless detection fleet for phase 0 (windowing / tracker state deferred to E-proper).
- Judge contract as the alert emit boundary ([[2026-05-29_watchman-judge-backend-io-contract]]).
- WMS as fleet-singleton reconciler (greenfield, K8s-native).
- SQS transport to Judge (Kafka later, per [[2026-05-29_watchman-judge-backend-io-contract]] decision #3).

## Related Decisions Implicit Here

- **Surveillance stream:** Phase 0 pins to Redis Streams as the frame-bus (per [[2026-06-02_watchman-phase0-fleet-fit]]); pipeline consumes that stream + motion signals from the connector.
- **Watch arming:** Manager Service arms/disarms; disarmed cameras emit no detections (phase-0 design confirmed by this meeting's Lambda-invocation context).
- **Frontend contract:** Brad's UI expects [[2026-06-02_frontend-sketch-ui]] — conversational forensic search + Patrol/Active mode toggle. Backend must support queryable detection history + per-site mode state.

## Cross-references

- **Fleet architecture parent:** [[topics/fleet-architecture/_summary]]
- **Phase-0 ingest pipeline:** [[2026-06-02_watchman-phase0-fleet-fit]]
- **Judge alert contract:** [[2026-05-29_watchman-judge-backend-io-contract]]
- **Watch Management Service:** [[2026-05-28_watch-management-service-design]]
- **Frontend design:** [[2026-06-02_frontend-sketch-ui]]
- **Workstream §5:** Active workstream tracking backend build progress

---

## Notes / Open Questions for Mark

**Storage decision blocks backend schema:** The choice between Postgres / OpenSearch / S3 vector search will determine how alerts and detections are indexed and queried. Should this be decided before Valeri builds the Lambda, or is it safe to start with a generic output format and plug in storage later?

**Lambda invocation point needs API design alignment:** If the Lambda fires during connector run, it creates a bidirectional dependency (connector → Lambda → backend writes). Does the backend write need to block the connector, or is async/fanout acceptable? This affects whether Lambda sits in-process (synchronous pull) or out-of-band (asynchronous push).
