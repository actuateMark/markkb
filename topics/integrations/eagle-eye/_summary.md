---
title: "Eagle Eye Integration"
type: summary
topic: integrations/eagle-eye
tags: [integration, vms, eagle-eye, cloud-vms]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Eagle Eye Integration

Eagle Eye Networks is a **cloud-based VMS** platform. The Actuate integration spans both [[actuate-alarm-senders]] and [[actuate-integration-calls]], providing alert delivery and camera/stream management. Eagle Eye is notable for supporting **three generations of API** (Camera Manager, v2, and v3).

## Components

### EagleEyeAlertSender (alarm sender)

Defined in [[actuate-alarm-senders]] at `eagle_eye/eagle_eye_alert_sender.py`. Extends `EventListenerAlertSender`. Alerts are delivered **asynchronously via SQS** to the `event_queue_eagle_eye.fifo` queue. The payload includes the camera ESN (`camera.camera_id`), customer ID, an ISO 8601 timestamp with timezone, and per-detection bounding boxes converted to normalized percentages (`[x_min_pct, y_min_pct, x_max_pct, y_max_pct]`). Handles `Decimal` to `float` conversion for DynamoDB-sourced model response data.

Config fields: `camera.camera_id` (ESN), `customer.id`.

### Eagle Eye Integration Calls

Defined in [[actuate-integration-calls]] at `eagle_eye/eagle_eye_calls.py`. Module-level functions (not a class) covering three API generations:

**Camera Manager (legacy):**
- `get_camera_manager_token()` -- OAuth2 password grant with app_name/api_key as Basic auth
- `get_camera_manager_url()` -- Retrieves [[rtsp-deep-dive|RTSP]] stream URL for a camera
- `get_camera_manager_list()` -- Lists all cameras

**v2:**
- `get_token_v2()` -- Two-step authenticate + authorize flow using API key header, returns auth_key cookie and brand subdomain
- `get_url()` -- Builds [[rtsp-deep-dive|RTSP]] stream URL via `/api/v2/media/cameras/{id}/streams` (with special [[mjpeg-and-still-image-formats|MJPEG]] fallback for Acadian-Monitoring)
- `get_camera_list_v2()` -- Device list endpoint

**v3 (current):**
- `get_token()` -- OAuth2 refresh token grant via `auth.eagleeyenetworks.com`, base64-encoded app_name:api_key
- `get_base_url()` -- Discovers customer-specific API hostname via `/api/v3.0/clientSettings`
- `get_url_v3()` -- Retrieves [[rtsp-deep-dive|RTSP]] URL from `/api/v3.0/feeds` endpoint, supports proxy token fallback for multi-account setups
- `get_camera_list()` -- Paginated camera list via `/api/v3.0/cameras`
- `camera_exists_v3()` -- Camera existence check with false-negative safety (returns True on errors)
- `get_proxy_tokens()` / `get_users()` -- Reseller proxy token generation for multi-account management
- `is_valid_token()` -- Token validity check

## Auth Methods

- **Camera Manager:** OAuth2 password grant (username/password + app_name/api_key as Basic auth)
- **v2:** API key authentication header + cookie-based session
- **v3:** OAuth2 refresh token grant (refresh_token stored in DynamoDB tokens table, app credentials base64-encoded)

## Architecture

The [[vms-connector]] uses Eagle Eye integration calls during startup to authenticate, discover the base URL, retrieve camera lists, and construct stream URLs. [[rtsp-deep-dive|RTSP]] streams are then consumed by standard URL-based pullers in [[actuate-pullers]] (no Eagle Eye-specific puller exists). When detections occur, the `EagleEyeAlertSender` enqueues events to SQS for the event-listener to deliver back to Eagle Eye.

## Relationship to Other Components

- [[actuate-alarm-senders]] -- EagleEyeAlertSender lives here, extending EventListenerAlertSender
- [[actuate-integration-calls]] -- `eagle_eye_calls.py` provides all camera discovery, auth, and URL construction
- [[vms-connector]] -- consumes integration calls for login/stream setup, builds the sender via factory
- [[actuate-pullers]] -- standard URL pullers used (no Eagle Eye-specific puller)
