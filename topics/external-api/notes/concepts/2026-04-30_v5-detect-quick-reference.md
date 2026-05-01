---
title: "v5 /detect quick reference for partner integrations"
type: concept
topic: external-api
tags: [v5, partner-docs, integration, quick-start]
created: 2026-04-30
updated: 2026-04-30
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# v5 `/detect` Quick Reference

A short, copy-pasteable answer for partners who are wiring up the v5 API for the first time and want clarity on the endpoint URL, where each parameter goes, and a complete working request.

## What partners typically ask

- **"Which URL do I call to run inference?"** — There is one inference endpoint: `POST /v5/detect`. The model name is a JSON body field (`model_id`), not a path segment. URLs like `/v5/intruder/detections` or `/v5/{model}/detect` will return 404.
- **"Where do `camera_id`, `max_slices`, `sensitivity` go — query string, form-data, or body?"** — Everything goes in the **JSON request body** with `Content-Type: application/json`. Nothing is sent as form-data or query parameters. Request shape is fixed: top-level fields for `model_id` / `frames` / `camera_id` / `site_id`, and a nested `data` object for model-specific tuning.
- **"Can I see a complete request?"** — Yes, full `curl` examples are below, plus the live Swagger UI auto-filters to whatever your API key can access.

---

Currently, there is one inference endpoint: `POST /v5/detect`. The model name is a JSON body field (`model_id`), we don't go by the path currently, that was in our older endpoints. URLs like `/v5/intruder/detections` or `/v5/{model}/detect` will return 404.
All arguments (camera_id, max_slices, sensitivity) go in the **JSON request body** with `Content-Type: application/json`. Nothing is sent as form-data or query parameters. There is only one request format for all models. There are a few shared top-level fields for `model_id` / `frames` / `camera_id` / `site_id`, and a nested `data` object for model-specific tuning.
For reference, I've included a full curl example below as well as a list of the relevant endpoints for the API and documentation. The credentials we provided should allow access to the /docs endpoint. 

## Endpoints

| Purpose                                | Method + URL                                   |
| -------------------------------------- | ---------------------------------------------- |
| Run inference (any model)              | `POST https://dev-api.actuateui.net/v5/detect` |
| List available models for your API key | `GET https://dev-api.actuateui.net/v5/models`  |
| Interactive Swagger UI (role-filtered) | `https://dev-api.actuateui.net/docs`           |
| OpenAPI JSON (for codegen / Postman)   | `https://dev-api.actuateui.net/openapi.json`   |

The Swagger UI filters its contents to match the permissions on the API key making the request, so what you see is exactly what you can call.

---

## Request structure

All parameters belong in the JSON body:

```json
{
  "model_id": "intruder",
  "frames": ["<base64 JPEG>", "<base64 JPEG>"],
  "data": {
    "sensitivity": "medium",
    "max_slices": 1,
    "stationary_filter": "false",
    "ignore_labels": []
  },
  "camera_id": "cam-lobby-01",
  "site_id": "site-hq"
}
```

| Field | Location | Required | Notes |
|-------|----------|----------|-------|
| `model_id` | top-level | yes | One of the `id` values returned by `GET /v5/models` |
| `frames` | top-level | yes | Array of 1–15 entries; each entry is either a base64-encoded JPEG or an `http(s)://` URL to a JPEG |
| `data` | top-level | no | Object holding model-specific tuning. Defaults applied if omitted. |
| `camera_id` | top-level | no | Echoed back in the response (max 256 chars) |
| `site_id` | top-level | no | Echoed back in the response (max 256 chars) |
| `data.sensitivity` | nested | no | `"low"`, `"medium"`, `"high"`, or a float `0 < x < 1.0`. Default `"medium"`. |
| `data.max_slices` | nested | no | `intruder` only. `1` (default) = single-pass; `2`–`9` = multi-tile inference for high-resolution images. |
| `data.stationary_filter` | nested | no | `"true"` removes stationary objects, `"tag"` marks them, `"false"` disables. Requires 2+ frames. |
| `data.ignore_labels` | nested | no | Array of detection-class names to drop from the response. |

