---
title: AP summary-disable — monitoring handoff (NR-auth-suspect incident signal)
author: kb-bot
created: 2026-05-27
updated: 2026-05-27
tags: [autopatrol, vms-connector, autopatrol-server, immix, monitoring, handoff, incident-maybe, new-relic-auth]
---

# AP summary-disable — monitoring handoff

Handoff from a long monitoring session (context got token-heavy). Picks up the [[2026-05-20_ap-summary-disable-plan|AP summary-send disable]] post-merge soak.

## TL;DR for the next session

1. **Re-verify [[new-relic|New Relic]] MCP auth FIRST.** The auth flow was broken at handoff time. The last "incident" numbers below are **UNVERIFIED** — they may be a NR-auth artifact (wrong/empty account, stale creds), not a real prod regression. Do **not** act on them until a clean authed query reproduces them.
2. If the failure signals are real, it's an Immix-side `end_patrol` **HTTP 400** rejection — see "The suspect signal" below.
3. The rollout itself (all PRs) is **complete and was clean for ~5 days** before this signal.

## Rollout state — COMPLETE

| Item | State |
|---|---|
| vms-connector #1709 (connector end_patrol + retry; feat → stage) | ✅ merged 2026-05-21 |
| vms-connector #1711 (stage → rearchitecture) | ✅ merged 2026-05-22 18:00 UTC (`8cd265c8f`) |
| autopatrol-server #28 (disable raise + keepalives + server end_patrol; → main) | ✅ merged 2026-05-21 |
| [[kubernetes-deployments]] #392 (prod autopatrol-server 0.1.25 → 0.1.26) | ✅ merged 2026-05-22 20:10 UTC; prod pod confirmed on `0.1.26` |

Prod fleet hit 100% new-code rollover within ~2.5h of the rearch merge. From 2026-05-22 through ~2026-05-26 the soak was **rock-solid**: `end_patrol succeeded` growing linearly, **zero** retry / raised / exhausted signals, SMTP FDMD warm-start firing, storage writes confirmed.

## The suspect signal (2026-05-27, NR auth was broken — TREAT AS UNVERIFIED)

Last poll before auth broke returned, over a 4h window on `cluster_name='Connector-EKS'`:

- `end_patrol succeeded`: ~26 (had been ~95-114 every prior cycle)
- `end_patrol attempt N/3 non-ok`: ~160 (had been **0** for 5 days)
- `end_patrol exhausted 3 attempts`: ~80 (had been **0** for 5 days)
- Exhausted log line: `end_patrol exhausted 3 attempts (last status=400); patrol may remain in STARTED on Immix`
- A 6h TIMESERIES showed the failures roughly **constant** across the window (~9-11 exhausted / 30 min), not a spike.

**If real**, this means Immix started rejecting `update_patrol(FINISHED)` with HTTP 400, ~80% of patrols failing to transition to FINISHED. Retries can't help a 400.

**Why it might be REAL:** the standing in-code caveat (`autopatrol-server/server/autopatrol_queue.py:122-128`, now commented out) warns that without a prior `raise_patrol_alert`, Immix's response to `update_patrol(Finished)` is bad. The connector calls `end_patrol` with no prior raise, and since #392 the server no longer raises either. **But** this condition has been true since 2026-05-22 20:10 and was CLEAN for 5 days — so a sudden onset on 05-27 points to an Immix-side change (the "Immix team is fixing on their side" work — possibly a deploy that regressed), not our code.

**Why it might be a NR-AUTH ARTIFACT:** auth was confirmed broken right after this poll. An unauthed/mis-scoped MCP session can return numbers from the wrong account or partial data. The clean-for-5-days→sudden-80%-failure shape is suspicious enough to demand re-verification.

## Next session checklist

1. **Fix NR MCP auth.** (Auth flow was failing; couldn't locate the re-auth recipe in KB. Check the newrelic MCP server config / token. The account id in use was `3421145`.)
2. **Re-run the core query** (authed):
   ```
   SELECT filter(count(*), WHERE message LIKE '%end_patrol succeeded%') AS success,
          filter(count(*), WHERE message LIKE '%end_patrol exhausted%') AS exhausted,
          filter(count(*), WHERE message LIKE '%end_patrol attempt%non-ok%') AS retry_non_ok
   FROM Log WHERE cluster_name = 'Connector-EKS'
     AND message LIKE '%end_patrol%' SINCE 4 hours ago
   ```
3. **If exhausted/non-ok are still high:** find onset via `... message LIKE '%end_patrol exhausted%' TIMESERIES 1 hour SINCE 48 hours ago`, correlate with any Immix-side deploy, and escalate to whoever owns the Immix integration. This is a real revenue/lifecycle signal (patrols stuck in STARTED).
4. **If they're 0:** the 05-27 numbers were a NR-auth artifact; resume the light heartbeat (or stop — the change is verified).

## Watch-loop mechanics (if continuing)

- Core health query + fleet image-tag breakdown:
  `SELECT uniqueCount(pod_name) FROM Log WHERE cluster_name='Connector-EKS' AND message LIKE '%starting patrol%' SINCE 4 hours ago FACET capture(container_image, r'.*:(?P<tag>[^:]+)$')`
- Baseline state file: `/tmp/local-test-stack/pr-watch-state.json`
- `empty_metrics_dict` is a **separate pre-existing admin-side issue** our PR #1712 merely surfaced (admin fix `fix/ap-empty-metrics-fallback` rolling out; count was declining 1984 → ~1300 before auth broke). Not connector-related.

## Cross-refs

- [[2026-05-20_ap-summary-disable-plan]] — full plan + transition-window analysis.
- [[autopatrol-server-deployment]] — deploy mechanism.
- [[2026-05-20_local-ap-e2e-stack-installed]] — local validation harness.
- [[feedback-cross-repo-transition-window-order]], [[feedback-audit-storage-writes-not-logs]] — methodology memories from this work.
