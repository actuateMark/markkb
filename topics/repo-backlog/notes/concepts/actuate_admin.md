---
title: "actuate_admin backlog"
type: concept
topic: repo-backlog
tags: [backlog, github, actuate_admin]
repo: aegissystems/actuate_admin
created: 2026-06-25
updated: 2026-06-25
author: kb-bot
issue_count_open: 52
issue_count_high_impact: 6
issue_count_lhf: 10
issue_count_stale: 41
high_impact_issue_numbers: [2310, 1085, 899, 2230, 2482, 307]
lhf_issue_numbers: [2482, 2239, 2233, 2177, 2443, 2453, 2238, 2237, 2230, 2224]
stale_issue_numbers: [306, 337, 336, 308, 416, 307, 471, 395, 448, 488, 446, 507, 514, 510, 551, 512, 571, 570, 564, 585, 594, 218, 663, 697, 694, 705, 734, 899, 809, 955, 956, 879, 707, 699, 1025, 1018, 1085, 1075, 1145, 1151, 1165]
full_issue_numbers: [2482, 2453, 2443, 2310, 2239, 2238, 2237, 2233, 2230, 2224, 2177, 1165, 1151, 1145, 1085, 1075, 1025, 1018, 956, 955, 899, 879, 809, 734, 707, 705, 699, 697, 694, 663, 594, 585, 571, 570, 564, 551, 514, 512, 510, 507, 488, 471, 448, 446, 416, 395, 337, 336, 308, 307, 306, 218]
---

# actuate_admin backlog

