---
title: "New Relic Programmatic Deep Links"
type: concept
topic: new-relic
tags: [new-relic, deep-links, urls, admin-integration, tooling]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# New Relic Programmatic Deep Links

How to construct URLs that link directly to filtered NR views. Useful for admin UI integration, Slack alerts, and debugging shortcuts.

## Account Info

- **Account ID:** 3421145
- **Cluster:** `Connector-EKS` (connector fleet)

## What Works and What Doesn't

**NR redirects ALL `one.newrelic.com` URLs through a state management layer** that replaces query parameters with opaque `state=` UUIDs. This means dynamic per-site deep links via URL params do NOT work for any NR UI path.

| Format | Status | Notes |
|--------|--------|-------|
| `/nrql-editor?account=X&query={nrql}` | **BROKEN** | Redirects through `/experience-switch?state=...` → `/nr1-core?state=...`, query param lost |
| `/logger?account=X&query={filter}` | **BROKEN** | Same redirect, query param lost |
| `/logger?account=X&duration={ms}` | **PARTIAL** | Duration may be honored but filter is not |
| `onenr.io/{code}` | **WORKS** | Short codes from NR "Share" button. Already in production. No programmatic API. |
| NerdGraph `staticChartUrl` | **WORKS** | Returns PNG image URL. Already implemented in admin. Not interactive. |
| NerdGraph dashboard creation | **WORKS** | Create dashboards programmatically, then link to stable dashboard URLs |

**Current admin production state** (`connector_logs_link.py` line 25): Uses `/logger?account=3421145&duration=1800000` with NO site filtering -- everyone lands on the same unfiltered logs page.

## The Core Problem

NR's SPA architecture intercepts all URL parameters and routes through an opaque state system. There is no stable URL format that passes a dynamic NRQL query to the UI. This is a known NR platform limitation.

## Format 1: onenr.io Short Codes (Only Working Interactive Links)

Short codes are the ONLY working method for interactive NR links. Created manually via NR UI "Share" button. No programmatic creation API exists.

Created manually via NR UI "Share" button. No programmatic API.

**Already in use in [[admin-api/_summary|Actuate Admin API]]** (`actuate_admin/inframap/sites/customer/customer_menu.py`):

| Short Code | Dashboard |
|------------|-----------|
| `onenr.io/0oQDWaDr5jy` | AI Link logs |
| `onenr.io/0oR80yXMaRG` | Motion chart |
| `onenr.io/0Zw0NrkdDjv` | AI Link deployment |
| `onenr.io/0VRVLxG1xQa` | [[sentinel-components|Sentinel]] deployment |
| `onenr.io/0Bj3yglpGwX` | K8s cluster dashboard |

**How to create new ones:** Open any NR view → click "Share" → "Get permalink" → copy the `onenr.io` URL.

**Limitation:** Cannot be created programmatically. Each is a manual one-time action. Good for static dashboards, not for per-site dynamic links.

## Format 3: NerdGraph staticChartUrl (Already Implemented)

Returns a PNG image URL of a chart. **Already implemented in admin codebase:**

```python
# actuate_admin/inframap/connector/newrelic.py
def get_chart(self, nrql: str):
    query = """
    {
        actor {
            account(id: 3421145) {
                nrql(query: "%s") {
                    staticChartUrl(chartType: LINE, format: PNG)
                }
            }
        }
    }
    """ % nrql
    result = self.graphql(query)
    return result["data"]["actor"]["account"]["nrql"]["staticChartUrl"]
```

**Use cases:** Embed charts in Slack alerts, email reports, admin dashboard tiles. Non-interactive but doesn't require NR login to view.

## Existing Admin Integration

The admin codebase already has NR link infrastructure:

| File | What It Does |
|------|-------------|
| `inframap/connector/connector_logs_link.py` | Generates NR logger URL (currently uses broken `/logger?query=` format -- should be updated) |
| `inframap/connector/newrelic.py` | NerdGraph GraphQL client with `staticChartUrl` |
| `inframap/sites/customer/customer_menu.py` | `onenr.io` short codes for dashboards |

