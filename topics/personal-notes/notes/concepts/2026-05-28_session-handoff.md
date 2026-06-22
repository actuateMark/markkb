---
title: "Session handoff — 2026-05-28 pickup from 2026-05-27 EOD"
type: concept
topic: personal-notes
tags: [handoff, pyav17, vms-connector, admin-api, deploy-branch]
created: 2026-05-28
updated: 2026-05-28
author: kb-bot
outgoing:
  - topics/vms-connector/notes/syntheses/2026-05-26_pyav17-local-validation.md
  - topics/admin-api/notes/entities/admin-api-auth.md
  - topics/actuate-platform/notes/entities/branch-conventions.md
  - topics/personal-notes/notes/daily/2026-05-27.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/personal-notes/notes/daily/2026-05-28.md
  - topics/vms-connector/notes/syntheses/2026-05-28_per-frame-log-volume-stage-vs-rearch.md
incoming_updated: 2026-05-30
---

# Session handoff — 2026-05-28

Pickup state for a fresh session opened on the morning of 2026-05-28. Read this FIRST, then run `/daily-scope` to set today's picks.

## Entry point — read in this order

1. **This doc** (current state, blockers, decisions pending).
2. [[2026-05-27]] daily-note — what closed yesterday + the Notes/Learnings sections from the sibling sessions (brain-in-jar handoff, AP empty-metrics close-out).
3. [[2026-05-26_pyav17-local-validation]] — the PyAV-17 validation ladder + the lib's compat-shim migration.
4. [[admin-api-auth]] — how to drive prod admin API (token at `~/.config/actuate/admin_token`, route gotchas, kubectl image-verify recipe).
5. [[branch-conventions]] §"vms-connector: branch → ECR image → deployment fleet" — the **two-prod-fleet** topology + custom-branch tagging axis (the thing that bit the standup wording twice).

## In-flight thread 1 — PyAV-17 overnight soak (revert this morning)

**State:** 3 customers pinned to `featurepyav-17-bump-clean` overnight as of 2026-05-27:

| Cust ID | Container | Pre-phase (revert target) | Integration |
|---|---|---|---|
| **705** | `actuate-nyc-alibi-vigilant` | STAGE | [[rtsp-deep-dive|rtsp]] / [[h264-deep-dive|h264]] |
| **573** | `actuate-nyc-avigilon` | REARCH | avigilon / [[h264-deep-dive|h264]] |
| **1751** | `actuate-nyc-genetec` | REARCH | genetec / [[h264-deep-dive|h264]] |

