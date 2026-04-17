---
title: "Source: Healthcheck Setup Procedure"
type: source
topic: camera-health-monitoring
tags: [worklog, setup, onboarding, admin-ui]
ingested: 2026-04-14
author: kb-bot
---

# Healthcheck Setup Procedure

Worklog notes capturing the admin UI steps to enable healthcheck-only monitoring for a site.

## Steps

1. Set the site phase to **"rearchitecture"**.
2. Scroll to the bottom of the site configuration.
3. Select **"healthcheck only"** mode.
4. Enter a comma-separated list of **email addresses** for alert recipients.
5. Enter a comma-separated list of **cell phone numbers** for alert recipients.

## Context

This is a lightweight setup flow, reflecting that CHM can be deployed independently of the full VMS connector pipeline. The "healthcheck only" mode means the site runs no detection/alerting workload -- only periodic health monitoring. The rearchitecture phase requirement indicates this runs on the newer K8s-based infrastructure rather than the legacy deployment.

## See Also

- [[healthcheck-architecture]] -- full system design
- [[health-check-types]] -- what checks run after setup
