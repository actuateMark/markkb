---
title: "Firebat operations runbook (team handoff)"
type: concept
topic: personal-laptop
tags: [firebat, runbook, offboarding, systemd, operations]
created: 2026-06-22
updated: 2026-06-22
author: kb-bot
incoming:
  - _tooling/DEVBOX-BOOTSTRAP.md
  - topics/engineering-process/notes/concepts/2026-06-24_secrets-refresh-runbook.md
  - topics/engineering-process/notes/syntheses/2026-06-22_actuate-footprint-handoff.md
  - topics/engineering-process/notes/syntheses/2026-06-22_dead-mans-checklist.md
  - topics/engineering-process/notes/syntheses/2026-06-22_offboarding-plan.md
  - topics/offboarding-overview.md
  - topics/offboarding/notes/concepts/2026-06-22_manual-action-checklist.md
  - topics/offboarding/notes/concepts/2026-06-23_firebat-dashboard-ownership-handoff.md
  - topics/offboarding/notes/concepts/2026-06-23_local-repo-audit.md
  - topics/offboarding/notes/concepts/2026-06-24_firebat-kb-git-sync-task.md
incoming_updated: 2026-06-25
---

# Firebat operations runbook

Operating manual for the **Firebat mini PC** — an always-on Ubuntu 24.04 box that runs ~14 user systemd timers powering Mark's morning-routine automation, the operational dashboard, and the KB site. Written for a teammate who has **never touched the box**. Company-owned hardware; it stays after Mark's departure (last day Fri 2026-06-26). See [[2026-06-22_offboarding-plan]] for the re-home plan and [[2026-04-30_three-tier-routine-check-pattern]] for the architecture these scripts follow.

## Box facts

| Property | Value |
|---|---|
| System hostname | `actuate-dev` (the `agetty` console prompt + avahi/mDNS name) |
| Tailnet hostname | `mork-firebat` (MagicDNS) |
| OS | Ubuntu 24.04 LTS |
| Login user | `mork` (passwordless sudo; password fallback `morkrocks`) |
| Linger | `loginctl enable-linger mork` — user services persist across reboot with no login |
| Provisioning source | `aegissystems/actuate-dev-toolkit` (local clone `/home/mork/work/local_network_scripts`) |

### How to reach it

| Pathway | Command | Notes |
|---|---|---|
| Tailscale (default) | `ssh mork@mork-firebat` | MagicDNS over wireguard, works from any network. Plain key-auth (NOT `tailscale up --ssh`). |
| Same-LAN mDNS | `ssh mork@actuate-dev.local` | Only when laptop+box share a non-isolated network. `Actuate_5G` has AP/client isolation — won't work there; use Tailscale. |
| Direct ethernet | `ssh mork@fe80::8647:9ff:fe34:b4f2%enp0s31f6` | Last-resort recovery cable. IPv6 link-local pinned via eui64. Works with no upstream network. |

Liveness probe: `ssh mork@mork-firebat 'uptime; df -h /; free -m'`. Status page regenerates every 30s at `http://mork-firebat/` — a stuck timestamp means the box is genuinely down.

## How everything is deployed (source of truth)

**Do not hand-edit scripts on the box.** They are deployed from the toolkit repo. Edit the source, then redeploy:

