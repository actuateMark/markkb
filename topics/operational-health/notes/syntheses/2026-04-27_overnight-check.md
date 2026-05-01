---
title: "FAILED: Overnight Check 2026-04-27"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, status-failed]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
status: failed
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# FAILED: Overnight Check 2026-04-27

The automated [[automation-overnight-check|overnight check]] failed at 2026-04-27T08:14:19-04:00.

- **Exit code:** 0
- **Host:** mork-ThinkPad-P14s-Gen-5
- **Expected output at:** `/home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/2026-04-27_overnight-check.md`
- **Validation:** stdout did not start with `---` frontmatter OR lacked a `title:` line.

## stderr (last 100 lines)

```

```

## stdout (last 50 lines)

```
  WHERE message LIKE '%40672%' AS '40672',
  WHERE message LIKE '%45061%' AS '45061',
  WHERE message LIKE '%37837%' AS '37837'
) SINCE 12 hours ago
```

**Q4 — Connector-side autopatrol errors by container**
```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE '%autopatrol%'
  AND level = 'ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 10
```

**Q5 — Connector fleet ERROR hotspots**
```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND level = 'ERROR'
FACET container_name
SINCE 12 hours ago LIMIT 15
```

**Q6 — Alert delivery ERROR counts**
```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND level = 'ERROR'
  AND container_name IN (
    'queue-evalink-consumer',
    'queue-eagle-eye-consumer',
    'smtp-frame-receiver',
    'cert-manager-webhook',
    'clips-smtp-worker'
  )
FACET container_name
SINCE 12 hours ago
```

**Q7 — New NR Issues (use MCP tool, not NRQL)**
```
mcp__newrelic__list_recent_issues(accountId=3421145, since="12 hours ago")
```
Filter results to `openedAt >= now - 12h` before summarizing.

</details>

## End
```

## Debug

- Full logs: `/home/mork/.local/state/overnight-check/`
- journalctl: `journalctl --user -u overnight-check.service --since '2 hours ago'`
- Manual rerun: `/home/mork/bin/overnight-check.sh`
