---
type: concept
topic: actuate-libraries
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
incoming:
  - topics/fleet-architecture/notes/concepts/library-decomposition-required.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/personal-laptop/notes/concepts/2026-04-27_handoff-repos-architectural-dashboard.md
  - topics/vms-connector/notes/syntheses/connector-evolution.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-05-01
---

# Dependency Graph

The 41 libraries in the actuate-libraries monorepo form a directed acyclic graph of internal dependencies. Understanding which libraries are leaves (no actuate dependencies), which are core (many dependents), and which are high-fan-out (many dependencies) is essential for assessing the blast radius of any change.

## Leaf Libraries (No Internal Dependencies)

These libraries depend only on external PyPI packages and can be changed with minimal risk of cascading breakage:

- [[actuate-filterpy]] -- vendored Kalman filter (numpy, scipy only)
- [[actuate-log]] -- logging utilities (stdlib only, zero dependencies)
- [[actuate-healthcheck-objects]] -- healthcheck data objects (pure data classes)
- [[actuate-queue-consumer]] -- SQS consumer base (zero declared deps)
- [[actuate-sqs]] -- SQS sender (boto3 only)
- [[actuate-secrets]] -- AWS Secrets Manager wrapper (boto3 only)
- [[actuate-network]] -- subnet validation (boto3 only)
- [[actuate-notification]] -- Slack/email notifications (boto3 only)
- [[actuate-imutils]] -- [[opencv-entity|OpenCV]] image utilities
- [[actuate-math]] -- bounding box math, NMS, IoU
- [[actuate-instrumentation]] -- data capture for debugging

## Core Libraries (Many Dependents)

These are depended on by many other libraries. A breaking change here cascades widely:

**[[actuate-config]]** -- consumed by virtually every library that needs runtime configuration. Direct dependents include [[actuate-daos]], [[actuate-connector-observers]], [[actuate-pullers]], [[actuate-classic-inference-client]], [[actuate-monitoring]], [[actuate-movement]], and more. It itself depends on [[actuate-admin-api]] and [[actuate-daos]], creating a tight bidirectional coupling at the config/data layer.

**[[actuate-daos]]** -- the data access layer. Depended on by [[actuate-alarm-senders]], [[actuate-connector-observers]], [[actuate-classic-inference-client]], [[actuate-monitoring]], and [[actuate-pullers]]. Depends on [[actuate-threadpool]], [[actuate-healthcheck-objects]], [[actuate-config]], and [[actuate-admin-api]].

**[[actuate-inference-objects]]** -- the canonical Detection/BoundingBox types. Consumed by [[actuate-inference-client]], [[actuate-inference-slicing]], [[actuate-filters]], [[actuate-connector-observers]], [[actuate-viz]], [[actuate-pipeline-objects]], and [[actuate-alarm-senders]]. Depends on [[actuate-imutils]] and [[actuate-math]].

**[[actuate-pipeline-objects]]** -- ImageDataPacket, WindowDataPacket, and related frame-processing types. Used by [[actuate-connector-observers]], [[actuate-alarm-senders]], [[actuate-pullers]], [[actuate-healthmonitoring]], and the pipeline itself.

**[[actuate-threadpool]]** -- error-handling ThreadPoolExecutor wrapper, used by [[actuate-daos]], [[actuate-alarm-senders]], [[actuate-connector-observers]], [[actuate-classic-inference-client]], and [[actuate-integration-calls]].

## High-Fan-Out Libraries (Many Dependencies)

**[[actuate-connector-observers]]** has the widest dependency fan-out of any library, pulling in: [[actuate-alarm-senders]], [[actuate-config]], [[actuate-pipeline-objects]], [[actuate-filters]], [[actuate-botsort]], [[actuate-daos]], [[actuate-frames]], [[actuate-sort]], [[actuate-imutils]], [[actuate-image-cache]], [[actuate-threadpool]], and [[actuate-inference-objects]]. A change to any of these can affect observer behavior.

**[[actuate-alarm-senders]]** depends on: [[actuate-integration-calls]], [[actuate-inference-objects]], [[actuate-viz]], [[actuate-daos]], [[actuate-event-listener]], [[actuate-pipeline-objects]], [[actuate-secrets]], and [[actuate-threadpool]].

**[[actuate-pullers]]** depends on: [[actuate-image-cache]], [[actuate-config]], [[actuate-movement]], [[actuate-pipeline-objects]], [[actuate-healthmonitoring]], and [[actuate-connector-observers]].

## Key Dependency Chains

**Inference chain**: [[actuate-filterpy]] -> [[actuate-botsort]] / [[actuate-sort]] -> [[actuate-connector-observers]]. The Kalman filter library underpins both trackers, which feed into the observers.

**Alert chain**: [[actuate-integration-calls]] -> [[actuate-alarm-senders]] -> [[actuate-connector-observers]]. VMS API calls are wrapped by alarm senders, which are held by observers.

**Frame acquisition chain**: [[actuate-movement]] + [[actuate-image-cache]] -> [[actuate-pullers]]. Motion detection gates frame submission, and the image cache stores decoded frames for downstream consumers.

**Config/data backbone**: [[actuate-secrets]] -> [[actuate-admin-api]] -> [[actuate-config]] <-> [[actuate-daos]]. Secrets retrieval feeds into the admin API, which feeds config parsing and data access. The bidirectional dependency between config and daos is a known coupling point.

## Practical Implications

When modifying a leaf library, only its direct consumers need re-testing. When modifying a core library like [[actuate-config]] or [[actuate-inference-objects]], the dev-version workflow (see [[dev-workflow]]) becomes critical because the blast radius spans most of the monorepo. The UV workspace makes local cross-library testing straightforward, but CI must validate the full dependency closure before merge to main.
