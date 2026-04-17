---
title: "Source: Digital Watchdog DW Spectrum / IPVMS API and Actuate Integration"
type: source
topic: integrations/digital-watchdog
tags: [source, integration, digital-watchdog, documentation]
ingested: 2026-04-15
author: kb-bot
---

## API Overview

Digital Watchdog DW Spectrum (based on Network Optix / Nx Witness platform, also related to Hanwha Wave) exposes a **REST API** with multiple versions. The Actuate integration supports both legacy `ec2` endpoints and modern `rest/v1`-`v3` endpoints, with optional cloud relay proxy access via `vmsproxy.com`.

### Authentication

Multiple auth methods are supported with cascading fallback:

1. **HTTP Digest Auth**: Primary method -- `HTTPDigestAuth(username, password)` against the server API.
2. **HTTP Basic Auth**: Fallback if Digest fails.
3. **Cloud OAuth2**: For cloud-connected systems, uses OAuth2 password grant to `{cloud_url}/cdb/oauth2/token` with `client_id=3rdParty`. Returns a Bearer token. Requires a `cloud_system_id` which is either configured or resolved via `https://nxvms.com/cdb/system/get`.
4. **Session Token (REST v1)**: POST to `/rest/v1/login/sessions` with JSON credentials, returns a session token.

Cloud user detection queries `/rest/v3/login/users/{username}` (falls back to v2) to check if `type == "cloud"`.

### Key Endpoints

- **Camera List (legacy)**: `GET /ec2/getCamerasEx?format=json` -- returns JSON array of camera objects with `id` (GUID) fields.
- **Camera List (v5/REST)**: `GET /rest/v1/devices` -- modern device listing endpoint.
- **System Info**: `GET /rest/v{2,3}/system/info` -- returns `cloudHost` for determining the cloud relay domain.
- **System Settings**: `GET/PATCH /rest/v3/system/settings` or `GET /api/systemSettings?maxWebMTranscoders={count}` -- used to increase transcoding connection limits. The `increase_connection_count()` function tries Basic auth, Digest auth, and Bearer token PATCH in sequence.
- **Cloud Relay**: `https://{cloud_system_id}.relay.vmsproxy.com/` -- cloud proxy URLs for remote access.
- **Hard Drive Status** (from Confluence KB): Returns JSON with `freeSpace`, `isOnline`, `isUsedForWriting`, `isWritable`, `name`, `reservedSpace`, `serverId`, `storageId`, `storageStatus` fields.

### CHM-Relevant Diagnostics

- **Storage health**: The `test_harddrive_connection` data (from Confluence "Digital Watchdog" page) includes `freeSpace`, `isOnline`, `isWritable`, `storageStatus` -- directly relevant for storage monitoring.
- **Camera existence**: `camera_exists_dw()` queries the camera list and iterates to find matching `id` GUIDs (stripping braces). Supports both Digest and Basic auth fallback.
- **Connection limits**: `increase_connection_count()` adjusts `maxWebMTranscoders` and `maxHttpTranscodingSessions` to prevent connection throttling. Tries 5+ auth/method combinations.
- **Aspect ratio mismatches**: `check_mismatch()` compares primary and substream resolutions to detect aspect ratio discrepancies that could affect inference quality.
- **Cloud connectivity**: Cloud relay reachability via `vmsproxy.com` domains indicates whether remote access is functional.

### Actuate-Specific Notes

The integration module at `actuate-integration-calls/digital_watchdog/dw_utils.py` is one of the largest (~500 lines). Config supports `use_nx_proxy` (cloud relay), `use_v5` (REST v1 vs ec2), and separate `nx_username`/`nx_password` for cloud auth. The Confluence KB has two relevant pages: "Digital Watchdog" (page 160268625) with storage JSON examples, and "Digital Watchdog / Hanwha Wave" (page 160071905) with links to Nx Community Forums and HTTP motion configuration docs.

### Confluence References

- "Digital Watchdog" (kb, page 160268625) -- storage status JSON examples
- "Digital Watchdog / Hanwha Wave" (kb, page 160071905) -- resources, motion config
- "vms-connector: Supported Integrations" (EDOCS, page 496828419)
- "Motion Filters" (kb, page 160268644) -- DW HTTP motion configuration
