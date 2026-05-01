---
title: "Stale schedule cleanup — what we disabled (2026-04-24 sweep)"
type: synthesis
topic: autopatrol
tags: [autopatrol, vch, cleanup-lambda, sweep, audit, report, immix]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
- Error: File "2026-04-24_stale-schedule-disable-roster" not found.
incoming:
  - Error: File "2026-04-24_stale-schedule-disable-roster" not found.
incoming_updated: 2026-05-01
---

# Stale AutoPatrol/VCH schedule cleanup — sweep results

Presentation-ready audit of every schedule the cleanup Lambda + manual sweep disabled on 2026-04-24, why each was a cleanup candidate, and the customer-camera impact. Sourced from the live admin audit endpoint (`?disabled_by=cleanup_lambda`) cross-referenced with the [[2026-04-24_stale-schedule-cleanup-investigation|2026-04-24 scan CSV]].

## Headline

- **76 schedules disabled** (previously had `scheduleStatus=Active` in admin)
- **727 cameras** on those schedules no longer running failing patrols
- **841 cameras** at the affected sites in total (some sites have cameras on other still-active schedules)
- **41 customer sites** affected
- **11 Immix tenants** spanned
- Integration mix: AutoPatrol=15, VCH=61
- All 76 verified by querying Immix under each schedule's authoritative tenant (from `s3://actuate-settings/`)

## Why these were disabled

Every schedule in this batch was confirmed gone in Immix, by one of two evidence types under the schedule's authoritative tenant (per its deployer-written `settings.json`):

- **`gone_explicit` (61 schedules):** Immix returned HTTP 200 with `scheduleStatus ∈ {Deleted, Removed}`. Customer deleted the schedule on Immix's side.
- **`gone_400` (15 schedules):** Immix returned HTTP 400 with body `"Immix system is unavailable. If this problem persists please contact Immix support team"`. Empirically observed (see [[2026-04-23_immix-api-error-patterns]]) — this is Immix's response for schedules that no longer exist on their side, when queried under the schedule's authoritative tenant. Persistent per-schedule, not a fleet-wide outage.

Cleanup mechanism: PATCH each admin schedule with `{scheduleStatus: "Deleted", disabledBy: "cleanup_lambda", disabledAt: <timestamp>}`. The admin view's existing post-save hook tears down the connector container via `model.deploy()` → `should_undeploy=True` → `model.undeploy()`.

## Per-customer breakdown (sorted by camera-impact)

### Site 1 (customer_id=35829)

**3 schedules disabled · 250 cameras across them · site has 100 total cameras · integration: AutoPatrol, VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 192 | `b2cf1550-651c-…` | Raise | VCH | 100 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |
| 341 | `140e67cc-de3e-…` | test | AutoPatrol | 100 | gone_explicit (200/Deleted) | 2026-01-14 | 2026-04-24T19:34:32 |
| 160 | `9bc5e518-29df-…` | 50 test | VCH | 50 | gone_explicit (200/Deleted) | 2025-09-17 | 2026-04-24T19:34:32 |

### Site A (customer_id=36799)

**3 schedules disabled · 85 cameras across them · site has 42 total cameras · integration: AutoPatrol, VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 256 | `31391dcb-52e2-…` | asdf | AutoPatrol | 41 | gone_explicit (200/Deleted) | 2025-12-09 | 2026-04-24T19:34:32 |
| 344 | `a3ade835-c449-…` | test | AutoPatrol | 41 | gone_explicit (200/Deleted) | 2026-01-20 | 2026-04-24T19:34:32 |
| 193 | `ff1d998e-416e-…` | Raise | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |

### 400 North Ashley (customer_id=35878)

**3 schedules disabled · 52 cameras across them · site has 18 total cameras · integration: AutoPatrol, VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 153 | `fedbc0a5-42f3-…` | 400NA AP Actuate Daily 11:00 | AutoPatrol | 18 | gone_400 (400/(err)) | 2025-09-10 | 2026-04-24T19:34:32 |
| 152 | `a0e878cc-98a0-…` | 400NA AP Actuate Sat/Sun 13:00 | AutoPatrol | 18 | gone_400 (400/(err)) | 2025-09-10 | 2026-04-24T19:34:32 |
| 147 | `c2aebe68-d31f-…` | 400NA VCH Actuate Test 1 | VCH | 16 | gone_400 (400/(err)) | 2025-09-10 | 2026-04-24T19:34:32 |

### hanwha 2 (Health Check) (customer_id=45845)

