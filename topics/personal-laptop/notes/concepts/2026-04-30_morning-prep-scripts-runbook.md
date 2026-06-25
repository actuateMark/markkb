---
title: "Morning-prep scripts — operations runbook"
type: concept
topic: personal-laptop
tags: [runbook, ops, firebat, morning-prep, scripts, repo-scan, jira-sync, autopatrol, pr-review-digest, three-tier, new-relic]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
outgoing:
  - topics/engineering-process/notes/syntheses/2026-04-30_three-tier-routine-check-pattern.md
  - topics/personal-laptop/notes/syntheses/2026-04-30_firebat-script-conversion-candidates.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - home/offboarding/2026-06-23_firebat-dashboard-ownership-handoff.md
  - home/offboarding/2026-06-23_local-repo-audit.md
  - home/operations/2026-06-22_firebat-operations-runbook.md
  - topics/engineering-process/notes/syntheses/2026-04-30_three-tier-routine-check-pattern.md
  - topics/personal-laptop/notes/syntheses/2026-04-30_firebat-script-conversion-candidates.md
incoming_updated: 2026-06-25
---

# Morning-prep scripts — operations runbook

Operational reference for the pure-Python scripts that pre-compute morning-routine data on the Firebat (`mork-firebat`). All scripts follow the [[2026-04-30_three-tier-routine-check-pattern|three-tier routine check pattern]] (Firebat → laptop → LLM-fallback). The corresponding skill SKILL.mds (`/repo-scan`, `/autopatrol-cleanup-lambda-check`) carry a Step 0 preamble that delegates to these scripts.

**Audience:** future-me at the kitchen table when something broke at 6am, or a future Claude session running Tier-3 LLM fallback that has to diagnose why Tier 1/2 went silent.

## Script inventory

| Script | Cadence | Source of truth | Tier 1 host | Tier 2 host |
|---|---|---|---|---|
| `repo-scan` | morning-prep batch (Mon-Fri 06:00 ET) | `/home/mork/work/local_network_scripts/files/repo-scan.sh` | Firebat `~/bin/repo-scan` | Laptop `~/bin/repo-scan` |
| `autopatrol-cleanup-check` | morning-prep batch | `.../files/autopatrol-cleanup-check.sh` | Firebat `~/bin/autopatrol-cleanup-check` | Laptop `~/bin/autopatrol-cleanup-check` (not yet installed) |
| `autopatrol-overnight-check` | morning-prep batch | `.../files/autopatrol-overnight-check.sh` | Firebat `~/bin/autopatrol-overnight-check` | Laptop install on demand |
| `jira-sync.sh` | daily 06:30 ET (Firebat), 10:37 ET (laptop) | `.../files/jira-sync.sh` | Firebat `~/bin/jira-sync.sh` | Laptop `~/bin/jira-sync.sh` |
| `pr-review-digest` | hourly + boot (Firebat), on-demand (laptop) | `.../files/pr-review-digest.sh` | Firebat `~/bin/pr-review-digest` | Laptop `~/bin/pr-review-digest` |
| `morning-prep.sh` | Mon-Fri 06:00 ET (Firebat) | `.../files/morning-prep.sh` | Firebat `~/bin/morning-prep.sh` | n/a — orchestrator only on Firebat |
| `run-dashboard-check.sh` | hourly + boot (Firebat) | `.../files/run-dashboard-check.sh` | Firebat `~/bin/run-dashboard-check.sh` | Laptop `/dashboard-check` skill (Tier 2 fallback) |

Deployment: edit the source-of-truth file under `/home/mork/work/local_network_scripts/files/`, then run `phase-13-tasks.sh` to push to Firebat. For laptop install, `cp` directly + `chmod 755`.

## Canonical paths

