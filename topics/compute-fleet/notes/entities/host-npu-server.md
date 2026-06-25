---
title: "Host: npu-server"
type: entity
topic: compute-fleet
tags: [compute-fleet, npu-server, intel-meteor-lake, npu, arc-xe-lpg, tailnet, llm-shop, watchman]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
status: on-tailnet
tailnet_fqdn: npu-server.tail9b2a4e.ts.net
tailnet_ip: 100.71.153.1
outgoing:
  - topics/compute-fleet/_summary.md
  - topics/compute-fleet/notes/entities/host-actuate-dev.md
  - topics/compute-fleet/notes/entities/host-laptop.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-04_https-via-tailscale-certs.md
  - topics/llm-shop/notes/concepts/2026-05-04_phase-1-installed.md
  - topics/llm-shop/notes/concepts/2026-05-04_status-dashboard-sketch.md
  - topics/llm-shop/notes/concepts/2026-05-05_ollama-vulkan-broken-on-meteor-lake.md
  - topics/llm-shop/notes/concepts/harness-pattern.md
  - topics/llm-shop/notes/syntheses/2026-05-04_llm-shop-initial-architecture.md
incoming:
  - home/operations/2026-06-22_npu-server-llm-shop-runbook.md
  - topics/compute-fleet/_summary.md
  - topics/compute-fleet/notes/entities/host-actuate-dev.md
  - topics/compute-fleet/notes/entities/host-laptop.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-04_https-via-tailscale-certs.md
  - topics/llm-shop/notes/concepts/2026-05-04_phase-1-installed.md
  - topics/llm-shop/notes/concepts/2026-05-04_status-dashboard-sketch.md
  - topics/llm-shop/notes/concepts/2026-05-05_ollama-vulkan-broken-on-meteor-lake.md
  - topics/llm-shop/notes/concepts/2026-05-06_model-routed-proxy.md
incoming_updated: 2026-06-25
---

# Host: npu-server

Company-owned NPU/GPU box on the office server rack. Primary tenant is the [[host-npu-server-watchman-service|Watchman test service]]; secondary tenant (planned) is the [[llm-shop/_summary|LLM shop]]. Shared resource — treat existing dev artifacts as load-bearing.

## Hardware

| Component | Spec | Notes |
|---|---|---|
| CPU | Intel Core Ultra 7 155H (Meteor Lake) | 16 physical cores (6P + 8E + 2 LP-E), 22 logical |
| iGPU | Intel Arc Xe-LPG (`8086:7dd5`) | 8 Xe-cores, ~17 TOPS FP16. `xe` driver loaded (modern path, not just legacy `i915`) |
| **NPU** | **Intel NPU 3720 (`8086:7d1d`)** | **~11 TOPS INT8. `intel_vpu` driver loaded.** Device at `/dev/accel/accel0` |
| RAM | 30 GiB | 8 GiB swap |
| Disk | 937 GB NVMe (`/dev/nvme0n1p2`) | 788 GB free at last check (2026-05-04) |
| OS | Ubuntu 24.04 LTS | Kernel 6.17.0-14-generic |

## Access

- **Canonical SSH** (since 2026-05-04): `ssh npu-server` (alias defined in `~/.ssh/config`)
- **Tailnet FQDN**: `npu-server.tail9b2a4e.ts.net`
- **Tailnet IP**: `100.71.153.1`
- **Tailnet identity**: registered under Mark's user (`mark@`) — no admin-issued tag yet (deferred until admin adds `tag:llm-shop` to the ACL; see "Deferred hardening" below)
- **Fallback SSH** (still works, used pre-tailnet, candidate for shutoff once team coordinates): `ssh -i ~/.ssh/npu-server -p 3327 actuate@158.106.215.138`
- **Hostname** (OS-level, cosmetic OEM default): `actuate-Default-string` — referred to in code/docs as `npu-server`
- **SSH key** on Mark's laptop: `~/.ssh/npu-server` (ed25519, generated 2026-05-04, comment `claude-laptop-to-npu`)
- **`actuate` user password** (initial, for sudo): in credential manager — NOT stored here. **Leaked in chat 2026-05-04** during this session; should be rotated when team coordinates (see Deferred hardening below).

## User account

- Operating user: `actuate` (uid 1000)
- Groups: `actuate, adm, cdrom, sudo, dip, video, plugdev, users, lpadmin, docker, render`
- Sudo: requires password (no NOPASSWD)
- Docker: `actuate` is in `docker` group → containers without sudo
- NPU access: `actuate` is in `render` group → has read/write on `/dev/accel/accel0` ✓
- iGPU access: `actuate` is in `video` and `render` groups → has access to `/dev/dri/*` ✓

## Existing workloads (DO NOT DISTURB)

These directories and processes are active development for [[watchman-repo|Watchman]]. Treat as load-bearing:

| Path / process | Purpose |
|---|---|
| `~/actuate-watchman/` | [[watchman-repo|Watchman repo]] — main service code |
| `~/actuate-watchman/.venv/bin/watchman-service --config service_config.json` | Continuously running service (PID 2146781 at 2026-05-04 inventory) |
| `~/actuate-watchman-old-main/`, `~/nlss_branch/`, `~/nlss_branch_latest/` | [[watchman-repo|Watchman]] branches / versions for benchmarking |
| `~/intel/` | Intel toolchain (likely OpenVINO, drivers) |
| `~/venvs/` | Existing Python virtualenvs for [[watchman-repo|Watchman]] / OpenVINO work |
| `~/model_cache/` | HuggingFace / ML model cache for [[watchman-repo|Watchman]] |
| `~/mediamtx*` | Media server for benchmarking video pipelines |
| `~/ffmpeg_cam*.log`, `~/start_*streams.sh` | Stream test scaffolding |
| `~/run_benchmark*.py`, `~/overflow_benchmark.py`, `~/i7_*.sh` | Benchmark scripts |
| `~/npu.tar.gz`, `~/npu_test*` | NPU benchmarking artifacts |

**Implication:** All LLM-shop work lives in `~/llm-shop/` ONLY. Never modify the directories above without explicit coordination with whoever owns [[watchman-repo|Watchman]] dev.

## Resource discipline (planned)

The [[llm-shop/_summary|LLM shop]] tenant is RAM-capped and CPU-yielding so it never starves [[watchman-repo|Watchman]]:

| Resource | Cap / discipline |
|---|---|
| RAM | `MemoryMax=18G` on `llm-shop.slice` |
| CPU | `CPUWeight=50` ([[watchman-repo|Watchman]] gets default 100, so it's prioritized) |
| iGPU | Cooperative sharing via `xe` driver; GPU-on-demand (not always-loaded) |
| Disk | All writes confined to `~/llm-shop/` |
| Ports | Loopback only (`127.0.0.1:11434` for Ollama); reverse proxy via Caddy on `tailscale0` interface |

## Tailnet onboarding (executed 2026-05-04)

What actually happened:

1. Mark's tailnet user is **not an admin** — no auth-key generation, no ACL editing, no tailnet-HTTPS toggle. Used SSO device-auth flow instead (no auth key).
2. Hit a **`/tmp` permissions bug** on the box mid-install: `/tmp` was `drwxr-xr-x` (mode `755`) instead of standard `drwxrwxrwt` (`1777`). Caused all `apt update` GPG verification to fail (apt drops privileges to `_apt` user, which couldn't write temp files). **Fixed with `sudo chmod 1777 /tmp`** — likely affected [[watchman-repo|Watchman]] dev too; flagged to team. Worth a quick KB cross-link if the same problem recurs on other shared hosts.
3. Install commands that worked:
   ```bash
   sudo chmod 1777 /tmp                   # fix perms
   sudo apt update
   sudo apt install -y tailscale
   sudo tailscale up --hostname=npu-server # SSO flow — visit URL, sign in, approve
   ```
4. Verified: FQDN `npu-server.tail9b2a4e.ts.net.`, sshd listening on port 22 (the `:3327` was external-only port-forward at the office firewall).
5. Added `Host npu-server` block to `~/.ssh/config` on Mark's laptop with `IdentityFile ~/.ssh/npu-server`, `Port 22`, `IdentitiesOnly yes`.
6. Verified `ssh npu-server "hostname; tailscale status; echo OK"` works end-to-end.

## Deferred hardening (Phase 2, requires team coordination)

These were intentionally NOT done because they affect other team members:

- [ ] **Disable password auth in `/etc/ssh/sshd_config`** — would break other devs SSH'ing in via the public IP at port 3327. Coordinate first.
- [ ] **Rotate the `actuate` user password** — shared account; rotation affects everyone. Coordinate first. Especially needed because the initial password leaked in a Claude session on 2026-05-04.
- [ ] **Request `tag:llm-shop`, `tag:devbox`, `tag:office` from tailnet admin** — required for tag-based federation discovery (Phase 3 of [[llm-shop/_summary]]). Once tags are defined in ACL, re-tag this box: `sudo tailscale up --advertise-tags=tag:llm-shop,tag:devbox,tag:office`.
- [ ] **Request HTTPS Certificates enable from tailnet admin** — admin console → Settings → DNS → HTTPS Certificates. Required for Tailscale-issued LE certs via `tailscale cert`. See [[2026-05-04_https-via-tailscale-certs]] (currently deferred-status).
- [ ] **Push firebat's SSH pubkey to `npu-server` `authorized_keys`** so `ssh npu-server` works from firebat too (currently only laptop is keyed).

## Identifying Watchman activity (for the polite-tenant pause hook)

[[watchman-repo|Watchman]] service is continuous (always-on background); it doesn't have a discrete "benchmarking now" signal. Approach: **rely on cgroup CPU/MemoryWeight to handle sharing** (kernel scheduler is good at this), with a fallback hook that:

1. Reads the [[watchman-repo|Watchman repo]]'s known benchmark script names (`i7_full_test.sh`, `start_benchmark_streams.sh`, `run_benchmark*.py`, `overflow_benchmark.py`) at LLM-shop service startup
2. Polls `pgrep -af` every 5s for matches
3. If any match in flight: routes inference to CPU-only / queues requests
4. If none: full iGPU access

Implementation deferred to install session.

## Cross-references

- [[compute-fleet/_summary]] — fleet topic
- [[llm-shop/_summary]] — service topic (the planned tenant)
- [[2026-05-04_llm-shop-initial-architecture]] — design decisions for the LLM shop