Full open-issue inventory for [aegissystems/actuate_admin](https://github.com/aegissystems/actuate_admin/issues). The auto-refresh block is overwritten by [[skill-repo-scan|/repo-scan]]; **Curated notes** are hand-maintained and preserved across refreshes.

## Curated notes

*(Hand-maintained. Not touched by /repo-scan.)*

### Landscape

49 open issues split hard into two groups:

- **8 active (2026)** — filed this year, real ongoing work. See cluster table below.
- **41 stale (>180d, most >3y)** — filed 2021–2022, probably predate most of today's admin API architecture. These need **case-by-case codebase-scan follow-up**, not bulk-close.

### Active clusters (recent work, 2026)

| Cluster | Issues | Notes |
|---------|--------|-------|
| **Schedule / override semantics** | 2310, 2230, 1085, 955, 585 | 2310 (override midnight arm miss) is the highest-scored issue in this repo — prod bug. 2230 was the Global Guardian incident restore. 1085 / 955 are old variants of the same class — worth checking whether 2310's fix subsumes them. |
| **Aurora / DB ops** | 2239 | Feb 2026 Aurora upgrade rollback — should have a postmortem note in the KB; probably already addressed operationally but keep open until Europe upgrade lands. |
| **Config validation (launch-time)** | 2238, 2237, 2224 | Three parallel "prevent bad config from going live" tickets — CHM validation, invalid-config-launch prevention, `connector_version` clearing on phase change. Coherent mini-epic. |
| **Europe / i18n** | 2177, 237 (libraries) | 2177 is the active "prod-proxy missing for admin aurora in Europe" — ties into the region expansion workstream. |
| **Ignore-zone sensitivity auto-tune** | 2233 | Self-contained, moderate LHF — clear spec ("when IZ covers >50%, set sensitivity 1/1"). |

### Codebase-scan follow-up plan (41 stale items)

These are **not** deletion candidates. Many of the 2021-2022 tickets describe real issues that were likely addressed by subsequent admin refactors but never closed. The plan:

1. **Batch 1 (Onboarding / wizard):** 551, 488, 510, 446, 694 — walk the [[onboarding-wizard|onboarding wizard]] git history; most of this was rewritten during the 2023-24 React migration.
2. **Batch 2 (Monitoring UI):** 218, 395, 514, 512, 1165 — Monitoring v2 likely addresses most; verify against current UI before commenting.
3. **Batch 3 (Auto-add / integration settings — Axis / SMTP / Immix / Alibi / Mobotix):** 306, 307, 308, 336, 337, 448, 507, 564, 570, 594, 879, 1151 — integration auto-add flow has been reworked heavily; check integration modules and close/bump per module.
4. **Batch 4 (Camera / site CRUD):** 395, 416, 471, 585, 594, 663, 705, 707, 734, 809, 1018, 1025, 1075, 1145 — likely mixture of already-fixed and still-valid. Bump-or-close only with evidence.
5. **Batch 5 (Schedule / override, stale variants of active cluster):** 395, 514, 699, 956 — probably consolidate into #2310 if the fix for 2310 addresses them.

Workflow per ticket: `git log --all --grep=<keyword>` + manual spot-check of the relevant view/model → comment on the GH issue with commit refs → close with `addressed by <commit>` OR bump with "still valid as of <scan date>, candidate for <workstream>." Full list in `stale_issue_numbers` frontmatter.

**Do not batch-close without per-ticket evidence.**

### Known ownership
- No active assignees on any ticket — all community/Mark-led triage.

<!-- BEGIN-AUTO-REFRESH repo-scan -->
_Last refreshed: **2026-06-25** by [[skill-repo-scan]] — 52 open issues._

### 🔥 High-impact (top 10 by score)

| # | Title | Labels | Assignee | Score | Idle |
|--:|-------|--------|----------|------:|------|
| 2310 | [Schedule overrides firing at midnight cause sites to miss arm on override start…](https://github.com/aegissystems/actuate_admin/issues/2310) | `bug` | — | 5 | 3mo |
| 1085 | [Schedule override for multiple days is not working](https://github.com/aegissystems/actuate_admin/issues/1085) | `bug` | — | 3 | 4y |
| 899 | [Error with motion ignore zones calculation](https://github.com/aegissystems/actuate_admin/issues/899) | `bug` | — | 3 | 4y |
| 2230 | [Global Guardian: Restore 234 deleted timed schedules (148 sites affected)](https://github.com/aegissystems/actuate_admin/issues/2230) | — | — | 2 | 4mo |
| 2482 | [Auto-onboard NLSS cameras (create Camera/Stream/WebhookStream from a gateway se…](https://github.com/aegissystems/actuate_admin/issues/2482) | `enhancement` | — | 1 | 19d |
| 307 | [Auto-add SMTP settings on Alibi](https://github.com/aegissystems/actuate_admin/issues/307) | — | — | 1 | 5y |

### 🧹 Low-hanging fruit (top 10 by score)

| # | Title | Labels | Assignee | Score | Idle |
|--:|-------|--------|----------|------:|------|
| 2482 | [Auto-onboard NLSS cameras (create Camera/Stream/WebhookStream from a gateway se…](https://github.com/aegissystems/actuate_admin/issues/2482) | `enhancement` | — | 5 | 19d |
| 2239 | [Aurora PostgreSQL Upgrade Failure - actuateadminprodcluster (Feb 5, 2026)](https://github.com/aegissystems/actuate_admin/issues/2239) | — | — | 5 | 4mo |
| 2233 | [Auto-set alert sensitivity to 1/1 when motion ignore zones cover >50% of image](https://github.com/aegissystems/actuate_admin/issues/2233) | — | — | 5 | 4mo |
| 2177 | [Missing prod-proxy endpoint for admin aurora in Europe](https://github.com/aegissystems/actuate_admin/issues/2177) | — | — | 5 | 5mo |
| 2443 | [Speed up Sync / settings file generation for multi-site selections](https://github.com/aegissystems/actuate_admin/issues/2443) | — | — | 4 | 1mo |
| 2453 | [actuate_admin pod logs absent from New Relic — blocks AutoPatrol deploy-chain o…](https://github.com/aegissystems/actuate_admin/issues/2453) | — | — | 3 | 1mo |
| 2238 | [Validation for enabling CHM](https://github.com/aegissystems/actuate_admin/issues/2238) | — | — | 3 | 4mo |
| 2237 | [Add validation to prevent launching sites with invalid configurations](https://github.com/aegissystems/actuate_admin/issues/2237) | — | — | 3 | 4mo |
| 2230 | [Global Guardian: Restore 234 deleted timed schedules (148 sites affected)](https://github.com/aegissystems/actuate_admin/issues/2230) | — | — | 3 | 4mo |
| 2224 | [Clear connector_version when deployment_phase is changed from CUSTOM](https://github.com/aegissystems/actuate_admin/issues/2224) | — | — | 3 | 4mo |

### 🔍 Codebase-scan follow-up candidates (idle >180d)

*These are **not** bulk-close candidates — each needs case-by-case review. Many may already be addressed by later work; some deserve a bump. Walk the codebase for context before commenting.*

| # | Title | Labels | Idle |
|--:|-------|--------|------|
| 306 | [Axis camera configuration - support for multiviews](https://github.com/aegissystems/actuate_admin/issues/306) | — | 1871d |
| 337 | [Auto-Add for SMTP needs to get the output name from the NVR](https://github.com/aegissystems/actuate_admin/issues/337) | — | 1864d |
| 336 | [Auto-add if Immix is selected, add a field per camera to enter the immix e-mail](https://github.com/aegissystems/actuate_admin/issues/336) | — | 1864d |
| 308 | [Auto-add SMTP on Alibi: add with SMTP-specific settings](https://github.com/aegissystems/actuate_admin/issues/308) | — | 1855d |
| 416 | [Sort columns on customer site to find issues](https://github.com/aegissystems/actuate_admin/issues/416) | — | 1839d |
| 307 | [Auto-add SMTP settings on Alibi](https://github.com/aegissystems/actuate_admin/issues/307) | — | 1834d |
| 471 | [Expose configurable period for no motion and video loss alerts to customers](https://github.com/aegissystems/actuate_admin/issues/471) | — | 1814d |
| 395 | [Monitoring UI: Audit trail that the operator viewed the video](https://github.com/aegissystems/actuate_admin/issues/395) | `backlog` | 1814d |
| 448 | [Feature: Customer Profiles with default metrics](https://github.com/aegissystems/actuate_admin/issues/448) | — | 1813d |
| 488 | [Quick way to have all the cameras have the same settings](https://github.com/aegissystems/actuate_admin/issues/488) | `wishlist` | 1807d |
| 446 | [Error creating a site with a fake IP](https://github.com/aegissystems/actuate_admin/issues/446) | — | 1807d |
| 507 | [Import ignore zones from Axis](https://github.com/aegissystems/actuate_admin/issues/507) | — | 1804d |
| 514 | [Monitoring: Customizable outcomes](https://github.com/aegissystems/actuate_admin/issues/514) | — | 1800d |
| 510 | [Validate credentials on wizard](https://github.com/aegissystems/actuate_admin/issues/510) | — | 1794d |
| 551 | [Onboarding Enhancements](https://github.com/aegissystems/actuate_admin/issues/551) | — | 1792d |

_(26 more stale issues — full list in `stale_issue_numbers` frontmatter property.)_

### 📊 Labels

| Label | Count |
|-------|------:|
| `wishlist` | 10 |
| `bug` | 3 |
| `backlog` | 2 |
| `needs more info` | 2 |
| `enhancement` | 1 |
| `verify` | 1 |

### 🗃️ Full open inventory

<details><summary>All 52 open issues (click to expand — sorted newest first)</summary>

| # | Title | Labels | Assignee | Age | Idle |
|--:|-------|--------|----------|-----|------|
| 2482 | [Auto-onboard NLSS cameras (create Camera/Stream/WebhookStream from a gateway se…](https://github.com/aegissystems/actuate_admin/issues/2482) | `enhancement` | — | 19d | 19d |
| 2453 | [actuate_admin pod logs absent from New Relic — blocks AutoPatrol deploy-chain o…](https://github.com/aegissystems/actuate_admin/issues/2453) | — | — | 1mo | 1mo |
| 2443 | [Speed up Sync / settings file generation for multi-site selections](https://github.com/aegissystems/actuate_admin/issues/2443) | — | — | 1mo | 1mo |
| 2310 | [Schedule overrides firing at midnight cause sites to miss arm on override start…](https://github.com/aegissystems/actuate_admin/issues/2310) | `bug` | — | 3mo | 3mo |
| 2239 | [Aurora PostgreSQL Upgrade Failure - actuateadminprodcluster (Feb 5, 2026)](https://github.com/aegissystems/actuate_admin/issues/2239) | — | — | 4mo | 4mo |
| 2238 | [Validation for enabling CHM](https://github.com/aegissystems/actuate_admin/issues/2238) | — | — | 4mo | 4mo |
| 2237 | [Add validation to prevent launching sites with invalid configurations](https://github.com/aegissystems/actuate_admin/issues/2237) | — | — | 4mo | 4mo |
| 2233 | [Auto-set alert sensitivity to 1/1 when motion ignore zones cover >50% of image](https://github.com/aegissystems/actuate_admin/issues/2233) | — | — | 4mo | 4mo |
| 2230 | [Global Guardian: Restore 234 deleted timed schedules (148 sites affected)](https://github.com/aegissystems/actuate_admin/issues/2230) | — | — | 4mo | 4mo |
| 2224 | [Clear connector_version when deployment_phase is changed from CUSTOM](https://github.com/aegissystems/actuate_admin/issues/2224) | — | — | 4mo | 4mo |
| 2177 | [Missing prod-proxy endpoint for admin aurora in Europe](https://github.com/aegissystems/actuate_admin/issues/2177) | — | — | 5mo | 5mo |
| 1165 | [Monitoring UI: Labels for search not being inherited from parent](https://github.com/aegissystems/actuate_admin/issues/1165) | — | — | 3y | 3y |
| 1151 | [Mobotix: Buttons to remove Actuate settings](https://github.com/aegissystems/actuate_admin/issues/1151) | — | — | 3y | 3y |
| 1145 | [Trigger motion on cameras failing](https://github.com/aegissystems/actuate_admin/issues/1145) | — | — | 3y | 3y |
| 1085 | [Schedule override for multiple days is not working](https://github.com/aegissystems/actuate_admin/issues/1085) | `bug` | — | 4y | 4y |
| 1075 | [Paginate the history](https://github.com/aegissystems/actuate_admin/issues/1075) | — | — | 4y | 4y |
| 1025 | [Ability to have an e-mail address for verification different than the username](https://github.com/aegissystems/actuate_admin/issues/1025) | `backlog` | — | 4y | 4y |
| 1018 | [Display recommendation on Immix alarms setup](https://github.com/aegissystems/actuate_admin/issues/1018) | `wishlist` | — | 4y | 4y |
| 956 | [Ability to export the camera list](https://github.com/aegissystems/actuate_admin/issues/956) | `needs more info` | — | 4y | 4y |
| 955 | [Schedule override for less than 24h](https://github.com/aegissystems/actuate_admin/issues/955) | `wishlist` | — | 4y | 4y |
| 899 | [Error with motion ignore zones calculation](https://github.com/aegissystems/actuate_admin/issues/899) | `bug` | — | 4y | 4y |
| 879 | [For SMTP configuration, change Axis to send images instead of video (video is c…](https://github.com/aegissystems/actuate_admin/issues/879) | `verify` | — | 4y | 4y |
| 809 | [Customize favicon for group](https://github.com/aegissystems/actuate_admin/issues/809) | `wishlist` | — | 4y | 4y |
| 734 | [Separate the tables for FP reduction into its own database to speed up restores](https://github.com/aegissystems/actuate_admin/issues/734) | `wishlist` | — | 4y | 4y |
| 707 | [Display NVR requirements on Wizard](https://github.com/aegissystems/actuate_admin/issues/707) | `needs more info` | — | 4y | 4y |
| 705 | [Create a button to add a site to that group from the hierarchy](https://github.com/aegissystems/actuate_admin/issues/705) | — | — | 4y | 4y |
| 699 | [Send errors from Django Q to Slack channel](https://github.com/aegissystems/actuate_admin/issues/699) | `wishlist` | — | 4y | 4y |
| 697 | [Automatically add holiday calendars to new sites](https://github.com/aegissystems/actuate_admin/issues/697) | `wishlist` | — | 4y | 4y |
| 694 | [OpenEye site wizard seems to not applying the VMS fields to the customer](https://github.com/aegissystems/actuate_admin/issues/694) | — | — | 4y | 4y |
| 663 | [Reorder the site hierarchy history (latest should appear at the top)](https://github.com/aegissystems/actuate_admin/issues/663) | — | — | 4y | 4y |
| 594 | [SmartPss: ability to update the IP on customer level and propagate to cameras](https://github.com/aegissystems/actuate_admin/issues/594) | `wishlist` | — | 4y | 4y |
| 585 | [Renaming sites causes orphan schedules](https://github.com/aegissystems/actuate_admin/issues/585) | — | — | 4y | 4y |
| 571 | [Ticketing notification system](https://github.com/aegissystems/actuate_admin/issues/571) | — | — | 4y | 4y |
| 570 | [SES email ingress](https://github.com/aegissystems/actuate_admin/issues/570) | — | — | 4y | 4y |
| 564 | [Detect integration type based on version response from device](https://github.com/aegissystems/actuate_admin/issues/564) | `wishlist` | — | 4y | 4y |
| 551 | [Onboarding Enhancements](https://github.com/aegissystems/actuate_admin/issues/551) | — | actuateMark | 4y | 4y |
| 514 | [Monitoring: Customizable outcomes](https://github.com/aegissystems/actuate_admin/issues/514) | — | — | 4y | 4y |
| 512 | [Monitoring: Add threat level and anticipated outcome](https://github.com/aegissystems/actuate_admin/issues/512) | — | tatiana-actuate | 4y | 4y |
| 510 | [Validate credentials on wizard](https://github.com/aegissystems/actuate_admin/issues/510) | — | — | 4y | 4y |
| 507 | [Import ignore zones from Axis](https://github.com/aegissystems/actuate_admin/issues/507) | — | — | 4y | 4y |
| 488 | [Quick way to have all the cameras have the same settings](https://github.com/aegissystems/actuate_admin/issues/488) | `wishlist` | actuateMark | 4y | 4y |
| 471 | [Expose configurable period for no motion and video loss alerts to customers](https://github.com/aegissystems/actuate_admin/issues/471) | — | — | 4y | 4y |
| 448 | [Feature: Customer Profiles with default metrics](https://github.com/aegissystems/actuate_admin/issues/448) | — | — | 5y | 4y |
| 446 | [Error creating a site with a fake IP](https://github.com/aegissystems/actuate_admin/issues/446) | — | actuateMark | 5y | 4y |
| 416 | [Sort columns on customer site to find issues](https://github.com/aegissystems/actuate_admin/issues/416) | — | — | 5y | 5y |
| 395 | [Monitoring UI: Audit trail that the operator viewed the video](https://github.com/aegissystems/actuate_admin/issues/395) | `backlog` | — | 5y | 4y |
| 337 | [Auto-Add for SMTP needs to get the output name from the NVR](https://github.com/aegissystems/actuate_admin/issues/337) | — | — | 5y | 5y |
| 336 | [Auto-add if Immix is selected, add a field per camera to enter the immix e-mail](https://github.com/aegissystems/actuate_admin/issues/336) | — | — | 5y | 5y |
| 308 | [Auto-add SMTP on Alibi: add with SMTP-specific settings](https://github.com/aegissystems/actuate_admin/issues/308) | — | — | 5y | 5y |
| 307 | [Auto-add SMTP settings on Alibi](https://github.com/aegissystems/actuate_admin/issues/307) | — | — | 5y | 5y |
| 306 | [Axis camera configuration - support for multiviews](https://github.com/aegissystems/actuate_admin/issues/306) | — | — | 5y | 5y |
| 218 | [Fish2Eye previewer](https://github.com/aegissystems/actuate_admin/issues/218) | `wishlist` | — | 5y | 4y |

</details>

<!-- END-AUTO-REFRESH repo-scan -->

## Related

- [[repo-backlog/_summary|repo-backlog topic]]
- Latest scan: [[2026-06-25_scan]]
- GitHub: [aegissystems/actuate_admin/issues](https://github.com/aegissystems/actuate_admin/issues)
