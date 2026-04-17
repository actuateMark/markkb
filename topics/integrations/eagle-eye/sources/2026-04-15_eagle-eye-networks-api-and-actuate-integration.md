---
title: "Source: Eagle Eye Networks Cloud API and Actuate Integration"
type: source
topic: integrations/eagle-eye
tags: [source, integration, eagle-eye, documentation]
ingested: 2026-04-15
author: kb-bot
---

## API Overview

Eagle Eye Networks is a **cloud-hosted VMS** that exposes both a legacy Camera Manager API (v2) and a modern REST API (v3). The Actuate integration supports all three API generations: Camera Manager, v2, and v3. Base URLs are dynamically resolved per-account.

### Authentication

Three distinct auth flows are supported:

1. **Camera Manager (legacy)**: OAuth2 password grant to `https://rest.cameramanager.com/oauth/token` with `HTTPBasicAuth(app_name, api_key)`. Returns `access_token` and `expires_in`.
2. **API v2**: Two-step flow -- POST to `https://login.eagleeyenetworks.com/g/aaa/authenticate` with API key header, then POST to `/g/aaa/authorize`. Returns `auth_key` cookie and `active_brand_subdomain`.
3. **API v3**: OAuth2 refresh token grant to `https://auth.eagleeyenetworks.com/oauth2/token`. Uses Base64-encoded `app_name:api_key` as Basic auth. Refresh tokens are stored in the Actuate tokens DAO (DynamoDB). The base URL is resolved via `GET /api/v3.0/clientSettings` which returns `httpsBaseUrl` with hostname and port.

### Key Endpoints

- **v3 Camera List** (`GET /api/v3.0/cameras?include=status,notes,capabilities&pageSize=100`): Paginated camera list with status info. Each camera has `name`, `id`, and optional `status` fields.
- **v3 Camera Detail** (`GET /api/v3.0/cameras/{camera_id}`): Single camera lookup; returns 404 if not found.
- **v3 Feeds** (`GET /api/v3.0/feeds?deviceId={camera_id}&type={resolution}&include=rtspUrl`): Returns RTSP stream URLs for a camera. Access token is appended as query parameter.
- **v3 Accounts** (`GET /api/v3.0/accounts`): Lists user accounts, used for proxy token generation.
- **v3 Proxy Tokens** (`POST https://auth.eagleeyenetworks.com/api/v3.0/authorizationTokens`): Creates reseller proxy tokens for accessing cameras across sub-accounts.
- **v2 Camera List** (`GET /g/device/list?A={auth_key}`): Legacy camera list via brand subdomain.
- **v2 Streams** (`GET /api/v2/media/cameras/{camera_id}/streams?A={access_key}`): Returns RTSP stream URL.
- **Camera Manager Streams** (`GET /rest/v2.0/cameras/{camera_id}/streams`): Returns stream URLs including RTSP.

### CHM-Relevant Diagnostics

- **Token validity**: `is_valid_token()` checks `GET /api/v3.0/accounts/self` for 401 responses. Token refresh failures are logged.
- **Camera existence**: `camera_exists_v3()` checks the camera detail endpoint; 404 means confirmed missing. Falls back to proxy tokens for multi-account setups.
- **Feed availability**: Empty feed results (`totalSize == 0`) trigger proxy token fallback, indicating the camera may belong to a sub-account.

### Actuate-Specific Notes

The integration module at `actuate-integration-calls/eagle_eye/eagle_eye_calls.py` is the most complex of the seven, supporting three API generations. Refresh tokens are persisted in DynamoDB via `tokens_dao`. The proxy token mechanism handles multi-tenant Eagle Eye accounts where cameras are spread across sub-accounts. The Confluence KB "API Docs" page (160399389) references Eagle Eye alongside other integrations. The connector auth method is listed as "API Token" in the integration matrix.

### Confluence References

- "API Docs" (kb, page 160399389) -- references Eagle Eye
- "actuate-integration-calls: API Integrations Reference" (EDOCS, page 496336908)
- "vms-connector: Supported Integrations" (EDOCS, page 496828419)
