---
title: "Ajax Integration Components"
type: entity
topic: integrations/ajax
tags: [integration, ajax, components, rtsp]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/entities/actuate-integration-calls.md
  - topics/actuate-platform/notes/concepts/multi-region-deployment.md
  - topics/actuate-platform/notes/syntheses/integration-landscape.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase4-generic-diagnostics.md
  - topics/integrations/ajax/_summary.md
  - topics/team-structure/notes/entities/paolo-zilioti.md
incoming_updated: 2026-05-01
---

# Ajax Integration Components

Ajax Systems is a security hardware vendor whose "video edge" NVR devices support ONVIF and [[rtsp-deep-dive|RTSP]]. The Actuate integration uses the Ajax cloud API to discover cameras, create ONVIF users, and construct [[rtsp-deep-dive|RTSP]] URLs for video pulling. At runtime, frames are pulled via the standard SMTP/[[rtsp-deep-dive|RTSP]] path since Ajax camera events arrive via SMTP.

## Integration Calls -- AjaxCalls

Defined in [[actuate-pullers]]'s sibling library `actuate-integration-calls` at `actuate_integration_calls/ajax/ajax.py`. The `AjaxCalls` class provides API methods for interacting with Ajax cloud services.

### Authentication

- **Credentials**: Retrieved from the [[actuate-admin-api|Actuate admin API]] (`AdminApi.get_named_configuration`): `ajax_company_id`, `ajax_x_company_token`, `ajax_api_key`, `ajax_api_base_url`, `ajax_username`, `ajax_password_hash`, `ajax_user_id`.
- **Login** (`__login`): Posts username + password hash to `/login` endpoint with `X-API-Key` header. Returns a `sessionToken`.
- **Dual auth modes**: Methods support either company-level auth (`X-Company-Token` header) or user-level auth (`X-Session-Token` header).

### Hub and Camera Discovery

- **`__get_hub_id`**: Iterates hubs at `/user/{user_id}/hubs`, fetches each hub's info, matches by name, returns the `hubId`.
- **`__get_cameras_from_hub`**: Lists cameras from `/user/{user_id}/hubs/{hub_id}/cameras` via session token auth. Returns camera IDs and names.
- **`__get_video_edge`**: Fetches video edge device info at `/company/{company_id}/spaces/{space_id}/devices/video-edges/{video_edge_id}`. Returns channel list and network interface configuration.

### ONVIF User Management

- **`__create_onvif_user`**: Creates an ONVIF user (username, password, role) on a video edge device. Uses the endpoint `/company/{company_id}/spaces/{space_id}/devices/video-edges/{video_edge_id}/onvif/users`. Roles can be `ADMIN`, `OPERATOR`, or `USER`.

### RTSP URL Construction

- **`__get_rtsp_settings`**: Fetches [[rtsp-deep-dive|RTSP]] port (`httpPort`) from `/company/{company_id}/spaces/{space_id}/devices/video-edges/{video_edge_id}/rtsp`.
- **`__build_rtsp_url`**: Constructs an [[rtsp-deep-dive|RTSP]] URL in the format `rtsp://[User]:[Password]@[Address]:[RTSP port]/[channelId]_[m|s]` where `m` = mainstream and `s` = substream. Extracts the IP address from the video edge's ethernet or wifi network interface. Can optionally create an ONVIF user as part of URL construction.

## Config Classes

Ajax sites use `SMTPConnectorConfig` from [[actuate-config]] (`actuate_config/connector/smtp/smtp_config.py`) because camera events arrive via SMTP. In `factory.py`, `integration_type == "ajax"` routes to `SMTPConnectorFactory`:

```python
if integration_type == "SMTP_per_camera" or integration_type == "ajax":
    from ..smtp.smtp_factory import SMTPConnectorFactory as Factory
```

- **SMTPCustomerConfig** -- adds `smtp_port`, optional `smtp_auth_port`, and filename reading config.
- **SMTPCamera** -- standard `CameraConfig` with no additional fields.

## Video Pulling

At runtime, Ajax cameras push motion event images via SMTP. The SMTP receiver in [[vms-connector]] accepts these and feeds them into the pipeline. For sites that also need continuous [[rtsp-deep-dive|RTSP]] streaming, the [[rtsp-deep-dive|RTSP]] URL constructed by `AjaxCalls` is used with the standard `AvUrlFramePuller` or `UrlFramePuller`.

## Key Architectural Notes

- Ajax API credentials are global (per-company), not per-site. They are stored centrally in the admin configuration.
- The integration bridges two protocols: Ajax cloud API for device discovery/management, and ONVIF/[[rtsp-deep-dive|RTSP]] for actual video access.
- ONVIF user creation is a one-time setup step; the resulting credentials are then used in [[rtsp-deep-dive|RTSP]] URLs for ongoing streaming.
