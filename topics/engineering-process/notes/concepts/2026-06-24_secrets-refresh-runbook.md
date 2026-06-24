---
type: concept
topic: engineering-process
tags: [secrets, credentials, runbook, offboarding, rotation]
created: 2026-06-24
updated: 2026-06-24
author: kb-bot
---

# Consolidated secrets / credentials refresh runbook

One place listing **every credential in Mark's automation ecosystem** — where it lives, who owns it, how to refresh/rotate it, and how to verify. Written for a successor operating the [[2026-06-22_firebat-operations-runbook|Firebat]] box after Mark's departure (last day 2026-06-26). Canonical cred source is `actuate-dev-toolkit/CLAUDE.md` ("Secrets / credentials + recovery"). Re-home work is tracked in [[2026-06-24_offboarding-asks]] §A/§B and `2026-06-22_offboarding-plan` (WS-A / ENG-376).

**Never print secret values.** All Firebat timers are pure-Python / pure-bash, zero-token by design — there is **no Anthropic dependency** in the timer fleet.

## At-a-glance ownership map

| Cred | Owner today | Status for offboarding | Re-home action |
|---|---|---|---|
| AWS (Roles Anywhere) | **Team** (host machine cert) | ✅ Survives departure — no action | none |
| GitHub `gh` | Personal `actuateMark` | ⚠ Re-home (§A/§B) | swap to org PAT / machine account |
| New Relic | Personal `mark@actuate.ai` NRAK | ⚠ Re-home + **rotate** (leaked key purged 2026-06-22) | mint team/service User key |
| Atlassian | Personal `mark@actuate.ai` | ⚠ Re-home (§A/§B) | re-issue under service account |
| Tailscale | User-owned `mark@` (expiry 2026-10-20) | ⚠ Re-tag to `tag:server` | tagged auth key at box console (§C) |
| CodeArtifact token | Derived from AWS (ephemeral, ~12h) | ✅ Follows AWS — no separate secret | re-fetch via `get-authorization-token` |
| Anthropic API key | Personal (laptop / ad-hoc only) | ⚠ Decommission personal key | NOT a Firebat dependency |
| Slack webhooks | n/a for personal automation | ✅ None in timer fleet | nothing to rotate |

Verify all five identity creds at once with `~/bin/firebat-identity-verify.py` (read-only; never prints secrets; exit 0 = all PASS). The 3 re-home WARNs (GitHub / NR / Atlassian) flip to PASS as each swap completes. Pre-re-home baseline: `~/identity-baseline-pre-rehome.json`.

---

## 1. AWS — IAM Roles Anywhere (team-owned, survives departure)

| Field | Value |
|---|---|
| Used by | `run-dashboard-check`, `billing-reconcile-check`, `ecr-lifecycle-audit`, `morning-prep` |
| Secret path (Firebat) | `~/.config/aws-rolesanywhere/mork-firebat.crt` + `mork-firebat.key` (host X.509 cert) |
| Role | `dashboard-check-rolesanywhere` · trust-anchor `328fdc80-…` · account `388576304176` |
| Profile | `AWS_PROFILE=dashboard-check` |
| Owner | **Team-owned machine identity.** Named "mork-firebat" but it is a host cert, NOT Mark's SSO — it stays after Mark leaves. |

**How to refresh / reissue** (only when the cert is near expiry):
1. Check expiry: `openssl x509 -in ~/.config/aws-rolesanywhere/mork-firebat.crt -noout -dates`
2. Reissue the cert via the IAM → Roles Anywhere console against the same trust anchor (full reproducible procedure in [[2026-04-27_iam-rolesanywhere-minipc]]).
3. Replace **both** files (`.crt` and `.key`) on the box, mode 600.
4. **Verify:** `aws sts get-caller-identity --profile dashboard-check` → returns the dashboard-check role ARN.

Full rebuild runbook (cert gen, trust anchor + profile creation, signing-helper install): [[2026-04-27_iam-rolesanywhere-minipc]].

---

## 2. GitHub — `gh` PAT (personal → re-home)

| Field | Value |
|---|---|
| Used by | `repo-scan`, `git-fetch-major-repos`, `pr-review-digest`, KB bare-repo push |
| Secret path (Firebat) | `~/.config/gh/hosts.yml` (the `oauth_token:` field; gh credential helper injects it for HTTPS git) |
| Owner | **PERSONAL `actuateMark`** — must re-home to an org machine account / org PAT |