**8 schedules disabled · 46 cameras across them · site has 6 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 1032 | `911ca04e-e0a8-…` | Visual Camera Health | VCH | 6 | gone_explicit (200/Deleted) | 2026-04-08 | 2026-04-24T19:34:32 |
| 1033 | `56b9ba89-8985-…` | Visual Camera Health | VCH | 6 | gone_explicit (200/Deleted) | 2026-04-08 | 2026-04-24T19:34:32 |
| 1034 | `1c963f06-bcbf-…` | Visual Camera Health | VCH | 6 | gone_explicit (200/Deleted) | 2026-04-08 | 2026-04-24T19:34:32 |
| 1036 | `e3b3ba1a-109a-…` | Visual Camera Health | VCH | 6 | gone_explicit (200/Deleted) | 2026-04-08 | 2026-04-24T19:34:32 |
| 1037 | `64ef36df-90eb-…` | Visual Camera Health | VCH | 6 | gone_explicit (200/Deleted) | 2026-04-08 | 2026-04-24T19:34:32 |
| 1051 | `7f02ec73-3af8-…` | Visual Camera Health | VCH | 6 | gone_explicit (200/Deleted) | 2026-04-14 | 2026-04-24T19:34:32 |
| 1052 | `c76c0856-5216-…` | Visual Camera Health | VCH | 6 | gone_explicit (200/Deleted) | 2026-04-14 | 2026-04-24T19:34:32 |
| 1035 | `b5509ab8-9824-…` | Visual Camera Health | VCH | 4 | gone_explicit (200/Deleted) | 2026-04-08 | 2026-04-24T19:34:32 |

### Lab Hik (customer_id=38314)

**2 schedules disabled · 32 cameras across them · site has 16 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 185 | `0f532fbd-a3df-…` | Raise | VCH | 16 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |
| 172 | `f9be679d-7474-…` | VCH 2 | VCH | 16 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |

### CORPORATE SERVICES (5600055) (customer_id=38711)

**1 schedule disabled · 29 cameras across them · site has 29 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 1048 | `9dc3b41b-bb24-…` | Visual Camera Health | VCH | 29 | gone_explicit (200/Deleted) | 2026-04-09 | 2026-04-24T19:34:32 |

### Andrew's Test Site - DO NOT DELETE (customer_id=38380)

**2 schedules disabled · 28 cameras across them · site has 14 total cameras · integration: AutoPatrol, VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 195 | `938441e3-c339-…` | asdf | AutoPatrol | 14 | gone_explicit (200/Deleted) | 2025-09-30 | 2026-04-24T19:34:32 |
| 194 | `7e5f4319-4747-…` | Vch test 1 | VCH | 14 | gone_explicit (200/Deleted) | 2025-09-30 | 2026-04-24T19:34:32 |

### Site 3 (customer_id=37325)

**3 schedules disabled · 15 cameras across them · site has 7 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 170 | `f9611595-41bb-…` | Raise | VCH | 5 | gone_explicit (200/Deleted) | 2025-09-26 | 2026-04-24T19:34:32 |
| 190 | `5046995a-efd9-…` | VCH | VCH | 5 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |
| 257 | `f1f30a00-9a90-…` | VCH Demo | VCH | 5 | gone_explicit (200/Deleted) | 2025-12-09 | 2026-04-24T19:34:32 |

### hanwha (customer_id=37980)

**1 schedule disabled · 13 cameras across them · site has 13 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 157 | `670dcb17-a549-…` | Test Device Workers 1 | VCH | 13 | gone_explicit (200/Deleted) | 2025-09-17 | 2026-04-24T19:34:32 |

### hanwha (Health Check) (customer_id=43928)

**1 schedule disabled · 13 cameras across them · site has 13 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 663 | `66ff7bd4-4b8b-…` | Visual Camera Health | VCH | 13 | gone_explicit (200/Deleted) | 2026-03-09 | 2026-04-24T19:34:32 |

### 400 North Ashley GF 1 (1) (customer_id=37458)

**1 schedule disabled · 12 cameras across them · site has 12 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 136 | `3adc2460-f9dd-…` | asdfasdf | VCH | 12 | gone_explicit (200/Deleted) | 2025-08-29 | 2026-04-24T19:34:32 |

### 500 North Ashley (customer_id=35870)

**1 schedule disabled · 12 cameras across them · site has 12 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 146 | `ad2673dd-d567-…` | 500NA VCH Actuate Test 1 | VCH | 12 | gone_400 (400/(err)) | 2025-09-10 | 2026-04-24T19:34:32 |

