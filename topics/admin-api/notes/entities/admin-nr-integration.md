---
title: "Admin API: New Relic Integration"
type: entity
topic: admin-api
tags: [admin-api, new-relic, nerdgraph, deep-links, monitoring]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Admin API: New Relic Integration

The [[admin-api]] already has NR integration code for generating log links and chart images.

## Files

### `inframap/connector/connector_logs_link.py`
Generates NR logger URLs for connector sites. **Currently uses the broken `/logger?query=` format** -- should be updated to use `/nrql-editor?query=` per [[nr-programmatic-deep-links]].

### `inframap/connector/newrelic.py`
NerdGraph GraphQL client. Implements `get_chart(nrql)` which calls NerdGraph `staticChartUrl` API to generate PNG chart images from NRQL queries. Used for embedding charts in admin pages and Slack notifications.

### `inframap/sites/customer/customer_menu.py`
Contains `onenr.io` short codes for static NR dashboards:
- AI Link logs, motion charts, deployment dashboards, K8s cluster view
- These are manually created via NR "Share" button, not programmatic

## Known Issue

`connector_logs_link.py` generates `/logger?query=` URLs which NR redirects and strips. The query parameter is lost, resulting in an unfiltered log view. **Fix: switch to `/nrql-editor?query=` format.**

## Related

- [[nr-programmatic-deep-links]] -- working URL formats
- [[new-relic]] -- NR topic overview