The accepted fields under `data` vary per model — call `GET /v5/models` and inspect each model's `data_schema` for the authoritative list.

### Frame size limits

- Maximum 15 frames per request
- Maximum 8192 × 8192 pixels per frame
- Base64 frames must be ≤ ~4.5 MB encoded — for larger images, host the JPEG and pass an `http(s)://` URL in the `frames` array instead.

---

## Complete examples

### 1. Single base64-encoded frame

```bash
# Encode the image (single line, no wrapping)
BASE64_FRAME=$(base64 -w 0 my_image.jpg)

curl -X POST https://dev-api.actuateui.net/v5/detect \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model_id\": \"intruder\",
    \"frames\": [\"$BASE64_FRAME\"],
    \"data\": {
      \"sensitivity\": \"medium\",
      \"max_slices\": 1
    },
    \"camera_id\": \"cam-lobby-01\",
    \"site_id\": \"site-hq\"
  }"
```

### 2. Multiple frames via URL

```bash
curl -X POST https://dev-api.actuateui.net/v5/detect \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model_id": "intruder",
    "frames": [
      "https://your-server.com/frame1.jpg",
      "https://your-server.com/frame2.jpg"
    ],
    "data": {
      "sensitivity": "high",
      "ignore_labels": ["bicycle"]
    },
    "camera_id": "cam-lobby-01"
  }'
```

### 3. High-resolution slicing for distant or small objects

```bash
curl -X POST https://dev-api.actuateui.net/v5/detect \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model_id": "intruder",
    "frames": ["<base64 high-resolution frame>"],
    "data": {
      "sensitivity": "medium",
      "max_slices": 4
    }
  }'
```

---

## Response shape

`200 OK`:

```json
{
  "model_id": "intruder",
  "detections": {
    "0": [
      {
        "label": "person",
        "confidence": 0.87,
        "center_x": 640.0,
        "center_y": 360.0,
        "width": 120.0,
        "height": 280.0
      },
      {
        "label": "car",
        "confidence": 0.72,
        "center_x": 400.0,
        "center_y": 300.0,
        "width": 200.0,
        "height": 100.0
      }
    ],
    "1": []
  },
  "camera_id": "cam-lobby-01",
  "site_id": "site-hq"
}
```

`detections` is keyed by frame index (`"0"` is the first frame in the request, `"1"` the second, etc.). Each value is the list of objects detected in that frame.

| Field | Type | Description |
|-------|------|-------------|
| `model_id` | string | Echo of the model that ran |
| `detections[N][].label` | string | Detected class (e.g. `"person"`, `"car"`) |
| `detections[N][].confidence` | float | Confidence score 0.0–1.0 |
| `detections[N][].center_x/y` | float | Bounding-box center in pixels |
| `detections[N][].width/height` | float | Bounding-box dimensions in pixels |
| `detections[N][].tags` | string[] or null | Optional, e.g. `"stationary_detection"` when stationary filter is in `tag` mode |
| `camera_id` / `site_id` | string or null | Echoed back from request, omitted if not sent |

---

## Common error codes

| Status | Meaning                                                                             |
| ------ | ----------------------------------------------------------------------------------- |
| `400`  | Bad request — invalid image, insufficient frames, or invalid parameter value        |
| `403`  | Your API key does not have access to the specified model                            |
| `404`  | Unknown `model_id` (or you hit a URL that doesn't exist — see endpoint table above) |
| `422`  | Invalid `data` parameters for the specified model                                   |
| `500`  | Server error                                                                        |

---

## Cross-links

- [[v5-api-design]]
- [[ebus-partner-access]]
- [[2026-04-29_v5-slicing-as-parameter]] — internal note on the slicing-as-parameter pattern
- [[partner-api-credential-runbook]]
