---
title: "Ajax Integration"
type: summary
topic: integrations/ajax
tags: [integration, api-client, ajax]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Ajax Integration

Ajax Systems is a security hardware manufacturer producing wireless alarm systems, hubs, and video devices (NVRs / "video edges"). Actuate integrates with Ajax primarily to provision ONVIF users, discover cameras, and build RTSP URLs so that Ajax video-edge devices can be onboarded into the Actuate pipeline.

## Components

### AjaxCalls -- Integration Calls Module

Defined in [[actuate-integration-calls]] at `ajax/ajax.py`. The `AjaxCalls` class is an API client that wraps the Ajax cloud REST API. Key capabilities:

- **Login** -- authenticates with username + password hash to obtain a session token.
- **Hub discovery** -- lists hubs for a user and resolves a hub by name to its ID.
- **ONVIF user management** -- creates ONVIF users on video-edge devices so Actuate can pull RTSP streams.
- **RTSP URL construction** -- combines the video edge's IP address, RTSP port, channel ID, and ONVIF credentials into an `rtsp://` URL (`rtsp://[User]:[Pass]@[IP]:[Port]/[channelId]_[m|s]`).
- **Camera enumeration** -- retrieves cameras attached to a hub for automated onboarding.

### Puller

No dedicated Ajax puller exists. Once an RTSP URL is constructed via `AjaxCalls`, the standard RTSP puller in [[actuate-pullers]] handles frame ingestion.

### Alarm Sender

There is no Ajax-specific alarm sender. Alert delivery uses whichever monitoring sender is configured on the site.

## Auth Method

Authentication uses **two layers**:

1. **API-key auth** -- every request includes an `X-API-Key` header. The key, company ID, company token, and base URL are retrieved from the Actuate admin API (`AdminApi.get_named_configuration`).
2. **Session-token auth** -- the `login` endpoint returns a session token used in `X-Session-Token` headers. Alternatively, a company-level `X-Company-Token` can be used for operations that support it.

All credentials are stored centrally and fetched at `AjaxCalls.__init__` time.

## Key Config Fields

Ajax credentials are **not** stored in the per-site `settings.json`. They are global named configurations: `ajax_company_id`, `ajax_x_company_token`, `ajax_api_key`, `ajax_api_base_url`, `ajax_username`, `ajax_password_hash`, `ajax_user_id`.

## Relationship to Other Components

- [[actuate-integration-calls]] -- AjaxCalls lives here, providing the REST API client
- [[actuate-pullers]] -- standard RTSP puller consumes the URLs built by AjaxCalls
- [[vms-connector]] -- uses AjaxCalls during onboarding workflows to provision cameras
- [[actuate-alarm-senders]] -- no Ajax-specific sender
