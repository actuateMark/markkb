---
title: "NRQL Efficient Query Patterns"
type: concept
topic: new-relic
author: kb-bot
created: 2026-04-16
updated: 2026-04-16
tags: [nrql, query-optimization, context-management, new-relic, observability]
incoming:
  - topics/aws-cost/notes/concepts/aws-cost-explorer-access-pattern.md
  - topics/billing/notes/concepts/2026-05-14_inference-api-e2m-rules.md
  - topics/engineering-process/notes/entities/agent-nrql-investigator.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/fleet-architecture/notes/concepts/observability-and-tracing.md
  - topics/fleet-architecture/notes/syntheses/2026-05-29_watch-manager-observability.md
  - topics/new-relic/_summary.md
  - topics/new-relic/notes/concepts/actuate-nr-data-model.md
  - topics/new-relic/notes/concepts/nr-connector-query-cookbook.md
  - topics/new-relic/notes/concepts/nr-log-level-strategy.md
incoming_updated: 2026-06-25
---

# NRQL Efficient Query Patterns

This note defines how to write NRQL queries that return **maximum signal in minimum tokens**. Every query run through the [[new-relic]] MCP tool returns its full result into the Claude Code context window. Poorly scoped queries waste thousands of tokens on noise, crowding out space for actual reasoning. Follow these rules rigorously.

## The Golden Rule

**Never use `SELECT *`.** Every query must select only the attributes you need. A single `SELECT * FROM Log LIMIT 50` can easily return 50 multi-line JSON blobs with dozens of attributes each -- burning 10,000+ tokens for data you will not use. Always name your columns explicitly.

## Core Principles

### 1. Aggregate First, Drill Second

The most efficient investigation pattern is a two-phase approach:

**Phase 1 -- Count and categorise.** Use aggregation functions to understand the shape of the problem before looking at any individual log line.

```sql
-- Good: understand error distribution first (small response)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'connector-%'
  AND level = 'ERROR'
SINCE 30 minutes ago
FACET message LIMIT 10
```

**Phase 2 -- Targeted drill-down.** Only after you know *which* error to investigate, fetch a small number of specific log lines.

```sql
-- Good: fetch 5 examples of the specific error you identified
SELECT message, container_name, timestamp FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'connector-%'
  AND level = 'ERROR'
  AND message LIKE '%NoneType%'
SINCE 30 minutes ago LIMIT 5
```

### 2. Always Scope with WHERE

Every connector query must include **at minimum** `cluster_name = 'Connector-EKS'`. For site-specific investigations, add `container_name`. For fleet-segment queries, use `container_name LIKE 'connector-%'` or `container_name LIKE 'staging-connector-%'`.

```sql
-- Bad: scans all logs across all clusters
SELECT count(*) FROM Log WHERE level = 'ERROR' SINCE 1 hour ago

-- Good: scoped to the connector fleet
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'connector-%'
  AND level = 'ERROR'
SINCE 1 hour ago
```

### 3. Use the Tightest Time Window Possible

`SINCE` should be as narrow as the question demands. Investigating a current issue? Use `SINCE 30 minutes ago`. Checking overnight health? Use `SINCE 8 hours ago`. Never default to `SINCE 1 week ago` unless you genuinely need trend data.

| Question | Appropriate Window |
|---|---|
| "Is this site erroring right now?" | `SINCE 15 minutes ago` |
| "Did the deploy cause a regression?" | `SINCE 1 hour ago COMPARE WITH 1 hour ago` |
| "Did autopatrol run overnight?" | `SINCE 8 hours ago` |
| "What's the weekly error trend?" | `SINCE 7 days ago TIMESERIES 1 day` |

### 4. LIMIT as Small as Possible

Default NRQL LIMIT is 10 for FACET queries and 100 for non-FACET. Always set it explicitly and keep it small.

- **FACET queries:** `LIMIT 10` covers most diagnostic needs. Use `LIMIT 20` if you need broader coverage.
- **Raw log queries:** `LIMIT 5` is almost always enough to understand a pattern. Never exceed `LIMIT 20` for raw rows.

### 5. Prefer Aggregation Functions

These functions compress thousands of rows into a single result:

