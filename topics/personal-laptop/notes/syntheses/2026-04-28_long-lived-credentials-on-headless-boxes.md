---
title: "Long-lived credentials on headless personal boxes"
type: synthesis
topic: personal-laptop
tags: [credentials, secrets, tailscale, github, gh-cli, automation, minipc, security]
created: 2026-04-28
updated: 2026-04-28
author: kb-bot
incoming:
  - home/offboarding/2026-06-22_offboarding-plan.md
  - topics/engineering-process/notes/concepts/2026-04-28_minting-github-pats-for-automation.md
  - topics/personal-laptop/notes/concepts/2026-04-27_handoff-repos-architectural-dashboard.md
  - topics/personal-laptop/notes/concepts/2026-04-28_handoff-repos-dashboard-phase-2-code-health.md
  - topics/personal-laptop/notes/syntheses/2026-04-27_minipc-tooling-improvements.md
  - topics/personal-notes/notes/daily/2026-04-28.md
incoming_updated: 2026-06-25
---

# Long-lived credentials on headless personal boxes

Why every morning the [[2026-04-23_firebat-minipc-as-claude-dev-box|Firebat minipc]] kept demanding two separate browser reauths — Tailscale SSH and `gh` — and how we permanently eliminated both. Closes the gh-auth gate listed in [[2026-04-27_minipc-tooling-improvements]] and unblocks [[2026-04-27_handoff-repos-architectural-dashboard|the §69 /app/repos dashboard]].

## The two daily papercuts

The minipc was set up so that two separate auth surfaces required ongoing human attention:

1. **Tailscale SSH check** — `ssh mork@mork-firebat` would intermittently reject with a `https://login.tailscale.com/a/...` URL needing a browser click. Default check-period is 12h.
2. **`gh` token expiry** — `~/bin/collect-repos.sh` and any `gh` invocation on the box would fail with auth errors. Sometimes daily, sometimes weekly, never predictable.

Each one alone is a 30-second fix. Together they made the minipc feel less like infrastructure and more like a chore. **Infrastructure that demands daily human attention is broken infrastructure.**

## Root causes (not what they look like)

### Tailscale: the `--ssh` flag is the culprit, not Tailscale itself

`phase-05-tailscale.sh` originally brought the box up with `tailscale up --ssh --hostname=mork-firebat --accept-dns=true`. The `--ssh` flag opts in to *Tailscale's* SSH-handling layer — a separate auth path on top of the wireguard tunnel that obeys tailnet ACL rules. When the ACL has `action: "check"` for the relevant `src/dst` pair (which is the default for `autogroup:owner`), every connection from a "stale" client triggers a fresh browser check.

Plain `sshd` on port 22 is unaffected. Tailscale's SSH layer is **opt-in and orthogonal** — disabling it doesn't disable SSH access, it just removes the extra check-mode gating.

For a single-user, always-on personal box, Tailscale SSH adds:
- Audit / session recording — *unused on a personal box*
- ACL-controlled per-user gating — *only one user exists*
- Browser reauth gates — *the entire papercut*

It removes nothing in exchange. **Net liability for this use case.**

### `gh`: OAuth tokens are device-fingerprinted; rsyncing creds across hosts breaks them

The minipc's `gh` token broke because `phase-07-claude-config.sh` line 80 used to rsync `~/.config/gh/` from laptop → minipc. That copies the laptop's OAuth-flow token onto the minipc. Two failure modes:

1. **GitHub fingerprints OAuth tokens** loosely (IP, user-agent, behavior). When the same token appears from two different machines, GitHub may classify it as suspicious and revoke server-side.
2. **Re-auth on the laptop revokes the token globally.** Every time `gh auth login` runs on the laptop (e.g., to get a new scope), the previous token is revoked everywhere. The minipc's copy dies silently.

So even though the laptop never has a problem (it reauths and gets a fresh token), the minipc's copy is collateral damage on an unpredictable cadence.

## The fix pattern (the durable one)

Two mostly-orthogonal changes:

### 1. Tailscale: drop `--ssh`; use plain key-auth over the tailnet

```bash
sudo tailscale up --reset --hostname=mork-firebat --accept-dns=true
```

`--reset` is required when transitioning *off* a non-default flag. Without it, Tailscale errors with "changing settings via 'tailscale up' requires mentioning all non-default flags."

