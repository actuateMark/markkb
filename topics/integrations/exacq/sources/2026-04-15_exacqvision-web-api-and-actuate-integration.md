---
title: "Source: exacqVision Web API and Actuate Integration"
type: source
topic: integrations/exacq
tags: [source, integration, exacq, documentation]
ingested: 2026-04-15
author: kb-bot
---

## API Overview

exacqVision (by Johnson Controls) exposes an **HTTP REST API** via a built-in web service. The Actuate integration uses this for session management and video stream access. Official API docs: `https://www.exacq.com/integration/developers/` and `https://crm.exacq.com/release/evWebAPI/`.

### Authentication

Authentication uses **session-based HTTP login** with two supported methods depending on server version:

1. **Legacy method** (GET): `http://{server_ip}:{server_port}/login.web?s={server_name}&u={username}&p={password}&responseVersion=2` -- returns JSON with `sessionId`.
2. **New server version** (POST): `http://{server_ip}:{server_port}/login.web` with form data (`mode=simple`, `l=2`, `s={server_name}`, `u={username}`, `p={password}`, `login=Login`). The session ID is extracted from the HTML response via regex matching of `logout.web?s=(.+)"`.

Both methods have 10-second timeouts. If legacy fails, the new method is attempted as fallback.

### Key Endpoints

- **login.web**: Session establishment (GET or POST depending on server version).
- **video.web**: Video frame/stream access. URL parameters include `s` (session), `camera` (camera ID), `format`, `w`/`h` (width/height), `q` (quality 1-10). Supports JPEG pull and HTTP streaming modes.
- **config.web**: Camera configuration. `config.web?output=json&showAll=true` returns JSON with all cameras including substreams.

### Video Format Types

| Format | Type | Connector Behavior |
|--------|------|--------------------|
| 0 | Native JPEG | HTTP pull via video.web |
| 5 | H.264 (AVC) | RTSP stream (`rtsp://{user}:{pass}@{ip}:{stream_port}/{camera_id}`) |
| 6 | Transcoded JPEG | HTTP pull via video.web |
| 7 | H.265 (HEVC) | HTTP stream via video.web with `iframes=0&multipart_encode=0` |

Formats 5 and 7 result in video streaming mode; 0 and 6 result in JPEG frame pulls with configurable quality and resolution.

### CHM-Relevant Diagnostics

- **Session health**: Failure to obtain a session ID indicates the exacq server is unreachable or credentials are invalid. Both login methods are tried before raising an exception.
- **Camera status**: Camera existence can be checked via the config.web endpoint. The `showAll=true` parameter exposes substreams.
- **Recording/storage**: Not directly exposed through the integration-calls module; would require querying the exacq server's storage status endpoints.

### Actuate-Specific Notes

The integration module at `actuate-integration-calls/exacq/exacq_utils.py` provides `get_session_id()` and `get_stream_url()`. There is a dedicated vms-connector reference doc at `docs/integrations/exacq.md` with detailed format/quality documentation. The Confluence KB space has a dedicated "Exacq" page (page 160071956) and "vms-connector: Exacq Integration" (EDOCS page 496402453). The auto-add feature in actuate_admin parses HTML from config.web and does not use `showAll`, so substreams may not be exposed as selectable options.

### Confluence References

- "vms-connector: Exacq Integration" (EDOCS, page 496402453)
- "Exacq" (kb, page 160071956)
- "actuate-integration-calls: API Integrations Reference" (EDOCS, page 496336908)
