---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [risk, operations, infrastructure, process]
---

# Active Risks (April 2026)

A catalog of the highest-priority risks facing Actuate engineering and product as of April 2026, drawn from Jira ticket analysis, support queue patterns, and initiative status.

## 1. Four Unowned Highest-Priority ENG Tickets

Four tickets in the ENG project are marked **Highest priority but have no assignee**:

- **Schedule race condition** -- A concurrency bug where simultaneous schedule updates can produce inconsistent state. This directly affects monitoring reliability and is relevant to [[vinicius-flores]]'s External API schedule work (ENG-123).
- **EKS upgrade** -- Amazon EKS cluster version upgrade. Falling behind on EKS versions risks losing security patches and eventually hitting end-of-support. This is infrastructure work under [[jacob-weiss]]'s purview.
- **VPA (Vertical Pod Autoscaler)** -- Configuration or deployment of VPA for right-sizing Kubernetes pod resources. Without VPA, pods may be over- or under-provisioned, leading to wasted spend or OOM kills.
- **Thundering herd** -- A pattern where many connector pods simultaneously retry or reconnect after a transient failure, overwhelming downstream services. This is particularly dangerous for the model servers in ds-model-prod and for DynamoDB/SQS throughput.

These four tickets represent a gap in engineering capacity allocation. [[jacob-weiss]] as engineering lead would typically triage and assign these, but their unowned status suggests either staffing constraints or prioritization conflicts with the active product initiatives.

## 2. Database CPU Spikes (BT-926 / BACK-623 / BACK-638)

A **recursive CTE** in the Admin API's PostgreSQL queries is causing Aurora CPU spikes. [[tatiana-hanazaki]] is actively working this (BACK-638), and it also appears in the support tracker (BT-926). The risk is cascading: if the database becomes unresponsive, configuration updates stall, which can cause connector pods to operate on stale settings or fail to start.

This is a particularly insidious risk because Aurora CPU spikes may be intermittent, correlating with specific query patterns (e.g., deeply nested site hierarchies or large customer accounts).

## 3. AIM Initiative Stalled

The Alerts Improvements initiative (H1.3, project AIM) has **25 out of 29 issues unassigned**. This initiative was intended to improve the alerts pipeline -- the core mechanism by which Actuate delivers value to customers. A stalled alerts initiative means known issues in alert delivery, formatting, deduplication, or routing are not being addressed.

The root cause appears to be staffing: with AutoPatrol (H1.2), Watchman, and External API all competing for engineering time, AIM has been deprioritized by omission rather than by decision.

## 4. Integration Failures in Support Queue

Multiple active support tickets report integration failures with key partners:

- **Evalink** -- trial integration issues ([[integrations/evalink/_summary|Evalink]], Adam Kawczynski on BT-902)
- **Patriot** -- alarm delivery failures
- **DW (Digital Watchdog)** -- connectivity or format issues
- **Immix** -- the primary revenue channel (~$800K/12mo, see [[revenue-drivers]])

Immix failures are especially concerning given its revenue significance. Each integration failure represents a customer experiencing missed or delayed alerts, directly impacting Actuate's value proposition.

## 5. EBUS v5 API Blocked

The EBUS v5 API update (ENG-126) is still in "To Do" status, waiting for [[mark-barbera]]'s review queue to clear. EBUS is a European integration partner, and delays here affect the EU market timeline. Mark's cross-initiative spread (AUTO + CS3 + ENG) is the bottleneck.

## See Also

- [[jacob-weiss]] -- engineering lead responsible for infrastructure risks
- [[tatiana-hanazaki]] -- working the DB performance risk
- [[revenue-drivers]] -- business impact of these risks
- [[data-flow-architecture]] -- system context for understanding failure modes