After this, `ssh mork@mork-firebat` is just plain key-based SSH over the tailnet IP. No browser flow. Ever. The laptop's pubkey is already in `~/.ssh/authorized_keys` on the minipc — that's how SSH worked at all when Tailscale's check-mode was satisfied — so dropping the Tailscale layer just exposes the underlying always-working sshd.

Codified in `phase-05-tailscale.sh`'s §4b block: detect `RunSSH: true` in `tailscale debug prefs` (NOT `tailscale status --json` — that doesn't expose `RunSSH`) and force a `tailscale up --reset` to drop it. Connection drops mid-command (we just severed our own session); script swallows the broken-pipe exit and re-verifies in a fresh connection.

**Alternative if you want to keep Tailscale SSH:** edit the tailnet ACL at https://login.tailscale.com/admin/acls and change `"action": "check"` → `"action": "accept"` for the relevant rule. Same effect (no browser reauth), but the policy lives outside the toolkit — partial loss of "all-from-code." Dropped `--ssh` was the cleaner choice for this box.

### 2. `gh`: per-host long-lived classic PAT, installed via a dedicated phase script

Mint a **classic** PAT (NOT fine-grained) at https://github.com/settings/tokens/new with:
- **Expiration: No expiration** (only available on classic; FGPATs cap at 1y)
- **Scopes: `repo`, `read:org`** (minimum for `gh pr list`, `gh repo list <org>`, private-repo cloning)

Save the `ghp_…` value as the only contents of `~/.config/minipc-secrets/github-pat` (mode 600, dir mode 700, gitignored). Install on the remote via:

```bash
ssh "$TARGET" 'gh auth login --with-token --hostname github.com' < ~/.config/minipc-secrets/github-pat
```

This is what `phase-15-secrets.sh` does. The token only ever lands inside `~/.config/gh/hosts.yml` on the remote (which `gh` itself writes mode 600). It's decoupled from any laptop activity — laptop reauths don't revoke it.

**Why classic over fine-grained PAT or GitHub App:**
| Option | Expiry | Per-repo scope | Setup complexity | Verdict |
|---|---|---|---|---|
| Classic PAT, "No expiration" | none | broad (all org repos by default) | one form | ✅ Right for personal admin box |
| Fine-grained PAT | max 1y | yes, per-repo allowlist | one form + repo list | rotation toil ; allowlist drifts from repos-config |
| GitHub App installation token | auto-rotates | yes, fine-grained | App + private key on box | overkill for personal box |

Personal box, blast radius matched. If this minipc gets compromised, it can read all your repos — same as your laptop. The threat model isn't "minimize blast on this token"; it's "minimize ongoing reauth toil." Classic-PAT + no-expiration wins on that axis.

## The secrets-channel pattern (generalises)

`~/.config/minipc-secrets/` (mode 700, gitignored) is a **laptop-local secrets directory** that the toolkit pulls from but never includes in the repo. Any per-host credential the minipc needs follows the same shape:

- One file per secret, raw value as the only content, mode 600
- `phase-15-secrets.sh` reads each file and pushes via SSH stdin to its appropriate `--with-token`-style installer on the remote
- Required secrets fail loudly with a setup-instruction message; optional secrets skip silently
- Re-runnable, idempotent

Currently:
- `github-pat` (required) — classic PAT, scopes `repo` + `read:org`
- `anthropic-api-key` (optional) — for headless `claude -p` runs with budgeted billing

Future fits naturally:
- `aws-access-key` — already handled by Roles Anywhere ([[2026-04-27_iam-rolesanywhere-minipc]]), so unused, but the slot is here
- `smtp-creds` — for daily-summary emails
- `signing-key` — code-signing, package-publishing

The pattern resists creep because each new secret is one file + a few lines of phase-15. No yak-shaving a fancier vault.

## The leak incident and what it taught us (2026-04-28)

While moving the PAT from the GitHub-issued form to its installation, an intermediate version of the file ended up at `/home/mork/work/local_network_scripts/github_pat` — inside the toolkit's git working tree, mode 600 but one `git add -A` away from being committed and pushed to the private (still-public-to-collaborators) `aegissystems/actuate-dev-toolkit` repo. The first eight characters of the token also surfaced in a routine `head -c 50` debug command in conversation transcripts.

