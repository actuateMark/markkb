---
title: "Source: Microservice and Library Split Plan"
type: source
topic: actuate-libraries
tags: [worklog, architecture, fastapi, openapi, client-generation, codeartifact]
ingested: 2026-04-14
author: kb-bot
---

# Microservice and Library Split Plan

Worklog notes outlining the plan for splitting functionality into microservices with auto-generated client libraries.

## Plan (Four Steps)

1. **Write a FastAPI template repo** -- standardized project structure for new microservices.
2. **Extract the OpenAPI spec** -- programmatically get the FastAPI-generated OpenAPI specification from a running server.
3. **Generate client library** -- auto-generate a Python client from the OpenAPI spec and publish it to the artifact repository (CodeArtifact).
4. **Use the client library in applications** -- consumers import the published client. Ideally, rebuilds are triggered automatically when libraries update; otherwise, updates are just a version bump in the consuming service.

## Significance

This represents the strategy for decoupling Actuate's monolith into independently deployable services. The auto-generated client approach ensures API contracts stay in sync between producers and consumers without manual maintenance. FastAPI was chosen specifically because it generates OpenAPI specs natively, making step 2 trivial.

## See Also

- [[worklog-artifact-repository]] -- where generated libraries are published
- [[worklog-bump-process]] -- how version bumps work in practice
