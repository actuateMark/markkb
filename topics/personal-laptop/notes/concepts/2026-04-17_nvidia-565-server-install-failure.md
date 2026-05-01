---
title: "NVIDIA 565-server install failure and recovery (2026-04-16)"
type: concept
topic: personal-laptop
tags: [nvidia, gpu, ubuntu, suspend, incident, kernel-modules]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/personal-laptop/_summary.md
incoming_updated: 2026-05-01
---

Automatic nvidia driver update attempted 565-server install, failed mid-transaction, left GPU in broken state. Recovery via upgrade to 580-open (prebuilt modules) succeeded and is now stable.

## What Happened

On 2026-04-16, apt tried to install `nvidia-kernel-source-565-server` (565.57.01). The DKMS build failed — likely incompatibility with kernel 6.17.0-20. Apt rolled back, but all `nvidia-*-565-server` packages ended up in residual-config (`rc`) state instead of being fully removed. Before the state settled, attempting to sleep the laptop triggered a GPU driver error and required a hard shutdown to recover. Subsequently, apport crash dialogs kept resurfacing for the failed install.

## Root Cause

DKMS-based driver builds (`-server` variant) compile against the running kernel at install time. When the build failed, the package transaction left the system in an intermediate state: modules broken, config stubs orphaned, but no automatic cleanup. The broken driver was still being loaded on boot, causing suspend to fail.

## Solution Applied

Upgraded to `nvidia-driver-580-open` (580.126.09) using the **prebuilt signed modules** approach (`linux-modules-nvidia-580-*` package). This avoids DKMS entirely — the kernel modules are pre-compiled and signed by Canonical, matching the installed kernel version. Install was clean and immediate.

## Verification (2026-04-17)

- **`nvidia-smi`**: RTX 500 Ada, driver 580.126.09, CUDA 13.0 — working
- **Loaded modules**: `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm` all present
- **Suspend/resume proven**: overnight sleep 21:49 → 09:21 (11.5h), both `nvidia-suspend.service` and `nvidia-resume.service` exit 0
- **`dpkg --audit`**: no broken packages
- **Kernel logs**: benign warning on resume: `NVRM: rm_power_source_change_event: Failed to handle Power Source change event, status=0x11` — cosmetic, does not affect functionality

## Why It Works Now

Modern Ubuntu with HWE (Hardware Enablement) kernels ships prebuilt nvidia modules tied to each kernel release. The 580-open driver variant leverages this: no DKMS compilation, no kernel compatibility guessing, just signed binaries that match the kernel. DKMS is now marked as auto-removable — nothing on this laptop depends on it for nvidia.

## Cleanup Procedure (Reusable)

```bash
# Remove stale apport crash dialogs
sudo rm /var/crash/nvidia-*565-server*.crash

# Purge residual packages from failed install
sudo apt purge '*565-server*'

# Inspect autoremove before running (on this laptop it wants to remove
# local overrides nvidia-firmware-580 and nvidia-modprobe, which are newer
# than repo versions — keep those)
apt-get -s autoremove
sudo apt autoremove
```

## Local Overrides (Do Not Remove Blindly)

- `nvidia-firmware-580` 580.126.20-1ubuntu1 (local, newer than repo)
- `nvidia-modprobe` 595.58.03-1ubuntu1 (local, much newer than repo)

These are installed locally and explicitly newer than available repo versions. Autoremove will flag them because they're "manually installed" but they should be kept.

## Diagnostic Commands

| Command | Purpose |
|---------|---------|
| `nvidia-smi` | Driver version, GPU model, CUDA capability, memory usage |
| `dkms status` | Show active DKMS modules (empty = using prebuilt only) |
| `lsmod \| grep nvidia` | Confirm all nvidia modules are loaded |
| `dpkg -l \| grep -E '^rc'` | Find residual-config packages left from failed installs |
| `journalctl -k --since "2 days ago" \| grep -iE "nvidia\|suspend\|resume"` | Kernel logs for driver/sleep issues |
| `systemctl status nvidia-suspend.service nvidia-resume.service` | Verify suspend hooks ran cleanly |
| `ls /var/crash/` | Check for apport crash files to clean up |

## Takeaway

On modern Ubuntu with HWE kernels, prefer the `-open` driver variant with prebuilt signed modules over `-server` with DKMS. Avoids compilation failures and provides immediate stability.
