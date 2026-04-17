---
title: "Source: New Relic NerdGraph API for Programmatic Dashboards"
type: source
topic: infrastructure
tags: [worklog, newrelic, nerdgraph, graphql, dashboards, observability]
ingested: 2026-04-14
author: kb-bot
---

# New Relic NerdGraph API for Programmatic Dashboards

Source: internal troubleshooting notes with New Relic API documentation references for generating programmatic dashboard links and embeddable charts.

## Use Case

Generate permalinks to specific log searches and resources programmatically using the NerdGraph (GraphQL) API. This enables linking directly to relevant dashboards and charts from internal tools, alerts, and reports.

## Key Documentation

- **NRQL via NerdGraph**: [nerdgraph-nrql-tutorial/#embeddable-charts](https://docs.newrelic.com/docs/apis/nerdgraph/examples/nerdgraph-nrql-tutorial/#embeddable-charts) -- execute NRQL queries via GraphQL and generate embeddable chart URLs.
- **Create Widgets/Dashboards**: [create-widgets-dashboards-api](https://docs.newrelic.com/docs/apis/nerdgraph/examples/create-widgets-dashboards-api/) -- programmatically create dashboard widgets.
- **Dashboard Management**: [nerdgraph-dashboards](https://docs.newrelic.com/docs/apis/nerdgraph/examples/nerdgraph-dashboards/) -- CRUD operations on dashboards via NerdGraph.
- **Data Sharing**: [manage-your-dashboard/#data-share](https://docs.newrelic.com/docs/query-your-data/explore-query-data/dashboards/manage-your-dashboard/#data-share) -- sharing and embedding dashboard data.

## Application

These APIs can be used to build deep-links from internal tools (admin UI, alerting systems, reports) directly into the relevant New Relic dashboards, eliminating manual navigation and improving incident response time.