**How to refresh / re-home** (§A/§B — after the team picks the identity):
1. Mint an org PAT (scopes `repo`, `read:org`). Prior art: [[2026-04-28_minting-github-pats-for-automation]].
2. On the box, the clean path:
   - `gh auth logout --hostname github.com`
   - `gh auth login --hostname github.com --git-protocol https` (paste the org token)
   - `gh auth setup-git`
   - (Or simply replace the `oauth_token:` value in `~/.config/gh/hosts.yml`.)
3. **Verify:** `gh auth status` and `gh api repos/aegissystems/vms-connector --jq .full_name`.

---

## 3. New Relic — NRAK User key (personal → re-home + rotate)

| Field | Value |
|---|---|
| Used by | `run-dashboard-check`, autopatrol checks (direct NerdGraph — **not** the NR MCP) |
| Secret paths (Firebat) | `~/.config/newrelic/key` (NRAK) + `~/.config/newrelic/account_id` (`3421145`) |
| Owner | **PERSONAL `mark@actuate.ai` NRAK** — pending WS-A rotation |

> ⚠ A leaked NR key was purged from KB git history on 2026-06-22 — this key **must be rotated**, not just re-homed.
> Note: `~/.config/nr/api-key` in older notes is the **laptop** path; the Firebat path is `~/.config/newrelic/key`.

**How to refresh / re-home:**
1. Mint a new User key in the NR UI (ideally under a team / service user, not a person).
2. On the box: `printf '%s' '<new NRAK>' > ~/.config/newrelic/key && chmod 600 ~/.config/newrelic/key`
3. Revoke the old key in the NR UI.
4. **Verify:** `~/bin/firebat-identity-verify.py` — the New Relic WARN flips to PASS; or `--run-timers` to confirm `run-dashboard-check` exits 0.

---

## 4. Atlassian — API token (personal → re-home)

| Field | Value |
|---|---|
| Used by | `jira-sync` |
| Secret path (Firebat) | `~/.config/atlassian/api-token` — JSON `{"email":…, "token":…, "site":…}` |
| Owner | **PERSONAL `mark@actuate.ai`** — re-issue under a service account |

**How to refresh / re-home:**
1. Create a new token at id.atlassian.com → Security → API tokens.
2. Edit the JSON file on the box:
   `{"email":"<service-email>","token":"<new>","site":"https://actuate-team.atlassian.net"}`
3. `chmod 600 ~/.config/atlassian/api-token`
4. **Verify:** `~/bin/jira-sync.sh --force --dry-run` (or `firebat-identity-verify.py` → Atlassian WARN flips to PASS).

---

## 5. Tailscale — node identity (user-owned → re-tag)

| Field | Value |
|---|---|
| Used by | network reachability of **all** the above (timers reach AWS/NR/GitHub/Atlassian over the tailnet) |
| Secret location | node identity in `tailscaled` state (no file you edit) |
| Owner | **USER-owned by `mark@`** · key expiry **2026-10-20** — re-tag to `tag:server` |

**How to re-home** (§C — needs a tailnet admin):
1. Admin: ensure `tag:server` exists in `tagOwners` + ACL grants team SSH/HTTP to `tag:server`; mint a **reusable, tagged** auth key.
2. **At the box console** (firebat, then npu-server — ⚠ NOT over SSH; re-auth can drop the session and the unattended box goes dark):
   `sudo tailscale up --authkey=tskey-… --advertise-tags=tag:server`
3. **No-admin stopgap:** a staying teammate runs `sudo tailscale logout && sudo tailscale up` at the console and logs in under their own account (node becomes theirs; tags are cleaner but this unblocks with zero admin).
4. **Verify:** `~/bin/firebat-identity-verify.py` shows `tailscale.identity` tagged.

---

## 6. AWS CodeArtifact token (derived from AWS — no separate secret)

| Field | Value |
|---|---|
| Used by | `uv` / `pip` auth for private **actuate** Python packages (local dev + `billing-reconcile` `uv sync`) |
| Secret | **None stored** — an ephemeral (~12h) token fetched on demand from AWS, so it follows the AWS Roles Anywhere identity |
| Registry | `actuate-388576304176.d.codeartifact.us-west-2.amazonaws.com/pypi/actuate/simple/` · domain `actuate`, owner `388576304176`, region `us-west-2` |