- Repo: `aegissystems/actuate-dev-toolkit`, local clone `/home/mork/work/local_network_scripts`.
- Script sources live in `files/` (e.g. `files/pr-review-digest.sh` → deployed to `~/bin/pr-review-digest`).
- Systemd unit sources also live in `files/` → deployed to `~/.config/systemd/user/`.
- Deploy with **`./phase-13-tasks.sh`** (scp's scripts + units, runs `systemctl --user daemon-reload`, enables/starts timers, restarts the app). It is idempotent.
- Dashboard/Caddy: `phase-09-dashboard.sh`. 11ty blog: `phase-14a-blog.sh`. Quartz: `phase-14b-quartz.sh`. FastAPI app: `phase-12-app.sh`. Secrets: `phase-15-secrets.sh`.
- The git-fetch repo list is **data, not code**: `files/repos-config.json` → `~/.config/minipc-repo-cron/repos.json`. Add/drop tracked repos by editing this JSON + re-running phase-13.

A few scripts under `~/.local/bin/` (the `kb-*` job-runner family: `kb-jobs-reap`, `kb-job-runner`, `kb-job-archive`) and the `kb-relink`/`kb-incoming-refresh`/`kb-lint`/`kb-recap` tools were deployed by earlier phases; their unit files live in `~/.config/systemd/user/` like the rest.

## Timer inventory

All are **`systemctl --user`** timers (run as user `mork`, not root). Inspect the live schedule any time with:

```
ssh mork@mork-firebat 'systemctl --user list-timers --all'
```

| Timer | Schedule | What it does | Script | Cred | Output / logs |
|---|---|---|---|---|---|
| `morning-prep` | Mon–Fri 06:00 ET | Orchestrator: runs repo-scan → autopatrol-overnight-check → autopatrol-cleanup-check sequentially (~50s). Primes `/daily-scope` cache. | `~/bin/morning-prep.sh` | gh+aws+nr (via sub-scripts) | `claude-jobs/morning-prep-<date>.summary.json` (+ `-latest` symlink) |
| `morning-prep-self-audit` | Mon 07:00 ET | Weekly audit that the morning batch ran green; emits `morning_prep_self_audit_status` sink signal. | `~/bin/morning-prep-self-audit` | none | `claude-jobs/` + dashboard sink |
| `run-dashboard-check` | hourly + boot | Pure-Python operational dashboard. ~21 NRQL calls/hr + AWS. Writes signals to the sink. | `~/bin/run-dashboard-check.sh` | aws+nr | `~/Documents/worklog/dashboard/latest/` → `http://mork-firebat/dashboard/` |
| `pr-review-digest` | hourly + boot | Open-PR digest across the tracked repos, scored by review-readiness/age/size. | `~/bin/pr-review-digest` | gh | `claude-jobs/pr-review-digest-<date>.stdout` + sink |
| `git-fetch-major-repos` | hourly (+rand offset) | Clones/fetches the ~16 repos in `repos.json`, writes per-repo state JSON for `/app/repos`. | `~/bin/git-fetch-major-repos.sh` | gh | `~/.local/state/minipc-tasks/repos-detailed/` |
| `jira-sync` | daily 06:30 ET | Refreshes the auto-synced Jira queue block in `mark-todos.md`. Idempotent (skip if synced today). | `~/bin/jira-sync.sh` | atlassian | splices `mark-todos.md`; backups in `~/.local/state/jira-sync/` |
| `billing-reconcile-check` | daily 04:00 PT | Admin-Postgres ↔ Snowflake billing reconciliation (NF2). Needs `~/work/sales-dashboard` w/ `.env` + IP whitelisted in RDS SG. | `~/bin/billing-reconcile-check` | aws | `~/.local/state/minipc-tasks/billing/` |
| `ecr-lifecycle-audit` | daily 13:00 UTC | Flags deployed Lambda/ECS/EKS images at risk of ECR lifecycle pruning. | `~/bin/ecr-lifecycle-audit` | aws | `claude-jobs/` + sink |
| `kb-relink` | daily 03:00 | KB wikilink + tag + bare-topic enrichment (Passes 1–3). | `~/bin/kb-relink` | none | journal; mutates vault |
| `kb-incoming-refresh` | daily 03:30 | Refresh incoming-link frontmatter snapshots (Pass 4). Runs after relink. | `~/bin/kb-incoming-refresh` | none | journal; mutates vault |
| `kb-lint` | daily 04:00 | Nightly KB lint + safe autofix. **Exit 1/2 = findings, not failure** (`SuccessExitStatus=1 2`). | `~/bin/kb-lint` | none | journal |
| `kb-jobs-reap` | every 5 min | Reaps stale `/app/kb/query` job dirs: SIGTERM >10min, SIGKILL >13min, purge >24h. | `~/.local/bin/kb-jobs-reap` | none | journal |
| `rebuild-blog` | every 5 min | Rebuilds the 11ty dashboard site from artifacts; atomic rotate to serve dir. | `~/bin/rebuild-blog.sh` | none | `~/.local/state/minipc-dashboard/blog-output` |
| `rebuild-quartz` | every 5 min | Rebuilds the Quartz KB site from the synced vault; quarantines broken-frontmatter files; atomic rotate. | `~/bin/rebuild-quartz.sh` | none | `~/.local/state/minipc-dashboard/quartz-output` |
| `launchpadlib-cache-clean` | daily | **System default** (`/usr/lib/systemd/user/`), not ours. Ignore. | — | none | — |

**Stale/dead timers — safe to clean up.** `pr-1660-soak-t{6,8,18,24}h`, `pr-1688-soak-{t1h,tonight}` are one-shot PR-soak timers from May that already fired and will never fire again (`NEXT` shows `-`). Disable + remove their units when convenient:
```
systemctl --user disable --now pr-1660-soak-t6h.timer  # etc. for each
rm ~/.config/systemd/user/pr-16{60,88}-soak-*.{timer,service}
systemctl --user daemon-reload
```

## Credential map

Four identities. AWS is already team-owned; the other three are still Mark-personal and must be re-homed/rotated (tracked in [[2026-06-22_offboarding-plan]] WS-A / ENG-376). **Never print secret values.**

| Cred | Used by | Where the secret lives | Current owner | Rotation |
|---|---|---|---|---|
| **AWS** (Roles Anywhere) | run-dashboard-check, billing-reconcile-check, ecr-lifecycle-audit, morning-prep | Host X.509 cert `~/.config/aws-rolesanywhere/mork-firebat.{crt,key}` → role `dashboard-check-rolesanywhere`, trust-anchor `328fdc80-…`, account `388576304176`. `AWS_PROFILE=dashboard-check`. | **Team-owned machine identity** (survives Mark). Named "mork-firebat" but is a host cert, not Mark's SSO. | Check expiry `openssl x509 -in ~/.config/aws-rolesanywhere/mork-firebat.crt -noout -dates`. Reissue via IAM → Roles Anywhere console, replace both files, test `aws sts get-caller-identity --profile dashboard-check`. |
| **GitHub** (`gh`) | repo-scan, git-fetch-major-repos, pr-review-digest, KB bare-repo push | `~/.config/gh/hosts.yml` (PAT). gh credential helper injects it for HTTPS git. | **PERSONAL `actuateMark`** — re-home to an org machine account / org PAT. | Mint org PAT (scopes `repo`, `read:org`), replace `oauth_token:` in `hosts.yml`, `gh auth status` to verify. Prior art: [[2026-04-28_minting-github-pats-for-automation]]. |
| **[[new-relic|New Relic]]** | run-dashboard-check, autopatrol checks | `~/.config/newrelic/key` (NRAK) + `~/.config/newrelic/account_id` (`3421145`). NOT NR MCP — direct nerdgraph. | **PERSONAL `mark@actuate.ai` NRAK** (pending WS-A rotation). *(The `~/.config/nr/api-key` in old notes is the laptop path, not Firebat.)* | New User key in NR UI (ideally team/service), `echo NEWKEY > ~/.config/newrelic/key && chmod 600`. **A leaked NR key was purged from KB git history 2026-06-22 — rotate it.** |
| **Atlassian** | jira-sync | `~/.config/atlassian/api-token` JSON `{email, token, site}` | **PERSONAL `mark@actuate.ai`** — re-issue under a service account. | New token at id.atlassian.com → Security → API tokens, update the JSON, `chmod 600`, verify `~/bin/jira-sync.sh --force --dry-run`. |
| **Tailscale** | network reachability of all the above | node identity in tailscaled state | **USER-owned by `mark@`** (key expiry 2026-10-20) — re-tag to `tag:server`. | Re-auth at the box (**console/physical — can drop SSH**): `sudo tailscale up --authkey=tskey-… --advertise-tags=tag:server`. Needs a tagged auth key + `tag:server` in the ACL. |

Verify all five at once with the harness (next section). The Anthropic API key is **not** a Firebat concern — all timers are pure-Python, zero-token by design.

## Verification harness

`~/bin/firebat-identity-verify.py` (source: `actuate-dev-toolkit/files/`) checks the 5 identities + every timer's last-run result, prints PASS/WARN/FAIL, never prints secrets. Three modes:

```
~/bin/firebat-identity-verify.py                     # read-only; compare to baseline
~/bin/firebat-identity-verify.py --baseline out.json # capture current state to JSON
~/bin/firebat-identity-verify.py --run-timers        # actively fire each cred-dependent timer, confirm exit 0
```

Pre-re-home baseline (0 FAIL, 3 WARN = the 3 re-home targets) is at `~/identity-baseline-pre-rehome.json`. **After each re-home step the matching WARN should flip to PASS.** kb-lint exit 2 is treated as a normal findings signal, not a failure.

## The dashboard web app — `http://mork-firebat/`

Served by **Caddy on :80** (LAN/tailnet-private, no HTTPS — `.local`/tailnet hosts can't get public certs). Config at `/etc/caddy/Caddyfile` (deployed by phase-09). Routes, most-specific first:

| URL | Backend | Serves |
|---|---|---|
| `/app/kb/query*` | FastAPI `127.0.0.1:8081` | `/kb-ask` headless query endpoint |
| `/app/kb/*` | static (Quartz) | the Obsidian KB site (`quartz-output`) |
| `/app/api/*` | FastAPI `127.0.0.1:8081` | metrics, observations, healthz, Swagger |
| `/app/*` | static (11ty) | the dashboard (`blog-output`) |
| `/obsidian/*` | container `127.0.0.1:8080` | headless Obsidian web UI (admin) |
| `/dashboard/*` | static | `/dashboard-check` artifact (`~/Documents/worklog/dashboard/latest`) |
| `/logs/*` | file browser | `~/.local/state/claude-jobs/` (browse listing) |
| `/` | static fallback | status page (regenerated every 30s) |

**FastAPI app:** `minipc-app.service` (user service, `Type=simple`, `uv run uvicorn main:app --port 8081`, `Restart=on-failure`). Working dir `~/minipc-app`. Restart with `systemctl --user restart minipc-app.service`; logs `journalctl --user -u minipc-app -n 50`.

**Rebuilding the static sites manually:**
```
ssh mork@mork-firebat 'systemctl --user start rebuild-blog.service'    # 11ty dashboard
ssh mork@mork-firebat 'systemctl --user start rebuild-quartz.service'  # Quartz KB site
# or run the scripts directly to see output:
ssh mork@mork-firebat '~/bin/rebuild-blog.sh'
ssh mork@mork-firebat '~/bin/rebuild-quartz.sh'
```
Both rebuild every 5 min on their own; the manual start just forces an immediate refresh. Each rotates a `.prev` copy for one-level rollback.

## The KB bare repo

The KB Obsidian vault is the same content on the laptop and Firebat (converges via Obsidian Sync). For git history there is a **bare repo on Firebat: `mork@mork-firebat:~/git/knowledgebase.git`**. The laptop pushes commits here; the Firebat's `rebuild-quartz` reads the live vault (not the bare repo) and rebuilds the public KB site every 5 min.

- Vault on Firebat: `~/Documents/worklog/work/knowledgebase` (note `~/Documents/worklog/knowledgebase` is a **symlink** to it). Quartz reads `…/work/knowledgebase/topics`.
- Obsidian Sync does **not** sync `.git/`, so git push/pull is manual.
- **Offboarding action (WS-B):** make an `aegissystems` org repo the canonical remote, not Mark's personal `actuateMark/markkb`. Add a `gitleaks` pre-commit hook (a live NR key leaked into history was purged 2026-06-22).

## Managing timers — the commands

```
# Inspect
systemctl --user list-timers --all                  # all schedules, next/last fire
systemctl --user status <name>.timer                # one timer
systemctl --user cat <name>.service                 # see the unit + ExecStart
journalctl --user -u <name>.service -n 50           # recent logs

# Run / stop / control
systemctl --user start <name>.service               # fire NOW (out of schedule)
systemctl --user stop <name>.timer                  # stop future firings
systemctl --user disable --now <name>.timer         # disable + stop
systemctl --user enable --now <name>.timer          # enable + start

# Add or change (do it via the repo, not by hand)
#   1. add/edit files/<name>.{timer,service} + files/<name>.sh in the toolkit repo
#   2. ./phase-13-tasks.sh   (scp + daemon-reload + enable/start)
# Manual install if needed:
scp files/<name>.timer files/<name>.service mork@mork-firebat:.config/systemd/user/
ssh mork@mork-firebat 'systemctl --user daemon-reload && systemctl --user enable --now <name>.timer'

# Remove
ssh mork@mork-firebat 'systemctl --user disable --now <name>.timer'
ssh mork@mork-firebat 'rm ~/.config/systemd/user/<name>.{timer,service} && systemctl --user daemon-reload'
```

Canonical paths: stdout digests `~/.local/state/claude-jobs/<name>-<date>.{stdout,stderr}`; structured JSON `~/.local/state/minipc-tasks/<topic>/`; dashboard sink `~/Documents/worklog/dashboard/sink/observations.jsonl`; units `~/.config/systemd/user/`.

## Three-tier routine-check pattern

These scripts are **Tier 1** of the [[2026-04-30_three-tier-routine-check-pattern|three-tier pattern]]:

1. **Tier 1 — Firebat script** (canonical). `~/bin/<name>` on a `--user` timer. Zero tokens, honest exit codes, survives headless.
2. **Tier 2 — laptop script** (fallback). Same `~/bin/<name>` on the laptop, for when Firebat is unreachable.
3. **Tier 3 — LLM skill** (last resort). `~/.claude/skills/<name>/`. Each such skill's procedure begins with a "prefer the script" preamble that walks Tiers 1–2 first. When Tier 3 runs, it must diagnose *why* the scripts failed and patch them.

Hard rule (bitten 2026-04-30): **never run `claude -p` on a cron on this box** — permission gates and OAuth-gated MCP don't survive headless. Keep automation in pure Tier-1 scripts.

## When something breaks — first-look tree

1. Box alive? `ssh mork@mork-firebat 'uptime; df -h /; free -m'`. Can't SSH → try mDNS / direct-cable pathway. Status page stuck → box is down (hardware/network, not a script).
2. Timers healthy? `systemctl --user list-timers --all`. Anything `failed` or stuck `activating` → `journalctl --user -u <name> -n 50`.
3. Identities OK? `~/bin/firebat-identity-verify.py`. A FAIL points at the specific cred (AWS cert expired, gh PAT revoked, NR/Atlassian token rotated).
4. Caddy serving? `curl -fsS http://mork-firebat/logs/ | head` and `curl -fsS http://mork-firebat/app/api/healthz`.
5. Morning batch ran? `curl -fsS http://mork-firebat/logs/morning-prep-latest.summary.json | jq` — `date` should be today, each `exit_code` 0.
6. Per-script debugging (common errors + cred-rotation procedures) → [[2026-04-30_morning-prep-scripts-runbook]].

## Related

- [[2026-06-22_offboarding-plan]] — the re-home plan (WS-A identities, WS-D runbooks) this document satisfies.
- [[2026-04-30_morning-prep-scripts-runbook]] — per-script playbooks, common errors, cred-rotation step-by-step.
- [[2026-04-30_three-tier-routine-check-pattern]] — the architecture the Tier-1 scripts follow.
- `aegissystems/actuate-dev-toolkit` (`/home/mork/work/local_network_scripts`) — provisioning phases + deployed script/unit sources (source of truth).
