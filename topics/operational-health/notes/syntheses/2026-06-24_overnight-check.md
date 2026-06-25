---
title: "FAILED: Overnight Check 2026-06-24"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, status-failed]
created: 2026-06-24
updated: 2026-06-24
author: kb-bot
status: failed
---

# FAILED: Overnight Check 2026-06-24

The automated [[automation-overnight-check|overnight check]] failed at 2026-06-24T10:59:58-04:00.

- **Exit code:** 0
- **Host:** mork-ThinkPad-P14s-Gen-5
- **Expected output at:** `/home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/2026-06-24_overnight-check.md`
- **Validation:** stdout did not start with `---` frontmatter OR lacked a `title:` line.

## stderr (last 100 lines)

```

```

## stdout (last 50 lines)

```
WHERE cluster_name = 'Connector-EKS'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%' OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET CASES(
  WHERE message LIKE '%41158%' AS 'site_41158',
  WHERE message LIKE '%41178%' AS 'site_41178',
  WHERE message LIKE '%40672%' AS 'site_40672',
  WHERE message LIKE '%45061%' AS 'site_45061',
  WHERE message LIKE '%37837%' AS 'site_37837')
SINCE 12 hours ago LIMIT 10

-- 2. AutoPatrol — autopatrol-server error count
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS' AND container_name = 'autopatrol-server' AND level = 'ERROR'
SINCE 12 hours ago

-- 3. AutoPatrol — CNCTNFAIL per site
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS' AND message LIKE '%CNCTNFAIL%'
  AND (message LIKE '%41158%' OR message LIKE '%41178%' OR message LIKE '%40672%' OR message LIKE '%45061%' OR message LIKE '%37837%')
FACET CASES(
  WHERE message LIKE '%41158%' AS 'site_41158',
  WHERE message LIKE '%41178%' AS 'site_41178',
  WHERE message LIKE '%40672%' AS 'site_40672',
  WHERE message LIKE '%45061%' AS 'site_45061',
  WHERE message LIKE '%37837%' AS 'site_37837')
SINCE 12 hours ago LIMIT 10

-- 4. AutoPatrol — connector-side autopatrol errors by container
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS' AND container_name LIKE '%autopatrol%' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

-- 5. Connector fleet — overnight error counts
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

-- 6. Alert delivery — canonical containers
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago

-- 7. New Relic issues opened
FROM NrAiIssue SELECT count(*) FACET priority SINCE 12 hours ago LIMIT 10
```

</details>

## End
```

## Debug

- Full logs: `/home/mork/.local/state/overnight-check/`
- journalctl: `journalctl --user -u overnight-check.service --since '2 hours ago'`
- Manual rerun: `/home/mork/bin/overnight-check.sh`
