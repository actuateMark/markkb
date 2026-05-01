---
title: "actuate-secrets"
type: entity
topic: actuate-libraries
tags: [library, utility, aws, secrets-manager, credentials]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

## Purpose

actuate-secrets (v1.0.1) is a lightweight wrapper around AWS Secrets Manager. It provides two interfaces for retrieving secrets: a class-based `SecretManager` and a module-level `get_secret` function. These are the sole mechanism by which Actuate services retrieve database credentials, API tokens, and other sensitive configuration.

## Public API

### `SecretManager` (class)

Instantiates a boto3 Secrets Manager client with a 3-second connect timeout and 3 retries.

- **`get_secret(secret_name)`** -- Fetches a secret by name. Returns a parsed dict if the secret string looks like JSON (starts with `{`), the raw string otherwise, or decoded binary for binary secrets.
- **`get_stage_secrets(secret_name, stage="prod")`** -- Convenience method that builds the secret ID as `{stage}/actuate/{secret_name}` and delegates to `get_secret`.

### `get_secret(secret_name)` (module-level function)

Legacy function in `secrets.py`. Uses a module-level boto3 session and a `secret_cache` dict for in-process caching. Same JSON-detection logic as `SecretManager.get_secret` but adds caching to avoid repeated API calls. Also initialises a module-level SES client (unused in the function itself; likely a leftover from early code).

## Dependencies

- **boto3** >=1.35.20 -- AWS SDK.
- **psycopg2-binary** ~=2.9.10 -- listed as a dependency but not imported directly; likely present for consumers that immediately connect to Postgres after retrieving credentials.

## Consumers

[[actuate-admin-api]] (`AdminApi` uses `SecretManager` for API tokens), [[actuate-daos]] (`AdminDAO` uses `SecretManager` for Postgres credentials), [[actuate-wireguard]] (`WireGuardDAO` for DB credentials), [[actuate-monitoring]] (`NewRelicMonitor` uses `get_secret` for [[new-relic|New Relic]] keys).

## Notable Patterns

- **Two parallel interfaces**: `SecretManager` (instance-based, no caching, configurable retries) and `get_secret` (module-level, cached). Newer code prefers `SecretManager`; older code still uses the module-level function.
- **Automatic JSON parsing**: Both interfaces detect JSON secrets by checking if the string starts with `{` and return a dict, making it transparent whether a secret is a simple string or a structured credential bundle.
- **Secret naming convention**: Actuate secrets follow the pattern `{stage}/actuate/{service}` (e.g., `prod/actuate/postgres`, `prod/actuate/new_relic`).
