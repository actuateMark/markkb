---
title: "Source: Sharding Strategy -- Multiprocessing Cost Analysis"
type: source
topic: vms-connector
tags: [worklog, sharding, multiprocessing, cpu, cost, optimization]
ingested: 2026-04-14
author: kb-bot
---

# Sharding Strategy -- Multiprocessing Cost Analysis

**Origin:** `/home/mork/Documents/worklog/worklog/Sharding Strategy.md`

A brief but impactful analysis note documenting the empirical finding that multiprocessing is the single most expensive operation in the connector, and outlining short-term and long-term strategies to reduce unnecessary sharding.

## Key Finding

Splitting the connector into multiple processes incurs a CPU increase of at least 50-80% (or more) compared to running in a single process. This overhead comes from process isolation, duplicated memory, and OS scheduling costs rather than from the camera workloads themselves.

## Implication

If even one additional camera can be kept on the same process (e.g., 25 instead of 24), it eliminates a shard boundary and saves approximately 0.5-2 CPU. Doing this on a single site can offset CPU increases across 10 other sites. This is a strong argument for raising the default shard size when hardware allows it.

## Short-Term Strategy

1. Determine the comfortable maximum cameras-per-process for a given native resolution and FPS combination.
2. Configure different shard sizes in the connector accordingly, rather than using a single default for all sites.

## Long-Term Strategy

1. Log per-site performance data to DynamoDB (or similar).
2. Analyze whether each site is lagging behind or over-provisioned.
3. Set shard sizes dynamically based on observed performance.

## Significance

This note captures the empirical motivation for the current default shard size of 24 (later raised from lower values) and foreshadows the adaptive/dynamic sharding concept. The long-term vision of performance-data-driven shard sizing has not yet been implemented as of April 2026.
