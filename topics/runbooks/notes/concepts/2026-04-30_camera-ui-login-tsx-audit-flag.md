---
title: "Runbook: Camera-ui Login.tsx audit-flag (recurring uncommitted change)"
type: concept
topic: runbooks
tags: [runbook, camera-ui, git, hygiene, audit-flag, process]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-30.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/runbooks/_backlog.md
  - topics/runbooks/_summary.md
incoming_updated: 2026-05-01
---

# Camera-ui `Login.tsx` audit-flag

## When this applies

The morning ritual's branch survey reports `camera-ui` on `main` with uncommitted modifications to `src/Components/pages/Login.tsx`. This has been recurring for 5+ days and gets flagged every morning as a surface item, but never gets resolved because nobody decides what the diff is *for*. This runbook is the decision tree to retire the noise.

## Symptoms

```
=== camera-ui ===
main
 M src/Components/pages/Login.tsx
```

The file shows up as modified on `main` (working tree dirty) without an associated branch or PR. No recent intent in the local commit history. No one has touched it intentionally in days, but `git status` keeps reporting it.

## Diagnose

**1. Inspect the diff and capture intent (if any):**

```bash
cd /home/mork/work/camera-ui

# What changed?
git diff src/Components/pages/Login.tsx

# When did it diverge? (mtime is unreliable for git; use reflog + diff)
git log --oneline -5 -- src/Components/pages/Login.tsx
git stash list 2>&1 | head -5

# Is there a related WIP branch elsewhere?
git branch -a --contains $(git hash-object src/Components/pages/Login.tsx) 2>&1 | head -10
```

**2. Decide the bucket** by the diff's nature:

| Diff content | Bucket |
|---|---|
| Active feature work (new logic, wired-up components) | Branch & PR |
| Debug / console.log / temporary `any` casts / commented blocks | Discard |
| Local dev override (e.g. hardcoded URL pointing at a sibling service) | Stash + document |
| Real bug fix touching < 20 lines | Branch & PR |
| Generated / auto-formatted churn (whitespace, import order) | Discard or align tooling |

If the diff is unrecognisable — that itself is a finding. Re-derive the original intent from the file's recent PR history (`gh pr list --state all --search "Login.tsx"`); if no recent PR mentions it, it's almost certainly residue from an aborted attempt.

## Fix

Pick exactly one of the three paths based on the bucket above. **Don't leave it dirty for one more day.**

**Path A — Branch & PR (active intent):**

```bash
cd /home/mork/work/camera-ui
git checkout -b fix/login-tsx-<short-slug>
git add src/Components/pages/Login.tsx
git commit -m "fix(login): <one-line WHY>"
git push -u origin HEAD
gh pr create --fill --base main --draft  # draft until tested in browser
```

**Path B — Discard (no intent / debug residue):**

```bash
cd /home/mork/work/camera-ui
git diff src/Components/pages/Login.tsx > /tmp/login-tsx-discard-$(date +%Y%m%d).diff  # paranoia keeper
git checkout -- src/Components/pages/Login.tsx
```

The `/tmp` keeper expires on next reboot — that's intentional. If the diff was important you'd remember.

**Path C — Stash + document (local dev override):**

```bash
cd /home/mork/work/camera-ui
git stash push -m "camera-ui Login.tsx: local dev override <reason>" -- src/Components/pages/Login.tsx
git stash list  # capture stash@{N}
```

Then add a one-line entry to `topics/personal-laptop/notes/concepts/dev-stash-index.md` (create if missing) describing the stash purpose. Without that index the stash will rot.

## Verify

```bash
cd /home/mork/work/camera-ui
git status --short  # expect: nothing under src/Components/pages/Login.tsx
git branch --show-current  # depends on path: still 'main' for B, branch name for A, 'main' for C
```

Tomorrow morning's ritual should no longer flag this surface.

## Prevent

- **Daily ritual rule:** any uncommitted change on `main` that's >7 days old gets surfaced as a Step 5 interview pick (not a free-floating Surface line). Forces a decision.
- **Stash hygiene:** keep `topics/personal-laptop/notes/concepts/dev-stash-index.md` current — every Path-C stash without an index entry is a future audit-flag in waiting.
- **Tool guard:** consider a pre-commit / pre-push hook on `camera-ui` that warns when `main` has uncommitted changes older than N days. Not blocking — just a heads-up.

## Cross-refs

- [[skill-daily-scope]] Step 3 — where the audit-flag surfaces today
- [[runbooks/_summary|Runbooks]] — sibling process runbooks
- mark-todos `## Today's Scope` — recurring surface entry that this runbook retires