### Site 4 (customer_id=37255)

**3 schedules disabled · 11 cameras across them · site has 4 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 166 | `f64800c1-76b0-…` | VCH | VCH | 4 | gone_explicit (200/Deleted) | 2025-09-25 | 2026-04-24T19:34:32 |
| 173 | `86dee5c6-a26b-…` | VCH 2 | VCH | 4 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |
| 124 | `30eb029c-9068-…` | Demo VCH | VCH | 3 | gone_explicit (200/Deleted) | 2025-08-23 | 2026-04-24T19:34:32 |

### EB (customer_id=38235)

**3 schedules disabled · 9 cameras across them · site has 3 total cameras · integration: AutoPatrol, VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 168 | `cf5dd7e2-abad-…` | Raise | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-25 | 2026-04-24T19:34:32 |
| 167 | `710491bb-05ee-…` | Remote Patrol for Persons Afterh... | AutoPatrol | 3 | gone_explicit (200/Deleted) | 2025-09-25 | 2026-04-24T19:34:32 |
| 174 | `e014485f-3c22-…` | VCH 2 | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |

### Site 2 (customer_id=38319)

**3 schedules disabled · 9 cameras across them · site has 3 total cameras · integration: AutoPatrol, VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 992 | `11d09ce2-befe-…` | AutoPatrol | AutoPatrol | 3 | gone_explicit (200/Deleted) | 2026-04-02 | 2026-04-24T19:34:32 |
| 191 | `1c089bfe-69dd-…` | Raise | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |
| 993 | `39e1d98e-3924-…` | test | AutoPatrol | 3 | gone_explicit (200/Deleted) | 2026-04-02 | 2026-04-24T19:34:32 |

### Victoria - Demo (customer_id=46292)

**1 schedule disabled · 9 cameras across them · site has 9 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 1057 | `f03a4928-1f91-…` | Visual Camera Health | VCH | 9 | gone_explicit (200/Deleted) | 2026-04-23 | 2026-04-24T19:34:32 |

### ULTA #0583 PARKWAY PLAZA (4666517) (customer_id=38737)

**1 schedule disabled · 8 cameras across them · site has 8 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 959 | `db5eb770-edb7-…` | Visual Camera Health | VCH | 8 | gone_explicit (200/Deleted) | 2026-04-01 | 2026-04-24T19:34:32 |

### Victoria - EE Demo (customer_id=39221)

**4 schedules disabled · 8 cameras across them · site has 2 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 214 | `05f2730c-cd34-…` | NewT | VCH | 2 | gone_explicit (200/Deleted) | 2025-10-30 | 2026-04-24T19:34:32 |
| 213 | `ff963f83-b509-…` | Test | VCH | 2 | gone_explicit (200/Deleted) | 2025-10-30 | 2026-04-24T19:34:32 |
| 215 | `a13d25c9-98ec-…` | test1 | VCH | 2 | gone_explicit (200/Deleted) | 2025-10-30 | 2026-04-24T19:34:32 |
| 216 | `28d0aedc-7aac-…` | test1 | VCH | 2 | gone_explicit (200/Deleted) | 2025-10-30 | 2026-04-24T19:34:32 |

### AB (customer_id=38315)

**2 schedules disabled · 6 cameras across them · site has 3 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 186 | `152a203c-f380-…` | Raise | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |
| 175 | `dacc71f2-8805-…` | VCH 2 | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |

### DH (customer_id=38316)

**2 schedules disabled · 6 cameras across them · site has 3 total cameras · integration: AutoPatrol, VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 187 | `89295489-f629-…` | Raise | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |
| 598 | `0e8f2e9a-0fac-…` | test | AutoPatrol | 3 | gone_explicit (200/Deleted) | 2026-03-03 | 2026-04-24T19:34:32 |

### London (customer_id=35876)

**1 schedule disabled · 6 cameras across them · site has 7 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 148 | `54923949-a0c2-…` | London VCH Actuate Test 1 | VCH | 6 | gone_400 (400/(err)) | 2025-09-10 | 2026-04-24T19:34:32 |

### McCall (customer_id=38318)

**2 schedules disabled · 6 cameras across them · site has 3 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 189 | `f51ce963-78c0-…` | Raise | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |
| 178 | `667a7dd8-2b08-…` | VCH 2 | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |

### New York (customer_id=35877)

