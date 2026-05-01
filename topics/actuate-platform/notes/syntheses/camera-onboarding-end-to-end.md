---
title: "Camera Onboarding End-to-End"
type: synthesis
topic: actuate-platform
tags: [synthesis, cross-topic, onboarding, admin-api, connector-deployer, settings, watchman, lifecycle, vms-connector]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/product-roadmap/notes/syntheses/improvement-opportunities.md
incoming_updated: 2026-05-01
---

# Camera Onboarding End-to-End

This synthesis traces the full lifecycle of a camera from customer signup to first detection across the current [[actuate-platform/_summary|Actuate Platform Overview]], then contrasts it with the self-service [[onboarding-wizard]] proposed for [[watchman/_summary|Actuate Watchman]]. The two flows reveal fundamentally different assumptions about who the operator is, what infrastructure exists at the customer site, and how much human intervention is acceptable.

## Current Platform: The Partner-Mediated Flow

The current onboarding path is a multi-system, multi-actor process that can take days to complete. Every step involves a human decision routed through a partner monitoring center.

### Step 1: Customer and Site Creation in Admin API

The journey begins in the [[admin-api/_summary|Actuate Admin API]] (Django 6.0 + DRF on ECS). A partner or Actuate operations user creates a customer record via `/api/customer/` and then a site, specifying the VMS integration type (one of 19+ supported: [[rtsp-deep-dive|RTSP]], Milestone, Avigilon, Genetec, etc.), management server IP, credentials, recording server addresses, and alarm sender configurations (Immix recipients, webhook endpoints, etc.). Camera records are created under the site, each with a GUID, resolution, codec, and product assignment (intruder, loitering, weapon, fire, etc.).

For [[actuate-wireguard]] sites, the admin team must provision a WireGuard tunnel so the connector can reach cameras on the customer's private network. This involves Teltonika RUT241 router deployment, tunnel key exchange, and [[actuate-network]] VPC subnet overlap checks. The WireGuard provisioning is tracked as a separate workflow (ENG-117, currently Phase 5A).

### Step 2: Settings File Generation

The [[admin-api/_summary|Actuate Admin API]] generates a [[settings-files|settings.json]] -- a deeply nested JSON document with three top-level sections: `customer` (site metadata, VMS credentials, processing parameters, confidence thresholds, motion detection toggles), `monitoring` (CloudWatch-style alarm definitions for FPS, processing latency, heartbeat), and `recording_servers` (per-camera pipeline config including model name, input size, FPS, polygonal exclusion/inclusion zones, crop regions, area filters, stationary object settings, and per-class IoU thresholds).

Each camera's `streams.production.threat` block is the AI pipeline specification. Getting this right is critical -- incorrect [[ignore-zones|ignore zones]] or confidence thresholds produce either missed detections or an avalanche of false positives. The 150+ [[settings-files|settings files]] in the [[settings-files]] repository testify to the manual effort required. This is the problem [[settings-automation/_summary|Settings Automation (H1.4)]] and the PPF/Classifyr initiatives aim to reduce.

### Step 3: Connector Deployment via connector_deployer

With settings ready, the [[admin-api/_summary|Actuate Admin API]] calls the [[connector-deployer]] FastAPI service (running in the `connector` namespace, 4 production replicas + 1 canary). The deployer's `/start` endpoint receives a `DeploymentRequest` (stage, architecture, NAT, WireGuard flag, image tag, lead) and translates it into Kubernetes resources:

1. **YAML generation** -- The deployer loads base YAML templates (`deployment.py`, `vpa.py`, `pdb.py`) and patches them with site-specific configuration: ECR image URI (mapped from stage and architecture -- `arm_connector_rearch` or `connectors_rearch`), resource requests (memory calculated as `cameras * 32MB + 500MB base`), environment variables, and volume mounts for settings.
2. **K8s resource creation** -- Via `kubernetes-asyncio`, the deployer creates a Deployment in the `rearchitecture` namespace, a paired VerticalPodAutoscaler, and a PodDisruptionBudget. For Camera Health Monitoring, it also creates a randomized CronJob.
3. **Hostname normalization** -- The deployment name is sanitized (lowercase, hyphens, 63-char limit) from the site identifier.

### Step 4: Connector Startup and Frame Acquisition

The connector pod starts, executing `connector.py`. The [[connector-factory]] reads `integration_type` from settings and lazy-imports the matching factory class. The factory calls `core()` to initialize boto3 clients, build observers (loitering, line crossing, blacklist per camera), and start motion listeners. It then constructs camera objects, each with a puller (URL, Milestone, Socket, JPG, S3, SQS, or Buffer depending on VMS type), an [[pipeline-architecture|ImagePipeline]], and configured alarm senders via [[actuate-alarm-senders]].

If the site exceeds the [[sharding|shard size]] (default 24 cameras), `ChunkedSiteManager` forks into multiple processes with round-robin camera distribution, incurring 50-80% CPU overhead but eliminating GIL contention across shards.

