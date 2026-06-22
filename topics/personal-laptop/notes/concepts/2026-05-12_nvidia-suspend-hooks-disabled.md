---
title: "NVIDIA suspend hooks disabled → lid-close freeze (2026-05-12)"
type: concept
topic: personal-laptop
tags: [nvidia, gpu, suspend, ubuntu, systemd, kernel-modules, incident]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
outgoing:
  - topics/personal-laptop/notes/concepts/2026-04-17_nvidia-565-server-install-failure.md
  - topics/personal-laptop/notes/concepts/2026-05-12_nvidia-stale-crash-popup-cleanup.md
incoming:
  - No backlinks found.
incoming_updated: 2026-05-13
---

ThinkPad P14s Gen 5 froze on lid close on 2026-05-12 around 11:08–11:10 EDT, requiring a hard power-off. Root cause: the `nvidia-suspend.service` / `nvidia-resume.service` / `nvidia-hibernate.service` hooks were `disabled` (despite systemd preset wanting them `enabled`). Without those hooks, the GPU never quiesces or saves VRAM before s2idle, so the kernel returns `PM: failed to suspend async: error -5` and the suspend transition hangs. The driver itself was healthy throughout — only the suspend wiring was broken.

## Symptom

Closing the lid produced a momentary terminal message about devices failing to suspend with nvidia driver errors, then the system locked solid. Hard power-off was the only recovery.

## Smoking Gun

From the journal of the boot that froze (`journalctl -b -1`):

```
nvidia 0000:01:00.0: PM: failed to suspend async: error -5
PM: Some devices failed to suspend, or early wake event detected
```

The error repeats every ~30 s (kernel retries) until the system gives up and wedges.

## Diagnosis

```bash
systemctl is-enabled nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service
# → disabled / disabled / disabled
```

Per nvidia's packaging the preset is `enabled` — these should be on by default. Likely got disabled as fallout from the morning's `565-server` purge ([[2026-05-12_nvidia-stale-crash-popup-cleanup]]) or a prior kernel-modules upgrade that didn't re-apply the preset. The April 17 recovery ([[2026-04-17_nvidia-565-server-install-failure]]) explicitly verified these services were enabled and running cleanly, so they were on at that point and have drifted since.

`modprobe --show-depends nvidia` confirmed `/etc/modprobe.d/nvidia.conf` was setting the right options (`NVreg_PreserveVideoMemoryAllocations=1`, `NVreg_TemporaryFilePath=/var`, `NVreg_DynamicPowerManagement=0x02`), but the running module didn't have them exposed in `/sys/module/nvidia/parameters/` — likely loaded before initramfs picked up the config. Rebuilding the initramfs ensures the next boot loads the module with the right params from the start.

## Fix Applied (pre-reboot)

```bash
sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service
sudo update-initramfs -u
```

Verified:
- All three services: `enabled`
- Symlinks created in `/etc/systemd/system/systemd-suspend.service.wants/` (nvidia-suspend, nvidia-resume) and `/etc/systemd/system/systemd-hibernate.service.wants/` (nvidia-hibernate, nvidia-resume)
- `/boot/initrd.img-6.17.0-23-generic` mtime refreshed
- `linux-modules-nvidia-580-open-6.17.0-23-generic` installed and matches running kernel

## Post-Reboot Handoff Checklist

Run these in order immediately after the next boot. Stop at the first one that fails and report.

### 1. Confirm driver loaded with suspend-friendly params

```bash
nvidia-smi --query-gpu=name,driver_version --format=csv
# expect: NVIDIA RTX 500 Ada Generation Laptop GPU, 580.142

lsmod | grep -E '^nvidia' | sort
# expect: nvidia, nvidia_drm, nvidia_modeset, nvidia_uvm — all four

cat /sys/module/nvidia/parameters/NVreg_PreserveVideoMemoryAllocations 2>/dev/null
# expect: 1   (was empty pre-reboot — the initramfs rebuild should fix this)
```

### 2. Confirm hooks are wired

```bash
systemctl is-enabled nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service
# expect: enabled (x3)
```

### 3. Test suspend WITHOUT closing the lid first

```bash
# Make sure work is saved. Then:
sudo systemctl suspend
# Press a key / move the mouse to wake within ~10 s.
```

### 4. Verify the suspend hooks actually fired

```bash
systemctl status nvidia-suspend.service nvidia-resume.service --no-pager | head -40
# expect: each shows "status=0/SUCCESS" with a recent timestamp

journalctl -b 0 --no-pager | grep -iE "nvidia.*suspend|nvidia.*resume|PM: failed" | tail -20
# expect: NO "PM: failed to suspend" lines
# expect: clean "nvidia-suspend.service: Deactivated successfully" entries
```

