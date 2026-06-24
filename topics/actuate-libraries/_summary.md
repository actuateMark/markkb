---
title: Actuate Libraries
type: summary
topic: actuate-libraries
tags: [libraries, monorepo, uv, codeartifact, shared-packages]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497221647"
created: 2026-04-13
updated: 2026-04-14
author: kb-bot
---

# Actuate Libraries

41 Python packages managed as a **UV workspace monorepo**. Published to AWS CodeArtifact (`actuate-388576304176.d.codeartifact.us-west-2.amazonaws.com/pypi/actuate/simple/`). CI auto-publishes on merge to main.

## Library Catalog

### Core Processing (7)
| Package | Version | Purpose |
|---------|---------|---------|
| actuate-pipeline | 2.11.18 | Chain-of-responsibility frame processing (4 pipeline types) |
| actuate-pipeline-objects | 1.6.0 | ImageDataPacket, ProductDataPacket, WindowDataPacket |
| actuate-frames | 2.0.0 | Frame metadata persistence to S3/DynamoDB |
| actuate-filters | 2.0.4 | Detection filters (IOU, confidence, [[ignore-zones|ignore zones]], blacklist, stationary) |
| actuate-math | 1.1.0 | Bounding box operations, IOU calculations, NMS |
| actuate-image-cache | 1.2.0 | Thread-safe LRU/TTL image caching |
| actuate-threadpool | 1.2.0 | Error-handling ThreadPoolExecutor wrapper |

### Camera & Stream (6)
| Package | Version | Purpose |
|---------|---------|---------|
| [[actuate-pullers]] | 1.17.7 | Unified frame pulling from 19+ VMS sources |
| [[actuate-movement]] | 1.2.5 | Frame-difference motion detection (CPU + GPU CUDA) |
| [[actuate-suddenscenechange]] | 2.3.2 | SIFT-based camera tampering/[[scene-change-detection|scene change detection]] |
| [[actuate-blur]] | 1.1.3 | FFT-based blur detection |
| [[actuate-imutils]] | 1.0.4 | [[opencv-entity|OpenCV]] image processing utilities |
| [[actuate-image-manipulation]] | 1.1.6 | Fisheye dewarping via native C library |

### AI & Inference (7)
| Package | Version | Purpose |
|---------|---------|---------|
| [[actuate-inference-client]] | 1.1.2 | HTTP client for YOLO model servers (httpx, sync+async) |
| [[actuate-classic-inference-client]] | 2.2.4 | Legacy inference client (to be deprecated) |
| [[actuate-inference-objects]] | 1.2.0 | Detection, BoundingBox, format_detections |
| [[actuate-inference-slicing]] | 1.0.1 | SAHI-style sliced inference for high-res images |
| [[actuate-vlm]] | 0.3.1 | Vision Language Model client (SQS + DynamoDB polling) |
| [[actuate-botsort]] | 1.2.0 | BoT-SORT multi-object tracker (Kalman + appearance features) |
| [[actuate-sort]] | 1.0.2 | SORT tracking (Kalman + IoU association) |

### Integration & Alerting (5)
| Package | Version | Purpose |
|---------|---------|---------|
| [[actuate-integration-calls]] | -- | VMS API clients ([[ajax-components|Ajax]], AutoPatrol, Avigilon, DW, Eagle Eye, Exacq, [[hikcentral-components|HikCentral]], LISA, Milestone) |
| [[actuate-alarm-senders]] | -- | 25+ alert sender implementations |
| [[actuate-connector-observers]] | -- | [[observer-pattern|Observer pattern]] (intruder, loiterer, line crossing, blacklist) |
| [[actuate-event-listener]] | 1.1.4 | Analytics event sending via SQS FIFO |
| [[actuate-notification]] | 1.0.2 | Slack (SNS) and email (SES) notifications |

### Configuration & Data (6)
| Package | Version | Purpose |
|---------|---------|---------|
| [[actuate-config]] | -- | Settings.json parsing into typed objects (20+ VMS configs, 25+ alert configs) |
| [[actuate-daos]] | -- | DAO library (17 DAOs: DynamoDB, S3, SQS, SNS, PostgreSQL, CloudWatch, NR, Datadog) |
| [[actuate-admin-api]] | 1.2.2 | Admin API client (cameras, customers, models, configs) |
| [[actuate-secrets]] | 1.0.1 | AWS Secrets Manager wrapper with caching |
| [[actuate-sqs]] | 1.1.1 | SQS message sending wrapper (standard + FIFO) |
| [[actuate-queue-consumer]] | 1.0.0 | SQS consumer base framework with SIGTERM handling |

### Health & Monitoring (4)
| Package | Version | Purpose |
|---------|---------|---------|
| [[actuate-healthcheck-objects]] | 1.1.2 | Healthcheck data objects |
| [[actuate-healthmonitoring]] | 1.0.5 | SES/SNS/job queue alert mechanisms |
| [[actuate-monitoring]] | 1.1.4 | Deployment health ([[new-relic|New Relic]], CloudWatch, Datadog) |
| [[actuate-instrumentation]] | 0.0.3 | Data capture for debugging |

### Utilities (5)
| Package | Version | Purpose |
|---------|---------|---------|
| [[actuate-log]] | 1.0.2 | Logging configuration, ActuateLogAdapter |
| [[actuate-viz]] | 1.1.5 | Detection bounding box drawing, [[ignore-zones|ignore zones]], trajectories |
| [[actuate-network]] | 1.0.4 | VPC subnet overlap checks, VPN route integration |
| [[actuate-wireguard]] | 1.0.9 | WireGuard tunnel management, Teltonika RMS |
| [[actuate-tests]] | 0.0.3 | Shared test utilities and sample data |

## Dev Workflow

1. Feature branch in actuate-libraries
2. Dev version published to CodeArtifact automatically
3. Consumer repo (vms-connector) pins dev version for testing
4. Merge to main → stable version published
5. Consumer pins stable version → merge to rearchitecture

See [[dev-workflow]] for the conceptual model, [[ci-pipeline-mechanics]] for the CI publish pipeline internals and known workarounds, and [[2026-04-14_connector-library-deployment-lifecycle]] for the full operational process.

### Known CI Issues (April 2026)

- **`gh pr merge` doesn't trigger workflows** — the GitHub API merge uses a token that suppresses further CI. Workaround: push an empty commit to main after merge.
- **`bump-version-stable.sh` JSON quoting bug** — `xargs -P` mangles JSON args to `jq` when `[patch]`/`[minor]` tags are in the commit message. Workaround: manually bump with `uv version --package <lib> --frozen <version>`, commit with `[no ci]`, then push empty commit to trigger publish.