| Function | When to Use |
|---|---|
| `count(*)` | "How many?" -- error rates, log volume |
| `uniqueCount(attribute)` | "How many distinct?" -- unique sites, unique errors |
| `latest(attribute)` | "What's the most recent value?" -- latest status, last message |
| `earliest(attribute)` | "When did this first appear?" |
| `rate(count(*), 1 minute)` | "What's the rate?" -- events per minute |
| `percentile(attribute, 95)` | Latency distributions |
| `filter(count(*), WHERE ...)` | Compare subsets in a single query |

### 6. Use FACET for Grouped Summaries

`FACET` is your primary tool for understanding distributions without returning raw rows.

```sql
-- Efficient: one row per container with its error count
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND level = 'ERROR'
SINCE 1 hour ago
FACET container_name LIMIT 10
```

### 7. Use TIMESERIES for Trends

When you need to understand how something changed over time, use `TIMESERIES` instead of fetching raw timestamped rows. This returns one data point per time bucket instead of thousands of rows.

```sql
-- Good: 12 data points showing the trend
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-34692'
  AND level = 'ERROR'
SINCE 1 hour ago TIMESERIES 5 minutes
```

### 8. Use COMPARE WITH for Regression Detection

Instead of running two separate queries to compare time windows, use `COMPARE WITH` to get both in one response.

```sql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'staging-connector-%'
  AND level = 'ERROR'
SINCE 30 minutes ago
COMPARE WITH 30 minutes ago
FACET message LIMIT 10
```

## Anti-Patterns

### Never Do This

| Anti-Pattern | Why It's Bad | Fix |
|---|---|---|
| `SELECT * FROM Log LIMIT 50` | Returns every attribute on 50 rows -- massive token dump | `SELECT message, level, container_name FROM Log LIMIT 5` |
| `SELECT message FROM Log WHERE message LIKE '%error%' LIMIT 100` | Unscoped scan + huge result | Add `cluster_name`, `container_name`, `level = 'ERROR'`, reduce LIMIT |
| `SINCE 7 days ago` for debugging | Scans a week of data for a current issue | Use `SINCE 30 minutes ago` |
| `FACET message LIMIT 100` | Message text is highly unique -- 100 facets = 100 long strings | `FACET message LIMIT 10` or facet on `container_name` first |
| Running the same broad query repeatedly | Burns tokens each time | Save the result mentally, refine subsequent queries |

### Prefer This Instead

```sql
-- Discovery: what containers are active? (tiny response)
SELECT uniqueCount(message) FROM Log
WHERE cluster_name = 'Connector-EKS'
SINCE 1 hour ago FACET container_name LIMIT 20

-- Diagnosis: what errors exist? (small response)
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-34692'
  AND level = 'ERROR'
SINCE 30 minutes ago FACET message LIMIT 5

-- Detail: read specific error messages (controlled response)
SELECT message, timestamp FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name = 'connector-34692'
  AND level = 'ERROR'
  AND message LIKE '%NoneType%'
SINCE 30 minutes ago LIMIT 3
```

## Attribute Discovery

When you need to know what attributes are available, use `keyset()`:

```sql
-- What attributes exist on connector logs?
SELECT keyset() FROM Log
WHERE cluster_name = 'Connector-EKS'
SINCE 1 hour ago
```

This returns attribute names and types -- run it once per session, then use the results to craft targeted queries. See [[actuate-nr-data-model]] for a pre-documented reference so you can skip this step entirely.

## Template Queries for Common Operations

See [[nr-connector-query-cookbook]] for ready-to-paste query templates. The cookbook follows all efficiency patterns documented here.

## Summary Checklist

Before running any NRQL query, verify:

- [ ] No `SELECT *` -- named attributes only
- [ ] `WHERE cluster_name = 'Connector-EKS'` present (for connector queries)
- [ ] `container_name` scoped (fleet segment or specific site)
- [ ] `SINCE` is as narrow as the question requires
- [ ] `LIMIT` is explicitly set and small (5-10 for raw, 10-20 for FACET)
- [ ] Aggregation phase complete before drilling into raw rows
- [ ] `TIMESERIES` used instead of raw rows for trend questions
- [ ] `COMPARE WITH` used instead of two separate queries for before/after

## Related

- [[actuate-nr-data-model]] -- attribute reference
- [[nr-connector-query-cookbook]] -- ready-to-use templates
- [[nr-log-level-strategy]] -- which levels to query and why
- [[connector-fleet-monitoring]] -- real-world monitoring patterns from production releases