| What | Where |
|---|---|
| Script outputs (digests) | `~/.local/state/claude-jobs/<name>-<YYYY-MM-DD>.{stdout,stderr}` |
| Structured JSON | `~/.local/state/minipc-tasks/<topic>/<name>-<YYYY-MM-DD>.json` |
| Dashboard sink | `~/Documents/worklog/dashboard/sink/observations.jsonl` (component=code-health for repo-side, component=autopatrol-cleanup, etc.) |
| Caddy /logs/ | http://mork-firebat/logs/ — auto-exposes `~/.local/state/claude-jobs/` |
| Caddy /app/api/observations | http://mork-firebat/app/api/observations — dashboard sink as JSON |
| Caddy /app/repos/ | http://mork-firebat/app/repos/ — per-repo cards reading sink signals |
| morning-prep summary | `~/.local/state/claude-jobs/morning-prep-latest.summary.json` (symlink) |
| systemd unit dir | `~/.config/systemd/user/` |
| journal | `journalctl --user -u <unit>.service --since '24 hours ago'` |

## First-look diagnostic tree

When a routine looks broken in the morning, walk this tree top-down before any deep dive.

1. **Is the morning-prep batch run completed today?**
   ```
   curl -fsS http://mork-firebat/logs/morning-prep-latest.summary.json | jq
   ```
   - `date` matches today, `finished_at` populated → batch ran fine, individual sub-scripts OK to inspect
   - `date` is yesterday or older → batch didn't fire today; check Firebat power / tailnet / `systemctl --user status morning-prep.timer`
   - 404 / no response → Caddy or Firebat unreachable; SSH directly: `ssh mork@mork-firebat 'systemctl --user is-active morning-prep.timer'`

2. **Did each sub-script succeed?**
   - In the summary JSON: `skills.<name>.exit_code` should be `0`
   - Non-zero → drill into the per-script section below
   - `invoker: "script"` → the pure-Python ran (good); `invoker: "claude"` → still LLM-driven (autopatrol-overnight-check until conversion lands)

3. **Is the per-script digest readable?**
   ```
   curl -fsS "http://mork-firebat/logs/<name>-$(date +%F).stdout"
   ```
   - Empty / 404 → script didn't emit; check stderr at the same path with `.stderr`

4. **Are dashboard signals fresh?**
   ```
   curl -fsS "http://mork-firebat/app/api/observations" | jq '.summary.newest_observation, .summary.overall'
   ```
   - `newest_observation` >65 min old → dashboard-check is wedged; see "dashboard-check" section
   - `overall: red` → at least one signal is in red zone; see /app/repos/ or /dashboard/ for the offender

## Per-script playbooks

### repo-scan

Fetches open + closed-60d issues from 7 repos, scores via [[curate.py]], emits 9 dashboard sink signals.

**Manual run:**
```
~/bin/repo-scan                      # full run (KB writes + sink)
~/bin/repo-scan --no-kb              # skip curate.py (digest + sink only)
~/bin/repo-scan --no-sink            # skip dashboard sink (KB only)
~/bin/repo-scan --repos camera-ui    # subset of repos
```

**Common errors + fixes:**

| Error | Cause | Fix |
|---|---|---|
| `gh: command requires login` | gh PAT expired or not installed | `gh auth login` (laptop) or re-run phase-15-secrets.sh (Firebat) |
| `gh issue list: HTTP 401` | PAT revoked | regenerate PAT, update `~/.config/gh/hosts.yml` on both hosts |
| `curate.py not found` | curate path wrong (laptop) | check `~/.claude/skills/repo-scan/curate.py` exists; if not, sync from main repo |
| `closed60d=0` for active repo | not a bug — see [[2026-04-30_firebat-script-conversion-candidates]]; `gh issue list --state closed --search "closed:>=..."` returns nothing if no issues actually closed in window | none — real signal of "issues opened, never closed" |
| Sink writes "PARTIAL" | `~/Documents/worklog/dashboard/sink/observations.jsonl` not writable | `chmod 644` the sink, or `mkdir -p ~/Documents/worklog/dashboard/sink/` if the dir is missing |

**Where the data lands:**
- KB scan: `topics/repo-backlog/notes/scans/<YYYY-MM-DD>_scan.md`
- Per-repo catalogs: `topics/repo-backlog/notes/concepts/<repo>.md` (curated notes section is preserved)
- Sink: 9 signals tagged `source_skill=repo-scan`
- /app/repos/ leaderboard automatically incorporates the new signals