The puller thread connects to the camera stream and begins pulling frames. [[rtsp-deep-dive|RTSP]] pullers use [[opencv-entity|OpenCV]]/[[pyav-entity|PyAV]]; Milestone uses a proprietary socket protocol. Frames are stored in the `TTLImageCache` and wrapped in `ImageDataPacket` objects.

### Step 5: First Detection

Frames flow through the three-phase pipeline: pre-processing (resize, motion detection via FDMD), processing (YOLO inference via [[inference-pool|AsyncInferencePool]] with AIMD congestion control, routing to `ds-model-prod` K8s model servers), and post-processing (stationary filter, IoU, [[ignore-zones|ignore zones]], sliding window, confirmation). When an observer triggers (e.g., `IntruderObserver` sees consecutive detections exceeding `frame_thresh`), it opens a detection window, persists frames to S3/DynamoDB, and fires the alert through `MultiAlertSender` to the configured destinations -- Immix SMTP, webhook, SQS queue, or any of 25+ sender types.

**Total elapsed time from signup to first detection:** typically hours to days, depending on WireGuard provisioning, settings tuning, and partner coordination.

## Watchman: The 10-Minute Self-Service Flow

[[watchman/_summary|Actuate Watchman]]'s [[onboarding-wizard]] (F-001) compresses this into a 9-step guided wizard targeting under 10 minutes, with zero technician involvement.

The flow is deliberately sequenced: **infrastructure** (steps 1-3: deployment type selection, WireGuard tunnel setup, WiFi configuration), **discovery** (step 4: ONVIF/[[rtsp-deep-dive|RTSP]] camera discovery on the local network), **context** (steps 5-6: site type classification, camera naming/zone assignment), **people** (step 7: up to 5 emergency contacts with escalation tier assignment), **policy** (step 8: protection priorities influencing patrol camera prioritization and severity weighting), and **activation** (step 9: animated Go Live sequence while agents initialize and the first patrol cycle begins).

### Key Differences

| Dimension | Current Platform | [[watchman-repo|Watchman]] |
|---|---|---|
| **Actor** | Partner ops / Actuate engineer | Business owner (non-technical) |
| **Camera discovery** | Manual IP/GUID entry in Admin API | Automatic ONVIF/[[rtsp-deep-dive|RTSP]] network scan |
| **Settings generation** | Manual JSON configuration (150+ fields) | Inferred from site type + protection priorities |
| **Deployment** | connector_deployer API call from Admin | Automated on Go Live |
| **Time to first alert** | Hours to days | Target < 10 minutes |
| **Tunnel setup** | Separate ops workflow (ENG-117) | Guided wizard step (Teltonika or Actuate Secure App) |
| **Post-setup tuning** | Extensive ([[ignore-zones|ignore zones]], thresholds, sensitivity) | Minimal -- Site Context Agent learns over time |

### What Makes 10 Minutes Possible

[[watchman-repo|Watchman]] achieves this compression by making three structural bets: (1) BYOD cameras eliminate hardware provisioning -- the customer's existing 4-30 cameras are discovered automatically; (2) site type classification replaces per-camera manual tuning -- a retail store gets different defaults than a warehouse; (3) the [[multi-agent-architecture|Learning Agent]] provides a feedback loop that tunes thresholds post-deployment, removing the need for upfront precision.

The current platform's settings file is a 150+ field specification that encodes years of per-site tuning knowledge. [[watchman-repo|Watchman]]'s bet is that VLM-assisted assessment (via the [[vlm-fp-reduction]] filter), site type defaults, and adaptive learning can replace that manual precision with automated approximation good enough for the 4-30 camera market.

### Shared Infrastructure

Despite the radically different user experience, [[watchman-repo|Watchman]]'s onboarding still terminates in the same backend: a [[vms-connector]] deployment, [[actuate-libraries]] pipeline, `ds-model-prod` inference, DynamoDB/S3 storage, and SQS alert delivery. The [[connector-deployer]] will likely still create the K8s resources -- the difference is that the deployment request is generated automatically by the [[onboarding-wizard|onboarding wizard]] rather than manually by an admin user. The question is whether the current deployer's API contract (stage, architecture, NAT, WireGuard flag, image tag) can absorb the self-service flow without significant modification, or whether Watchman needs its own deployment orchestrator.

## Implications

The onboarding gap between the two flows is the clearest expression of the B2B2B-to-B2B pivot. The current flow assumes a skilled intermediary who knows VMS types, network topology, and detection tuning. [[watchman-repo|Watchman]] assumes a business owner who knows their site layout and what they want protected. Bridging this gap requires [[settings-automation/_summary|Settings Automation (H1.4)]] to mature (automated settings generation from site context), [[actuate-wireguard]] to support self-service provisioning, and the [[admin-api/_summary|Actuate Admin API]] to expose onboarding-friendly endpoints that don't require deep platform knowledge. The 10-minute target is aspirational -- but meeting it would validate the entire [[watchman-repo|Watchman]] market thesis.