We rotated the token immediately (revoked old, minted new, redeployed via phase-15). But two systemic gaps surfaced:

1. **No defensive gitignore patterns for secret-shaped filenames.** A blank-slate `.gitignore` will happily track `github_pat`, `secrets.txt`, `.env`, etc. Added a deny-list of common fumble-filenames (`github_pat`, `*.token`, `*.pem`, `.env*`, `secrets.{txt,yaml,json}`, etc.). **Important lesson:** initially used broad globs (`*secret*`, `*token*`) which silently ignored the legitimate `phase-15-secrets.sh` script itself. Narrowed to specific patterns. **Verify gitignore additions against `git check-ignore -v $(git ls-files)`** before trusting them.

2. **No pre-commit secret-scanning hook.** Filename-based gitignore is necessary-but-not-sufficient — someone can paste a token into `notes.md` and that won't trigger any rule. Right defense is a pre-commit hook running `gitleaks` or a regex scan for `ghp_[A-Za-z0-9]{36,}`, `sk_live_…`, `xoxb-…`, etc. against the staged diff. **Open follow-up.**

3. **Verify file contents aren't echoed to stdout when poking at credentials.** `head -c 50 file` to confirm "is this the file I think it is?" prints raw token bytes. Use `wc -c file && stat -c %y file` (size + mtime) to fingerprint without exposing content. Or `sha256sum file | cut -c1-12` for a content-tied hash with no risk of leaking the secret itself.

The blast radius for the leaked-prefix-in-transcript was limited (we rotated within ~5 min, and an 8-char prefix isn't enough to use the token alone), but the pattern of "fingerprint a file by sampling its contents" needs to die wherever credentials are involved.

## Verifying the fix is durable

Run this from the laptop on any morning. If it succeeds without any browser flow, the fix held:

```bash
ssh mork@mork-firebat 'tailscale debug prefs | grep -E "RunSSH|Hostname"; gh api /user --jq .login'
```

Expected output:
```
"RunSSH": false,
"Hostname": "mork-firebat",
actuateMark
```

If `RunSSH` ever flips back to `true` (e.g., re-running an old version of phase-05), `phase-05-tailscale.sh` §4b will detect and drop it idempotently. If the gh token ever stops working, `phase-15-secrets.sh` rebuilds the auth from `~/.config/minipc-secrets/github-pat` — no need to reauth on the laptop.

## Files inventory (this batch)

In `aegissystems/actuate-dev-toolkit`:
- `phase-05-tailscale.sh` — drop `--ssh` from up; add §4b (detect+drop existing `--ssh` advertisement); fix `^10\.` regex bug to `^100\.` (Tailscale CGNAT range starts at 100., not 10.)
- `phase-07-claude-config.sh` — remove `.config/gh` from dotconfigs rsync (was the recurring source of clobbering)
- `phase-15-secrets.sh` — NEW, installs PAT and any optional API keys from `~/.config/minipc-secrets/`
- `provision-host.sh` — add `15:phase-15-secrets.sh` to the orchestrator's phase list
- `.gitignore` — defensive deny-list for secret-shaped filenames
- `README.md` — new "Access pathways" + "Secrets" sections

On the laptop (not in repo):
- `~/.config/minipc-secrets/github-pat` (mode 600) — the PAT itself

## Related

- [[2026-04-27_minipc-tooling-improvements]] — the 2026-04-27 batch this closes follow-ups for
- [[2026-04-27_handoff-repos-architectural-dashboard]] — the workstream this unblocks (both gates now closed)
- [[2026-04-23_firebat-minipc-as-claude-dev-box]] — the box this all runs on
- [[2026-04-27_iam-rolesanywhere-minipc]] — sibling auth surface (AWS), already long-lived; secrets-channel pattern handles non-AWS
- [[2026-04-28_minting-github-pats-for-automation]] — step-by-step how-to for the PAT minting itself
- `firebat-minipc-access` — Claude session-memory file for access creds + URLs (updated 2026-04-28 to add LAN/mDNS as the third pathway). Lives at `~/.claude/projects/-home-mork-work-local-network-scripts/memory/firebat-minipc-access.md`, not in the KB.
