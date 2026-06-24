---
title: "actuate-instrumentation"
type: entity
topic: actuate-libraries
tags: [library, utility, debugging, data-dump, instrumentation]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/syntheses/2026-05-12_adr-actuate-instrumentation-v1.md
  - topics/engineering-process/notes/syntheses/2026-05-22_actuate-testing-toolkit-overview.md
  - topics/engineering-process/notes/syntheses/2026-06-22_offboarding-plan.md
  - topics/infrastructure/notes/entities/new-relic.md
  - topics/new-relic/_summary.md
  - topics/new-relic/notes/concepts/actuate-nr-data-model.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
  - topics/profiling-and-performance/notes/concepts/2026-05-12_actuate-instrumentation-v1-installed.md
incoming_updated: 2026-06-24
---

## Purpose

actuate-instrumentation (v0.0.3) provides lightweight tools for instrumenting the codebase with runtime data capture. Currently it contains a `data_dump` subpackage with functions for dumping and loading JSON data snapshots during debugging and development.

## Key Functions

### `data_dump.data_scripts`

- **`data_dump(prefix="data", data=None)`** -- Creates a `./local_data/` directory, reads the local `settings.json`, merges it into the provided `data` dict, and writes the combined payload to `./local_data/{prefix}_{timestamp}.json`. Raises `ValueError` if `data` is None. Useful for capturing the full state of a connector run (settings + runtime data) at a specific point in time.

- **`data_load(filename)`** -- Reads a previously dumped JSON file from `./local_data/{filename}.json` and returns the parsed dict. Raises `ValueError` if the file does not exist.

## Dependencies

None. Pure Python standard library only.

## Consumers

Used ad-hoc during development and debugging of connector services. Not typically deployed in production; the `0.0.3` version indicates early/experimental status.

## Notable Patterns

- **Settings capture**: `data_dump` automatically includes the site's `settings.json` alongside the caller's data, creating self-contained snapshots that can reproduce issues without access to the original environment.
- **Timestamped filenames**: Each dump gets a Unix timestamp suffix, allowing multiple captures without overwriting.
- **Local-only storage**: Dumps go to `./local_data/`, not S3 or any remote store, keeping this strictly a development tool.
