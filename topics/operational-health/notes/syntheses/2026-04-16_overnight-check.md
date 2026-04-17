---
title: "FAILED: Overnight Check 2026-04-16"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, automated, status-failed]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
status: failed
---

# FAILED: Overnight Check 2026-04-16

The automated overnight check failed at 2026-04-16T17:59:28-04:00.

- **Exit code:** 1
- **Host:** mork-ThinkPad-P14s-Gen-5
- **Expected output at:** `/home/mork/Documents/worklog/knowledgebase/topics/operational-health/notes/syntheses/2026-04-16_overnight-check.md`
- **Validation:** stdout did not start with `---` frontmatter OR lacked a `title:` line.

## stderr (last 100 lines)

```

```

## stdout (last 50 lines)

```
You've hit your limit · resets 9pm (America/New_York)
```

## Debug

- Full logs: `/home/mork/.local/state/overnight-check/`
- journalctl: `journalctl --user -u overnight-check.service --since '2 hours ago'`
- Manual rerun: `/home/mork/bin/overnight-check.sh`
