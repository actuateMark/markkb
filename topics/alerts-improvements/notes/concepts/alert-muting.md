---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [alerts, muting, scheduling, permissions, stalled]
---

# Alert Muting

Alert muting is a planned feature within [[alerts-improvements]] that would allow operators to suppress alerts from specific cameras, zones, or alert types for defined time periods. Despite being a fundamental operational need, the feature is currently stalled with most implementation work unassigned.

## Why Muting Matters

Without muting, operators face an all-or-nothing choice: receive every alert or disable alerting entirely. In practice, there are many legitimate reasons to temporarily suppress alerts:

- **Scheduled maintenance** -- technicians working on or near cameras generate expected activity
- **Known events** -- a delivery window, construction work, or a planned gathering
- **Testing** -- deploying new cameras or adjusting detection settings produces expected false positives
- **Nuisance suppression** -- a camera with a known false positive source that has not yet been fixed with ignore zones

Without structured muting, operators resort to workarounds: ignoring alerts (which trains them to ignore real ones), disabling cameras (which creates coverage gaps), or flooding support with complaints.

## Planned Capabilities

### Scheduled Muting (AIM-7)
Mute alerts according to a recurring schedule. This handles predictable events: mute the loading dock camera from 6-8 AM every weekday for deliveries. Scheduled muting is the highest-value variant because it is set-once and solves the problem permanently for recurring events.

### On-Demand Muting (AIM-6)
A "Mute Alerts" configuration option (labelled REQFE -- requires frontend) that allows operators to mute a camera or alert type immediately for a specified duration. This handles ad-hoc situations: "mute this camera for 2 hours while the contractor is here."

### Permission Controls (AIM-13)
Enhanced user permissions to control who can mute alerts. This is critical in multi-operator environments -- a junior operator should not be able to silence critical alerts site-wide. Permission tiers would likely include:
- Which users can mute
- Maximum mute duration per role
- Which alert severity levels can be muted (perhaps CRITICAL alerts cannot be muted without supervisor approval)

### Immix Integration (AIM-91)
Receiving alarm schedule signals from Immix (assigned to Jessica Bae). This would allow muting to be synchronised with the monitoring center's schedule -- if Immix knows a site is in a maintenance window, that signal could automatically suppress alerts in Actuate's system.

## Current Status: Stalled

The Alerts Improvements project has 29 open issues with 25 unassigned. Alert muting is tracked in two places:

**AIM project:**
- AIM-7 (Scheduled alert muting) -- To Do, unassigned
- AIM-6 (Mute Alerts configuration) -- To Do, unassigned

**ED project:**
- ED-12 (Alert Muting parent) -- In Progress, assigned to Jessica Bae
- ED-27, ED-28, ED-30, ED-31 (implementation subtasks) -- all unassigned

The split tracking across AIM and ED projects, combined with the lack of assignees on implementation tickets, suggests this feature has been planned but not prioritised for active development. It is the least actively staffed H1.x initiative.

## Relationship to Watchman

Alert muting becomes even more important in [[watchman]]'s context, where the [[multi-agent-architecture|Escalation Agent]] can trigger phone calls and SMS. A false-positive-driven phone call at 3 AM would be significantly more disruptive than a false positive email. Watchman's escalation tiers (CRITICAL with phone call, HIGH with SMS) make robust muting capabilities a prerequisite for production deployment.
