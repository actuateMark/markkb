---
title: "Terminology Conflict: Watchman Product Definition (Cloud vs Edge) — RESOLVED"
type: concept
topic: fleet-architecture
tags: [watchman, terminology, product-scope, resolved, cloud-vs-edge]
jira: ""
confluence: ""
created: 2026-06-01
updated: 2026-06-01
author: kb-bot
incoming:
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-06-01_adr-watchman-mvp-slim-connector.md
  - topics/personal-notes/notes/daily/2026-06-01.md
incoming_updated: 2026-06-19
---

# Terminology Conflict: Watchman Product Definition (Cloud vs Edge) — RESOLVED

## Resolution (2026-06-01)

**RESOLVED:** "[[watchman-repo|Watchman]]" is an overloaded term in architecture discussions.

- **KB [[watchman-repo|Watchman]]** (topics/watchman/_summary) = cloud-native, multi-agent AI security operator. This is the product, the fleet-rearchitecture integration, the Agent infrastructure, and the target for the MVP slim connector work.
- **v10 Doc "[[watchman-repo|Watchman]]"** (line 312 of the received architecture) = on-prem/edge variant mentioned as a contrast to v10's cloud-only scope. This is NOT the same product and does NOT refer to the Actuate [[watchman-repo|Watchman]] in the KB.

**Implication:** The [[watchman-repo|Watchman]] MVP slim connector work targets **KB [[watchman-repo|Watchman]] (cloud-native)**, and the v10 document's on-prem reference is a separate deployment scenario unrelated to this effort.

**Cross-link:** See [[2026-06-01_adr-watchman-mvp-slim-connector|Watchman MVP Slim Connector Design]] for the connector work this resolves ([[rtsp-deep-dive|RTSP]]→inference→[[watchman-repo|Watchman]] services ingest point).

---

## Original Conflict (Documented Below for Context)

**Issue:** Two incompatible definitions of "[[watchman-repo|Watchman]]" currently exist in the KB and received architecture docs.

## The Conflict

### Definition 1: KB `watchman/_summary.md`

> "AI-Powered Virtual Security Operator Platform -- the next major product. A fully cloud-based system..."

**Classification:** Cloud-native multi-agent product. Product layer includes [[watch-entity|Watch Management Service]], Site Supervisor Agent, Patrol Agent, etc. Deployment context is Kubernetes in AWS (us-west-2).

### Definition 2: Received v10 Architecture Doc (Line 312)

> "Edge inference. Cloud-only by design. On-prem deployment is a separate product ([[watchman-repo|Watchman]]), not this one."

**Classification:** On-prem / edge product (contrasted with v10's cloud-only scope).

## Why This Matters

1. **Cross-repo dependency planning:** If [[watchman-repo|Watchman]] is the on-prem product, then it's a **separate deployment target** from the cloud v10 platform. But KB framing treats [[watchman-repo|Watchman]] as cloud-native, implying shared infra/libraries.

2. **Portfolio positioning:** Is [[watchman-repo|Watchman]] a single product, or a portfolio (cloud + edge variants)? Affects GTM, SKU design, and feature prioritization.

3. **[[watch-entity|Watch]] Management Service scope:** The [[2026-05-28_watch-management-service-design]] is framed as applying to **fleet-rearchitecture proposals A–E**. If [[watchman-repo|Watchman]] is on-prem only, does [[watch-entity|Watch]] Manager apply to the cloud v10 platform? If [[watchman-repo|Watchman]] is cloud-native, are A–E and v10 even compatible?

4. **[[edge-hardware-track|Edge hardware track]]:** `topics/integrations/morphean/notes/concepts/edge-hardware-track.md` references on-prem inference. If v10 is "cloud-only by design" and [[watchman-repo|Watchman]] is on-prem, then edge-hardware-track is **[[watchman-repo|Watchman]] scope**, not v10 scope. This clarifies boundaries but requires explicit confirmation.

## Questions for Clarification

1. **Product boundaries:** Is [[watchman-repo|Watchman]] (a) cloud-only (aligns with KB), (b) on-prem-only (aligns with v10), (c) both cloud and edge, or (d) a portfolio with different names?

2. **v10 relationship:** Is v10 (Cloud Video Analytics Platform) the cloud variant, and [[watchman-repo|Watchman]] the on-prem variant, of the same product? Or are they distinct products?

3. **[[watch-entity|Watch]] Management Service:** Does it apply to both v10 (cloud) and [[watchman-repo|Watchman]] (edge), or just one?

4. **Morphean edge track:** Is the on-prem/edge inference work in `edge-hardware-track.md` part of [[watchman-repo|Watchman]], or a separate effort?

## Immediate Action

**Before proceeding with cross-repo design work or product roadmap updates, clarify [[watchman-repo|Watchman]]'s cloud-vs-edge scope via:**

1. Review v10 source document context (was "[[watchman-repo|Watchman]] = on-prem product" stated intentionally or as an example?)
2. Consult Product team ([[watchman-repo|Watchman]] PRD v2 is in [[2026-05-29_watchman-prds-summary]]) for official definition
3. Update `watchman/_summary.md` and this note once clarified
4. Audit all cross-references (`edge-hardware-track`, `Watch Manager`, fleet proposals) for consistency

**Until clarified, treat [[watchman-repo|Watchman]] as potentially ambiguous in discussions.** Don't assume cloud-only or on-prem-only without context.

---

**Related:** [[2026-06-01_cloud-video-analytics-platform-v10|Cloud v10 source]], [[watchman/_summary]]
