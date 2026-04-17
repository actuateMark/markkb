---
title: "actuate-daos"
type: entity
topic: actuate-libraries
tags: [library, config-data, data-access, dynamodb, s3, sqs, postgres, newrelic, metrics]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

## Purpose

actuate-daos (v3.2.13) is the data access layer for the Actuate platform. It provides DAO classes for DynamoDB, S3, SQS, PostgreSQL (via Camera Admin API), and metrics backends (CloudWatch, New Relic). Nearly every service that reads or writes persistent data goes through this library.

## Architecture

### DaoManager -- Centralised DAO Registry

`DaoManager` is the entry point. It accepts all DAO instances in its constructor (defaulting to mock implementations for each) and exposes them as typed properties. This allows connectors to receive a single DaoManager object and access any data store through it. Mock defaults make testing straightforward -- instantiating `DaoManager()` with no arguments gives a fully mocked set of DAOs.

The managed DAOs are: `AdminDAO`, `ImageDataDAO`, `WindowIdsDAO`, `CameraStatusDAO`, `ActuateMetricsDAO`, `EnrichedFrameDAO`, `HealthcheckDAO`, `ErrorAlarmDAO`, `SQSDAO`, `S3DAO`, `BlacklistDAO`, `PeopleFlowDAO`, `AnalysisDAO`, `SceneChangeDAO`, `TokenDAO`, `MotionDAO`, `ClipsMetadataDAO`, `HeartbeatDAO`.

### AdminDAO -- PostgreSQL Access via Camera Admin

`AdminDAO` manages a psycopg2 `ThreadedConnectionPool` against the Camera Admin PostgreSQL database. Credentials come from AWS Secrets Manager via `actuate-secrets.SecretManager`. It provides:

- **Generic query helpers**: `query_dict_array`, `query_one`, `execute`, `bulk_execute`, `query_from_file` -- all handle connection pooling and retries.
- **Camera Admin API wrappers**: `get_frame_queue_info_by_camera_id`, `get_motion_queue_info_by_camera_id`, `get_cameras`, `get_site_details`, `list_sites`, `list_webhooks`, `get_ai_model`, `get_configuration` -- these delegate to `AdminApi` for REST calls.
- **Credential/token access**: `get_api_token` (direct DB query for auth tokens), `check_immix_credential`.
- **New Relic integration**: `get_new_relic_mute_rule_id`, `reset_new_relic_mute_rule_id`.
- **Command history**: `save_command_history`, `update_task_id`.

### BaseDynamoDAO -- DynamoDB Base Class

`BaseDynamoDAO` is an abstract base providing a full DynamoDB interface: `get_item`, `put_item`, `update_item`, `delete_item`, `query`, `scan`, `batch_write`, `batch_get`, `batch_delete`, `transact_write`, `transact_get`. It also implements Python dunder methods (`__getitem__`, `__setitem__`, `__delitem__`, `__iter__`, `__contains__`, `__len__`) so DynamoDB tables can be used with dict-like and iterable syntax. Concrete DAOs (HealthcheckDAO, ImageDataDAO, WindowIdsDAO, etc.) extend this class with domain-specific methods.

### S3DAO -- Object Storage

`S3DAO` provides `send_bytes_to_s3`, `get_image_bytes`, `get_file_list`, `get_file`, `get_download_url`, `save_frame`. It uses a botocore client with the Expect header unregistered for performance and an `ActuateThreadPoolExecutor` for async uploads. Includes a self-healing `check_thread` method that detects hanging S3 uploads and triggers a pod reboot via the connector-deploy-svc.

### SQSDAO -- Message Queuing

`SQSDAO` wraps SQS operations: `create_queue`, `create_fifo_video_queue`, `send_message`, `receive_message`, `delete_message`. Takes a root queue URL in the constructor and builds full queue URLs from queue names.

### Metrics DAOs

- **`CloudwatchMetricsDAO`** -- publishes custom metrics (FPS, motion percentage, alerts, processing speed) to CloudWatch.
- **`NewRelicMetricsDAO`** -- publishes the same metrics to New Relic via the telemetry SDK.
- **`ActuateMetricsDAO`** -- abstract base for metrics backends.

### Other DAOs

- `HealthcheckDAO` -- DynamoDB table for healthcheck run results.
- `EnrichedFrameDAO` -- stores enriched frame metadata.
- `ErrorAlarmDAO` -- error alarm state.
- `BlacklistDAO` -- detection blacklist management.
- `PeopleFlowDAO` -- people counting/flow data.
- `SceneChangeDAO` -- scene change detection records.
- `MotionDAO` -- motion event records.
- `ClipsMetadataDAO` -- video clip metadata.
- `HeartbeatDAO` -- site heartbeat updates.
- `CameraStatusDAO` -- per-camera connection status.
- `WindowIdsDAO` -- detection window ID tracking.
- `ImageDataDAO` -- image metadata.
- `TokenDAO` -- authentication token storage.

### Mocks

Every DAO has a corresponding mock in `mocks/` (e.g. `AdminDAOMock`, `S3DAOMock`). These are used as DaoManager defaults and in unit tests. The mock pattern lets the entire data layer be swapped out with zero AWS calls.

## Dependencies

- **actuate-threadpool** >=1.0.0 -- thread pool for async S3 uploads.
- **actuate-healthcheck-objects** ~=1.1 -- healthcheck packet types.
- **actuate-config** >=1.3.5 -- BaseConnectorConfig for DynamoDB DAO construction.
- **actuate-admin-api** >=0.1.12 -- REST calls to Camera Admin.
- **newrelic-telemetry-sdk** >=0.5.1 -- New Relic metrics publishing.
- **psycopg2-binary** ~=2.9.10 -- PostgreSQL driver.
- **moto[dynamodb]** >=5.0.21 -- DynamoDB mocking for tests.
- **requests**, **boto3** -- AWS SDK and HTTP.

## Consumers

vms-connector (primary), actuate-monitoring (NewRelicMonitor uses AdminDAO), actuate-healthmonitoring, actuate-alarm-senders, actuate-queue-consumer -- essentially any service that persists data or reads from Camera Admin.

## Notable Patterns

- **Mock-first DaoManager**: All constructor defaults are mocks, so `DaoManager()` is test-safe out of the box.
- **Private attributes with name mangling**: `__` prefix on all DaoManager fields; tests access them via `_DaoManager__field_name`.
- **Connection pool retry loop**: AdminDAO retries `getconn()` up to 5 times with 200ms backoff on pool exhaustion.
- **Self-healing S3 uploads**: S3DAO detects hanging uploads and triggers pod reboots through the deploy service.
