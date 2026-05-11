---
title: "Handoff: PR #1681 stage→rearch promotion"
type: concept
topic: vms-connector
tags: [handoff, vms-connector, billing, billing-emit, promotion, soak]
created: 2026-05-07
updated: 2026-05-07
author: kb-bot
outgoing:
  - topics/personal-notes/notes/daily/2026-05-07.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/personal-notes/notes/daily/2026-05-07.md
  - topics/personal-notes/notes/daily/2026-05-08.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-09
---

# Handoff: PR #1681 stage→rearch promotion (deferred 2026-05-07 → 2026-05-08)

## Entry point

Read this, then [PR #1681](https://github.com/aegissystems/vms-connector/pull/1681) body. Decision tonight: **don't merge** — body is stale and the freshest commits on stage have ~30 min of soak. Tomorrow morning: refresh body, decide on #1684 inclusion, get review, ship.

## Current state

| Field | Value |
|---|---|
| PR | [#1681](https://github.com/aegissystems/vms-connector/pull/1681) |
| Base → head | `rearchitecture` ← `stage` |
| Mergeable | yes (no conflicts) |
| Status | `BLOCKED`, `REVIEW_REQUIRED` (Cursor security review SUCCESS) |
| Replaces | closed PR #1679 (overlay-branch deviation; flow is direct stage→rearch) |
| Body coverage | 7 PRs (#1665, #1669, #1671, #1674, #1675, #1677, #1680) |
| Stage actually contains | 11 substantive commits (4 PRs not in body: #1682, #1683, #1684, #1685) |

## Stage commits since PR opened (16:37Z 2026-05-07)

| PR | Time | Note |
|---|---|---|
| #1682 | 18:15Z | Emit healthcheck fallback for misconfigured-but-active AP sites |
| #1683 | 19:36Z | Rename fallback → "misconfigured" + site-level fallback for empty `camera_streams` |
| #1685 | 20:02Z | **Remove `site_product_started` emits — downstream-dead signal** |
| #1684 | 20:17Z | `chore(deps)`: bump actuate-filters/connector-observers/daos/pullers for line-crossing motion gates |

## The #1675 ↔ #1685 wash

PR #1675 (in the bundle) added `site_product_started/_ended` emits on every AutoPatrol cronjob run. PR #1685 (today, **not** in the bundle's body) removes the `_started` half — billing dropped it as a dead signal. **Ship them together** — otherwise we'd deploy a feature that's already been retracted. See concept [[2026-05-07_site-product-started-deprecated]] for the rationale.

## Open question for tomorrow: #1684 scope

PR #1684 (line-crossing parked-vehicle false-alarm gates, libs side: actuate-libraries [#345](https://github.com/aegissystems/actuate-libraries/pull/345)) is **unrelated** to the billing-emit storyline. Two options:

1. **Bundle:** retitle PR #1681 to capture both threads. Faster, but mixed concerns make rollback noisier.
2. **Split:** open a small `chore: bump libs` stage→rearch PR after #1681 ships. Cleaner blast radius.

Lean toward (1) only if the libs bump has independently soaked clean overnight. Default: split.

## Concrete next steps (in order)

1. **Soak check** — confirm `:stage` images carrying #1685 (cd9565af1) have not regressed billing-emit volume or surfaced new ERROR patterns. NRQL pattern from [[../../../personal-notes/notes/daily/2026-05-06|2026-05-06]] PR-#1679 stage validation.
2. **Body refresh** — rewrite PR #1681 body to cover all 11 commits; explicitly call out the #1675/#1685 wash and the misconfigured-fallback rename arc.
3. **#1684 decision** — bundle vs. split.
4. **Squash subject** — must contain `[patch:vms-connector]` (or higher); must NOT contain `[no ci]`. Strip the `📦 Update library changes report [skip ci]` lines from auto-generated body. See `feedback_library_no_dev_versions.md` / 2026-04-22 PR #341 incident.
5. **Reviewer** — `BLOCKED` won't lift without one. Self-merge per process if no reviewer available.
6. **Post-merge** — set up soak monitor mirroring PR #1660 pattern (Tier-1 systemd one-shots on Firebat — *Firebat must be back online first*).

## Gotchas

- **Firebat was offline at wrap time** (last seen ~2h before 21:00Z 2026-05-07). Confirm it's back before scheduling Tier-1 soak monitors. Tier-3 LLM fallback works but burns tokens.
- **Body staleness will continue** if more PRs land on stage tomorrow before the merge — re-check stage tip vs body coverage just before merging.
- **Squash-merge default is unsafe** — pass explicit `--subject` and `--body` (or edit in GitHub UI).

## Links

- PR [#1681](https://github.com/aegissystems/vms-connector/pull/1681)
- Concept: [[2026-05-07_site-product-started-deprecated]]
- Closed PR: [#1679](https://github.com/aegissystems/vms-connector/pull/1679) (overlay-branch deviation)
- Lib bump: actuate-libraries [#345](https://github.com/aegissystems/actuate-libraries/pull/345)
- mark-todos: §21 archive ([[2026-05-04]] § "Closed Workstreams") — billing-emit lineage parent
- Daily: [[2026-05-07]]

---

## Update 2026-05-08

**Active PR is now [#1688](https://github.com/aegissystems/vms-connector/pull/1688)**, not #1681. Iteration history:

| PR | Disposition | Why |
|---|---|---|
| #1681 | closed 2026-05-08T17:37Z | Replaced; user wanted #1684 line-crossing libs split out |
| #1686 | closed 2026-05-08 (later same day) | Rule-violation: used overlay branch `stage-to-rearch-2026-05-08-billing` (forbidden after #1679) |
| #1687 | closed 2026-05-08 (same time as #1686) | Was based on #1686's overlay branch |
| **#1688** | **OPEN, MERGEABLE, BLOCKED on REVIEW_REQUIRED** | Rule-compliant: `head=stage, base=rearchitecture` direct; **full bundle including #1684** |

**Soak verdict (still GREEN, applies to #1688 unchanged).** This morning's `nrql-investigator` 12h check on stage tip `6d95785d7` validated the full bundle:

- `site_product_started` = 0/12h post-#1685 (was ~70/hr) — emit-removal clean
- `site_product_ended` = ~446k/12h, steady — `_ended` flow unaffected
- Healthcheck-fallback emits (#1682/#1683) running silently, no novel log patterns
- ERROR rate elevated on `connector-43939`/`33917`/+4 sites = transient VMS Singapore proxy relay degradation, **pre-merge onset**, self-resolved 11:43Z 2026-05-08 — NOT deploy-correlated
- 0 new error classes vs pre-#1680 baseline
- #1684 line-crossing libs bump not implicated in any elevated ERROR

**Idempotency-guard FACET inconclusive** (`admin_camera_id` not on NR logs); low-risk given `_ended` volume normality. Alternate verification path if needed: Django admin query on `SiteProductEvent` uniqueness rather than NR logs.

**Merge deferred to Monday 2026-05-11.** Tracked in mark-todos `## Morning Follow-Ups → Seeded for 2026-05-11`. Drift risk: PR #1688 has `head=stage`, so any weekend commits to stage expand the bundle automatically.

### Monday morning procedure (concrete next steps)

1. **Drift check.** `cd /home/mork/work/vms-connector && git fetch origin && git log --oneline origin/rearchitecture..origin/stage` — diff vs the 11-commit set documented in #1688's body. If nothing new: skip (2). If drift: run (2).
2. **Re-soak via `nrql-investigator` subagent** with the same 6-check NRQL pattern from this morning (focus on whatever's net-new; full pattern in 2026-05-08 daily note Notes / Learnings).
3. **Refresh PR body if needed** to cover any new commits.
4. **Get reviewer to clear `REVIEW_REQUIRED`.** The closed-#1681 approval did not carry over to #1688.
5. **Merge** — squash subject must contain `[patch:vms-connector]` (or higher) and must NOT contain `[no ci]` / `[skip ci]`. Strip the auto-generated `📦 Update library changes report [skip ci]` lines from the squash body. Squash-merge default is unsafe — pass explicit `--subject` and `--body`, or edit in GitHub UI.
6. **Post-merge soak monitor** — Tier-1 systemd one-shots on Firebat (now back online) mirroring the PR #1660 pattern. Watch `:rearchitecture` images for: zero `site_product_started` events; steady `_ended` volume; no new error classes vs the 12h pre-merge baseline.
7. **Close §20 fully** in mark-todos when soak holds 24h.

### Rule-compliance gotcha (saved as feedback memory)

Don't reach for an overlay branch (`stage-to-rearchitecture-YYYY-MM-DD-*`) to surgically exclude commits from a stage→rearch promotion. **Forbidden** — `head=stage, base=rearchitecture` direct, full stop. If a commit needs to be excluded, the rule-compliant mechanic is **revert on stage first** (small revert PR `head=revert-X, base=stage`, merge, then promote). See `feedback_no_overlay_branches_for_stage_to_rearch.md`.

### Cross-references for Monday context

- Today's wrap: [[2026-05-08]]
- Feedback memory: `feedback_no_overlay_branches_for_stage_to_rearch.md`
- Active PR: [#1688](https://github.com/aegissystems/vms-connector/pull/1688)
- Closed iteration: #1681, #1686 (overlay deviation), #1687 (was based on overlay)
