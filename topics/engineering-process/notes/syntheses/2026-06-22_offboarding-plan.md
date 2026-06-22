---
title: "Mark's offboarding plan — persist the setup so the team keeps the value"
type: synthesis
topic: engineering-process
tags: [offboarding, handoff, firebat, disaster-recovery, persistence, mark]
created: 2026-06-22
updated: 2026-06-22
author: kb-bot
---

# Offboarding plan of attack (last day: Fri 2026-06-26)

Consolidated plan for Mark's final week. **Guiding principle:** Mark's company access (SSO, GitHub org membership, Atlassian, email, Tailscale identity) dies Friday EOD. Anything that (a) **authenticates as Mark**, (b) **lives on Mark's personal account**, or (c) **sits only in Mark's head** must be re-homed, mirrored, or written down before then. Work is ordered by *"breaks silently the moment Mark leaves."*

## Decisions (set 2026-06-22)

| Question | Decision | Plan consequence |
|---|---|---|
| Firebat minipc + npu-server hardware | **Stays — company-owned** | Transfer *ownership + credentials*, keep automation running. |
| Successor | **Team-wide, no single owner** | Optimize for self-serve docs + ticket reassignment, not 1:1 handoff. |
| KB (`markkb`) + Claude config (`claude-config`) | **Scrub private info → mirror to aegissystems org → Confluence highlights** | Privacy pass is a hard gate before any mirror. |
| Effort split (~4.5 days) | **Land cheap PRs Mon, then all-in on handoff** | No Envera cutover, no new code. |

## The persistence problem in one diagram

```
DURABLE VALUE                         OWNED BY              ACTION
─────────────────────────────────────────────────────────────────────────
local_network_scripts (minipc IaC)    aegissystems org  ✓   none — already safe
KB vault (markkb)                      actuateMark (pers.)   scrub → mirror to org
Claude config (claude-config)          actuateMark (pers.)   scrub → mirror to org
firebat ~14 systemd timers             runs as user `mork`   re-home 4 identities
  ├─ Tailscale node                    mark@aegissystems.ai  reassign device owner
  ├─ GitHub (gh)                        actuateMark (pers.)   org machine account / PAT
  ├─ AWS (dashboard-check profile)      ? (verify)            team IAM identity
  └─ Atlassian + NR tokens             Mark's tokens         re-issue under team/service
npu-server LLM shop                    company HW, Mark tail  reassign device + runbook
Knowledge in Mark's head               —                     Confluence handoff doc
```

## Critical path (kick off Monday AM — has external lead time)

Workstream **A** depends on *other people*: a Tailscale admin to reassign device ownership, and whoever provisions org machine accounts / IAM identities. These cannot be done solo at the last minute. **Raise them first thing Monday.**

---

## Workstream 0 — Land & freeze in-flight code  *(Mon, ~½ day)*

**✅ COMPLETE 2026-06-22 — everything was already landed; nothing was left half-merged.**

