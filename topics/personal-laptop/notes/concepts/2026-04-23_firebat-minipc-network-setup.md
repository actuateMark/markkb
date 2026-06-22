---
title: "Firebat minipc — direct-ethernet setup"
type: concept
topic: personal-laptop
tags: [networking, hardware, edge-device, ssh, microk8s]
created: 2026-04-23
updated: 2026-04-23
author: kb-bot
incoming:
  - topics/personal-laptop/notes/concepts/2026-05-22_gnome-terminal-focus-steal-fix.md
  - topics/personal-laptop/notes/syntheses/2026-04-23_firebat-minipc-as-claude-dev-box.md
  - topics/personal-laptop/notes/syntheses/2026-04-24_minipc-dashboard-static-gen-refactor.md
  - topics/personal-laptop/notes/syntheses/2026-04-30_firebat-script-conversion-candidates.md
  - topics/personal-laptop/notes/syntheses/2026-05-05_firebat-minipc-followups-context.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-05-27
---

# Firebat minipc — direct-ethernet setup

Log of attempts to bring up a Firebat mini PC connected by a single ethernet cable directly to the XPS laptop (no router between them). Scripts for this live in `/home/mork/work/local_network_scripts/`.

## Device facts

| Field | Value |
|-------|-------|
| Form factor | Firebat mini PC — **Firebat_Computer AM02** |
| Hostname | `actuate-dev` (*not a user — this tripped us up*) |
| OS | Ubuntu 24.04.3 LTS, kernel 6.8.0-71-generic |
| Disk layout | `(hd0,gpt1)` ESP · `(hd0,gpt2)` `/boot` · `(hd0,gpt3)` LVM PV (`ubuntu-vg/ubuntu-lv`) |
| Workload | microk8s (installed; does not auto-start on boot) |
| Ethernet MAC | `84:47:09:34:b4:f2` (Intel NIC OUI) |
| IPv6 link-local | `fe80::8647:9ff:fe34:b4f2` (on `enp0s31f6` scope) |
| IPv4 address | *none — no DHCP server on this direct link; not needed for SSH over v6 LL* |
| SSH | port 22 open |
| Other ports checked | 80, 443, 445, 3389, 5000, 5357, 5900, 8080 — all closed |
| Local sudo user | `mork` (uid 1001, groups `mork`, `sudo`) — **created 2026-04-23 via init=/bin/bash rescue** |
| Auth | ssh key (`~/.ssh/id_ed25519` on laptop) + password fallback; passwordless sudo via `/etc/sudoers.d/90-mork` |
| ssh target | `ssh mork@fe80::8647:9ff:fe34:b4f2%enp0s31f6` |

Laptop side:
- Interface `enp0s31f6`, MAC `c4:ef:bb:eb:1f:27`, IPv6 link-local `fe80::b7bc:345c:c1f0:95d7`.
- No IPv4 address assigned on `enp0s31f6` (interface has link but no lease).

## Timeline

**T0 — cable plugged in.** `enp0s31f6` shows `UP, LOWER_UP` (PHY link detected) but no IPv4 and no responses to IPv6 all-nodes multicast. HDMI output blank. Initial hypothesis: device fully offline, hung, or NIC is dead.

**T+~3 min — HDMI lights up.** Minipc was simply slow to POST / boot. IPv6 all-nodes multicast (`ping6 -I enp0s31f6 ff02::1`) now returns a second neighbor: the minipc. OS stack is alive.

**T+~5 min — service probe.** Only SSH (port 22) is open. Device is a hardened Linux box, not a stock Windows install. The display asks for the `actuate-dev` login.

**T+~6 min — SSH auth attempt.** `ssh actuate-dev@fe80::8647:9ff:fe34:b4f2%enp0s31f6` with the laptop's `~/.ssh/id_ed25519` key → `Permission denied (publickey,password)`. The laptop's key is not in `actuate-dev`'s `authorized_keys`. No other keys exist in `~/.ssh` and ssh-agent only has this one key.

## What works

**IPv6 link-local is the right transport for this direct-cable setup.** No DHCP needed; both sides auto-assign `fe80::/64` addresses and you address the peer as `fe80::<remote-lladdr>%<local-interface>`. SSH over IPv6 link-local works fine once auth is sorted.

## What didn't work