**1 schedule disabled · 6 cameras across them · site has 6 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 149 | `e0f9c21f-05a2-…` | New York VCH Actuate Test 1 | VCH | 6 | gone_400 (400/(err)) | 2025-09-10 | 2026-04-24T19:34:32 |

### NS (customer_id=38317)

**2 schedules disabled · 6 cameras across them · site has 3 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 188 | `a3a66cf3-7f24-…` | Raise | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |
| 177 | `f5b997e9-5076-…` | VCH 2 | VCH | 3 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |

### RRMS Corona Office - 80409998 VID4000 (customer_id=44029)

**1 schedule disabled · 6 cameras across them · site has 6 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 696 | `836fa518-adce-…` | Visual Camera Health | VCH | 6 | gone_explicit (200/Deleted) | 2026-03-11 | 2026-04-24T19:34:32 |

### Lab Audio (customer_id=38313)

**3 schedules disabled · 5 cameras across them · site has 4 total cameras · integration: AutoPatrol, VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 498 | `02812a83-7834-…` | test | AutoPatrol | 2 | gone_explicit (200/Deleted) | 2026-02-24 | 2026-04-24T19:34:32 |
| 250 | `8ad5672f-649c-…` | Test AP 3 Actuate | AutoPatrol | 2 | gone_explicit (200/Deleted) | 2025-11-20 | 2026-04-24T19:34:32 |
| 184 | `4e5abae7-5182-…` | Raise | VCH | 1 | gone_explicit (200/Deleted) | 2025-09-28 | 2026-04-24T19:34:32 |

### VCH 1 (customer_id=37621)

**1 schedule disabled · 5 cameras across them · site has 5 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 140 | `8e882917-c655-…` | VCH Demo - UK | VCH | 5 | gone_explicit (200/Deleted) | 2025-09-05 | 2026-04-24T19:34:32 |

### VCH Demo Site (customer_id=42689)

**1 schedule disabled · 5 cameras across them · site has 5 total cameras · integration: AutoPatrol**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 431 | `4ea364f8-5825-…` | AutoPatrol | AutoPatrol | 5 | gone_explicit (200/Deleted) | 2026-02-19 | 2026-04-24T19:34:32 |

### 9 Dibble Street (customer_id=38578)

**1 schedule disabled · 4 cameras across them · site has 4 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 204 | `abfd214c-ca64-…` | VCH Check | VCH | 4 | gone_400 (400/(err)) | 2025-10-08 | 2026-04-24T19:34:32 |

### ECS Coffee - 3100 Harvester Rd, Burlington (customer_id=39455)

**1 schedule disabled · 4 cameras across them · site has 4 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 240 | `8a500667-45b7-…` | VCH | VCH | 4 | gone_explicit (200/Deleted) | 2025-11-06 | 2026-04-24T19:34:32 |

### Journey Juice (2) (customer_id=42376)

**1 schedule disabled · 4 cameras across them · site has 4 total cameras · integration: AutoPatrol**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 352 | `2cd94340-4b88-…` | JJ patrol | AutoPatrol | 4 | gone_explicit (200/Deleted) | 2026-02-10 | 2026-04-24T19:34:32 |

### New Office Cams (customer_id=37261)

**2 schedules disabled · 4 cameras across them · site has 2 total cameras · integration: AutoPatrol, VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 133 | `3f8d5271-43b5-…` | Autopatrol - Tue | AutoPatrol | 2 | gone_explicit (200/Deleted) | 2025-08-27 | 2026-04-24T19:34:32 |
| 134 | `4f4786a0-184b-…` | VCH prod | VCH | 2 | gone_explicit (200/Deleted) | 2025-08-27 | 2026-04-24T19:34:32 |

### 4.1 Test Legacy Sch 3 (customer_id=39381)

**1 schedule disabled · 3 cameras across them · site has 3 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 220 | `c40b2017-0f28-…` | VCH - RL | VCH | 3 | gone_explicit (200/Deleted) | 2025-11-04 | 2026-04-24T19:34:32 |

### Axis site (1) (customer_id=39418)

**2 schedules disabled · 2 cameras across them · site has 1 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 234 | `1e2ee05f-f1f0-…` | action - to verify height | VCH | 1 | gone_400 (400/(err)) | 2025-11-05 | 2026-04-24T19:34:32 |
| 235 | `636be1ba-57c9-…` | test | VCH | 1 | gone_400 (400/(err)) | 2025-11-05 | 2026-04-24T19:34:32 |

### ECS Coffee - Etobicoke (customer_id=39453)

