---
title: "In-room session runbook — finish the manual offboarding steps (2026-06-25)"
type: concept
tags: [offboarding, runbook, session, home]
updated: 2026-06-25
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-06-26
---

# In-room session runbook — finish the manual steps

> For a ~45-min working session: **Mark + a colleague**, with the firebat box console reachable. Goal: clear the team-gated §A–§I items in [[2026-06-22_manual-action-checklist]]. **Golden rule: never paste secret values into chat or shell history — type them on the box** (`read -s`, an editor, or the token prompt). Baseline before you start: **0 FAIL, 3 WARN** (GitHub, Atlassian, Tailscale) + rotate the NR key.

## What your colleague needs access to (match steps to who's in the room)
- **GitHub org admin** → mint the automation token (Phase 1). **[[new-relic|New Relic]] admin** → mint a User key. **Atlassian admin** → mint a service API token. **Tailscale admin** of `aegissystems.ai` (aziz / jacob / michael) → re-tag the box. **Team lead** → set Jira assignees. (One person may cover several.)

---

## Before the room — colleague pre-work (do in advance, ~15 min)
The successor mints all creds under their **own existing logins** and brings them to the session in a password manager / secure note — **don't send secrets over chat/email in plaintext.**
1. **GitHub fine-grained PAT** — github.com → avatar → *Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token*. Name `firebat-automation`; **Resource owner = `aegissystems`**; Repository access = All repositories; Permissions → **Contents: Read and write**, **Metadata: Read**, **Pull requests: Read**, **Issues: Read**. Generate → copy. *(If the org requires approval for fine-grained PATs, an org owner must approve it before it works.)*
2. **[[new-relic|New Relic]] User key** — one.newrelic.com → bottom-left user menu → *API keys → Create a key* → type **User**, name `firebat-automation` → copy the `NRAK-…`.
3. **Atlassian API token** — id.atlassian.com → *Security → API tokens → Create API token* → label `firebat-jira-sync` → copy (note their account email + `https://actuate-team.atlassian.net`).
4. **Tailscale — needs a tailnet admin** (likely **[[jacob-weiss|Jacob Weiss]]**, maybe **[[tatiana-hanazaki|Tatiana Hanazaki]]**; Mark/Mike/Aziz are not admins). Confirm with Jacob beforehand. (Admin) login.tailscale.com → *Access controls*: ensure `tag:server` exists in `tagOwners` + ACLs let team devices reach `tag:server` over SSH/HTTP; *Settings → Keys → Generate auth key* tagged `tag:server` → copy `tskey-…`. *Not a hard blocker — see Phase 3's fallback.*
5. **Their SSH public key** (for npu-server §D) — `cat ~/.ssh/id_ed25519.pub` (or `id_rsa.pub`) → copy.
6. **Access sanity check** — confirm they're an `aegissystems` org member who can read repos + approve PRs, have NR + Jira access, and **Tailscale installed on their own laptop** (needed for the verify step).

**Bring to the room (secure note):** GitHub PAT · NR `NRAK-…` · Atlassian token + email · Tailscale `tskey-…` (if admin) · their SSH pubkey.

## Phase 0 — Identity model  (§A · DECIDED)
**Decision (2026-06-25): named successor** — the person who'll own firebat + the dashboard mints all three creds under their **existing** GitHub / [[new-relic|New Relic]] / Atlassian logins. No new email/account/seat (a seatless service identity isn't easily available: GitHub needs a machine user or a fiddly GitHub App; NR query keys are per-user; Atlassian service accounts cost a seat). Use **least privilege** where possible (fine-grained GitHub PAT — Phase 1). Decoupling from a person later = GitHub App + NR/Jira service seats (future, non-blocking).

**→ Write the successor's name in [[2026-06-22_manual-action-checklist]] §A. "The §A identity" below = that person.**

## Phase 1 — Mint the 3 credentials  (colleague · ~10 min)
1. **GitHub** — **prefer a fine-grained PAT** (least privilege, since it's a person's account): Contents/Metadata/Issues/PRs **read** on all `aegissystems` repos + Contents **write** on `actuate-kb` and `claude-config`. *(Simpler fallback: a classic PAT with `repo` + `read:org`.)*
2. **[[new-relic|New Relic]]** — User API key (`NRAK-…`) minted as the §A identity.
3. **Atlassian** — API token at `id.atlassian.com → Security → API tokens` (service email).

*Hold these to paste on the box in Phase 2 — don't send them over chat.*

