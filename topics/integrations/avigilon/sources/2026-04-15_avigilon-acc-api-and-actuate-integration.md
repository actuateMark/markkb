---
title: "Source: Avigilon Control Center API and Actuate Integration"
type: source
topic: integrations/avigilon
tags: [source, integration, avigilon, documentation]
ingested: 2026-04-15
author: kb-bot
---

## API Overview

Avigilon Control Center (ACC) exposes a **REST API** that the Actuate connector uses for camera discovery and existence checking. The integration is also referred to as "Avigilon Control Center / Alta Aware" in internal documentation.

### Authentication

Authentication uses **API Token / Session Key** based auth. The session key is passed as a query parameter (`?session={session_key}`) on API requests rather than in headers. The integration matrix in vms-connector docs lists the auth method as "API Token."

### Key Endpoints

- **List Cameras** (`GET {api_endpoint}cameras?session={session_key}`): Returns a JSON response with `result.cameras` array. Each camera object includes an `id` field used for matching. The endpoint is used both for camera discovery and for verifying that a camera still exists on the NVR.

### Camera Existence Check

The `camera_exists_avigilon()` function in `actuate-integration-calls/avigilon/avigilon_utils.py` queries the cameras endpoint and iterates through the results to find a matching `camera_id`. The function follows a defensive pattern: on HTTP errors or exceptions, it returns `True` (assumes camera exists) to avoid false negatives that could cause the connector to incorrectly stop processing a camera. Only a successful response where the camera is definitively not found returns `False`.

### CHM-Relevant Diagnostics

- **Camera existence verification**: The `camera_exists_avigilon()` function can be used to determine if a camera has been removed from the NVR, which is relevant for CHM health status reporting.
- **API reachability**: HTTP status codes from the cameras endpoint indicate whether the ACC server is accessible. Non-OK responses are logged as warnings.
- **Connection parameters**: Uses `verify=False` (skips SSL verification) and a 15-second timeout for API calls.

### Actuate-Specific Notes

The integration module at `actuate-integration-calls/avigilon/avigilon_utils.py` is lightweight -- a single utility function for camera existence checking. The heavier lifting (stream URL construction, authentication lifecycle) likely lives in the vms-connector's camera module. The connector uses RTSP streams for video pulling. Confluence mentions Avigilon in the Integration Migration Status Table (status: "Not Started" as of Oct 2025, referring to rearchitecture migration). The Avigilon integration appears in the "actuate-integration-calls: API Integrations Reference" on EDOCS and the "vms-connector: Supported Integrations" page.

### Confluence References

- "actuate-integration-calls: API Integrations Reference" (EDOCS, page 496336908)
- "vms-connector: Supported Integrations" (EDOCS, page 496828419)
- "Integration Migration Status Table" (kb, page 160269555)
