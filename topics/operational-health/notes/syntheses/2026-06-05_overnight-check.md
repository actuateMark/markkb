---
title: "FAILED: Overnight Check 2026-06-05"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, status-failed]
created: 2026-06-05
updated: 2026-06-05
author: kb-bot
status: failed
---

# FAILED: Overnight Check 2026-06-05

The automated overnight check failed at 2026-06-05T10:14:01-04:00.

- **Exit code:** 0
- **Host:** mork-ThinkPad-P14s-Gen-5
- **Expected output at:** `/home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/2026-06-05_overnight-check.md`
- **Validation:** stdout did not start with `---` frontmatter OR lacked a `title:` line.

## stderr (last 100 lines)

```

```

## stdout (last 50 lines)

```
**Not gathered.** Queries blocked. Flags unevaluated: per-site patrol counts (41158, 41178, 40672, 45061, 37837), autopatrol-server ERROR count, per-site CNCTNFAIL counts, connector-side `%autopatrol%` ERROR breakdown. See Raw NRQL for the exact queries to run manually.

## Connector Fleet

**Not gathered.** Query blocked. Per-container ERROR FACET (threshold >100) unevaluated.

## Alert Delivery

**Not gathered.** Query blocked. ERROR counts for queue-evalink-consumer, queue-eagle-eye-consumer, smtp-frame-receiver, cert-manager-webhook, clips-smtp-worker (threshold >20) unevaluated. (Canonical hyphenated names were used in the prepared query; underscore variants avoided.)

## New Issues

**Not gathered.** `NrAiIssue` / `list_recent_issues` query blocked. Count, severity distribution, and top-3-by-entity unevaluated.

## Raw NRQL

<details>
<summary>Queries prepared but not executed (run manually in an attended session / terminal)</summary>

```bash
# --- AutoPatrol ---

# 1. Patrol counts per site
python3 ~/.claude/lib/nr_query.py "SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND message LIKE '%patrol%' FACET cases(WHERE message LIKE '%41158%' AS '41158', WHERE message LIKE '%41178%' AS '41178', WHERE message LIKE '%40672%' AS '40672', WHERE message LIKE '%45061%' AS '45061', WHERE message LIKE '%37837%' AS '37837') SINCE 12 hours ago LIMIT 10"

# 2. Autopatrol-server error count
python3 ~/.claude/lib/nr_query.py "SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR' SINCE 12 hours ago"

# 3. CNCTNFAIL counts per site
python3 ~/.claude/lib/nr_query.py "SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%' FACET cases(WHERE message LIKE '%41158%' AS '41158', WHERE message LIKE '%41178%' AS '41178', WHERE message LIKE '%40672%' AS '40672', WHERE message LIKE '%45061%' AS '45061', WHERE message LIKE '%37837%' AS '37837') SINCE 12 hours ago LIMIT 10"

# 4. Connector-side autopatrol errors
python3 ~/.claude/lib/nr_query.py "SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR' FACET container_name SINCE 12 hours ago LIMIT 10"

# --- Connector Fleet ---
python3 ~/.claude/lib/nr_query.py "SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND level='ERROR' FACET container_name LIMIT 15 SINCE 12 hours ago"

# --- Alert Delivery ---
python3 ~/.claude/lib/nr_query.py "SELECT count(*) FROM Log WHERE cluster_name='Connector-EKS' AND level='ERROR' AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker') FACET container_name SINCE 12 hours ago LIMIT 10"

# --- New Issues ---
python3 ~/.claude/lib/nr_query.py "FROM NrAiIssue SELECT count(*) FACET priority WHERE event='open' SINCE 12 hours ago LIMIT 10"
python3 ~/.claude/lib/nr_query.py "FROM NrAiIssue SELECT latest(title), latest(entityName) FACET issueId, priority WHERE event='open' SINCE 12 hours ago LIMIT 10"
```

Account: 3421145. Cluster: Connector-EKS. Window: SINCE 12 hours ago.

</details>

## End
```

## Debug

- Full logs: `/home/mork/.local/state/overnight-check/`
- journalctl: `journalctl --user -u overnight-check.service --since '2 hours ago'`
- Manual rerun: `/home/mork/bin/overnight-check.sh`
