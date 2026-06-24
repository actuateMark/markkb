---
title: "Offboarding — paste-ready asks + steps for the remaining items"
type: concept
topic: offboarding
tags: [offboarding, asks, handoff, checklist]
created: 2026-06-24
updated: 2026-06-24
author: kb-bot
---

# Remaining-item asks + steps

Copy-paste messages for the human-gated items + exact steps for the do-yourself ones. Tracks the [[2026-06-22_manual-action-checklist]].

## §A — Automation-identity decision  (→ team channel; also on [ENG-376](https://actuate-team.atlassian.net/browse/ENG-376))
> **Decision needed before I leave Fri:** the firebat automation box authenticates to GitHub / New Relic / Atlassian **as me** right now. When my accounts are deactivated, those timers (repo-scan, jira-sync, dashboard-check, etc.) break. We need to pick **one team-owned identity** for them to run as. Three options:
> 1. **Fastest (~5 min each):** a staying teammate or org owner mints the PAT/keys — durable past me, tied to that person.
> 2. **Most durable (~30 min):** a dedicated service/bot identity (a GitHub `actuate-automation` account + NR service user + Atlassian service user) — decoupled from everyone; may cost seats.
> 3. **Defer:** leave it on my creds until deactivation and provision after (risk: timers break the moment my account goes).
> I lean (1) for this week. Who can own it? Once decided, the GitHub/NR/Atlassian swap on the box takes ~10 min total.

## §C — Tailscale re-tag  (→ DM a tailnet admin: aziz.yousif@ / jacob@ / michael@)
> **~10 min, needs tailnet admin — the "box goes dark Friday" item.** The firebat minipc (`mork-firebat`) and npu-server are registered under **my** Tailscale identity; when I'm deactivated they drop off the tailnet and become unreachable. Fix = make them **tag-owned** instead. Either you do it, or grant me temporary admin. Steps:
> 1. `login.tailscale.com` → **Access controls**: ensure a `"tag:server"` exists in `tagOwners`, and that ACL grants let the team reach `tag:server` over SSH/HTTP.
> 2. **Settings → Keys → Generate auth key**, tagged `tag:server` (reusable, not ephemeral).
> 3. **At each box's console** (firebat, then npu-server — not over SSH, it can drop the session): `sudo tailscale up --authkey=tskey-… --advertise-tags=tag:server`.
> Verify after: `~/bin/firebat-identity-verify.py` shows `tailscale.identity` ✅ tagged.

## §B — GitHub / NR / Atlassian re-home on firebat  (after §A; I can drive over SSH once the identity's chosen)
On firebat, per the chosen §A identity:
- **GitHub:** `gh auth logout --hostname github.com` → `gh auth login --hostname github.com --git-protocol https` (paste the org token) → `gh auth setup-git`. Verify `gh api repos/aegissystems/vms-connector --jq .full_name`.
- **New Relic:** `printf '%s' '<new NRAK>' > ~/.config/newrelic/key && chmod 600 ~/.config/newrelic/key`; revoke the old key.
- **Atlassian:** edit `~/.config/atlassian/api-token` → `{"email":"<service-email>","token":"<new>","site":"https://actuate-team.atlassian.net"}`, `chmod 600`.
- Verify all: `~/bin/firebat-identity-verify.py` — the 3 WARNs flip to ✅; then `--run-timers` to confirm each cred-dependent timer exits 0.

## §D — npu-server SSH access  (→ team)
> npu-server (the local-LLM box) has no non-Mark SSH access set up. From your machine: `ssh npu-server.tail9b2a4e.ts.net` (accept the host key), then add a **non-Mark** public key to `~/.ssh/authorized_keys`. The LLM shop itself is consumed over HTTP on the tailnet (survives the §C re-tag) — this is for maintenance only. Runbook: `aegissystems/actuate-kb` → `2026-06-22_npu-server-llm-shop-runbook`.

## §F — Confluence publish  (you, in the Confluence UI)
1. New page in the team space, title **"Mark's Actuate footprint"**.
2. Paste the content of `2026-06-22_actuate-footprint-handoff.md` (the START-HERE map) from `aegissystems/actuate-kb`.
3. Link the runbooks: firebat-operations, dashboard-signals-catalog, npu-server-llm-shop, dead-man's-checklist.
*(Atlassian writes are blocked from my laptop, so this is a manual UI step.)*

## §G — Jira assignees  (→ team lead)
> I've posted per-ticket handoff comments on all 13 of my open tickets (current state + what's needed to pick up). They just need owners assigned. **Don't-drop:** CS3-31 (Highest), CS3-537 / CS3-323 (High), and ENG-300 (Watchman design — already pointed at Mike, needs confirming). Full ledger + suggested owners: `2026-06-22_offboarding-plan` § "Jira reassignment ledger".

## §I — Successor walkthroughs  (you schedule)
> **Watchman + fleet-arch (Mike + Paolo), 60–90 min before Fri:** walk the Phase-0 shape + the deploy/connector vs fleet/k8s split. Tickets ENG-300 (Mike) + ENG-383 (Paolo); spine = `2026-06-02_watchman-phase0-fleet-fit` + `2026-06-16_watchman-pipeline-backend-meeting`; agenda in `2026-06-23_watchman-fleet-handoff-paolo-mike`.
> **AutoPatrol (Brad), ~45 min:** the cleanup-Lambda state machine + `/autopatrol-cleanup-lambda-check`. Reading list in `2026-06-23_autopatrol-handoff`.

## §H — Friday: verify + decommission  (you + 1 teammate)
1. `~/bin/firebat-identity-verify.py --run-timers` → all ✅, every timer exits 0 under the new identities.
2. **Teammate-vantage check:** a colleague confirms from *their* machine — reach firebat over Tailscale, timers green, `aegissystems/actuate-kb` + Confluence readable.
3. Decommission: personal Anthropic API key, personal Slack webhooks, the laptop.
4. Transition the ENG-375 children to Done.

## Announce  (→ team channel)
> **The KB now lives at `aegissystems/actuate-kb`** (private). It has the full vault + a `_tooling/` bundle (skills, agents, scripts, SETUP.md) so anyone can clone-and-run their own instance. firebat auto-pulls it every 30 min. My Claude config is at `aegissystems/claude-config`. Start-here map: the `2026-06-22_actuate-footprint-handoff` note (also going to Confluence).

## Related
- [[2026-06-22_manual-action-checklist]] · [[2026-06-22_offboarding-plan]] · [[2026-06-22_actuate-footprint-handoff]]
