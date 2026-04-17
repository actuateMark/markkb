---
title: "Source: Version Bump Convention"
type: source
topic: actuate-libraries
tags: [worklog, versioning, ci, commit-conventions]
ingested: 2026-04-14
author: kb-bot
---

# Version Bump Convention

Worklog notes on the commit message convention used to trigger library version bumps in CI.

## Convention

Version bumps are triggered through specially formatted commit message tags:

- `[minor:actuate-pullers]` -- triggers a minor version bump for the `actuate-pullers` library
- `[patch:actuate-filters]` -- triggers a patch version bump for the `actuate-filters` library

The format is `[{bump-type}:{library-name}]` appended to the commit message. CI parses these tags to determine which libraries to version and publish.

## Supported Bump Types

- **minor** -- new backward-compatible functionality
- **patch** -- backward-compatible bug fixes

Major bumps are presumably handled differently (manual or a separate process), consistent with the caution around breaking changes in shared libraries.

## Context

This convention works with the CodeArtifact publishing pipeline described in [[worklog-artifact-repository]]. A commit with a bump tag triggers CI to increment the version and publish the new package. This is why pushes to `main` on actuate-libraries must be deliberate -- each push can auto-publish.

## See Also

- [[worklog-artifact-repository]] -- the publishing destination
- [[worklog-microservice-library-plan]] -- the broader library strategy
