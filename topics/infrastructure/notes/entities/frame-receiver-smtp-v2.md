---
title: "Frame Receiver SMTP V2"
type: entity
topic: infrastructure
tags: [smtp, frame-receiver, eks, kubernetes, argocd, motion-signals, ecr]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Frame Receiver SMTP V2

An SMTP server that receives email messages from on-premises cameras and NVRs, extracts frame image data and metadata, and uploads them to S3. It also interprets SMTP-based motion signals for sites configured to use that delivery method.

**Repository:** `aegissystems/frame_receiver_smtp_v2`
**Runtime:** Kubernetes pod on AWS EKS

## How It Works

When a camera sends an SMTP message containing an image attachment, the server parses the message, extracts the frame data and associated metadata, and uploads to S3 for downstream processing. The server uses multi-threaded workers (`MAX_WORKERS`, default 16) for concurrent message processing.

**Motion signals:** When a site selects SMTP as its motion delivery method, the server recognises motion signal messages, sends a notification to the motion signal queue, and discards the message body without uploading to S3.

**Inactive site filtering:** Messages for sites that have not updated their heartbeat within the last 15 minutes are silently discarded, reducing unnecessary processing.

## Encoded Usernames

The server supports encoded SMTP usernames for camera-to-server authentication. The `src/encoder.py` module provides `encode_smtp_username()` and `decode_smtp_username()` functions. Decoded usernames are cached in memory (up to `MAX_CACHE_SIZE`, default 250,000 entries). At startup, the cache is seeded with camera IDs (85% of capacity) and site IDs (15%).

## Deployment

Deployed to EKS via ArgoCD. The production manifest lives at `deployment/manifest.yaml` and the ArgoCD application at `argocd/application.yaml`. To release a new version, update the image tag in the manifest and commit -- ArgoCD handles the rollout. A separate dev manifest exists for pre-release container testing but is not tracked by ArgoCD and is not NLB-reachable.

## CI/CD

Commit messages containing `#minor`, `#major`, or `#patch` trigger a GitHub Actions build that pushes a new semver-tagged image to ECR and creates a corresponding Git release.

## Key Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `MAX_CACHE_SIZE` | 250,000 | Max decoded username cache entries |
| `DEREGISTRATION_DELAY_SLEEP` | 360s | Graceful shutdown sleep for NLB deregistration |
| `MAX_WORKERS` | 16 | Concurrent message processing threads |

The `DEREGISTRATION_DELAY_SLEEP` value should exceed `terminationGracePeriodSeconds`, which in turn should exceed the NLB deregistration delay, to avoid dropped connections during pod termination.