## Phase 2 — Re-home on firebat  (Mark drives over SSH · ~10 min)
```bash
ssh mork@mork-firebat        # one terminal for all of Phase 2

# 2a. GitHub
gh auth logout --hostname github.com
gh auth login  --hostname github.com --git-protocol https   # paste the new PAT at the prompt
gh auth setup-git
gh api repos/aegissystems/vms-connector --jq .full_name      # → aegissystems/vms-connector

# 2b. New Relic (no echo to history; account_id stays 3421145)
read -rs NRAK && printf '%s' "$NRAK" > ~/.config/newrelic/key && unset NRAK && chmod 600 ~/.config/newrelic/key
#   then REVOKE the old key in the NR UI (it was leaked→purged — rotate regardless)

# 2c. Atlassian — edit the JSON {email, token, site}
chmod 600 ~/.config/atlassian/api-token
${EDITOR:-nano} ~/.config/atlassian/api-token
#   {"email":"<service-email>","token":"<new>","site":"https://actuate-team.atlassian.net"}
~/bin/jira-sync.sh --force --dry-run                         # should succeed as the new identity

# 2d. Confirm all three flipped PERSONAL → service
~/bin/firebat-identity-verify.py | grep -iE 'github|newrelic|atlassian'
```

## Phase 3 — Tailscale re-tag  (admin + AT THE BOX CONSOLE · ~10 min)
**Admin needed: likely [[jacob-weiss|Jacob Weiss]] (maybe Tatiana); Mark/Mike/Aziz aren't admins.** *Reframe: this is **not** a "box goes dark" emergency — Tailscale is only remote reachability, not a functional dependency. The timers + KB git-sync (over the internet) + dashboard keep running, and the box stays LAN-reachable at the office (`actuate-dev.local`). What lapses without the re-tag is off-LAN access via `mork-firebat` once Mark's account is deactivated — and an admin can re-tag/re-add it later from the box console. Do it with Jacob if you can; if it slips, it's recoverable.*
⚠ **Do this at the firebat keyboard/monitor (or direct cable), NOT over SSH — re-auth drops the SSH session.**
1. **Admin** in `login.tailscale.com → Access controls`: ensure `tag:server` exists with `tagOwners`, and ACLs let team devices reach `tag:server` over SSH/HTTP.
2. **Admin → Settings → Keys → Generate auth key**, tagged `tag:server`.
3. **At the firebat console:**
   ```bash
   sudo tailscale up --authkey=tskey-… --advertise-tags=tag:server
   ```
4. Back on your laptop: `ssh mork@mork-firebat '~/bin/firebat-identity-verify.py | grep tailscale'` → should show **tagged**.

## Phase 4 — npu-server  (§D · BLOCKED: box is OFFLINE as of 2026-06-25 ~18:03 UTC)
**Confirmed offline** — both the tailnet (`100.71.153.1`, "last seen 3h ago") and the public-IP break-glass (`:3327`, "no route to host") are dead. **Power it on + reconnect to a network first** (e.g. when it lands at the office); it'll rejoin the tailnet under Mark's account automatically. Only then:
- From a machine with access: `ssh npu-server` (laptop, key `~/.ssh/npu-server`) or `ssh actuate@npu-server.tail9b2a4e.ts.net`; append a **non-Mark** public key to `~/.ssh/authorized_keys`; confirm `systemctl --user list-units 'llm-shop-*'` + `curl :8080/api/status`.
- Re-tag npu-server in Tailscale too (same as Phase 3, at its console). The HTTP service path survives the re-tag regardless; SSH key is maintenance-only. Runbook: [[2026-06-22_npu-server-llm-shop-runbook]].

## Phase 5 — Approve the 2 doc PRs  (colleague · ~3 min · §I)
Both docs-only, CI-green, just need a review approval:
- `aegissystems/vms-connector #1765` (architecture-rationale)
- `aegissystems/kubernetes-deployments #419` ([[argocd|ArgoCD]]/app-of-apps CLAUDE.md)
Open each → **Files changed → Review → Approve → Merge**. *([[actuate_admin]] #2537 is now conflict-free too, if you want to approve+merge it; actuate-libraries #392 is clean but merge deliberately — its `main` auto-publishes.)*

## Phase 6 — Verify  (§H · ~5 min)
```bash
ssh mork@mork-firebat '~/bin/firebat-identity-verify.py --run-timers'   # want 0 FAIL, the 3 WARNs now PASS
```
**Teammate-vantage check** — colleague, from *their* machine:
```bash
ssh mork@mork-firebat 'uptime'                                  # reachable over Tailscale
gh api repos/aegissystems/actuate-kb --jq .full_name            # org repo readable
```

## Phase 7 — Jira assignees  (§G · if team lead present)
Handoff comments are already posted on all open tickets — just set assignees. Don't-drop: **CS3-31** (Highest), **CS3-537**, **CS3-323**, **ENG-300**. Ledger in [[2026-06-22_offboarding-plan]].

---

## Done when
`firebat-identity-verify.py --run-timers` → **0 FAIL, 0 WARN**, all timers exit 0 under the new identities; box reachable from a colleague's machine; the 2 PRs merged. Then transition the ENG-375 children toward Done and tick §A/§B/§C/§H in [[2026-06-22_manual-action-checklist]].
