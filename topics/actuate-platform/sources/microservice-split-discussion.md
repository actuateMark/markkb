---
title: "Source: Microservice Split Discussion -- Future Distributed Architecture"
type: source
topic: actuate-platform
tags: [worklog, microservices, distributed-systems, message-broker, rearch, pipeline, celery]
ingested: 2026-04-14
author: kb-bot
---

# Microservice Split Discussion -- Future Distributed Architecture

Source: internal team chat exploring how to break the rearch (re-architecture) pipeline into distributed microservices using message brokers.

## Core Idea

The rearch pipeline is already designed so that each processing step is stateless -- any "stateful" configuration set during init can be moved onto the message packet itself. This makes it a strong candidate for decomposition into independent workers connected by message queues.

## Where to Split

The discussion identified several heuristics for choosing split points:

1. **Fan-out points** -- where one input produces multiple parallel outputs (e.g., a single frame sent to separate intruder and weapon pipelines).
2. **Unpredictable processing time** -- steps that bottleneck downstream (e.g., inference). With a message broker, each frame can move through the pipeline independently, and a final aggregator can work with whatever frames have arrived within a time window rather than blocking on stragglers.
3. **Bidirectional data flow** -- anywhere `A <-> B` can be refactored into `A -> B -> C` to remove tight coupling.

## Alert Window Service Concept

A proposed alert window service would:
- Open a window when triggered and watch for the next N inference results for that window.
- If any result triggers an alert, send it immediately rather than waiting for all frames.
- Backfill remaining frames asynchronously -- by the time a customer views the alert, processing is likely complete.
- Potentially use per-site SNS topics for organizing results.

## Prerequisites

- **Shared artifact repository** (CodeArtifact) to house shared libraries (packet patterns, pipeline classes).
- Once shared code is centralized, creating a new microservice is as simple as importing the relevant libraries, listening on a queue, and publishing results.

## Practical Approach

Rather than splitting every step into its own service, the team favored **large flexible pipeline chunks** (e.g., entire pre/post processing pipe-trees) with many replicas, breaking apart only at the heuristic points above. This balances performance with operational simplicity.
