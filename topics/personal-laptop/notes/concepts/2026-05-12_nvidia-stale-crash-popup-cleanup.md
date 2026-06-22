---
title: "NVIDIA stale apport crash popup cleanup (2026-05-12)"
type: concept
topic: personal-laptop
tags: [nvidia, gpu, ubuntu, apport, kernel-modules, cleanup]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
incoming:
  - topics/personal-laptop/notes/concepts/2026-05-12_nvidia-suspend-hooks-disabled.md
  - topics/personal-notes/notes/daily/2026-05-12.md
incoming_updated: 2026-05-27
---

Boot-time "Ubuntu has experienced an internal error" popup naming `nvidia-580` traced to a stale apport crash file referencing a no-longer-running kernel. Driver was healthy throughout; only the popup needed clearing. Also drained residual `rc`-state packages left over from the [[2026-04-17_nvidia-565-server-install-failure]] incident that had survived earlier cleanup passes.

## Symptom

After login on 2026-05-12, GNOME displayed the apport popup: "Ubuntu has experienced an internal error" referencing `nvidia-580`. No actual driver malfunction — `nvidia-smi` succeeded, all kernel modules loaded, current boot's journal had zero NVIDIA errors.

## Diagnosis

- Crash file: `/var/crash/linux-modules-nvidia-580-6.17.0-22-generic.0.crash`
- Crash referenced kernel `6.17.0-22-generic`; system was booted into `6.17.0-23-generic`
- Apport replays unread crash reports at login until the file is removed — the popup was historical, not current
- Bonus residue: four `nvidia-565-server` packages still in `rc` state, plus two stale `linux-*-nvidia-580-*` kernel-module packages for retired kernels (`-20`, `-22`)

The current driver state was clean: `nvidia-driver-580-open` 580.142, all modules (`nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`) loaded, GPU reporting normally.

## Resolution

Two-step cleanup:

```bash
# 1. Remove stale apport crash files
sudo rm /var/crash/linux-modules-nvidia-580-6.17.0-22-generic.0.crash
sudo rm /var/crash/_usr_bin_gnome-shell.1000.crash

# 2. Purge residual nvidia packages from the April 565-server incident +
#    leftover kernel-module packages for retired kernels
sudo dpkg --purge libnvidia-compute-565-server nvidia-compute-utils-565-server
sudo dpkg --purge nvidia-dkms-565-server nvidia-kernel-common-565-server \
    linux-modules-nvidia-580-open-6.17.0-20-generic \
    linux-objects-nvidia-580-6.17.0-22-generic
```

## Verification

- `/var/crash/` empty
- `dpkg -l | grep -E '565-server|^rc.*nvidia'` returns nothing
- `nvidia-smi`: RTX 500 Ada, driver 580.142 — unchanged, still working
- Loaded modules unchanged: `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`

## Paste Gotcha

The original cleanup command was a multi-line paste:

```
sudo dpkg --purge libnvidia-compute-565-server nvidia-compute-utils-565-server
   nvidia-dkms-565-server nvidia-kernel-common-565-server
```

Indentation on the wrapped line caused the terminal to treat it as two separate commands. The first ran fine; the second (`nvidia-dkms-565-server nvidia-kernel-common-565-server`) ran without `sudo dpkg --purge` in front and silently no-op'd. Verification after each cleanup step catches this — `dpkg -l | grep '^rc'` is the canonical check.

For shell snippets that exceed one terminal width, prefer either a single long line or an explicit `&&` chain rather than relying on indented continuation lines that paste-style editors may mangle. Avoid `\` line continuations entirely (see [[shell-snippet-format]]).

## Takeaway

When a crash popup names a kernel that isn't the one running, the underlying issue is almost always already fixed by a kernel upgrade — apport is just replaying history. `ls /var/crash/` + `uname -r` is a two-command diagnosis. Pair with `dpkg -l | grep '^rc'` to catch residual-config zombies from earlier failed transactions, which is what closes the loop on incidents like [[2026-04-17_nvidia-565-server-install-failure]].