- **IPv4 connectivity** — without a DHCP server on this link, neither side gets an IPv4 lease. Could be solved by either (a) running `dnsmasq` on the laptop scoped to `enp0s31f6`, or (b) assigning static 169.254.x.x APIPA addresses on both ends. Not needed if IPv6 link-local is enough for the task (it is, for SSH).
- **Current laptop SSH key** — rejected. No other keys locally.

## Useful commands

```bash
# Discover minipc (or any neighbor) on direct link
ping -c 3 -I enp0s31f6 ff02::1

# Inspect neighbor table
ip -6 neigh show dev enp0s31f6

# Connect via v6 link-local (note the %iface scope)
ssh actuate-dev@fe80::8647:9ff:fe34:b4f2%enp0s31f6

# Quick port probe over v6 link-local
for p in 22 80 443 3389; do
  timeout 2 bash -c "echo > /dev/tcp/fe80::8647:9ff:fe34:b4f2%enp0s31f6/$p" 2>/dev/null \
    && echo "$p OPEN" || echo "$p closed/filtered"
done
```

## Resolution — what actually worked (2026-04-23)

1. **`actuate-dev` was the hostname, not a user.** The `Ubuntu LTS actuate-dev tty1` and `actuate-dev login:` prompts were misleading — agetty prints `<hostname> login:`. No user by that name ever existed on the box. We wasted about 15 min on this false lead.

2. **Booted into `init=/bin/bash` via GRUB.** The box boots straight to the `grub>` rescue prompt, not a menu. Commands used:

   ```
   set root=(hd0,gpt2)
   linux /vmlinuz root=/dev/mapper/ubuntu--vg-ubuntu--lv rw init=/bin/bash
   initrd /initrd.img
   boot
   ```

   Note the `ubuntu--vg-ubuntu--lv` — LVM device-mapper names double any hyphens from the original VG/LV names and use a single hyphen as the VG/LV separator. `/vmlinuz` and `/initrd.img` are at the root of the `/boot` partition (gpt2), not under `/boot/`.

3. **In the rescue shell, created a fresh `mork` sudo user:**

   ```bash
   mount -o remount,rw /
   useradd -m -s /bin/bash -G sudo mork
   passwd mork
   mkdir -p /home/mork/.ssh
   echo 'ssh-ed25519 <pubkey>' >> /home/mork/.ssh/authorized_keys
   chown -R mork:mork /home/mork/.ssh
   chmod 700 /home/mork/.ssh
   chmod 600 /home/mork/.ssh/authorized_keys
   echo 'mork ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-mork
   chmod 440 /etc/sudoers.d/90-mork
   sync && mount -o remount,ro / && reboot -f
   ```

4. **The `echo >>` in the rescue shell mangled the pubkey.** `ssh-keygen -l -f authorized_keys` produced a fingerprint that didn't match our real key — likely a hand-typing error during the base64 blob. Fix was to rewrite the file *after* reboot using `cat > … <<EOF` via password-SSH from the laptop (`ssh-password-run.py`). Byte-perfect after that.

5. **On the laptop, NetworkManager fought us during the reboot.** NM saw the PHY link drop/recover and flushed the IPv6 link-local while trying to run DHCP (there's no DHCP server on this direct link). Fix that worked immediately: `sudo ip link set enp0s31f6 down && sudo ip link set enp0s31f6 up`. Kernel re-auto-assigns a fresh fe80:: on relink. For a persistent fix, create an NM profile that uses `ipv6.method link-local` and `ipv4.method disabled`:

   ```
   sudo nmcli connection add type ethernet ifname enp0s31f6 con-name minipc-direct \
       ipv4.method disabled ipv6.method link-local autoconnect yes
   ```

## Lessons

- **`init=/bin/bash` is not a tty-rich environment** — hand-typed `echo 'long base64 blob'` commands will silently drop or mistype characters. Prefer rewriting key files post-boot via a working shell once SSH password auth is available.
- **Host-named login prompts** (`<hostname> login:` via agetty) have caused confusion before. Always check `/etc/passwd` before assuming the prompted name is a user.
- **Direct ethernet cable ≠ need for DHCP.** IPv6 SLAAC link-local gives you reachability for free as soon as both NICs come up; SSH and most remote tools work fine over `fe80::...%iface`. NetworkManager has to be told not to try DHCP or it'll just repeatedly fail-and-flush.
- **The HDMI console can be slow on Firebat** — several minutes from power-on to first display on first-boot. Don't declare the device dead without waiting.

## Related

- [[edge-hardware-track]] — morphean edge hardware context (may or may not be this device)
- [[remote-access-proxy]] — infrastructure pattern for reachable edge devices
