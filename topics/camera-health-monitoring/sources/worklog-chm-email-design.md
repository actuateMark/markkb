---
title: "Source: CHM Email Consolidation and Severity Design"
type: source
topic: camera-health-monitoring
tags: [worklog, email, alerts, severity, notification-design]
ingested: 2026-04-14
author: kb-bot
---

# CHM Email Consolidation and Severity Design

Detailed worklog notes on how CHM email notifications should be structured, including consolidation logic, severity tiers, and a full email template.

## Consolidation Logic

Emails are consolidated on a per-CHM-run basis. Even if only one camera's status changes, the email summarizes the health of the entire site. The trigger for sending an email is a **status change** -- runs that return no errors do not generate emails. This prevents alert fatigue from stable-healthy sites.

## Severity Influence

Alert severity affects email behavior. Status changes to low-priority alerts (image quality, stream quality) should not trigger emails on their own. Only the check types with email addresses configured in CHM settings will receive instant notifications. The notes question whether email fields for stream and image quality should be removed entirely, since these are low-priority and should not trigger standalone alerts.

## Example Flow

- 10:00 AM: 3 new issues (1 low priority) -- 1 consolidated email with all 3 issues
- 11:00 AM: 2 issues persist, low priority resolves -- No email (no status change on high-priority items)
- 12:00 PM: 1 resolved, 1 persists -- 1 email covering the 2 issues (1 resolved, 1 ongoing)
- 1:00 PM: 1 persists -- No email (no change)

## Email Template

Subject format: `Health Check Results - [Site name] - [x] Issues Detected`

Body includes: site name, check timestamp, overall health score percentage, comparison to previous check, new issues grouped by priority (high/medium/low with color coding), resolved issues, total active issues, next check time, and a dashboard link.

Priority tiers: HIGH (connection lost), MEDIUM (scene change), LOW (video quality).

## See Also

- [[health-check-types]] -- the checks that generate these alerts
- [[healthcheck-architecture]] -- system context