**1 schedule disabled · 2 cameras across them · site has 2 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 239 | `8e8cb174-8f38-…` | VCH | VCH | 2 | gone_400 (400/(err)) | 2025-11-06 | 2026-04-24T19:34:32 |

### Elva Nunes Residence (customer_id=43138)

**1 schedule disabled · 2 cameras across them · site has 2 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 595 | `55439530-9de6-…` | VCH Check | VCH | 2 | gone_400 (400/(err)) | 2026-02-26 | 2026-04-24T19:34:32 |

### GWSI|GoldenWestSecurity|308151|CinmarkKester (customer_id=44781)

**1 schedule disabled · 2 cameras across them · site has 6 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 1053 | `fc13c9bd-b82a-…` | Visual Camera Health 2 | VCH | 2 | gone_explicit (200/Deleted) | 2026-04-16 | 2026-04-24T19:34:32 |

### Guardian Test (customer_id=37167)

**1 schedule disabled · 1 cameras across them · site has 1 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 120 | `d3e44531-32ee-…` | test | VCH | 1 | gone_explicit (200/Deleted) | 2025-08-21 | 2026-04-24T19:34:32 |

### VCH Test Site - VID9999 (customer_id=43632)

**1 schedule disabled · 1 cameras across them · site has 1 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 629 | `f123ae8f-8c68-…` | Visual Camera Health | VCH | 1 | gone_400 (400/(err)) | 2026-03-04 | 2026-04-24T19:34:32 |

### axis site - subsite (customer_id=39417)

**2 schedules disabled · 0 cameras across them · site has 0 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 232 | `a13faadc-c009-…` | VCH 1 | VCH | 0 | gone_400 (400/(err)) | 2025-11-05 | 2026-04-24T19:34:32 |
| 233 | `2a6916e9-e359-…` | VCH 11-4 | VCH | 0 | gone_400 (400/(err)) | 2025-11-05 | 2026-04-24T19:34:32 |

### Testing site (customer_id=39419)

**1 schedule disabled · 0 cameras across them · site has 0 total cameras · integration: VCH**

| pk | scheduleId | title | integration | cameras | verdict | created | disabled |
|---|---|---|---|---|---|---|---|
| 236 | `5a16a0fe-ef78-…` | test | VCH | 0 | gone_400 (400/(err)) | 2025-11-05 | 2026-04-24T19:34:32 |

## Method + audit trail

**Authoritative tenant discovery:** for each schedule, the cleanup script fetched `s3://actuate-settings/connector-{customer_id}-{integration}-{pk}/settings.json` and read `tenant_id` from the deployer-written settings. This is the same tenant the cleanup Lambda itself uses at runtime via the SQS message body.

**Immix probe shape:**
```
GET https://autopatrol.immixconnect.com/v/Schedules/{scheduleId}
  Headers:
    tenantId: <from S3 settings.json>
    Ocp-Apim-Subscription-Id: actuate
    Ocp-Apim-Subscription-Key: <prod/actuate/autopatrol AUTOPATROL_API_KEY>
```

**Reversibility:** every disabled schedule can be brought back via the AutoPatrol re-enable Lambda (`immix-autopatrol-schedule-reenable`) or by direct admin PATCH setting `scheduleStatus=Active, disabledBy=null, disabledAt=null, reenabledBy=...`. The full original dataset is captured in [[2026-04-24_stale-schedule-cleanup-investigation|the scan CSV]] + [[2026-04-24_patch-batch.json]].

**Pre-PATCH safety check:** every container in the batch was cross-referenced against [[new-relic|New Relic]] 7-day logs. Result: 33 actively logging textbook stale patterns (`"No patrols to run after all attempts, exiting"`, `CNCTNFAIL`, `emit_no_patrols_signal reason=site_disabled`), 43 silent (no log activity), **0 showing patrol-success signals.**

## Related

- [[2026-04-24_stale-schedule-cleanup-aar|After-action report]] — full timeline + the 14-of-19 false-positive incident + corrected methodology
- [[2026-04-24_stale-schedule-cleanup-investigation|Investigation note]] — methodology development + corrected scan results
- [[2026-04-23_immix-api-error-patterns|Immix API error pattern catalog]] — why 400 + body "Immix system is unavailable" means "gone"
- [[autopatrol-cleanup-lambda|Cleanup Lambda entity]] — pipeline design + status
- Audit endpoint: `GET https://admin.actuateui.net/api/auto_patrol_schedule/?disabled_by=cleanup_lambda`