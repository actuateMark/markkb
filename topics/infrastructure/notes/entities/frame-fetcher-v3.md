---
title: "Frame Fetcher V3"
type: entity
topic: infrastructure
tags: [lambda, python, dynamodb, s3, presigned-urls, api-gateway, alert-ui]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/infrastructure/notes/entities/create-detection-window.md
  - topics/operational-health/notes/syntheses/2026-05-16_overnight-check.md
incoming_updated: 2026-05-27
---

# Frame Fetcher V3

AWS Lambda that serves the [[alert-ui|alert UI]] by resolving frame and clip metadata from DynamoDB and returning S3 presigned URLs. It is the read-path backend for alert windows, livestream frames, MP4 clips, and AI Link ground-truth playback.

**Repository:** `aegissystems/frame_fetcher_v3`
**Runtime:** Python 3.13 (managed with `uv`)

## What It Does

The handler receives API Gateway events and routes GET/POST requests through a fixed-priority branch chain. Key capabilities:

- **Window frames** -- queries `EnrichedFrameV2` or `DetectedFrameV2` (age-based table selection: <24h prefers enriched, older uses detection with fallback) and returns presigned URLs for each frame.
- **MP4 clips** -- looks up `WindowIdsV2` for `mp4_path`; if none exists, asynchronously invokes `create_detection_window` to regenerate. Windows <1 hour old return an empty list by design. Cold-archived objects return `"cold"`.
- **Livestream** -- returns the latest frame(s) for a `custcam_id` within a configurable `fetch_horizon_hrs`.
- **AI Link** -- loads clips from `AILink_GroundTruth`, choosing between standard and [[sentinel-components|Sentinel]]/YourSix buckets based on username.
- **Authentication** -- shared-password and opaque-token model stored in `AuthorizationV2`. Recent windows (<1 hour) auto-mint tokens; older windows require the password flow.

## DynamoDB Tables

`EnrichedFrameV2`, `DetectedFrameV2`, `WindowIdsV2`, `AuthorizationV2`, and `AILink_GroundTruth`. The first three use GSIs for `window_id` and `custcam_id` time-based queries. Table names for Auth and WindowIds are hard-coded; others come from `framefetcher-params.json`.

## Deployment

`ci/deploy.sh` packages the Lambda zip with region-specific config (US `framefetcher-params.json` or EU `framefetcher-params-eu.json` renamed to the same filename). CI runs tests on push/PR to `main`, then auto-deploys to `us-west-2` and `eu-west-1` via GitHub Actions with OIDC role authentication.

## Key Operational Notes

- POST body parsing uses `eval()` -- safe only because the integration is trusted, but flagged for future migration to `json.loads`.
- Presigned URL lifetime depends on both the config expiry and the Lambda execution role credential validity.
- `custcam_id` encoding uses `num_sign` and `ampersand` placeholders for URL-unsafe characters.
