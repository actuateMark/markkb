---
title: "Eagle Eye Integration Components"
type: entity
topic: integrations/eagle-eye
tags: [integration, eagle-eye, components]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Eagle Eye Integration Components

## EagleEyeAlertSender

`EagleEyeAlertSender` extends `EventListenerAlertSender` and delivers detection alerts to Eagle Eye Networks via an SQS event queue rather than direct API calls. The `send(alert_data)` method constructs a message with the following structure:

- `queue_id`: Fixed to `"event_queue_eagle_eye.fifo"` (a FIFO SQS queue).
- `customer_id`: The Actuate customer ID.
- `esn`: The Eagle Eye camera ESN (Electronic Serial Number), sourced from `camera.camera_id`.
- `responses`: A list of detection objects, each containing `bbox` (percent-normalized bounding box), `confidence`, and `label`.
- `timestamp`: An ISO 8601 string with milliseconds and timezone offset.

The method delegates delivery to `self.event_listener.send_to_queue(data)`, which handles SQS message publishing. Bounding box normalization is performed by `bbox_to_percent()`, which converts center-x/y plus width/height coordinates into min/max percentages relative to frame dimensions, clamped to the 0-1 range. The `convert_decimals_to_float()` helper handles DynamoDB `Decimal` types that may appear in model responses. The `to_iso8601_with_tz()` method formats timezone-aware datetimes with the colon-separated UTC offset format required by Eagle Eye (e.g., `+03:00`).

## Eagle Eye Integration Calls (eagle_eye_calls)

The `eagle_eye_calls` module is the most comprehensive integration-calls module, supporting both Eagle Eye v2 and v3 APIs plus the legacy Camera Manager API.

### Authentication

- **v3 OAuth2**: `get_token()` exchanges a refresh token (stored in a tokens DAO) for an access token via `https://auth.eagleeyenetworks.com/oauth2/token` with Base64-encoded app credentials.
- **v2 auth**: `get_token_v2()` performs a two-step authenticate/authorize flow against `login.eagleeyenetworks.com`, returning an `auth_key` cookie and `active_brand_subdomain`.
- **Camera Manager**: `get_camera_manager_token()` uses OAuth2 password grant against `rest.cameramanager.com`.
- **Token validation**: `is_valid_token()` checks token validity by querying `/api/v3.0/accounts/self`.

### Camera and Stream Discovery

- **v3 cameras**: `get_camera_list()` paginates through `/api/v3.0/cameras` with status, notes, and capabilities. Returns a name-to-ID dictionary.
- **v3 feeds**: `get_url_v3()` fetches [[rtsp-deep-dive|RTSP]] stream URLs from `/api/v3.0/feeds` for a given camera and resolution type. Falls back to proxy tokens if the primary token has no access.
- **v2 cameras**: `get_camera_list_v2()` and `get_url()` use the legacy `/g/device/list` and `/api/v2/media/cameras` endpoints.
- **Camera Manager**: `get_camera_manager_list()` and `get_camera_manager_url()` query the Camera Manager REST API for camera lists and [[rtsp-deep-dive|RTSP]] URLs.

### Multi-Account Support

`get_users()` lists all accounts visible to the current token, and `get_proxy_tokens()` creates reseller-scoped authorization tokens for each sub-account, enabling multi-tenant camera discovery. `camera_exists_v3()` verifies camera existence by ID, falling back through proxy tokens on 404.

### Base URL Discovery

`get_base_url()` retrieves the per-account HTTPS base URL from `/api/v3.0/clientSettings`, which varies by Eagle Eye deployment region.

## EagleEyeConnectorConfig

`EagleEyeConnectorConfig` extends `BaseConnectorConfig` with `EagleEyeCustomerConfig` containing: `een_api` (API version flag), `username`, `password`, `app_name`, `api_key`, and `refresh_token`. Motion is always disabled (`use_motion = False`). `EagleEyeCamera` adds `camera_id` (from `camera_uid`), and `resolution` (from `een_stream_quality`, defaulting to `"preview"`).
