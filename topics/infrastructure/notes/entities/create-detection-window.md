---
title: "Create Detection Window"
type: entity
topic: infrastructure
tags: [lambda, python, mp4, opencv, ffmpeg, dynamodb, s3, sam]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# Create Detection Window

AWS Lambda that generates MP4 video clips from detection frame sequences. It is the write-path companion to [[frame-fetcher-v3]], which invokes it asynchronously when a window exists but has no `mp4_path`.

**Repository:** `aegissystems/create_detection_window`
**Runtime:** Python 3.9+ with [[opencv-entity|OpenCV]], [[ffmpeg-entity|FFmpeg]], and Slugify Lambda layers
**IaC:** AWS SAM (`template.yaml` + `samconfig.toml`)

## Processing Pipeline

1. Receives a `window_id` as input.
2. Queries DynamoDB (`DetectedFrameV2`, `EnrichedFrameV2`, `WindowIdsV2`) for frame metadata.
3. Downloads frame images from S3.
4. Draws bounding boxes on frames using [[opencv-entity|OpenCV]].
5. Encodes the annotated frame sequence into an MP4 using [[ffmpeg-entity|FFmpeg]].
6. Uploads the MP4 and a representative first frame to S3.
7. Updates DynamoDB with the resulting `mp4_path` and storage metadata.

## AWS Resources

The SAM template provisions the Lambda function, an IAM execution role (re-uses the existing `video-analyzer-stack` role), a CloudWatch log group, CloudWatch alarms for error and duration monitoring, and a dead-letter queue for failed invocations. The function runs inside a VPC with access to DynamoDB and the relevant S3 buckets (`detection-frames-aegis-v2`, `actuate-2-month-storage`, `actuate-6-month-storage`).

## Deployment

Three options:

- **`deploy.sh`** -- wrapper script supporting `dev`/`prod` stages, optional `--build-only` and `--force` flags.
- **SAM CLI** -- `sam build --use-container` then `sam deploy --config-env dev|prod`.
- **GitHub Actions** -- `develop.yml` auto-deploys to dev on push to `develop`. Production deployment on `main.yml` is currently disabled; manual trigger is available.

Function names: `create_detection_window_dev` (dev) and `create_detection_window_prod` (prod).

## Testing

The `invoke_mp4_lambda.py` utility script clears DynamoDB flags and re-invokes the Lambda for a given `window_id`, useful for forcing MP4 regeneration during debugging. Accepts `--stage`, `--window_id`, and `--url` parameters.

Local development uses `uv sync` for dependency installation (Lambda layers provide runtime deps; local deps are for dev/test only).