All three were kubectl-confirmed running the feature image at end of session 2026-05-27. The TTL on each is `2026-05-28T17:47-20:50Z` but it **will NOT auto-revert** — the `expire_custom_branches` cron is unbuilt (tracked as task #8).

### Today's concrete actions for the soak

**1. Per-site overnight verdict** — query NR for each container, window `SINCE 14 hours ago` (or since the per-site START time):
- av/[[pyav-entity|PyAV]] exception count (target: 0). Patterns: `FFmpegError`, `AVError`, `av.error`, `skip_frame`, `Traceback.*actuate_pullers`.
- CrashLoopBackOff / OOMKilled count (target: 0).
- Reconnect rate (`broken stream, restarting`) — comparable to pre-deploy baseline; pre-existing flakiness on cam01 of 705 is acceptable.
- Decode FPS / pipeline FPS samples — healthy / steady.
- Verdict per site: CLEAN / DEGRADED / CRASHED.

NR is reachable via `~/.claude/lib/nr_query.py` (NerdGraph + User API key) — DO NOT chase the broken NR MCP OAuth (proxy hangs, see 2026-05-27 daily note "Tooling finding"). Standing NR query rules apply: scope to `container_name`, tight time windows, aggregate first.

**2. Revert each to prior phase** — for each of the 3 customer IDs:

```bash
TOKEN=$(cat ~/.config/actuate/admin_token)
for id in 705 573 1751; do
  curl -fsS -X POST -H "Authorization: Token $TOKEN" -H "Content-Type: application/json" \
    -d '{"reason":"PyAV-17 soak revert — overnight verdict clean"}' \
    "https://admin.actuateui.net/api/customer/$id/revert_branch/" | python3 -m json.tool
done
```

Then verify each pod rolled back via kubectl:

```bash
for app in actuate-nyc-alibi-vigilant actuate-nyc-avigilon actuate-nyc-genetec; do
  echo "=== $app ==="
  kubectl get pods -n rearchitecture -l app=$app \
    -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.metadata.labels.deployment_phase,START:.status.startTime,STATUS:.status.phase
done
```

Expect IMAGE → `arm_connector_rearch:latest` (or `:stage` for 705 if STAGE→rearch image diff applies; the PHASE label should match `pre_custom_deployment_phase` from `branch_status`).

**3. Update PRs #358 (actuate-libraries) + #1714 (vms-connector) with the verdict** — task #6. If all 3 sites clean: post a per-site results table as a comment to each draft PR and consider moving them draft → Ready-for-Review. The [[h265-hevc-deep-dive|HEVC]] headline ([[ffmpeg-entity|FFmpeg]] 8.0 NALU rejection) is still untested locally — that's the AmeriGas-clone work (task #7 deferred portion).

### Why these 3 sites

- All Actuate-owned (safe to flip).
- Integration diversity: [[rtsp-deep-dive|rtsp]] + avigilon + genetec → exercises distinct puller code paths under av17.
- All [[h264-deep-dive|h264]] — the **[[h265-hevc-deep-dive|HEVC]] corruption test** (the headline #1703 benefit) is **NOT covered**; gated on the AmeriGas-clone sub-project (task #7 description has the design).

## In-flight thread 2 — PR #1713 → prod (blocked on REVIEW_REQUIRED)

**State:** vms-connector PR [#1713](https://github.com/aegissystems/vms-connector/pull/1713) (`stage → rearchitecture`) carries the modelz-cache thread-safety fix (`actuate-classic-inference-client 2.4.4` — fixes live `connector-39138/INDUSUR` pipeline-corruption incident) + BlacklistFilter decay opt-in. MERGEABLE but **BLOCKED on `reviewDecision: REVIEW_REQUIRED`**.

**Today's action:** ping the relevant reviewer (Jacob or whoever owns vms-connector rearch promotions). Once approved + at-merge time: **strip the `📦 Update library changes report` auto-bot commit line from the squash body** (CI-skip token hazard per CLAUDE.md — aborts all rearch workflows if it lands).

**Squash subject** (preserve verbatim):
```
stage → rearchitecture: blacklist decay opt-in + modelz cache lock [patch:vms-connector]
```

**Merge command shape** (per the PR body's at-merge recipe):
```bash
gh pr merge 1713 --repo aegissystems/vms-connector --squash \
  --subject "stage → rearchitecture: blacklist decay opt-in + modelz cache lock [patch:vms-connector]" \
  --body-file <stripped-body>
```

Merging to `rearchitecture` ships `arm_connector_rearch:latest` → the rearch **PROD** fleet (per [[branch-conventions]] — not pre-prod). [[watch-entity|Watch]] deploy + NR for `connector-39138` regression post-merge.

## In-flight thread 3 — PRs #358 + #1714 (PyAV-17 release train)

Both are **DRAFT**. Don't merge them until the soak verdict is in.

- **actuate-libraries [#358](https://github.com/aegissystems/actuate-libraries/pull/358)** (`feat/actuate-pullers-pyav17-api` → `main`) — compat-shim migration: `_AvError` alias + `_SKIP_DEFAULT`/`_SKIP_NONKEY` try/except shim. Version 1.17.19 → **1.17.20**. CI all green; dev wheel published as `actuate-pullers==1.17.21.dev1+feat.actuate.pullers.pyav17.api`. Merging to main auto-publishes 1.17.20 stable — **do not merge without explicit Mark go** (CLAUDE.md rule).
- **vms-connector [#1714](https://github.com/aegissystems/vms-connector/pull/1714)** (`feature/pyav-17-bump-clean` → `stage`) — pins av 13→17 + the dev wheel. ECR image `featurepyav-17-bump-clean` already pushed.

Order on Ready: #358 marks Ready → reviewed → squash-merge with `[patch:actuate-pullers]` → stable publishes → #1714 swaps dev pin to `==1.17.20` stable → marks Ready → merges to stage → eventually stage → rearchitecture.

## Other open carry-over (lower urgency)

- **Decide PR #91 → prod** (actuate-inference-api) — reviewed + 14/14 live-verify on dev; **decision still held** since 2026-05-22. Just needs a go/hold call + button click.
- **Autopatrol_onboarder PRs #14 / #15 / #16** — sibling-session PRs, all MERGEABLE, awaiting review-and-merge.
- **§3 cleanup-Lambda state-matrix verify** — rolled exec from 2026-05-07.

## Tasks created yesterday (follow-up work, not urgent today)

- **Task #6** — Update PRs #358 + #1714 with overnight soak results (resolved by Thread 1 step 3 above).
- **Task #8** — Build `expire_custom_branches` auto-revert cron. Real `actuate_admin` dev task; needs review + release flow; would mean future soaks self-revert. Worth doing this week so the next soak doesn't need a manual-revert seed.
- **Task #9** — Add `container_name` + `deployment_id` filters to `CustomerFilter` (`api/serializers/site/customer_view.py`). Small fix. Would let scripts resolve customer PKs without needing a human admin-UI lookup (which was needed yesterday for 573/1751).

## Deferred to a focused future session

- **AmeriGas-clone [[h265-hevc-deep-dive|HEVC]] member of the soak** (task #7 description) — the headline-benefit test. Needs careful design: no clean copy-customer API; alert-disable via `live_alert=False` per stream; ⚠️ live-camera-contention risk if the clone pulls AmeriGas's live [[rtsp-deep-dive|RTSP]] streams (could disrupt the real customer). Recorded-footage path is the safer route. Not for a tail-of-session start.

## Gotchas / tooling state

- **Token at `~/.config/actuate/admin_token`** (chmod 600). Read inline as `$(cat …)` so the value never prints. Belongs to Mark's user; audit rows attribute correctly.
- **kubectl context** — current is `inference-eks-us` (cluster `inference-eks-Ny9n`). The connector fleet lives in this cluster's `rearchitecture` namespace (~5.7k pods). NR labels it `cluster_name = Connector-EKS` — same thing. The connector fleet is **not in a separate AWS account** (lesson learned 2026-05-27); just run kubectl directly.
- **`reboot_connector` short-circuit** gates on `settings.STAGE != "prod"` (the **admin server's env**, NOT the customer's deployment_phase). Prod admin = `settings.STAGE==prod` → real reboots fire even for STAGE-phase customers.
- **NR MCP OAuth is broken** — use `~/.claude/lib/nr_query.py` bypass (NerdGraph + User API key). See 2026-05-27 daily note "Tooling finding" for full diagnosis.
- **CI-skip-token hazard** — `📦 Update library changes report` auto-bot commits embed CI-skip markers that abort all rearch workflows if they land in a squash body. Strip them at merge time (recurring incident — see `feedback-ci-skip-tokens-anywhere`).
- **vms-connector `stage` working tree** carries untracked scratch (CSVs, scripts) on Mark's checkout — non-blocking, sibling-session debris.

## Resumption checklist

- [ ] Read this doc + the entry-point chain above.
- [ ] Run `/daily-scope` for 2026-05-28 — the Morning Follow-Ups already name the 3-site revert + verdict.
- [ ] Per-site NR overnight verdict (Thread 1 step 1).
- [ ] Revert + kubectl-verify the 3 sites (Thread 1 step 2).
- [ ] Post verdict comments on PRs #358 + #1714 (Thread 1 step 3 / task #6).
- [ ] Ping a reviewer on PR #1713 (Thread 2).

## Cross-refs

- [[2026-05-27]] — yesterday's daily note (Closed Line Items + sibling-session Notes/Learnings)
- [[2026-05-26_pyav17-local-validation]] — local 4-tier validation + the SkipType finding
- [[admin-api-auth]] — prod [[admin-api-auth|admin API auth]] + verify-image kubectl recipe
- [[branch-conventions]] — branch→ECR→fleet map; the two-prod-fleet truth
- [[feedback-rearch-is-a-prod-fleet]] — auto-loaded memory; prevents the misclassification
- [[mark-todos]] §29 (custom-branch lifecycle), §30 ([[pyav-entity|PyAV]] release train), §3 (cleanup-Lambda)
- Tasks #6 / #7 / #8 / #9 (in-session TaskList) — open follow-ups
- vms-connector #1703 (proposal), #1713 (blacklist decay → rearch), #1714 ([[pyav-entity|PyAV]] connector PR)
- actuate-libraries #358 ([[pyav-entity|PyAV]] lib PR)
- actuate-inference-api #91 (held)
