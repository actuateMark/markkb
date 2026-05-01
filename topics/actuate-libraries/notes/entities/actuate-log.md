---
title: "actuate-log"
type: entity
topic: actuate-libraries
tags: [library, utility, logging, log-adapter, structured-logging]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/concepts/dev-workflow.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-05-01
---

## Purpose

actuate-log (v1.0.2) provides standardised logging utilities for Actuate services. It offers a custom log adapter with contextual metadata, a logger initialisation helper, a timing mixin, and a log filter. The goal is consistent log formatting across all services with built-in support for user/site/record context.

## Public API

### `ActuateLogAdapter`

A `logging.LoggerAdapter` subclass that prepends contextual information to every log message. Initialised with optional `app_name`, `username`, `site_id`, and `record_id`. The `process()` method formats messages as `[username] site_id: {id} {record_id} - {original_message}`, including only the fields that are set. Also silences noisy `botocore.credentials` logs by setting them to WARN.

### `init_logger(output_to_console=False)`

Configures the root logger at INFO level. When `output_to_console=True`, adds a `StreamHandler` to stdout with the standard Actuate format: `[%(asctime)s] %(name)s : %(levelname)s : %(message)s`.

### `LogTimeElapsedMixin`

A mixin class providing `log_time_elapsed(func)` -- a method decorator that logs how long a function takes in seconds. Lazily creates a `self.logger` attribute if one does not exist. Designed for use in classes that already have logging infrastructure.

### `FuturesFilter` (in `logger_filter.py`)

A `logging.Filter` that suppresses log messages containing "new futures", reducing noise from concurrent.futures thread pool logging.

## Dependencies

None. Uses only the Python standard library `logging` module.

## Consumers

Any Actuate service that needs structured logging. The `ActuateLogAdapter` is particularly useful in autopatrol and event-listener services where logs must be correlated to a specific user, site, and execution run.

## Notable Patterns

- **Context-aware log adapter**: Rather than passing context through every log call, `ActuateLogAdapter` is configured once and automatically prepends user/site/record context to all subsequent messages.
- **Requires Python 3.12+**: This is the only library in the monorepo that requires Python 3.12 rather than 3.11, likely for type hint features.
- **Mixin pattern for timing**: `LogTimeElapsedMixin` is designed to be mixed into existing classes rather than used standalone, keeping timing logic decoupled from business logic.
