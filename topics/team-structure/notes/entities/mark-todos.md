---
title: "Mark's High-Level TODOs"
type: entity
topic: team-structure
tags: [todos, mark, work-plan, priorities, personal]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Mark's High-Level TODOs

> **Note:** the "Current Jira Queue" section near the bottom is rewritten each day by [[automation-jira-sync]] — do not edit that section manually (see the HTML comment sentinels).

Personal workstream tracker for Mark Barbera's active work. High-level only — detail lives in individual concept/synthesis notes per topic. Update this as priorities shift.

Not the same as [[autopatrol/notes/entities/todo-list|autopatrol team todo-list]] (that one is product-team-wide).

---

## 1. Inference API v5 — finish for testing

**Priority:** current focus
**Tickets:** ENG-126 (external-api initiative → v5 detection API for [[integrations/ebus/_summary|EBUS]])
**Status:** in progress

### What's left

- [ ] Finish endpoint implementation
- [ ] Verify Swagger examples render correctly per model
- [ ] Verify per-model doc pages in `docs/api/v5/`
- [ ] Hand off to EBUS for partner testing
- [ ] Run `/validate-release` pre-merge
- [ ] Post-push audit (security, RBAC, bounded inputs, 404 hints filtered by role)

### Relevant KB

- [[external-api/_summary|external-api topic]] — initiative context
- [[inference-api/_summary|inference-api topic]] — architecture
- Skill chain: `/api-endpoint-development` → `/write-external-docs` → `/validate-release`

---

## 2. AutoPatrol — finish outstanding tasks

### 2a. Test the release

- [ ] Verify current stage deploy is healthy
- [ ] Check prod for regressions
- Related agent: [[agent-release-chain-watcher]]

### 2b. Fix the deferred-alert race condition

- [ ] Apply fix per investigation in [[2026-04-16_deferred-alert-race-condition]]
- [ ] Verify on stage
- [ ] Merge + deploy

### 2c. Push stage → prod with Brad Murphy's BB (bounding box) changes

**Ticket:** AUTO-351 — "Bounding boxes on AP clips to Immix" (marked ready to deploy in [[autopatrol/_summary|autopatrol summary]])

- [ ] Final verify on stage
- [ ] Push to prod
- [ ] Monitor Immix timeline for correct BB rendering

---

## 3. New Lambda — AutoPatrol stale-schedule cleanup