**LLM fallback (Tier 3):** the `/repo-scan` SKILL.md Step 0 preamble walks Tier 1 → Tier 2 → falls back to inline `gh issue list` orchestration. If Tier 3 is what's running, it has a diagnostic obligation (see [[2026-04-30_three-tier-routine-check-pattern]] § "Tier 3").

### autopatrol-cleanup-check

Pure-Python conversion of `/autopatrol-cleanup-lambda-check`. boto3 + nerdgraph, 10 parallel checks across Lambda / SQS / DDB / CloudWatch / NR / GH.

**Manual run:**
```
~/bin/autopatrol-cleanup-check          # default: stage env, with sink
~/bin/autopatrol-cleanup-check --no-sink
~/bin/autopatrol-cleanup-check prod     # once Step F lands
```

**Common errors + fixes:**

| Error | Cause | Fix |
|---|---|---|
| `AccessDeniedException: lambda:GetFunctionConfiguration` (or `dynamodb:Scan`, `logs:FilterLogEvents`, `sqs:GetQueueAttributes`) | IAM policy on `dashboard-check-rolesanywhere` missing the action | apply [[#IAM policy reset|IAM reset]] below; reference `local_network_scripts/files/iam-policy-autopatrol-cleanup-additions.json` |
| `AccessDeniedException: lambda:ListEventSourceMappings` despite being allowed | resource scoping mismatch — this action evaluates against event-source-mapping ARNs, not function ARNs | the policy must have `"Resource": "*"` for this one action (already encoded in v2 policy file) |
| `nerdgraph errors: ['NRDB query duration exceeded the set timeout']` | NRQL window too wide or pattern too greedy | tighten the query in the script (`SINCE 2 hours ago` instead of 24, drop `LIKE '%...%'`) |
| `nerdgraph errors: ['An error occurred resolving this field']` | NRQL syntax issue or missing schema | inspect `correlation_24h` query in the script; cross-check against working dashboard-check NRQL |
| `boto3 module not found` | not installed on Firebat | `ssh mork@mork-firebat 'pip3 install --user --break-system-packages boto3'` |
| Roles Anywhere: `KeyError: 'AccessKeyId'` | cert expired | inspect `/home/mork/.config/aws-rolesanywhere/mork-firebat.crt` — check expiry; reissue via Roles Anywhere console + replace cert+key files |

**Where the data lands:**
- Digest: `~/.local/state/claude-jobs/autopatrol-cleanup-lambda-check-<date>.stdout`
- JSON: `~/.local/state/minipc-tasks/autopatrol/cleanup-<date>.json`
- Sink: ~10 signals tagged `source_skill=autopatrol-cleanup-check`, `component=autopatrol-cleanup`

**Skill fallback:** [[skill-autopatrol-cleanup-lambda-check]] Step 0 preamble. References [[2026-04-20_cleanup-lambda-runbook]] for the deeper Lambda + SQS + DDB debugging procedures.

### autopatrol-overnight-check

NR-side autopatrol pipeline check. Pure-Python (boto3 not needed — only nerdgraph). 12-hour window covers overnight + early morning. Sites discovered dynamically via NRQL `capture()`.

**Manual run:**
```
~/bin/autopatrol-overnight-check          # default: with sink
~/bin/autopatrol-overnight-check --no-sink
```

**Common errors + fixes:**

| Error | Cause | Fix |
|---|---|---|
| `nerdgraph errors: NRDB query duration exceeded the set timeout` | NRQL window too wide or too many LIKEs | reduce `WINDOW` constant, drop redundant LIKE clauses, replace FACET cases() with single `capture()` FACET (current pattern) |
| `no patrol activity in window` (red) | autopatrol-server logging stopped → real outage OR log shipping broken | run `kubectl get pods -n rearchitecture \| grep autopatrol` from laptop |
| Sites show 0 patrols but pipeline shows messages | dynamic capture pattern doesn't match log format | inspect a sample log line: `python3 /tmp/probe.py "SELECT message FROM Log WHERE container_name = 'autopatrol-server' AND message LIKE '%Processing patrol_id%' SINCE 1 hour ago LIMIT 2"` and update `capture()` regex in the script |

**Where the data lands:**
- Digest: `~/.local/state/claude-jobs/autopatrol-overnight-check-<date>.stdout`
- JSON: `~/.local/state/minipc-tasks/autopatrol/overnight-<date>.json`
- Sink: 7+ signals tagged `source_skill=autopatrol-overnight-check`, `component=autopatrol-overnight`

**K8s checks DEFERRED.** The script doesn't run `kubectl get cronjobs` etc. — Firebat has no EKS access yet. If a site shows red, that's the trigger to run k8s commands from the laptop.

### jira-sync

Refreshes the auto-synced Jira queue section in [[mark-todos]]. Pure-Python (no LLM as of 2026-04-30 — see [[automation-jira-sync]]).

**Manual run:**
```
~/bin/jira-sync.sh                # honors idempotency (skip if synced today)
~/bin/jira-sync.sh --force        # rewrite section even if synced
~/bin/jira-sync.sh --dry-run --force   # render markdown to stdout, don't splice
```

**Common errors + fixes:**

| Error | Cause | Fix |
|---|---|---|
| `Atlassian creds not at ~/.config/atlassian/api-token` | creds file missing on this host | `scp ~/.config/atlassian/api-token mork@mork-firebat:.config/atlassian/api-token && chmod 600` |
| `urllib.error.HTTPError: 401` | API token revoked or rotated | regenerate Atlassian API token (id.atlassian.com → security → API tokens), update creds JSON on both hosts |
| `RuntimeError: AUTOSYNC sentinels not present in mark-todos.md` | someone removed `<!-- BEGIN-AUTOSYNC-JIRA -->` / `<!-- END-AUTOSYNC-JIRA -->` from the file | restore from `~/.local/state/jira-sync/mark-todos.<date>.bak` (7-day retention) |
| Section gets workstream-attribution to wrong § | `find_workstream_for_ticket` walks past the auto-sync section by mistake | check `BEGIN-AUTOSYNC-JIRA` is intact; the function stops at that sentinel |
| Daily `_jira-sync.md` failure note appearing in `topics/operational-health/notes/syntheses/` | run failed at the network or splice step | read the note's `## stderr (tail)` block; common causes covered above |

**Idempotency guard:** if mark-todos already shows `**Last synced:** TODAY` AND the section is well-formed, the script exits 0 without rewriting. Use `--force` to override.

**Manual recovery from corrupted mark-todos:**
```
cp ~/.local/state/jira-sync/mark-todos.<date>.bak \
   ~/Documents/worklog/knowledgebase/topics/personal-notes/notes/entities/mark-todos.md
```

### pr-review-digest

New (no prior LLM skill). Hourly digest of open PRs across 7 repos, scored by review-readiness + age + size.

**Manual run:**
```
~/bin/pr-review-digest             # full run with sink
~/bin/pr-review-digest --no-sink
~/bin/pr-review-digest --repos vms-connector,actuate-libraries
```

**Common errors + fixes:**

| Error | Cause | Fix |
|---|---|---|
| `gh pr list: HTTP 403` | rate-limited (rare with PAT) | wait 1 hour or check `~/.config/gh/hosts.yml` validity |
| All repos report 0 PRs but they exist | `gh` not finding `aegissystems` org | check `gh auth status` shows `Logged in to github.com account actuateMark` |
| Sink shows `repo_prs_*` keys with all-zero values | none of the repos have any open PRs (verify via `gh pr list`) | not an error — accurate state |
| Mark always shows 0 in `prs_pending_mark_review_count` even when expected | `reviewRequests` JSON shape might use `user.login` instead of `login` | inspect `gh pr view <N> --json reviewRequests` and verify the field path matches `score_review_priority()` |

**Where the data lands:**
- Digest: `~/.local/state/claude-jobs/pr-review-digest-<date>.stdout`
- JSON: `~/.local/state/minipc-tasks/pr-review/digest-<date>.json`
- Sink: 4 signals tagged `source_skill=pr-review-digest`, `component=code-health`
- /app/repos/ per-repo cards display them inline; leaderboard ranks repos by pending-Mark count

**No skill fallback.** This is script-only by design — there's no `/pr-review-digest` SKILL.md. Failures surface in the daily note's `## Notes / Learnings` per the [[2026-04-30_three-tier-routine-check-pattern]] anti-pattern guidance.

### morning-prep.sh (orchestrator)

Sequential runner for the morning batch. Lives only on Firebat — no laptop equivalent.

**Manual run:**
```
ssh mork@mork-firebat 'systemctl --user start morning-prep.service'
ssh mork@mork-firebat '~/bin/morning-prep.sh'   # direct invocation, bypasses systemd
```

**Common errors + fixes:**

| Error | Cause | Fix |
|---|---|---|
| Service shows `activating` for >30 min | sub-script hung (LLM tier hit a permission gate) | `systemctl --user stop morning-prep.service`; investigate the running sub-script via `pgrep -af claude-run-skill` |
| `summary.json.tmp` left behind | crash mid-batch | safe to delete; next run rebuilds; investigate via `~/.local/state/claude-jobs/morning-prep-<date>.stderr` |
| All sub-scripts exit 0 but content looks like "blocked" — see autopatrol failures of 2026-04-30 | LLM-fallback was triggered in headless mode without permission allowlists | per [[2026-04-30_three-tier-routine-check-pattern]] anti-pattern: don't put LLM on the box. Convert to Tier 1 script. |

### run-dashboard-check.sh

De-LLM operational dashboard. Already a pure script as of 2026-04-27. Hourly + boot.

**Manual run:**
```
ssh mork@mork-firebat '~/bin/run-dashboard-check.sh'
```

**Common errors + fixes:**

| Error | Cause | Fix |
|---|---|---|
| AWS Roles Anywhere fails | cert / key in `~/.config/aws-rolesanywhere/` expired | reissue + replace |
| NR API key missing | `~/.config/newrelic/key` not present | copy from laptop's `~/.config/newrelic/key` (read it once, scp over, `chmod 600`) |
| Render exit code 1 (yellow) or 2 (red) | dashboard-check classifies signals as yellow/red — not a bug | open http://mork-firebat/dashboard/ to see which signal flipped |

## Cross-cutting recovery procedures

### IAM policy reset

If multiple AWS calls fail with `AccessDeniedException`:

1. Inspect the role's current policies:
   ```
   AWS_PROFILE=prod aws iam list-role-policies --role-name dashboard-check-rolesanywhere
   AWS_PROFILE=prod aws iam get-role-policy \
     --role-name dashboard-check-rolesanywhere \
     --policy-name autopatrol-cleanup-readonly | jq .PolicyDocument
   ```
2. Compare against canonical: `local_network_scripts/files/iam-policy-autopatrol-cleanup-additions.json` (v2+).
3. Replace the inline policy via Console or:
   ```
   jq 'del(.Comment)' /home/mork/work/local_network_scripts/files/iam-policy-autopatrol-cleanup-additions.json > /tmp/policy.json
   AWS_PROFILE=prod aws iam put-role-policy \
     --role-name dashboard-check-rolesanywhere \
     --policy-name autopatrol-cleanup-readonly \
     --policy-document file:///tmp/policy.json
   ```
4. Wait ~60s for STS cache eviction, re-run the script.

### NR API key rotation

The Firebat reads NR API key from `~/.config/newrelic/key` and account ID from `~/.config/newrelic/account_id`. To rotate:

1. New API key from one.newrelic.com → user menu → API keys → create User key.
2. Replace the file on Firebat: `ssh mork@mork-firebat 'echo "NEW_KEY" > ~/.config/newrelic/key && chmod 600 ~/.config/newrelic/key'`
3. Verify: `ssh mork@mork-firebat '~/bin/run-dashboard-check.sh' | tail -5` — sink should accept new observations.

The NR account ID is `3421145` and rarely changes — if you rotate it, also update any hardcoded references in scripts (use `grep -r 3421145 ~/bin/`).

### Atlassian API token rotation

1. Generate at id.atlassian.com → Security → API tokens → Create. Copy the token immediately (only shown once).
2. Update `~/.config/atlassian/api-token` JSON: `{"email": "mark@actuate.ai", "token": "...", "site": "https://aegistechinc.atlassian.net"}`.
3. Replicate to Firebat: `scp ~/.config/atlassian/api-token mork@mork-firebat:.config/atlassian/api-token; ssh mork@mork-firebat 'chmod 600 ~/.config/atlassian/api-token'`.
4. Force a sync to verify: `~/bin/jira-sync.sh --force --dry-run` (dry-run to avoid clobbering today's section if it's already correct).

### Roles Anywhere cert/key reissue

Cert at `~/.config/aws-rolesanywhere/mork-firebat.crt` (laptop has its own pair). Default validity ~1 year.

1. Check expiry: `openssl x509 -in ~/.config/aws-rolesanywhere/mork-firebat.crt -noout -dates`
2. If <30 days, reissue via:
   - AWS Console → IAM → Roles Anywhere → trust anchor `328fdc80-23db-4256-a248-ad62793811d0` → CRL/cert management.
   - Or use the locally-stored CSR procedure (KB note: not yet written; for now, do it manually in the console).
3. Replace `mork-firebat.crt` and `mork-firebat.key` on Firebat. Test: `AWS_PROFILE=dashboard-check aws sts get-caller-identity`.

### gh PAT rotation

1. Generate at github.com → Settings → Developer settings → Personal access tokens (classic). Scopes: `repo`, `read:org`, `read:project`.
2. On Firebat: `ssh mork@mork-firebat 'gh auth login --with-token <<< NEWTOKEN'` (interactive may be blocked — use the file method: edit `~/.config/gh/hosts.yml` directly, replacing the `oauth_token:` field).
3. Verify: `ssh mork@mork-firebat 'gh auth status'`.
4. If laptop also rotated: same procedure, hosts file is at `~/.config/gh/hosts.yml`.

## When everything is broken

The "operational rescue" sequence:

1. SSH the box and confirm it's alive: `ssh mork@mork-firebat 'uptime; df -h /; free -m'`. If you can't SSH at all, see [[firebat-minipc-access]] for the IPv6-direct-cable last-resort.
2. Confirm timers are not all dead: `systemctl --user list-timers --all --no-pager`. Anything stuck in "activating" or "failed" gets investigated.
3. Confirm Caddy serves: `curl -fsS http://localhost/logs/ | head` (from inside the box) or `curl -fsS http://mork-firebat/logs/` (from laptop).
4. If Caddy is fine but data is stale, walk the per-script section above for whichever is reporting wrong data.
5. If 1 fails, you have a hardware/network issue, not a script issue. The Firebat status-page at http://mork-firebat/ is regenerated every 30s — if it's stuck on an old timestamp the box is genuinely down.

## Related

- [[2026-04-30_three-tier-routine-check-pattern]] — the architectural rule these scripts follow
- [[2026-04-30_firebat-script-conversion-candidates]] — inventory + per-skill conversion notes
- [[2026-04-23_firebat-minipc-as-claude-dev-box]] — Firebat hardware + provisioning history
- [[2026-04-20_cleanup-lambda-runbook]] — deeper debug procedures for the cleanup Lambda itself (not this check script)
- [[automation-jira-sync]] — entity reference for jira-sync (cadence, sentinels, conversion notes)
- [[skill-repo-scan]] — Tier 3 SKILL.md for repo-scan (the canonical fallback chain)
- [[skill-autopatrol-cleanup-lambda-check]] — Tier 3 SKILL.md for cleanup-check
- [[skill-daily-scope]] — primary consumer of these scripts (Step 2b cache-first patterns)
- [[firebat-minipc-access]] — SSH credentials, IPv6 direct-cable recovery
