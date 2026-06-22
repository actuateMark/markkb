---
title: "actuate-wireguard"
type: entity
topic: actuate-libraries
tags: [library, utility, wireguard, vpn, tunnel-management, database, rms, teltonika]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/entities/actuate-network.md
  - topics/actuate-libraries/notes/entities/actuate-secrets.md
  - topics/actuate-platform/notes/syntheses/camera-onboarding-end-to-end.md
  - topics/actuate-platform/notes/syntheses/watchman-vs-current-platform.md
  - topics/camera-health-monitoring/notes/syntheses/chm-enhanced-diagnostics-proposal.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase3-cross-camera-correlation.md
  - topics/data-access-control/_summary.md
  - topics/data-access-control/notes/syntheses/2026-05-11_admin-db-access-hardening.md
incoming_updated: 2026-05-27
---

## Purpose

actuate-wireguard (v1.0.10) provides WireGuard tunnel validation, data models, database access, Teltonika RMS integration, and CloudWatch metrics publishing. It is the central library for managing WireGuard VPN tunnels in the Actuate infrastructure, consumed by both the Django admin backend and the standalone wg-autoconf-service.

## Key Components

### Data Models (`models.py`)

- **`WireGuardTunnel`** -- Dataclass representing an `inframap_wireguardtunnel` row: id, name, client_public_key, client_tunnel_ip, server_id, subnets (list), subnets_are_virtually_assigned, tunnel_status, last_handshake, timestamps.
- **`WireGuardServer`** -- Dataclass representing an `inframap_wireguard` server row: id, name, zone, server_public_key.

These are framework-agnostic DTOs shared between Django and non-Django consumers.

### WireGuardDAO (`db.py`)

Full CRUD data access object using psycopg2 `ThreadedConnectionPool` (same pattern as [[actuate-daos]] `AdminDAO`). Credentials come from `actuate-secrets.SecretManager`.

**Read operations**: `get_all_tunnels`, `get_tunnel_by_id`, `get_server_mappings`, `get_server_by_id`, `get_all_existing_subnets`, `get_existing_client_tunnel_ips`, `get_existing_client_public_keys`.

**IP auto-assignment**: `get_next_available_tunnel_ip` iterates through the configured tunnel IP pool (skipping .0/.255), finding the first unused /32 address. `get_next_available_subnet` delegates to `actuate-network.suggest_next_available_subnet`.

**Create operations**: `create_tunnel` -- validates IP, subnets (internal/reserved/external/VPN overlap), then inserts with RETURNING. `create_tunnels_batch` -- processes multiple tunnels in one call with per-row validation and error reporting, supporting a validate-only mode for dry runs.

**Update operations**: `update_tunnel` -- dynamic SET clause from non-None fields, re-validates if subnets/IP change. `update_last_handshake` -- lightweight update for handshake timestamps.

**Delete**: `delete_tunnel` by ID.

### Validation (`validation.py`)

Extends [[actuate-network]]'s validation with WireGuard-specific checks:
- **`validate_ip_with_cidr`** -- Validates that a tunnel IP is a valid /32 CIDR.
- Re-exports all [[actuate-network]] validation functions.

### Teltonika RMS Integration

- **`TeltonikaRMSClient`** -- HTTP client for the Teltonika RMS API.
- **`register_device_with_rms`** -- Registers a WireGuard device with Teltonika RMS.
- **`RMSDeviceRegistrationRequest`/`RMSDeviceRegistrationResult`** -- Request/response models.
- **Exception hierarchy**: `RMSClientError`, `RMSConfigError`, `RMSAuthError`, `RMSValidationError`, `RMSAPIError`, `RMSNetworkError`.

### CloudWatch Metrics (`cloudwatch_metrics.py`)

- **`GatewayCloudWatchMetricsPublisher`** -- Publishes WireGuard gateway health metrics.
- **`collect_gateway_metrics`/`collect_host_metrics`** -- Metric collection helpers.
- **`publish_gateway_health_metrics`** -- Publishes collected metrics to CloudWatch under `CW_NAMESPACE`.

## Dependencies

- **boto3** >=1.35.20 -- AWS SDK.
- **psycopg2-binary** ~=2.9.10 -- PostgreSQL driver.
- **[[actuate-secrets]]** ~=1.0.1 -- DB credential retrieval.
- **[[actuate-network]]** ~=1.0 -- subnet validation and VPN overlap checks.

## Consumers

Camera Admin Django backend (WireGuard management views), wg-autoconf-service (standalone tunnel configuration daemon).

## Notable Patterns

- **Framework-agnostic models**: `WireGuardTunnel` and `WireGuardServer` are plain dataclasses, not Django models, allowing them to be shared across Django and non-Django services.
- **Batch create with dry-run**: `create_tunnels_batch` supports `validate_only_mode` for previewing bulk imports without writing to the database.
- **Unique violation handling**: `_handle_unique_violation` inspects psycopg2 error detail to produce user-friendly messages about duplicate keys or IPs.
- **Auto-assignment**: Both tunnel IPs and subnets can be auto-assigned when not provided, reducing manual configuration burden.