**TODO:** Update `connector_logs_link.py` to use `/nrql-editor?query=` instead of `/logger?query=`.

## Viable Implementation Options

### Option A: NerdGraph Dashboard per Site (Best Interactive Option)

Use the NerdGraph API to **programmatically create NR dashboards** with pre-configured widgets. Each dashboard has a stable URL that doesn't get redirected.

```python
# Create a dashboard via NerdGraph
mutation = """
mutation {
  dashboardCreate(accountId: 3421145, dashboard: {
    name: "Site 35832 - Connector Health"
    pages: [{
      name: "Overview"
      widgets: [
        {
          title: "Log Levels (24h)"
          configuration: {
            line: {
              nrqlQueries: [{
                accountIds: [3421145]
                query: "SELECT count(*) FROM Log WHERE container_name LIKE 'connector-35832%' SINCE 24 hours ago FACET level TIMESERIES 1 hour"
              }]
            }
          }
        }
        {
          title: "Errors"
          configuration: {
            table: {
              nrqlQueries: [{
                accountIds: [3421145]
                query: "SELECT count(*) FROM Log WHERE container_name LIKE 'connector-35832%' AND level = 'ERROR' SINCE 24 hours ago FACET message LIMIT 20"
              }]
            }
          }
        }
      ]
    }]
  }) {
    entityResult { guid }
  }
}
```

The returned dashboard GUID gives a stable URL: `https://one.newrelic.com/dashboards/{guid}`

**Pros:** Interactive, stable URL, customizable widgets, NR handles the rendering.
**Cons:** Requires creating a dashboard per site (or a template dashboard with variables). Could create dashboard sprawl.

**Variant -- Dashboard with Variables:** NR dashboards support `{{variable}}` syntax for dynamic filtering. Create ONE template dashboard with a `site_id` variable, then link with the variable pre-filled.

### Option B: NerdGraph staticChartUrl (Already Implemented, Non-Interactive)

Already in production at `actuate_admin/inframap/connector/newrelic.py`. Returns a PNG image URL embeddable anywhere without NR login.

Best for: Slack alerts, email reports, admin page inline charts.

### Option C: Internal Redirect Service with Embedded NR iframes

Build a small authenticated web page that embeds NR charts via `staticChartUrl` PNGs or the NR embedded chart API. The internal page URL is the stable link.

```
https://tools.actuateui.net/site/35832/health
```

This page renders: NR chart images + links to the raw NRQL queries (copyable, users paste into NR manually) + key metrics.

**Pros:** Works without NR login for images, short URLs, full control over layout.
**Cons:** Static images unless you use NR's embed API (requires NR login for interactive embeds).

### Option D: Improve Existing Admin Code (Quickest Win)

`connector_logs_link.py` currently links to an unfiltered NR logs page. Even though we can't deep-link with a query, we can improve this by:

1. Adding the site's `container_name` to the link text so users know what to search for
2. Pre-populating the clipboard with a ready-to-paste NRQL query
3. Linking to a per-site NerdGraph chart image instead

```python
def get_logs_link(obj):
    if obj.use_new_relic:
        container = f"connector-{obj.connector_id}"
        nrql = f"container_name LIKE '{container}%'"
        url = "https://one.newrelic.com/logger?account=3421145&duration=1800000"
        return mark_safe(
            f'<a href="{url}" target="_blank">Logs</a> '
            f'<small>(filter: <code>{nrql}</code>)</small>'
        )
```

## Recommended Path

1. **Immediate:** Option D -- add filter hint text next to the existing NR link in admin
2. **Short-term:** Option B -- embed `staticChartUrl` health charts per site in admin pages (infra already exists)
3. **Medium-term:** Option A -- investigate NR dashboard variables for a single template dashboard filterable by site ID
4. **Research:** Check if NR's newer "Instant Observability" or "Service Levels" features offer better deep-linking

## Related

- [[nrql-efficient-query-patterns]] -- query patterns that keep responses small
- [[nr-connector-query-cookbook]] -- ready-to-paste templates
- [[actuate-nr-data-model]] -- full attribute catalog
- [[admin-nr-integration]] -- existing NR code in admin API
