---
title: "Offboarding manual-action checklist — everything that needs human hands"
type: concept
topic: offboarding
tags: [offboarding, checklist, manual, ws-a, handoff, credentials]
created: 2026-06-22
updated: 2026-06-22
author: kb-bot
incoming:
  - home/README.md
  - home/offboarding/2026-06-23_autopatrol-handoff.md
  - home/offboarding/2026-06-23_firebat-dashboard-ownership-handoff.md
  - home/offboarding/2026-06-23_local-repo-audit.md
  - home/offboarding/2026-06-23_watchman-fleet-handoff-paolo-mike.md
  - home/offboarding/2026-06-24_firebat-kb-git-sync-task.md
  - home/offboarding/2026-06-24_offboarding-asks.md
  - home/offboarding/2026-06-25_in-room-session-runbook.md
  - home/offboarding/2026-06-25_team-handoff-announcement.md
  - home/offboarding/offboarding-overview.md
incoming_updated: 2026-06-26
---

# Offboarding manual checklist (Mark — last day Fri 2026-06-26)

> The single list of everything that **can't be automated** — credential re-homes, admin-console actions, team decisions, and final verification. Everything *codeable* is already done (8 handoff docs, KB secured, ENG-375 epic, verify harness, dead-man's checklist). This is the human-hands remainder.
>
> **Order matters:** §A (decide) unblocks §B; §C/§D/§F are independent; §H is Friday.
> **First & last move:** run `~/bin/firebat-identity-verify.py` on firebat — it tells you what's still red. Baseline: `~/identity-baseline-pre-rehome.json`. Plan: [[2026-06-22_offboarding-plan]] · Map: [[2026-06-22_actuate-footprint-handoff]].

---

## §A — DECIDE FIRST (team): the automation identity  ⛔ blocks §B

GitHub, [[new-relic|New Relic]], and Atlassian all need the **same** answer: *which team-owned identity does firebat's automation authenticate as?* Decide once, apply to all three.