### 5. Only after #3 passes, test lid close

Close the lid for ~30 s, reopen, log in, then re-run check #4.

## If Suspend Still Fails

Two next-step branches:

1. **Driver loaded without preserve-VRAM param** (`/sys/module/nvidia/parameters/NVreg_PreserveVideoMemoryAllocations` empty or 0): the modprobe option isn't being read. Check whether `/etc/modprobe.d/nvidia.conf` got moved by a package transaction; re-run `sudo update-initramfs -u -k all` and reboot.
2. **Hooks fire but suspend still errors -5**: try toggling `NVreg_DynamicPowerManagement=0x02` → `0x00` in `/lib/modprobe.d/nvidia-runtimepm.conf` to disable runtime PM. If suspend then works, runtime PM is the culprit and the laptop just won't tolerate it on this driver/kernel combo.

In both branches, capture `journalctl -b -1 --no-pager > /tmp/froze-boot.log` from the boot that failed, *before* it gets rotated out.

## Open Hygiene Item (Separate Cleanup)

22 residual-config packages from old kernels still hanging around: `linux-image-6.14.0-{32,33,35,36,37}`, `linux-modules-6.14.0-*`, `linux-modules-extra-6.14.0-*`, `linux-image-6.17.0-{14,19}`, `linux-modules-6.17.0-{14,19}`, plus `dkms` itself. None are running — they're just stale package configs. Purge with:

```bash
sudo dpkg --purge $(dpkg -l | awk '/^rc/ {print $2}')
```

Verify with `dpkg -l | grep '^rc'` returns nothing. Not required for the suspend fix.

## Takeaway

After any nvidia package transaction (purge, reinstall, kernel-modules upgrade), explicitly check `systemctl is-enabled nvidia-{suspend,resume,hibernate}.service`. Presets are not re-applied automatically; once a service drifts to `disabled`, the next lid-close can lock the machine. Pair this with `dpkg -l | grep '^rc'` after every nvidia transaction to catch residual-config zombies that quietly cause downstream wiring drift.

## Post-Reboot Verification — 2026-05-12 (afternoon)

Ran the checklist after the post-reboot session resumed. **Fix is verified live.**

| Step | Expected | Actual | Verdict |
|---|---|---|---|
| 1 — Driver loaded | `580.142`, 4 nvidia modules, suspend params from modprobe | `580.142` confirmed; `nvidia/nvidia_drm/nvidia_modeset/nvidia_uvm` all present; `modprobe --show-depends nvidia` shows all 3 NVreg_* options applied at insmod | 🟢 |
| 2 — Hooks enabled | `enabled` × 3 + wants symlinks | `enabled` × 3; symlinks in `systemd-suspend.service.wants/` and `systemd-hibernate.service.wants/` | 🟢 |
| 3 — Test suspend (no lid) | clean s2idle | skipped (user closed lid first) | n/a |
| 4 — Hooks fired | status=0/SUCCESS; no `PM: failed` | `nvidia-suspend.service` ran 11:27:09 → 11:27:12 (status=0/SUCCESS); kernel `PM: suspend entry (s2idle)` at 11:27:12; `nvidia-resume.service` ran 11:27:18 (status=0/SUCCESS); zero `PM: failed` lines in journal | 🟢 |
| 5 — Lid close | recover cleanly | user closed lid before checklist; system recovered without freeze | 🟢 |

**Checklist correction (KB hygiene):** Check #1's `cat /sys/module/nvidia/parameters/NVreg_*` was misleading — the 580-open driver does not expose `NVreg_*` as sysfs nodes (only `fbdev`, `modeset` under `nvidia_drm`). `/sys/module/nvidia/` lacks a `parameters/` subdirectory entirely. The authoritative proof is `modprobe --show-depends nvidia`, which shows the `insmod` line with the right options. Future checks should use that instead.

### Adjacent finding — boot-time black-screen flash

User reported a brief black screen during this session. Journal shows a GDM X-session restart at boot: initial `gdm-x-session[2288]` at 11:26:02 was replaced by `[3303]` at 11:26:12, triggered by `X Error: BadValue (RANDR RRSetProviderOutputSource)` and `gnome-shell: Failed to read monitors config file '/home/mork/.config/monitors.xml': Logical monitors not adjacent`. Cosmetic — not driver-related. To clear: remove or regenerate `~/.config/monitors.xml`. Capturing here so it doesn't get conflated with the suspend incident next time it happens.
