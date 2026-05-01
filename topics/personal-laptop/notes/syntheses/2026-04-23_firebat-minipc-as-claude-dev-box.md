---
title: "Firebat minipc as always-on Claude dev box"
type: synthesis
topic: personal-laptop
tags: [hardware, edge-device, tailscale, obsidian, nm-networking, claude-code-remote]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
---

# Firebat minipc as always-on Claude dev box

Motivation: an always-on box reachable from laptop and phone (including over cellular) that (1) hosts persistent Claude Code sessions, (2) keeps a synced Obsidian vault, (3) runs scheduled Claude/dev cron jobs, (4) surfaces live status at a simple URL, and (5) self-recovers after reboots. Setup must be scriptable and re-runnable for future hosts.

## Hardware & Base

**Firebat_Computer AM02**: Intel N100 (4 cores), 15 GB RAM, 98 GB disk, Ubuntu 24.04.3 LTS, hostname `actuate-dev`, Tailscale hostname `mork-firebat`. Machine is always on; SSH available via Tailscale or LAN fallback.

## Networking

NetworkManager manages all interfaces. Wifi profiles from the laptop were ported with `connection.autoconnect-priority` tuning: `Actuate_5G=100`, captive portals=10, rest=50. NM profile `direct-laptop` on `enp1s0` provides a deterministic fallback: `ipv6.method=link-local` and `ipv6.addr-gen-mode=eui64` yields a stable link-local address tied to the MAC, avoiding the default `stable-privacy` UUID hashing.

Tailscale is the primary remote-access path. Enterprise networks like `Actuate_5G` use AP/client isolation, blocking wifi-to-wifi SSH; Tailscale bypasses this. Machine authenticates to tailnet as `mork-firebat`.

## Dashboard & Status

mDNS (`avahi-daemon`) advertises the box as `actuate-dev.local`. Caddy listens on port 80, serving:
- `/` — live status page (uptime, network state, service checks), regenerated every 30 seconds by `gen-status-page.sh` via systemd timer.
- `/obsidian` — reverse-proxy to localhost:8080, the Obsidian container.
- `/dashboard` — static HTML from `/dashboard-check` skill runs (operational dashboard artifact).
- `/logs` — simple file browser over `~/.local/state/claude-jobs/` (scheduled-job output).

## Obsidian Headless

Container `ghcr.io/sytone/obsidian-remote` runs in unprivileged mode, vault bind-mounted at `/vaults/knowledgebase` pointing to the user's KB directory. Reverse-proxied through Caddy on `/obsidian`. User completes Sync setup interactively via the web UI post-provision.

## Persistence & Auto-Recovery

`loginctl enable-linger mork` allows the user to run long-lived tmux sessions (`main`) even after logout. A user systemd service keeps that session alive. Template wrapper `~/bin/claude-run-skill.sh` handles scheduled Claude jobs — no specific cron timers wired yet, but the pattern is ready.

Auto-login on tty1 (HDMI+keyboard) is configured as a final recovery layer: if future provisioning breaks networking, walking to the hardware allows command-line recovery without a password prompt.

## Reusable Provisioning

All setup lives in `/home/mork/work/local_network_scripts/`: 12 numbered phase scripts (0-bootstrap, 1-ssh, 2-base-packages, …, 11-obsidian-container), orchestrator, and README. All scripts are idempotent and parameterized by `TARGET` env var. Pointing the orchestrator at any Ubuntu 24.04 host reproduces the full setup end-to-end.

Configuration templates in `files/` are pushed verbatim: Caddyfile, systemd units, status-page generator, and the skill-runner wrapper.

## Key Lessons

**SSH key verification:** `init=/bin/bash` rescue shells can silently typo long base64 pubkeys. Always verify with `ssh-keygen -l -f <pubkey-file>` post-install.

**Hostname sanity:** `agetty` prints `<hostname> login:` at the prompt — don't confuse it with a username. Verify with `getent passwd` if unsure.

**NetworkManager wifi management:** Ubuntu's NM doesn't auto-manage wifi by default. Requires explicit `[device] managed=true` drop-in in `/etc/NetworkManager/conf.d/`.

**IPv6 link-local determinism:** NM's default `ipv6.addr-gen-mode=stable-privacy` hashes the connection UUID into the address, rotating it on every profile change. Switch to `eui64` mode to pin the LL address to the MAC — essential when the LL address is your SSH target.

**rsync + IPv6 link-local:** Use bracket notation with interface scope: `rsync -av user@[ipv6%iface]:path dest`. Without the `%iface` suffix, the kernel doesn't know which interface to use.

**Bash exit codes in arithmetic:** `((var++))` returns the pre-increment value as its exit code. With `set -e`, this kills the script when `var` is 0. Use `var=$((var+1))` to avoid the trap.

**Enterprise wifi isolation:** `Actuate_5G` and similar "managed" networks often enable AP/client isolation — wifi clients cannot see each other. Tailscale is the pragmatic escape hatch.

**systemctl substring traps:** `systemctl is-active X | grep -q active` matches "inactive" as a substring. Use `grep -qx active` (exact line match) to avoid false positives.

**Tailscale hostname collision:** Tailscale silently appends `-N` to colliding hostnames. Pick a unique hostname upfront.

## Cross-References

- [[2026-04-23_firebat-minipc-network-setup]] — initial SSH-access recovery (bootstrap prequel to this architecture)
- [[automation-overnight-check]] — template for the scheduled-job pattern replicated here
- [[dev-environment]] — macOS-focused; this box is the Ubuntu-equivalent shape
- [[remote-access-proxy]] — Actuate's internal WireGuard pattern; we chose Tailscale for personal-tier simplicity
