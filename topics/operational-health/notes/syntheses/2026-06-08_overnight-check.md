---
title: "FAILED: Overnight Check 2026-06-08"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, status-failed]
created: 2026-06-08
updated: 2026-06-08
author: kb-bot
status: failed
incoming:
  - No backlinks found.
incoming_updated: 2026-06-19
---

# FAILED: Overnight Check 2026-06-08

The automated [[automation-overnight-check|overnight check]] failed at 2026-06-08T10:06:05-04:00.

- **Exit code:** 0
- **Host:** mork-ThinkPad-P14s-Gen-5
- **Expected output at:** `/home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/2026-06-08_overnight-check.md`
- **Validation:** stdout did not start with `---` frontmatter OR lacked a `title:` line.

## stderr (last 100 lines)

```

```

## stdout (last 50 lines)

```
  WHERE message LIKE '%40672%' AS 'site_40672',
  WHERE message LIKE '%45061%' AS 'site_45061',
  WHERE message LIKE '%37837%' AS 'site_37837')
SINCE 12 hours ago LIMIT 10

# 1b. AutoPatrol-server error count
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS' AND container_name = 'autopatrol-server' AND level = 'ERROR'
SINCE 12 hours ago

# 1c. CNCTNFAIL counts per site
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS' AND message LIKE '%CNCTNFAIL%'
FACET cases(
  WHERE message LIKE '%41158%' AS 'site_41158',
  WHERE message LIKE '%41178%' AS 'site_41178',
  WHERE message LIKE '%40672%' AS 'site_40672',
  WHERE message LIKE '%45061%' AS 'site_45061',
  WHERE message LIKE '%37837%' AS 'site_37837')
SINCE 12 hours ago LIMIT 10

# 1d. Connector-side autopatrol errors
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS' AND container_name LIKE '%autopatrol%' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 10

# 2. Connector fleet error counts
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
FACET container_name SINCE 12 hours ago LIMIT 15

# 3. Alert delivery health
FROM Log SELECT count(*)
WHERE cluster_name = 'Connector-EKS' AND level = 'ERROR'
  AND container_name IN ('queue-evalink-consumer','queue-eagle-eye-consumer','smtp-frame-receiver','cert-manager-webhook','clips-smtp-worker')
FACET container_name SINCE 12 hours ago

# 4. NR Issues opened
FROM NrAiIssue SELECT count(*) SINCE 12 hours ago
FROM NrAiIssue SELECT count(*) FACET priority SINCE 12 hours ago LIMIT 10
FROM NrAiIssue SELECT count(*) FACET entityName SINCE 12 hours ago LIMIT 5
```

Manual CLI form (interactive session, approve when prompted):
```
python3 /home/mork/.claude/lib/nr_query.py "<query above>"
```
</details>

## End
```

## Debug

- Full logs: `/home/mork/.local/state/overnight-check/`
- journalctl: `journalctl --user -u overnight-check.service --since '2 hours ago'`
- Manual rerun: `/home/mork/bin/overnight-check.sh`