- [x] **DECIDED 2026-06-25 — Option 1: named successor (the firebat/dashboard owner) credentials.** A seatless/no-signup *service* identity isn't easily available for any of the three: GitHub query+push needs a machine user (new email) or a GitHub App (1-hour tokens, too fiddly for the cron scripts); NR NerdGraph queries need a per-user User key; Atlassian API tokens are per-user (a service account = a new licensed seat). The team doesn't want a new email/seat, so the **named successor mints all three under their existing logins** (least-privilege where possible — see §B1's fine-grained PAT). If the team later wants to decouple from a person → GitHub App + NR/Jira service seats (future task, not blocking).
  - Earlier options for the record: ~~Option 2 dedicated service/bot identity (needs new accounts/seats — declined)~~; ~~Option 3 defer (timers break at deactivation — declined)~~.
- [x] **Named successor / firebat owner: ____________________** *(fill in the person who'll own firebat + the dashboard; their logins back the automation)*

---

## §B — Credential re-homes on firebat  *(after §A; SSH-doable)*

For each: **mint the token in the provider UI → write it on the box (you type it; never paste secrets into chat) → I/you re-run the verify harness.**

### B1 — GitHub  (`repo-scan`, `git-fetch-major-repos`, `pr-review-digest`, KB-mirror push)
- [ ] Mint a credential per §A (classic PAT `repo`+`read:org`, or fine-grained: Contents/Metadata/Issues/PRs **read** on all aegissystems repos + Contents **write** on the 2 mirror repos).
- [ ] On firebat: `gh auth logout --hostname github.com` → `gh auth login --hostname github.com --git-protocol https` (paste token) → `gh auth setup-git`.
- [ ] Verify: `gh api repos/aegissystems/vms-connector --jq .full_name` + harness `github.identity` ✅.

### B2 — New Relic  (`~/.config/newrelic/key`; used by `run-dashboard-check`, `morning-prep`)
- [ ] In NR UI, as the §A identity, mint a **User API key** (`NRAK-…`).
- [ ] On firebat: `printf '%s' '<NRAK-new>' > ~/.config/newrelic/key` (mode 600).
- [ ] **Revoke the old key** (it was leaked into git history then purged — rotate regardless).
- [ ] Verify: harness `newrelic.key` shows the new (non-Mark) owner.

### B3 — Atlassian  (`~/.config/atlassian/api-token`; used by `jira-sync`)
- [ ] In Atlassian, as the §A identity, mint an API token (id.atlassian.com → Security → API tokens).
- [ ] On firebat: edit `~/.config/atlassian/api-token` (JSON: `{"email":"<service-email>","token":"<new>","site":"https://actuate-team.atlassian.net"}`).
- [ ] Verify: harness `atlassian.token` shows the service identity ✅.

---

## §C — Tailscale re-tag  ⚠ NEEDS A TAILNET ADMIN (Mark lacks admin)

Goal: make the firebat + npu-server nodes **tag-owned** (`tag:server`) so they survive Mark's deactivation. Currently user-owned by `mark@`.

- [ ] **Find a tailnet admin/owner** of `aegissystems.ai`. The tailnet has 5 members (aziz.yousif@, jacob@, mark@, michael@, tatiana@); Mark/Mike/Aziz are **not** admins, so the owner is most likely **[[jacob-weiss|Jacob Weiss]] (`jacob@`)** or **[[tatiana-hanazaki|Tatiana Hanazaki]] (`tatiana@`)** — ask Jacob first. Either have them do it, or grant Mark temporary admin.
- [ ] Admin: in `login.tailscale.com` → **Access controls**, ensure `"tag:server"` exists with `tagOwners`, and grants let team devices reach `tag:server` over SSH/HTTP (or the box becomes unreachable).
- [ ] Admin: **Settings → Keys → Generate auth key**, tagged `tag:server`.
- [ ] **At each box's console** (firebat, then npu-server): `sudo tailscale up --authkey=tskey-… --advertise-tags=tag:server`. ⚠ Do at the physical/console terminal — it can drop SSH.
- [ ] Verify: harness `tailscale.identity` ✅ (tagged). *Reframe: **not** a "box goes dark" emergency — Tailscale is only remote reachability, not a functional dependency. Timers + KB git-sync (over the internet) + dashboard keep running, and the box stays LAN-reachable at the office (`actuate-dev.local`). Without the re-tag, only off-LAN access via `mork-firebat` lapses when Mark's account is deactivated — recoverable later by any admin from the box console. Do it with Jacob if available; if it slips, it's not catastrophic.*

---

## §D — npu-server SSH access  *(independent)*
- [ ] From a team machine: `ssh npu-server.tail9b2a4e.ts.net` — accept the host key.
- [ ] Push a **non-Mark** SSH public key to the box (`~/.ssh/authorized_keys`) so maintenance access survives.
- [ ] Confirm the LLM-shop units are up: `systemctl --user list-units 'llm-shop-*'` + `curl :8080/api/status`. *(The HTTP service path already survives via the §C Tailscale re-tag; this is for maintenance only.)* Runbook: [[2026-06-22_npu-server-llm-shop-runbook]].

---

## §E — KB / config org mirror
- [x] **KB → `aegissystems/actuate-kb` (private) — DONE 2026-06-23.** Pushed via actuateMark (org allows member repo creation; didn't need the §A decision after all). Scrubbed first: gitleaks-clean + a colleague's personal IP purged from all history + incident-note naming neutralized. All 3 remotes (org, firebat, personal) carry the cleaned history.
- [x] **claude-config → `aegissystems/claude-config` (private) — DONE 2026-06-24.** 64 files (skills/agents/hooks/rules; no credentials/transcripts tracked); gitleaks-clean; 0 name-blame/IP/profanity. Last personal-account repo mirrored.
- [ ] Tell the team the KB now lives at `aegissystems/actuate-kb` (make it the canonical remote).
- [x] **firebat KB sync → git-pull from `aegissystems/actuate-kb` — DONE 2026-06-24** — firebat currently updates the vault via **Obsidian Sync (Mark's account)**, which freezes when that account ends. Replace with a `git pull` timer (pull-only, org canonical). At-the-box change; pairs with WS-A. Design + steps: [[2026-06-24_firebat-kb-git-sync-task]].

---

## §F — Confluence publish  *(Atlassian writes are laptop-blocked → do in the UI)*
- [ ] Publish [[2026-06-22_actuate-footprint-handoff]] as the team's "Mark's Actuate footprint" page.
- [ ] Link the high-value runbooks ([[2026-06-22_firebat-operations-runbook]], [[2026-06-22_dashboard-signals-catalog]], [[2026-06-22_npu-server-llm-shop-runbook]], [[2026-06-22_dead-mans-checklist]]).

---

## §G — Jira assignees  *(team lead)*
- [ ] Handoff comments are already posted on all 13 open tickets. **Team lead sets the assignees.** Don't-drop: CS3-31 (Highest), CS3-537/CS3-323 (High), ENG-300 (needs a named successor or it stalls). Ledger in [[2026-06-22_offboarding-plan]].

---

## §H — Final verification + decommission  *(Friday)*
- [ ] Full active verify on firebat: `~/bin/firebat-identity-verify.py --run-timers` → all ✅, all timers exit 0 under the new identities.
- [ ] **Teammate-vantage check:** a colleague confirms from *their* machine — reach firebat over Tailscale, timers green, org repos + Confluence readable.
- [ ] Decommission Mark-tied bits: personal Anthropic API key, personal Slack webhooks, the laptop.
- [ ] When green, transition the ENG-375 children to Done.

## §I — Successor handoffs  *(name an owner per workstream, then walk it)*
- [x] **[[watchman-repo|Watchman]] + fleet-arch** → Mike (ENG-300) + Paolo (ENG-383). Plan: [[2026-06-23_watchman-fleet-handoff-paolo-mike]].
- [ ] **Run the [[watchman-repo|Watchman]] walkthrough** (Mark + Mike + Paolo, 60–90 min) — the irreplaceable knowledge transfer; do before Friday.
- [ ] **Park ENG-183** (S3 cost) with whoever takes infra.
- [ ] **Name owners for the remaining unowned workstreams** and build a handoff plan for each (candidates: firebat automation + operational dashboard §9/§12; AutoPatrol §3/§14; billing §28; RDS upgrades §33; connector/[[pyav-entity|PyAV]] §15). The dashboard/firebat-automation layer is the most uniquely Mark's — it runs without an owner but won't be *maintained or extended* without one.
- [ ] **Repo-doc PRs (CLAUDE.md / docs handoff) — 6/10 merged 2026-06-25** (see [[2026-06-23_local-repo-audit]] § Execution status):
  - [x] **Merged** (docs-only, squashed): actuate-dev-toolkit #1, autopatrol-server #29, actuate_bi #12, actuate-inference-api #95, queue_consumer #194, [[ds-terraform-eks-v2]] #104.
  - [ ] **Need a review approval** (otherwise clean, CI green): vms-connector #1765, [[kubernetes-deployments]] #419.
  - [ ] **Needs work**: [[actuate_admin]] #2537 (conflicting + 1 failing check + review required).
  - [ ] **Held — do NOT auto-merge**: actuate-libraries #392 (clean, but its `main` auto-publishes; merge deliberately).
- [x] **Pushed 2 LOCAL-ONLY repos to the org 2026-06-23** — `aegissystems/actuate-integration-tools` + `aegissystems/software-arch-sketches` (private, with CLAUDE.md; both gitleaks-clean, .git ≈1M each). A full sweep of all 25 repos confirmed these were the ONLY two without a remote.
- [ ] **camera-ui CLAUDE.md** — skipped (local main 249 behind, stale base); apply the small tech-stack + live-streaming note manually on current main if desired.

## Related
- [[2026-06-22_offboarding-plan]] · [[2026-06-22_actuate-footprint-handoff]] · [[2026-06-22_dead-mans-checklist]] · [[2026-06-23_watchman-fleet-handoff-paolo-mike]]
- [[2026-06-22_firebat-operations-runbook]] · [[2026-06-22_dashboard-signals-catalog]] · [[2026-06-22_npu-server-llm-shop-runbook]]