- [x] **onboarder #14/#15/#16** (ENG-289) — already merged (no open PRs).
- [x] **admin #2506** — already merged to `staging` (checks green: `makemigrations --check` + security). Did not touch prod `main`.
- [x] **squash-body CI-skip skill fix** — already merged as **vms-connector #1755** (`fix(skill): guard squash body against build-suppression directives`); added `pr-body-skip-token-guard.yml` workflow too.
- [x] **actuate-libraries "orphan tests"** — NOT orphans: the 5 untracked test artifacts on the laptop are **stale local copies of tests already committed to `origin/main`** (laptop `main` is 92 commits behind). They pair with shipped features (adaptive motion floor #365/#369, dual-format line-crossing #1726). No PR needed — already preserved upstream.
- [x] **FREEZE in effect** — no new code; Envera cutover not started. In-flight threads → reassign via WS-C.

## Workstream A — Re-home firebat's 4 identities  *(Mon–Wed, HIGHEST RISK)*

This is what makes "company-owned hardware" actually persist. Each timer on firebat authenticates as Mark today. Re-home, then **verify every timer runs green under the new identity.** **Self-serve audit done 2026-06-22 — most of this we can do ourselves:**

- ✅ **AWS — ALREADY TEAM-OWNED, no action beyond documenting.** The `dashboard-check` profile uses **IAM Roles Anywhere**: host-bound X.509 cert (`~/.config/aws-rolesanywhere/mork-firebat.crt/.key`) → role `dashboard-check-rolesanywhere`, trust-anchor `328fdc80-…`, account `388576304176`. Machine identity, NOT Mark's SSO — survives departure. Affects `billing-reconcile-check`, `ecr-lifecycle-audit`, `run-dashboard-check`, `morning-prep`. Action: confirm cert/role won't be revoked (named mork-firebat but is a host identity); document in runbook.
- 🔧 **Tailscale — self-serve path identified.** Probe 2026-06-22: firebat node is **user-owned by `mark@`, no tags** (key expiry 2026-10-20). Fix = re-auth firebat + npu-server with a **tagged auth key** (`tag:server`) → makes them *tailnet-owned*, survive Mark's deactivation. Self-serve IF Mark can mint a tagged auth key (admin console) + `tag:server` exists in ACL. Then per box: `sudo tailscale up --authkey=tskey-… --advertise-tags=tag:server`. **Confirm Mark's Tailscale admin/owner rights + ACL tag.**
- 🔧 **GitHub — needs a non-Mark credential (partial self-serve).** firebat `gh` authenticates as personal **`actuateMark`**. Affects `repo-scan`, `git-fetch-major-repos`, `pr-review-digest`, KB bare-repo push. Self-serve only if an org bot/service account or org-PAT source exists (probe inconclusive). Prior art: [[2026-04-28_minting-github-pats-for-automation]]. **Check for an existing org machine account; else mint a fine-grained org PAT from a team-owned account.**
- ⏳ **New Relic + Atlassian tokens.** Token paths on firebat (verified 2026-06-22): NR → **`~/.config/newrelic/key`** (a personal `NRAK-` key owned by `mark@actuate.ai`); Atlassian → `~/.config/atlassian/api-token` (`mark@actuate.ai`). *(Note: `~/.config/nr/api-key` referenced in old notes is the **laptop** path, not firebat.)* **INCIDENT 2026-06-22: a NR Personal API Key was found leaked in KB git history** (purged — see § below). Rotation deferred per decision, but both tokens must be re-homed in this WS: revoke + mint NR replacement (ideally team/service) in NR UI → write to `~/.config/newrelic/key`; re-issue Atlassian token under a service account → write to `~/.config/atlassian/api-token`.
- [ ] **Verify pass — use the harness.** `~/bin/firebat-identity-verify.py` (source: `actuate-dev-toolkit/files/firebat-identity-verify.py`) checks all 4 identities + all 14 timers and prints PASS/WARN/FAIL. **Baseline captured 2026-06-22** at `~/identity-baseline-pre-rehome.json` (0 FAIL, 3 WARN = the 3 re-home targets). Wed/Thu workflow: re-home → `firebat-identity-verify.py` (warnings should flip to ✅) → `firebat-identity-verify.py --run-timers` (actively fires each credential-dependent timer to confirm exit 0 under the new identity). **⚠ Do the Tailscale re-auth with console/physical access — it can drop SSH if misconfigured.**
- [ ] Write the **credential map** (timer → identity → where the secret lives → how to rotate) into the firebat runbook (Workstream D).

### Secret-leak incident + WS-B push (2026-06-22)

During the WS-B markkb push, GitHub push-protection caught a **live NR Personal API Key** in `topics/operational-health/notes/syntheses/2026-05-01_overnight-check.md` (two pre-existing commits). The KB also had **237 modified + 284 untracked files** — a month of uncommitted drift. Actions taken:
- Committed all drift (junk excluded via new `.gitignore` rules: `*.bak-*`, `.~lock.*#`) + offboarding artifacts.
- Purged the key from **all** history with `git-filter-repo`; verified 0 real-key occurrences across all blobs locally + in the firebat bare repo (gc'd to expunge orphans).
- Force-pushed clean history to **github (`actuateMark/markkb`)** + **firebat**. GitHub never received the secret (protection blocked the first attempt).
- **Follow-up (WS-D):** add a `gitleaks` pre-commit hook to KB + `claude-config` — already a documented open follow-up in [[2026-04-28_long-lived-credentials-on-headless-boxes]]. Rotate the leaked NR key in WS-A.

## Workstream B — Liberate personal-account artifacts  *(Mon first thing, then Wed)*

- [ ] **Push markkb's 11 unpushed commits NOW** (last push 2026-05-22 — a month of work at risk). No-brainer, do Monday first thing.
- [ ] **Privacy scrub — markkb.** Strip secrets/tokens, the non-work dirs (`rpg junk/`, `world/`, `cool stuff/` sit *outside* the KB but verify nothing personal leaked in), colleague-naming in any "mistake" context (per the no-naming-in-Jira norm — apply the same to mirrored docs), and personal opinions. Then mirror to an `aegissystems` org repo.
- [ ] **Privacy scrub — claude-config.** Hooks/scripts may embed tokens, absolute personal paths, or opinions. Scrub, push current (1 commit ahead), mirror to org.
- [ ] **KB source-of-truth.** The bare repo lives on firebat (`mork@mork-firebat:~/git/knowledgebase.git`). Make the org repo the canonical remote, not Mark's personal `actuateMark/markkb`.

## Workstream C — Knowledge handoff for a no-owner team  *(Tue–Fri)*

- [ ] **Confluence landing page: "Mark's Actuate footprint."** The map — what runs where, how to operate it, where each knowledge thread lives. The single entry point for whoever picks up any thread.
- [ ] **Surface high-value KB syntheses into Confluence highlights:** autopatrol cleanup-lambda playbook (§3), OOM/VPA-floor analysis (§18), fleet-arch + Watchman analyses (§5), RDS extended-support upgrade runbook (§33), dashboard signal catalog (§9), the firebat operations runbook (Workstream D).
- [ ] **Reassign all 17 open assigned tickets** — full ledger below (§ "Jira reassignment ledger"). Set assignee to the natural owner or unassign with a per-ticket handoff comment. Neutral, factual.
- [x] **Offboarding epic FILED 2026-06-22 → [ENG-375](https://actuate-team.atlassian.net/browse/ENG-375)** (created via firebat — writes are IP-blocked from the laptop). No offboarding ticket existed before. 7 children, all assigned to Mark, time-boxed to close Fri 6/26: **ENG-376** WS-A (Highest, critical path) · **ENG-377** WS-0 · **ENG-378** WS-B · **ENG-379** WS-C1 · **ENG-380** WS-C2 (this reassignment ledger) · **ENG-381** WS-D · **ENG-382** WS-E. Hard rule in the epic: anything not Done by EOD Fri gets explicitly reassigned.
- [ ] **Hand off in-flight code threads with runbooks:** Envera TLS hardening + cutover (exact steps: scale master→0, rearch up, 60s queue retention bounds the gap, deployment must poll queue named exactly `envera_id`); PR #91 v5 split-intruder decision; §18 VPA-floor PR; §14 midnight arm-miss race fix.
- [ ] **Close or reassign active feature branches:** `vms-connector/fix/squash-body-suppression-guard`, `actuate_admin/chore/remove-vestigial-autopatrol-schedule-tier`.

## Workstream D — Operating runbooks (make the automation maintainable)  *(Wed–Fri)*

- [x] **Firebat operations runbook** — DRAFTED 2026-06-22 → [[2026-06-22_firebat-operations-runbook]] (196 lines, facts verified against the live box: 14-timer inventory + creds + logs + dashboard + KB bare repo + add/remove/three-tier + the verify harness). *Still to do: also land a copy in `actuate-dev-toolkit` + Confluence (WS-C1).*
- [ ] **npu-server / LLM-shop runbook** (§24): how local models are served, how `llm-shop-delegate` routes, the kb-intake / code-delegate harnesses. *(still open)*
- [x] **Dashboard signals catalog** — DRAFTED 2026-06-22 → [[2026-06-22_dashboard-signals-catalog]] (369 lines, ~89 signal defs across 15 components, sink schema, how-to-add, regression-rule reality check). Built from real `signals.json`.
- [ ] **"Keep the morning automation alive"** — the cron cache that `/daily-scope` + `/dashboard-check` read (`morning-prep.sh`), and what degrades if it stalls.

## Workstream E — Decommission what can't transfer  *(Fri)*

- [ ] Identify anything irreducibly tied to Mark: personal Anthropic API key billing (note: firebat timers are **script-based, zero-token** by design — Anthropic key is a laptop/Claude-Code concern, not firebat), personal Slack webhooks, the laptop itself.
- [ ] **Teammate-vantage verification:** have a colleague confirm from *their* machine — reach firebat over Tailscale, timers run green, KB org repo + Confluence readable. The real test of "did the re-home work."
- [ ] **Dead-man's checklist:** a one-pager of "if X breaks the week after Mark leaves, check Y" for the team.

---

## Day-by-day sequencing

| Day | Focus |
|---|---|
| **Mon 6/22** | WS-0 land PRs; push markkb 11 commits (B); **kick off A's external asks** (Tailscale admin, org GitHub/IAM identity) first thing. |
| **Tue 6/23** | Finish A (AWS + Atlassian/NR + verify all timers). Start C (Jira reassignment, Confluence skeleton). |
| **Wed 6/24** | B scrub + mirror both repos to org. D firebat runbook + credential map. |
| **Thu 6/25** | C Confluence highlights. D npu/dashboard runbooks. Teammate dry-run. |
| **Fri 6/26** | E decommission + teammate-vantage verification + dead-man's checklist. Buffer. |

## Jira reassignment ledger (WS-C)

All 17 tickets currently assigned to Mark (`assignee = Mark Barbera AND statusCategory != Done`, confirmed 2026-06-22). None are offboarding-specific — all are regular work needing a new owner. Suggested owners inferred from who's active in each area (Jacob = connector/infra/rearch, Paolo = External API / admin endpoints, Uladzimir = DS/eval epic ENG-292, Brad = AutoPatrol/customer). **Confirm owners with the team — don't unilaterally reassign.**

| Ticket | Status | Pri | Summary | Plan tie | Suggested disposition |
|---|---|---|---|---|---|
| ENG-289 | In Progress | Med | onboarder ops tooling + post-deploy verify | **WS-0** | Land open PR #16 this week, close out. |
| ENG-352 | In Review | Med | AP per-camera tier + crowd-not-Tier3 fix | AP | If merge-close, push it; else → AP owner. |
| ENG-300 | In Progress | Med | Watchman watch-mgmt service: fleet & scheduling arch design | §5 | **Design doc — needs a named successor or it stalls.** Hand to Watchman/ENG-292 owner. |
| ENG-309 | In Progress | Med | PyAV 13.1→17 vms-connector + watchman (AmeriGas soak) | connector | → Jacob (owns connector rearch). Pairs w/ ENG-136. |
| ENG-269 | In Progress | Med | admin automated endpoints for custom branches (§29) | §29 | → Paolo. Sibling of ENG-282. |
| ENG-247 | In Progress | Med | Research: move off raw SQL in non-admin contexts | research | Convert to doc + hand off, or reassign. |
| ENG-282 | Ready-to-Deploy | Med | Custom-branch lifecycle: admin endpoints + connector CI/CD | §29 | → Paolo. Ships; low risk. |
| ENG-246 | Ready-to-Deploy | Med | actuate-instrumentation perf extension (§30) | §30 | Reassign; ready, low risk. |
| ENG-136 | Ready-to-Deploy | High | PyAV upgrade 13.1→17 (nogil pixel conversion) | connector | → Jacob. Pairs w/ ENG-309. |
| CS3-31 | Ready-to-Deploy | **Highest** | Automatically update the reference image | CS3 | **Highest priority — reassign explicitly, don't let it drop.** |
| CS3-323 | Ready-to-Deploy | High | Cam count discrepancy dashboard vs report | CS3 | Land or reassign (CS3 owner). |
| CS3-58 | Ready-to-Deploy | Lowest | Configuration per camera | CS3 | Reassign; low. |
| CS3-537 | To Do | High | resolved_user on healthcheck rollup API | CS3 | Reassign CS3 owner. |
| ENG-183 | To Do | Med | S3 Cost Reduction — ranked action plan | §5/cost | Hand off as doc; ties to cost work. |
| ENG-94 | To Do | Med | Deferred alerts: send w/o frame fallback | AP/connector | Reassign. |
| CS3-505 | To Do | Med | add outcome to CHM alerts API | CS3 | Reassign. |
| BT-259 | Open | Med | "Use Motion" toggle bug | BT | Reassign BT owner. |

**In-flight code threads already in the plan** (not separate tickets, hand off with runbooks): Envera TLS + cutover, §18 VPA-floor PR, §14 midnight arm-miss race, PR #91 v5 decision.

## Related

- [[2026-05-05_laptop-config-portability-context]] — the §10 DR inventory (what must survive); offboarding flips the destination from future-Mark to the team.
- [[mark-todos]] §10 (portability), §9 (dashboard), §12 (minipc app), §24 (LLM shop), §3/§18/§5/§14/§33 (in-flight workstreams to hand off).
- `aegissystems/actuate-dev-toolkit` — minipc provisioning phases (`phase-00`…`phase-09`); the firebat runbook belongs here.
