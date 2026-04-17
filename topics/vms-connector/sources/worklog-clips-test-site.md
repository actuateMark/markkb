---
title: "Source: Clips Test Site Admin Settings Design"
type: source
topic: vms-connector
tags: [worklog, clips, test-site, admin, s3, deployment]
ingested: 2026-04-14
author: kb-bot
---

# Clips Test Site Admin Settings Design

**Origin:** `/home/mork/Documents/worklog/worklog/projects/clips test site/admin settings.md`

Design notes for a clips test site feature that allows uploading video clips for a given camera into an S3 bucket, with associated admin UI configuration.

## S3 Bucket Structure

Proposed path: `{standard-bucket-name}/{site-name}/{camera-name}/`

Uploads are configured per-camera. The initial plan was to enable it on all cameras but the note suggests adding it to verifier-flagged ones at minimum.

## Admin Configuration

- Add a "verifier" setting in the integrations dropdown.
- Add corresponding deployment settings and test deploy config.
- All settings live at the camera level (not site level).
- No S3 override needed -- uses the standard bucket.

## Clip File Model

Each uploaded clip file would be stored with metadata:

- **bucket_name**: Pre-filled with the default bucket when the form is created.
- **filename**: The clip file name.
- **site**: Site identifier.
- **camera_name**: Human-readable camera name.
- **camera_id**: Stable identifier (prevents broken references if the camera name changes).

## Additional Endpoints

- A "create bucket" endpoint for initial provisioning.
- A clip upload endpoint scoped to a specific camera.

## Significance

These notes capture early design thinking for the clips verification workflow. The key design decisions are: camera-level granularity, stable camera_id references (decoupled from mutable camera names), and use of the standard S3 bucket with a hierarchical path convention.
