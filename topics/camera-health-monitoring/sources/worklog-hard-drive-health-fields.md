---
title: "Source: Hard Drive Health Fields for Alibi"
type: source
topic: camera-health-monitoring
tags: [worklog, alibi, hard-drive, nvr, storage]
ingested: 2026-04-14
author: kb-bot
---

# Hard Drive Health Fields for Alibi

Worklog notes specifying the data fields collected for hard drive health monitoring on Alibi NVR integrations.

## Fields

- **Connection reachability** -- flag indicating whether the NVR is reachable
- **Illegal access** -- unknown/skip (not fully defined)
- **Storage** -- from `/containerinfo` endpoint; disk can be offline or abnormal
- **Reachable** -- boolean connectivity status
- **Hard drive error** -- boolean flag
- **Error message** -- optional, displayed on hover; covers conditions like abnormal disk, offline disk, etc.
- **Space low** -- boolean
- **Space full** -- boolean
- **Hard drive information/details** -- size and type of the drive

## Context

These fields are specific to the Alibi integration's NVR diagnostics. The `/containerinfo` endpoint is the source for disk status. The UI design includes hover-over error messages for detailed error context without cluttering the default view.

## See Also

- [[worklog-healthcheck-job-design]] -- how these fields are collected during job execution
- [[health-check-types]] -- broader healthcheck taxonomy