**How to obtain / refresh** (re-run whenever the token expires — full context in [[2026-05-20_actuate-admin-local-bringup]]):
```
export UV_INDEX_PRIVATE_REGISTRY_USERNAME=aws
export UV_INDEX_PRIVATE_REGISTRY_PASSWORD=$(AWS_PROFILE=prod aws codeartifact get-authorization-token \
  --domain actuate --domain-owner 388576304176 \
  --query authorizationToken --output text)
uv sync
```
On Firebat, swap `AWS_PROFILE=prod` for `AWS_PROFILE=dashboard-check` (the Roles-Anywhere profile). Because the token is derived from the AWS identity, **rotating/refreshing AWS (§1) is the only durable action** — there is nothing personal to re-home here. Dev package versions (e.g. `2.0.5.dev3`) publish here automatically on feature branches; stable on merge-to-main.

---

## 7. Anthropic API key (laptop / ad-hoc only — NOT a Firebat dependency)

| Field | Value |
|---|---|
| Used by | Optional ad-hoc headless `claude -p` runs only |
| Secret path | `~/.config/minipc-secrets/anthropic-api-key` (laptop, optional) |
| Owner | Personal — decommission on departure (§H) |

**Important:** This key is **not part of the Firebat timer fleet**. All ~14 timers are pure-Python/bash and run zero-token by design (hard rule: never run `claude -p` on a cron on this box — OAuth-gated MCP and permission gates don't survive headless). Offboarding action is simply to **decommission the personal key** (§H step 3); no firebat re-home needed.

---

## 8. Slack webhooks (none in personal automation)

There are **no Slack webhooks in Mark's automation timers.** All timer outputs land in local sinks (`~/Documents/worklog/dashboard/sink/observations.jsonl`) and the Caddy dashboard at `http://mork-firebat/` — the fleet is webhook-free by design. (The `aegissystems/sns_to_slack` Lambda is separate org infrastructure, not a personal-automation credential.) Nothing to rotate; on departure just decommission any personal webhook URLs per §H step 3.

---

## Provisioning-time secret handling

Secrets are read from `~/.config/minipc-secrets/` on the **laptop** (mode 700, gitignored) and pushed to the box by `phase-15-secrets.sh`. To save a token without it landing in shell history:
```
umask 077 && mkdir -p ~/.config/minipc-secrets && chmod 700 ~/.config/minipc-secrets
umask 077 && touch ~/.config/minipc-secrets/<file> && chmod 600 ~/.config/minipc-secrets/<file> && ${EDITOR:-nano} ~/.config/minipc-secrets/<file>
```

## Verification harness — single source of truth

`~/bin/firebat-identity-verify.py` (source: `actuate-dev-toolkit/files/`) checks all 5 identities + every timer's last-run result; prints PASS/WARN/FAIL; **never prints secret values**; exit 0 = all PASS, 1 = any FAIL.
```
~/bin/firebat-identity-verify.py                     # read-only; compare to baseline
~/bin/firebat-identity-verify.py --baseline out.json # capture current state to JSON
~/bin/firebat-identity-verify.py --run-timers        # fire each cred-dependent timer, confirm exit 0
```
`kb-lint` exit 2 is a normal findings signal, not a failure.

## Related

- [[2026-06-22_firebat-operations-runbook]] — the deep team-handoff operations runbook (read alongside this).
- [[2026-06-24_offboarding-asks]] — §A automation-identity decision, §B GitHub/NR/Atlassian re-home steps, §C Tailscale re-tag, §H Friday verify + decommission.
- [[2026-04-27_iam-rolesanywhere-minipc]] — full AWS Roles Anywhere rebuild/setup procedure.
- [[2026-04-28_minting-github-pats-for-automation]] — GitHub PAT minting prior art.
- [[2026-05-20_actuate-admin-local-bringup]] — CodeArtifact token fetch for `uv`/`pip`.
- `aegissystems/actuate-dev-toolkit` (`/home/mork/work/local_network_scripts`) — `CLAUDE.md` cred table + deployed script/unit sources (canonical source).
