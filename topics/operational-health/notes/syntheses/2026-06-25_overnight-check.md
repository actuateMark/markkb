---
title: "FAILED: Overnight Check 2026-06-25"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, status-failed]
created: 2026-06-25
updated: 2026-06-25
author: kb-bot
status: failed
---

# FAILED: Overnight Check 2026-06-25

The automated overnight check failed at 2026-06-25T10:13:21-04:00.

- **Exit code:** 0
- **Host:** mork-ThinkPad-P14s-Gen-5
- **Expected output at:** `/home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/2026-06-25_overnight-check.md`
- **Validation:** stdout did not start with `---` frontmatter OR lacked a `title:` line.

## stderr (last 100 lines)

```

```

## stdout (last 50 lines)

```
SINCE 12 hours ago
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837') LIMIT 10

-- 1b. AutoPatrol-server ERROR count
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- 1c. CNCTNFAIL counts per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND message LIKE '%CNCTNFAIL%'
SINCE 12 hours ago
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837') LIMIT 10

-- 1d. Connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 10

-- 2. Connector fleet overnight errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
SINCE 12 hours ago FACET container_name LIMIT 15

-- 3. Alert delivery health
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
SINCE 12 hours ago FACET container_name

-- 4. New NR Issues opened (last 12h)
FROM NrAiIssue SELECT count(*) FACET priority WHERE state='ACTIVATED' SINCE 12 hours ago LIMIT 10
FROM NrAiIssue SELECT title, priority, entityNames, conditionName, activatedAt WHERE state='ACTIVATED' SINCE 12 hours ago LIMIT 10
```

**Remediation for next run:** (a) ensure the `newrelic` MCP server is reachable/authenticated in the headless environment so `mcp__newrelic__execute_nrql_query` registers; or (b) add `Bash(python3 /home/mork/.claude/lib/nr_query.py *)` to the `permissions.allow` list in `~/.claude/settings.json` so the wrapper runs without an approval prompt in unattended sessions. The wrapper and API key are both present — only the permission/connection layer is missing.

</details>

## End
```

## Debug

- Full logs: `/home/mork/.local/state/overnight-check/`
- journalctl: `journalctl --user -u overnight-check.service --since '2 hours ago'`
- Manual rerun: `/home/mork/bin/overnight-check.sh`
