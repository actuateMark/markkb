---
title: "FAILED: Overnight Check 2026-06-09"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, status-failed]
created: 2026-06-09
updated: 2026-06-09
author: kb-bot
status: failed
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# FAILED: Overnight Check 2026-06-09

The automated [[automation-overnight-check|overnight check]] failed at 2026-06-09T09:45:38-04:00.

- **Exit code:** 0
- **Host:** mork-ThinkPad-P14s-Gen-5
- **Expected output at:** `/home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/2026-06-09_overnight-check.md`
- **Validation:** stdout did not start with `---` frontmatter OR lacked a `title:` line.

## stderr (last 100 lines)

```

```

## stdout (last 50 lines)

```
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago LIMIT 10
-- (if zero rows, drop the container_name filter and re-run)

-- 1b. autopatrol-server error count
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server' AND level='ERROR'
SINCE 12 hours ago

-- 1c. CNCTNFAIL per site
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name='autopatrol-server'
  AND message LIKE '%CNCTNFAIL%'
FACET cases(
  WHERE message LIKE '%41158%' AS '41158',
  WHERE message LIKE '%41178%' AS '41178',
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837')
SINCE 12 hours ago LIMIT 10

-- 1d. Connector-side autopatrol errors
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND container_name LIKE '%autopatrol%' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- 2. Connector fleet error counts
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- 3. Alert delivery error counts (canonical container names)
SELECT count(*) FROM Log
WHERE cluster_name='Connector-EKS' AND level='ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer',
                         'smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago

-- 4. NR Issues opened in window
FROM NrAiIssue SELECT count(*), latest(title), latest(entityName)
FACET issueId, priority SINCE 12 hours ago LIMIT 10
```

</details>

## End
```

## Debug

- Full logs: `/home/mork/.local/state/overnight-check/`
- journalctl: `journalctl --user -u overnight-check.service --since '2 hours ago'`
- Manual rerun: `/home/mork/bin/overnight-check.sh`
