---
title: "Task: switch firebat KB sync from Obsidian Sync → git-pull from aegissystems/actuate-kb"
type: concept
topic: offboarding
tags: [offboarding, firebat, kb, obsidian, git-sync, task]
created: 2026-06-24
updated: 2026-06-24
author: kb-bot
---

# Task — firebat KB auto-sync from the org repo

## STATUS — ✅ CONFIGURED & LIVE (2026-06-24)
Done on firebat: vault `~/Documents/worklog/work/knowledgebase` converted to a **git checkout of `aegissystems/actuate-kb`** (HTTPS via gh creds); **`kb-org-sync.timer`** runs every 30 min — `git pull --rebase --autostash` then commit + push local relink/enrichment back (so firebat's backlink-frontmatter flows to the org; **bidirectional, org = hub**). Both directions validated (pull "up to date"; push dry-run "everything up-to-date"). Vault backed up (`~/kb-vault-backup-pre-gitsync-*.tar.gz`). Timer registered in `firebat-identity-verify.py`. Scripts canonical in `actuate-dev-toolkit/files/kb-org-sync.*`. **Obsidian Sync** (Mark's account) is now redundant and stops harmlessly when the account ends — git is the durable path. **UPDATE 2026-06-24: Obsidian Sync DISABLED on firebat** (removed `sync` from the container's core-plugins.json + restarted; CLI/relink unaffected, backup saved). firebat is now solely git-synced — no live dependency on Mark's Obsidian account.

> **Why (offboarding gap):** firebat's KB vault is currently kept current by **Obsidian Sync tied to Mark's personal Obsidian account** — *not* git. When that account ends, **firebat's KB freezes** (relink/lint/Quartz keep running but on stale content). The canonical source is now **`aegissystems/actuate-kb`** (git). Switch firebat to pull from it, removing the personal-account dependency. Ref: the Obsidian-Git folder-sync approach — https://forum.obsidian.md/t/easy-git-plugin-sync-individual-folders-from-github-repos-to-and-from-your-vault/114501

## Current plumbing (verified 2026-06-24)
- **Vault:** `~/Documents/worklog/work/knowledgebase` (1096 md, 16M) — **NOT a git checkout** (no `.git`). `~/Documents/worklog/knowledgebase` is a symlink to it.
- **Content path:** **Obsidian Sync** (Mark's account) — the scripts explicitly guard against "Obsidian Sync writing concurrently." Obsidian runs **containerized** (linuxserver-style, `/config`), vault `work`.
- **Bare repo** `~/git/knowledgebase.git` — laptop *backup* push target; **no remotes, no post-receive hook** (not wired to the vault).
- **Consumers of the vault dir:** `kb-relink`, `kb-lint`, `kb-incoming-refresh` (read `KB_ROOT=~/.../work/knowledgebase`), `rebuild-quartz` (renders to `/app/kb`).
- **Auth:** firebat `gh` = `actuateMark` (org access). **Git over HTTPS works** (gh credential helper); git-over-SSH fails (github host key not trusted) — use HTTPS / `gh auth setup-git`. Durable once §A GitHub identity is re-homed.

## Target
firebat pulls `aegissystems/actuate-kb` into the vault on a timer; git is the **sole writer**; Obsidian Sync (Mark's account) is **disabled** for this vault.

## Approach A — systemd git-pull *(RECOMMENDED — firebat-native, matches the tier-1 pattern)*
1. **Auth:** on firebat, `gh auth setup-git` (HTTPS via gh token) — or once §A lands, the org identity. Confirm `git ls-remote https://github.com/aegissystems/actuate-kb.git` works.
2. **Disable Obsidian Sync** for this vault on firebat (remove the Mark-account dependency) so git owns the content.
3. **Make the vault a git checkout** (do at the box — Obsidian is open on it): back up the dir first; `git init`, `git remote add origin https://github.com/aegissystems/actuate-kb.git`, `git fetch`, `git reset --hard origin/master`. (Vault content already == org content, so reset should be clean; the backup covers any local-only drift.)
4. **`kb-org-sync` script + timer** (source in `actuate-dev-toolkit/files/`, deploy via phase-13): `git -C <vault> fetch --quiet && git -C <vault> reset --hard origin/master` (or `pull --ff-only`), idempotent, logs to `~/.local/state/claude-jobs/`, every ~15–30 min. Add to the `firebat-identity-verify.py` timer list.
5. **Verify:** relink/lint/incoming/Quartz still operate on the dir; Obsidian still opens it; push something to `actuate-kb` and confirm it lands on firebat within one timer cycle.

⚠ Gotchas: (a) `reset --hard` discards local-only changes — but firebat's relink/lint *write* to the vault; either let those changes be overwritten (they're regenerable) **or** have firebat commit+push its relink output back to the org (bi-directional — more complex; start with pull-only and let the org be canonical). (b) Do at the box: Obsidian + container are live. (c) Coordinate with the Obsidian-Sync cutover.

## Approach B — Obsidian Git community plugin *(the forum link's method)*
Install the **Obsidian Git** plugin into firebat's Obsidian, configure auto-pull from `actuate-kb`. Keeps Obsidian-managed; **fiddly in a containerized headless Obsidian** (plugin install + per-vault config inside `/config`). Better suited to *interactive/laptop* vaults than firebat's headless box. Use A for firebat; B is the pattern for anyone running the KB in a desktop Obsidian.

## When / dependencies
- Best done **at the office** alongside the WS-A firebat work (touches the live vault + container; pairs with the GitHub-identity re-home that makes the pull auth durable).
- The relink/lint *write-back* question (pull-only vs bi-directional) is the one design decision to settle — recommend **pull-only, org canonical** for simplicity; relink/lint output then lives in whatever pushes to the org (the laptop today, or a firebat commit step later).

## Related
- [[2026-06-22_manual-action-checklist]] · [[2026-06-22_firebat-operations-runbook]] · [[2026-06-22_offboarding-plan]] (WS-A)
