---
title: "GNOME terminal focus-steal — `focus-new-windows='strict'` fix"
type: concept
topic: personal-laptop
tags: [gnome, x11, focus, terminal, claude-code, ubuntu, regression-prone]
created: 2026-05-22
updated: 2026-05-22
author: kb-bot
incoming:
  - topics/operational-health/notes/concepts/2026-05-22_djangoq-cpu-spike-v8-rollback-verify-scan.md
  - topics/personal-notes/notes/daily/2026-05-22.md
incoming_updated: 2026-05-27
---

# GNOME terminal focus-steal — `focus-new-windows='strict'` fix

## Symptom

gnome-terminal pops to the foreground at random moments, stealing focus from whatever window had it. Most disruptive when:

- Trying to type a `sudo`/`polkit`/lockscreen password — keystrokes land in the terminal instead.
- Mid-paste in another app — focus jumps mid-stroke.
- Reading docs / chat — sudden context switch.

Happens repeatedly while a long-running [[claude-code|Claude Code]] session is open. Apparent trigger: each turn-end emits a notification.

## Root cause

Two ingredients combine:

1. **`org.gnome.desktop.wm.preferences focus-new-windows = 'smart'`** (Ubuntu's default). With `'smart'`, GNOME's WM (mutter) honors a window's _urgent_ / _demands-attention_ hint by raising and focusing it when the WM judges "the user probably wants this." That heuristic mis-fires constantly with terminal notifications.

2. **Claude Code's Stop hook in `~/.claude/settings.json` fires `notify-send` after every turn** (`'Session ready for input'`). The notification path through `notify-send` → notification daemon → gnome-shell ends up flagging gnome-terminal's window as wanting attention, and mutter raises+focuses it.

`focus-mode='click'` and `auto-raise=false` are already correct; they don't help here because the `'smart'` heuristic is what authorizes the raise.

## Fix

```bash
gsettings set org.gnome.desktop.wm.preferences focus-new-windows 'strict'
```

Effect is **immediate** (mutter picks up the change live — no logout/login). With `'strict'`, mutter never auto-focuses on attention hints. Windows that legitimately need attention still light up in the dock/taskbar; they just don't steal keyboard focus.

Verify by triggering an `_NET_WM_STATE_DEMANDS_ATTENTION` event:

```bash
# from another terminal, with a non-terminal window focused:
notify-send -u low -t 3000 'test' 'should NOT raise terminal'
# terminal stays in background, dock indicator may flash — that's fine
```

## Why this regresses

Ubuntu/GNOME desktop updates can reset `org.gnome.desktop.wm.preferences` to factory defaults during major version bumps (24.04 → 24.10, 24.10 → 25.04, etc.). The `'strict'` setting is not part of `~/.config/dconf/user` until set, and even after, a fresh user profile (or aggressive update) can wipe it.

Mark has applied this fix at least twice before (most recent: 2026-05-22). Each regression has been traced to a system update reverting GNOME prefs to default.

## Hardening — survive future resets

Two options for durability:

1. **dconf dump on the laptop-bootstrap inventory.** Add `dconf dump /org/gnome/desktop/wm/preferences/` to the laptop-portability checklist (§10 in [[mark-todos]]) so the value is captured and reapplied during disaster recovery. See [[2026-04-23_firebat-minipc-network-setup]] for inventory pattern.

2. **Skip the Claude Code Stop hook `notify-send` entirely** — drop the line from `~/.claude/settings.json` Stop hooks, or make it conditional on terminal not having focus (`xdotool getactivewindow getwindowname | grep -qv Terminal && notify-send ...`). This eliminates the trigger rather than the symptom. Downside: lose the audible/visual cue when Claude finishes a turn — Mark relies on this when multitasking.

Option 1 is preferred — preserves the notification cue, kills only the focus-steal. Option 2 is the fallback if `'strict'` itself ever regresses without an update.

## Related

- `~/.claude/settings.json` Stop hook — the trigger source
- [[mark-todos]] §10 — Laptop-config portability + disaster recovery (durable-fix candidate)
- [[claude-code|Claude Code]] — the notification source
- GNOME upstream docs: `focus-new-windows` in `org.gnome.desktop.wm.preferences` schema