**Repo:** `autopatrol_onboarder` ([aegissystems/autopatrol_onboarder](https://github.com/aegissystems/autopatrol_onboarder))
**Deploy:** new Lambda, sibling to the onboarder Lambda (same repo, separate function)
**Status:** not started — capturing the spec

### Problem

Many AP cronjob schedules continue to run after the Immix-side site/schedule has been deleted. Our cronjob keeps firing, pod keeps starting, pipeline logs `"no patrols to run, exiting"` and terminates. These stale cronjobs waste cluster resources and muddy the overnight health report.

### Design

```
VMS Connector pod (AP run)
  └─ detects "no patrols to run, exiting"
     └─ (after N consecutive failures) push SQS message: { site_id, schedule_id }
         └─ Cleanup Lambda (new, in autopatrol_onboarder repo)
             ├─ call Immix API: does site/schedule still exist + active?
             ├─ if gone: disable schedule on admin side (actuate_admin API)
             └─ if present: log, no-op
```

### Subtasks

- [ ] Decide on N (consecutive "no patrols to run" failures before enqueuing cleanup check)
- [ ] Identify the Immix API endpoint for site/schedule existence/activity
- [ ] Create SQS queue (FIFO? standard? dedup keys?) — terraform in the infra repo
- [ ] Add emit logic on the connector side — after N failures, push message
- [ ] Implement cleanup Lambda in `autopatrol_onboarder`
- [ ] Wire admin API call for "disable schedule"
- [ ] Terraform for Lambda + event source (SQS trigger)
- [ ] Alerting: if Lambda itself errors repeatedly, page
- [ ] Test on stage first
- [ ] Doc: concept note in `autopatrol/notes/concepts/` covering the runbook

### Open Questions

- Is "disable on admin side" reversible (for when Immix re-adds a schedule later)?
- Does the Immix API have a rate limit to consider for this Lambda?
- Should a human approve each deletion, or is this fully automatic?
- What logs does this Lambda emit to NR? (needs container_name scoping for queries)

### Related

- [[autopatrol/notes/entities/todo-list|AutoPatrol team todo-list]] — original spec for this feature (brief)
- [[autopatrol/_summary|autopatrol topic]]

---

## 4. API keys per customer within a group (v5 follow-up)

**Status:** design phase — **interview + plan required before any implementation**
**Context:** follow-up to §1 (v5 API / EBUS); expands partner-facing API access from one-key-per-partner to one-key-per-customer-within-a-group
**Priority:** after §1 ships

### Desired behavior

1. **Group admin UX** — a new permission in group settings unlocks a page that lets a group admin generate an API key for any individual customer under their group.
2. **Customer self-serve UX** — a separate page on the config site where the customer (or the main customer contact) can generate their own key.
3. **Per-key permissions are independent** — keys track their own permission set; a customer's key can only hit the models that customer is allowed to access, regardless of what the group-level key can reach.

### Design surface (open questions — resolve in interview/plan phase)

- Where does the keygen UI actually live — admin site (`actuate_admin`), config site (camera-ui / alert-ui?), or both with slightly different affordances?
- How is "customer within a group" modeled in `actuate_admin` today? Is it a `User`, a `Customer` record, a sub-group? The data model answer drives everything else.
- Who is allowed to generate: group admins only, customer self-serve only, or both with a setting to disable self-serve per group?
- Per-key scoping granularity (MVP vs. later) — models only? endpoints (e.g. v5 detect vs. submit)? sites? detection-count limits?
- Key lifecycle — expiration default, rotation cadence, revocation UI, audit log, "who generated this" provenance.
- Authorizer impact — does the existing Rust Lambda authorizer's DynamoDB lookup support a richer permission payload, or does it need a schema change? Versioned key format to stay backward-compatible?
- Billing / usage metering — per-key, per-customer, or per-group? Needed from day one or later?
- Rate limits — per-key?

### Pre-implementation plan

- [ ] Interview: meet with the EBUS / v5 stakeholder(s) to validate the UX and nail down the "customer vs. group" data model
- [ ] ADR covering data model, auth flow, UI placement — use [[adr-writing-guide]]
- [ ] Decide MVP scope for per-key permission granularity
- [ ] Spec against existing `actuate_admin` RBAC so we don't duplicate primitives
- [ ] Authorizer impact assessment — breaking change? versioned key format? migration path for existing keys?
- [ ] Security review before building — apply [[security-hardening-checklist]] to the design (RBAC-first, bounded inputs, audit trail, revocation story)

### Related

- §1 — v5 API work this follows from
- [[inference-api/_summary|inference-api topic]] — authorizer + endpoint surface
- [[admin-api/_summary|admin-api topic]] — user/group/customer/RBAC primitives
- [[external-api/_summary|external-api topic]] — partner-API initiative context
- [[security-hardening-checklist]] — design-review gate

---

<!-- BEGIN-AUTOSYNC-JIRA -->
## Current Jira Queue (auto-synced)

**Last synced:** 2026-04-16
**Source:** `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`

This section is **fully replaced** on every sync by the `jira-sync` automation (see [[automation-jira-sync]]). Manual edits in this section will be lost — add notes against tickets in the workstream sections above instead.

### Ready to Deploy (5)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| AUTO-351 | Medium | Story | Bounding boxes on AP clips to Immix *(tracked in §2c)* |
| CS3-430 | Medium | Sub-task | Account for dummy incident type in CHM API |
| CS3-31 | Highest | Sub-task | Automatically update the reference image |
| CS3-58 | Lowest | Task | Configuration per camera |
| CS3-323 | High | Bug | Discrepancy in cam count btwn dashboard and report |

### In Progress / In Review (3)

| Ticket | Status | Priority | Type | Summary |
|--------|--------|----------|------|---------|
| ENG-126 | In Review | Medium | Sub-task | External API: EBÜS API Integration Phase 1 *(tracked in §1)* |
| ENG-147 | In Progress | Medium | Task | Jira → Confluence automated docs sync + local Claude KB |
| ED-32 | In Progress | High | Sub-task | EBUS API Integration Phase 1 |

### To Do (5)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| AUTO-478 | High | Sub-task | Single image storage when no motion/alerts |
| AUTO-479 | High | Sub-task | Slip storage when no motion/alerts |
| ENG-136 | Medium | Task | PyAV upgrade 13.1 → 17.0 (nogil pixel conversion) |
| ENG-94 | Medium | Task | Deferred alerts: send without frame as fallback when cache expires |
| CS3-505 | Medium | Sub-task | add outcome to the API for CHM alerts |

### Open (1)

| Ticket | Priority | Type | Summary |
|--------|----------|------|---------|
| BT-259 | Medium | Bug | "Use Motion" toggle bug |

<!-- END-AUTOSYNC-JIRA -->

---

## Discipline

- Update this note at the end of each working session where one of these workstreams moved.
- When a workstream completes, archive it to a `## Done` section at the bottom (don't delete).
- When a new high-level TODO appears, add it — don't let work accumulate in chat-only form.

## Related

- [[team-structure/_summary|Team Structure topic]]
- [[engineering-process/notes/syntheses/2026-04-14_feature-development-lifecycle|Feature Development Lifecycle]]
- [[agents-catalog]] — which agents help with which workstream
- [[automation-jira-sync]] — the daily job that refreshes the "Current Jira Queue" section
