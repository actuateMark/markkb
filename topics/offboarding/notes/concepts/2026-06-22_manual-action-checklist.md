---
title: "Offboarding manual-action checklist — everything that needs human hands"
type: concept
topic: offboarding
tags: [offboarding, checklist, manual, ws-a, handoff, credentials]
created: 2026-06-22
updated: 2026-06-22
author: kb-bot
---

# Offboarding manual checklist (Mark — last day Fri 2026-06-26)

> The single list of everything that **can't be automated** — credential re-homes, admin-console actions, team decisions, and final verification. Everything *codeable* is already done (8 handoff docs, KB secured, ENG-375 epic, verify harness, dead-man's checklist). This is the human-hands remainder.
>
> **Order matters:** §A (decide) unblocks §B; §C/§D/§F are independent; §H is Friday.
> **First & last move:** run `~/bin/firebat-identity-verify.py` on firebat — it tells you what's still red. Baseline: `~/identity-baseline-pre-rehome.json`. Plan: [[2026-06-22_offboarding-plan]] · Map: [[2026-06-22_actuate-footprint-handoff]].

---

## §A — DECIDE FIRST (team): the automation identity  ⛔ blocks §B

GitHub, New Relic, and Atlassian all need the **same** answer: *which team-owned identity does firebat's automation authenticate as?* Decide once, apply to all three.

- [ ] **Pick the identity model** (team discussion — posted to [ENG-376](https://actuate-team.atlassian.net/browse/ENG-376)):
  - **Option 1 — staying teammate/owner credentials** *(fastest, ~5 min each)*: a person who's staying mints the PAT/keys. Durable past Mark; tied to that person.
  - **Option 2 — dedicated service/bot identity** *(most durable, more setup)*: e.g. a GitHub `actuate-automation` account + an NR service user + an Atlassian service user. Decoupled from everyone; may cost seats.
  - **Option 3 — defer**: leave on Mark's creds until deactivation, provision after (risk: timers break at deactivation).
- [ ] Record the decision here once made: **____________________**

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

- [ ] **Find a tailnet admin/owner** of `aegissystems.ai` (candidates seen on the tailnet: aziz.yousif@, jacob@, michael@). Either have them do it, or have them grant Mark temporary admin.
- [ ] Admin: in `login.tailscale.com` → **Access controls**, ensure `"tag:server"` exists with `tagOwners`, and grants let team devices reach `tag:server` over SSH/HTTP (or the box becomes unreachable).
- [ ] Admin: **Settings → Keys → Generate auth key**, tagged `tag:server`.
- [ ] **At each box's console** (firebat, then npu-server): `sudo tailscale up --authkey=tskey-… --advertise-tags=tag:server`. ⚠ Do at the physical/console terminal — it can drop SSH.
- [ ] Verify: harness `tailscale.identity` ✅ (tagged). *This is the "box goes dark Friday" item — highest priority of the lot.*

---

## §D — npu-server SSH access  *(independent)*
- [ ] From a team machine: `ssh npu-server.tail9b2a4e.ts.net` — accept the host key.
- [ ] Push a **non-Mark** SSH public key to the box (`~/.ssh/authorized_keys`) so maintenance access survives.
- [ ] Confirm the LLM-shop units are up: `systemctl --user list-units 'llm-shop-*'` + `curl :8080/api/status`. *(The HTTP service path already survives via the §C Tailscale re-tag; this is for maintenance only.)* Runbook: [[2026-06-22_npu-server-llm-shop-runbook]].

---

## §E — KB org mirror  *(after §B1 GitHub identity)*
- [ ] Create `aegissystems/markkb` + `aegissystems/claude-config` (both are **gitleaks-clean**, verified).
- [ ] `git remote add org <url>` in each + `git push org master/main`.
- [ ] Set the org repo as the canonical remote; tell the team where the KB now lives.

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
- [x] **Watchman + fleet-arch** → Mike (ENG-300) + Paolo (ENG-383). Plan: [[2026-06-23_watchman-fleet-handoff-paolo-mike]].
- [ ] **Run the Watchman walkthrough** (Mark + Mike + Paolo, 60–90 min) — the irreplaceable knowledge transfer; do before Friday.
- [ ] **Park ENG-183** (S3 cost) with whoever takes infra.
- [ ] **Name owners for the remaining unowned workstreams** and build a handoff plan for each (candidates: firebat automation + operational dashboard §9/§12; AutoPatrol §3/§14; billing §28; RDS upgrades §33; connector/PyAV §15). The dashboard/firebat-automation layer is the most uniquely Mark's — it runs without an owner but won't be *maintained or extended* without one.
- [ ] **Review + merge the 10 repo-doc PRs** (CLAUDE.md / docs handoff — see [[2026-06-23_local-repo-audit]] § Execution status): autopatrol-server #29, actuate_bi #12, ds-terraform-eks-v2 #104, actuate-dev-toolkit #1, vms-connector #1765, actuate_admin #2537, actuate-inference-api #95, actuate-libraries #392, kubernetes-deployments #419, queue_consumer #194. Docs-only, low-risk.
- [ ] **🚨 Push 2 LOCAL-ONLY repos to the org** — `actuate-integration-tools` and `software-arch-sketches` have **no git remote**; they exist only on Mark's laptop (CLAUDE.md committed locally). Create `aegissystems/<repo>` + push both, or they die with the laptop. *(Audit for other local-only repos too.)*
- [ ] **camera-ui CLAUDE.md** — skipped (local main 249 behind, stale base); apply the small tech-stack + live-streaming note manually on current main if desired.

## Related
- [[2026-06-22_offboarding-plan]] · [[2026-06-22_actuate-footprint-handoff]] · [[2026-06-22_dead-mans-checklist]] · [[2026-06-23_watchman-fleet-handoff-paolo-mike]]
- [[2026-06-22_firebat-operations-runbook]] · [[2026-06-22_dashboard-signals-catalog]] · [[2026-06-22_npu-server-llm-shop-runbook]]
