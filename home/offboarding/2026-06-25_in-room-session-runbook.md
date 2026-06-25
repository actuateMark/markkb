---
title: "In-room session runbook — finish the manual offboarding steps (2026-06-25)"
type: concept
tags: [offboarding, runbook, session, home]
updated: 2026-06-25
author: kb-bot
---

# In-room session runbook — finish the manual steps

> For a ~45-min working session: **Mark + a colleague**, with the firebat box console reachable. Goal: clear the team-gated §A–§I items in [[2026-06-22_manual-action-checklist]]. **Golden rule: never paste secret values into chat or shell history — type them on the box** (`read -s`, an editor, or the token prompt). Baseline before you start: **0 FAIL, 3 WARN** (GitHub, Atlassian, Tailscale) + rotate the NR key.

## What your colleague needs access to (match steps to who's in the room)
- **GitHub org admin** → mint the automation token (Phase 1). **New Relic admin** → mint a User key. **Atlassian admin** → mint a service API token. **Tailscale admin** of `aegissystems.ai` (aziz / jacob / michael) → re-tag the box. **Team lead** → set Jira assignees. (One person may cover several.)

---

## Phase 0 — DECIDE the identity model  (§A · 5 min · unblocks everything)
Pick ONE and write it into [[2026-06-22_manual-action-checklist]] §A:
- **(a) Org machine account** (e.g. `actuate-automation`) the team owns — its PAT + its NR/Atlassian identities. *Cleanest long-term; needs creating the account.*
- **(b) Fine-grained org PAT under a service/existing identity** — no new account; PAT scoped to the repos + NR key + Atlassian token under a service owner. *Fastest today.* ← recommended if you want it done this session.
- **(c) A named successor's personal creds** — quick, but re-couples firebat to one person.

Everything below uses "the §A identity."

## Phase 1 — Mint the 3 credentials  (colleague · ~10 min)
1. **GitHub** — classic PAT scopes `repo` + `read:org`; *or* fine-grained: Contents/Metadata/Issues/PRs **read** on all `aegissystems` repos + Contents **write** on `actuate-kb` and `claude-config`.
2. **New Relic** — User API key (`NRAK-…`) minted as the §A identity.
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

## Phase 3 — Tailscale re-tag  (admin + AT THE BOX CONSOLE · ~10 min · highest priority)
⚠ **Do this at the firebat keyboard/monitor (or direct cable), NOT over SSH — re-auth drops the SSH session.**
1. **Admin** in `login.tailscale.com → Access controls`: ensure `tag:server` exists with `tagOwners`, and ACLs let team devices reach `tag:server` over SSH/HTTP (else the box goes unreachable).
2. **Admin → Settings → Keys → Generate auth key**, tagged `tag:server`.
3. **At the firebat console:**
   ```bash
   sudo tailscale up --authkey=tskey-… --advertise-tags=tag:server
   ```
4. Back on your laptop: `ssh mork@mork-firebat '~/bin/firebat-identity-verify.py | grep tailscale'` → should show **tagged**.

## Phase 4 — npu-server  (§D · do only if it's reachable — SSH was timing out 2026-06-25)
- If the box is up: from a team machine `ssh npu-server.tail9b2a4e.ts.net` (accept host key), then append a **non-Mark** public key to `~/.ssh/authorized_keys`; confirm `systemctl --user list-units 'llm-shop-*'` + `curl :8080/api/status`.
- Re-tag npu-server in Tailscale too (same as Phase 3, at its console). The HTTP service path survives the re-tag regardless; SSH key is maintenance-only. Runbook: [[2026-06-22_npu-server-llm-shop-runbook]].

## Phase 5 — Approve the 2 doc PRs  (colleague · ~3 min · §I)
Both docs-only, CI-green, just need a review approval:
- `aegissystems/vms-connector #1765` (architecture-rationale)
- `aegissystems/kubernetes-deployments #419` (ArgoCD/app-of-apps CLAUDE.md)
Open each → **Files changed → Review → Approve → Merge**. *(actuate_admin #2537 is now conflict-free too, if you want to approve+merge it; actuate-libraries #392 is clean but merge deliberately — its `main` auto-publishes.)*

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
