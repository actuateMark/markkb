---
title: "Source: Local Dev Setup (Rye/UV)"
type: source
topic: vms-connector
tags: [worklog, dev-setup, uv, rye, local-development, actuate-libraries]
ingested: 2026-04-14
author: kb-bot
---

# Local Dev Setup (Rye/UV)

**Origin:** `/home/mork/Documents/worklog/worklog/rye stuff vms connector.md`

Practical setup notes for running the vms-connector locally, including system dependencies, editable library installs, and common troubleshooting.

## System Dependencies

```shell
sudo apt -y install libgeos-dev
sudo apt -y install libpq-dev
uv pip install pip
```

`libgeos-dev` is required by Shapely (used in ignore-zone geometry). `libpq-dev` is required by psycopg2 (used in some DAO paths).

## Editable Library Development

To develop against a local checkout of an actuate library:

```shell
uv pip install -e /path/to/actuate-libraries/actuate-library-name/
```

When done, uninstall the editable version so the connector reverts to the pinned release:

```shell
uv pip uninstall actuate-library-name
```

To refresh all libraries from CodeArtifact to match `requirements.txt`:

```shell
uv pip install -r requirements.txt --upgrade
```

## Troubleshooting: Cache Deserialization Error

If `uv` fails with `wrong msgpack marker FixArray(2)` during lockfile generation, clear the cache:

```shell
uv cache clean
```

## Local Webcam Testing

List available local video devices:

```shell
v4l2-ctl --list-devices
```

## Significance

These notes capture the practical local development workflow. The editable-install pattern (`uv pip install -e`) is the standard way to iterate on actuate-libraries changes alongside the connector without publishing dev versions to CodeArtifact. The `uv cache clean` fix addresses a recurring issue with corrupted lockfile caches.
