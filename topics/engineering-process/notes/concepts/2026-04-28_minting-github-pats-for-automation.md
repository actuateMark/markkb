---
title: "Minting GitHub PATs for automation"
type: concept
topic: engineering-process
tags: [github, gh-cli, credentials, secrets, automation, how-to]
created: 2026-04-28
updated: 2026-04-28
author: kb-bot
incoming:
  - topics/engineering-process/notes/syntheses/2026-06-22_offboarding-plan.md
  - topics/personal-laptop/notes/concepts/2026-04-27_handoff-repos-architectural-dashboard.md
  - topics/personal-laptop/notes/concepts/2026-06-22_firebat-operations-runbook.md
  - topics/personal-laptop/notes/syntheses/2026-04-28_long-lived-credentials-on-headless-boxes.md
  - topics/personal-notes/notes/daily/2026-04-28.md
incoming_updated: 2026-06-24
---

# Minting GitHub PATs for automation

Step-by-step for issuing a GitHub Personal Access Token suited to a long-lived automation host (headless box, scheduled job, CI runner). The architectural why lives in [[2026-04-28_long-lived-credentials-on-headless-boxes]] — read that first if "wait, why classic and not fine-grained?" comes up.

## Decision shortcut

| You have… | Mint | Why |
|---|---|---|
| A personal always-on box you fully own (Firebat minipc, home-lab Pi) | **Classic PAT, "No expiration"**, scopes `repo` + `read:org` | One-and-done; no rotation toil; blast-radius matched (already trust the box with all your repos). |
| A shared CI runner with multi-tenancy or a partner-touchable host | Fine-grained PAT, 1y expiry, repo-allowlist | Smaller blast radius justifies rotation calendar reminder. |
| Production automation under an org account | GitHub App + installation token | Auto-rotates, audit trail, can be revoked per-app without touching others. |
| A teammate's laptop | Their own classic PAT under their account | Don't share PATs across humans — non-repudiation breaks. |

This page covers the first row (classic PAT for personal automation). For the others, search `engineering-process` for newer notes.

## Step 1: open the right URL

https://github.com/settings/tokens/new

This is the **classic** tokens page. The fine-grained equivalent is at `/settings/personal-access-tokens/new` — different page, different limits, don't confuse them.

## Step 2: fill the form

| Field | Value |
|---|---|
| **Note** | Identifies which automation surface uses this token. Format: `<host> — <purpose>`, e.g. `mork-firebat minipc — repo dashboard + gh CLI`. Future-you needs to be able to look at the token list and remember what each one is for. |
| **Expiration** | `No expiration`. Click through GitHub's red warning. Yes, it's the right choice — see decision shortcut above. |
| **Scopes** | Check exactly what's needed. See scope table below. |

Common scope combinations:

| Use case | Scopes | Notes |
|---|---|---|
| Read-only automation (dashboard, monitoring, log scraping) | `repo` + `read:org` | `repo` parent box selects all four `repo:*` sub-scopes — that's correct for private-repo read access. |
| Read + write (push, PRs, issue ops) | `repo` + `read:org` + `workflow` | Add `workflow` only if you need to push files under `.github/workflows/`. Without it, GitHub silently rejects pushes touching workflow files. |
| Read-only public repos only | (no scopes — uncheck everything) | Anonymous-equivalent rate limit (60/hr instead of 5000/hr) but no token to leak. Rarely useful. |
| `gh repo delete`, branch protection, etc. | Add `delete_repo`, `admin:org`, etc. case-by-case | Don't add admin scopes "to be safe" — they massively expand blast radius. |

**Skip:** `gist` (unless you actually use gists), `notifications`, `user`, `admin:public_key`. None of these are needed for typical automation.

## Step 3: generate, then immediately save

GitHub shows the token **once**. Closing/refreshing the page loses it forever. Don't navigate away until you've saved it.

The token is a `ghp_…` string, ~40 characters. It's a bearer credential — anyone with the string can act as you (within the scopes you selected) until it's revoked.

## Step 4: save without leaking

The single hardest part. Two failure modes to avoid:

1. **Leaving it in shell history.** Running `echo "ghp_…" > file` puts it in `~/.bash_history`. Fix: use the editor approach — paste inside the editor where shell parsing doesn't apply. Bonus: the keystroke recording isn't a thing.
2. **Leaving it in a git working tree.** Saving to any path under `~/work/<repo>/` or `~/projects/<repo>/` makes the file susceptible to a stray `git add -A`. Fix: save to a dedicated *secrets directory outside any working tree*.

The right pattern for a personal box:

```bash
umask 077 && mkdir -p ~/.config/minipc-secrets && chmod 700 ~/.config/minipc-secrets
umask 077 && touch ~/.config/minipc-secrets/github-pat && chmod 600 ~/.config/minipc-secrets/github-pat && ${EDITOR:-nano} ~/.config/minipc-secrets/github-pat
```

Paste the `ghp_…` value as the only contents (no trailing newline matters; gh handles either). Save and exit.

**Anti-patterns to avoid** (all observed in the wild, including in this very project on 2026-04-28):

- ❌ `cat > ~/.config/.../file <<'EOF'` heredoc — terminator-indentation gotchas; some terminals add leading whitespace on paste, EOF doesn't terminate, shell hangs at `>` prompt.
- ❌ `echo "$TOKEN" > file` in interactive shell — token enters history.
- ❌ `head -c 8 file` to "verify it's the right file" — prints token bytes to your terminal scrollback; if the terminal is recorded (Claude Code, screen sharing, VS Code remote), the bytes leak.

If you need to fingerprint the file *without* exposing contents:

```bash
wc -c < ~/.config/minipc-secrets/github-pat
stat -c %y ~/.config/minipc-secrets/github-pat
sha256sum ~/.config/minipc-secrets/github-pat | cut -c1-12
```

These tell you "this file is 41 bytes, modified 2026-04-28 09:33, content hash starts 8a3f7c1e29bd" — enough to confirm it's the file you just wrote, none of the bytes are the token.

## Step 5: verify the token works (locally)

```bash
GH_TOKEN=$(cat ~/.config/minipc-secrets/github-pat) gh api /user --jq '.login'
```

Should print your GitHub login. Anything else (error, different login) means re-mint.

The `GH_TOKEN=...` prefix scopes the env-var to this single command — `gh` picks it up, the var doesn't persist into your shell. Don't `export GH_TOKEN=…` system-wide; that contaminates every subsequent `gh` command and is one shell-history leak away from the token escaping.

## Step 6: install on the remote

If the token is for a remote box (and you've followed [[2026-04-28_long-lived-credentials-on-headless-boxes]]'s secrets-channel pattern), pipe it via SSH stdin to `gh auth login --with-token`:

```bash
ssh "$TARGET" 'gh auth login --with-token --hostname github.com' < ~/.config/minipc-secrets/github-pat
```

The token never lands on remote disk except inside `~/.config/gh/hosts.yml` (which `gh` writes mode 600). Verify on the remote:

```bash
ssh "$TARGET" 'gh auth status && gh api /user --jq .login'
```

For the [[2026-04-23_firebat-minipc-as-claude-dev-box|Firebat minipc]] specifically, this is automated by `phase-15-secrets.sh` in `aegissystems/actuate-dev-toolkit`.

## Step 7: rotation procedure

Classic PATs with "No expiration" don't need scheduled rotation, but they do need *triggered* rotation when:

- **The token is suspected to have leaked.** If you ever see the value in shell history, a transcript, a screen-share recording, or a chat log — rotate immediately. Even a partial prefix can be a problem.
- **The host is decommissioned.** Revoke the host's token even if the box is going offline; tokens outlive their hosts.
- **The scopes need to change.** GitHub doesn't allow editing scopes on an existing token; mint a new one with the new scopes and revoke the old.

Rotation procedure:

1. Mint the replacement first (Step 1–4 again, same Note + scopes).
2. Save to the same `~/.config/minipc-secrets/<file>` path (overwrite).
3. Push to all hosts using it (`phase-15-secrets.sh` for the minipc; equivalent for other hosts).
4. **Then** revoke the old token at https://github.com/settings/tokens. Order matters — revoking first means a window where the host has no auth.
5. Verify with `gh api /user` on each host.

## Reference: scope cheat sheet

What each scope on the classic-PAT page actually controls (the GitHub UI labels are sometimes confusing):

| Scope | Grants |
|---|---|
| `repo` (parent) | Full read+write on all repos visible to the user (private + public + internal). Selecting it auto-checks `repo:status`, `repo_deployment`, `public_repo`, `repo:invite`, `security_events`. |
| `repo:status` only | Read commit-status checks. Useful if you only want CI-status read access. |
| `public_repo` only | Read+write on public repos only. |
| `read:org` | Read membership in orgs the user belongs to. Needed for `gh repo list <org>` to find private org repos. |
| `workflow` | Push/edit `.github/workflows/*` files. Without it, pushes touching workflow files silently 403. |
| `delete_repo` | Permanently delete repos. Don't grant unless specifically needed. |
| `admin:org` | Full org admin (manage members, settings). Almost never needed for automation. |
| `gist` | Create/read gists. Skip unless you specifically use gist API. |

For typical automation: `repo` + `read:org` is the right minimum. Everything else: justify to yourself why before checking.

## Related

- [[2026-04-28_long-lived-credentials-on-headless-boxes]] — architectural why
- [[2026-04-27_minipc-tooling-improvements]] — surrounding minipc tooling batch
- [[security-hardening-checklist]] — sibling reference for app-level credential handling (not for this scenario but adjacent)
- GitHub docs (canonical): https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
