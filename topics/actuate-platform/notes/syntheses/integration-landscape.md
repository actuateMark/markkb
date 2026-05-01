---
title: "Integration Landscape"
type: synthesis
topic: actuate-platform
tags: [synthesis, cross-topic, integrations, vms, alarm-senders, api, inbound, outbound, vms-connector, autopatrol]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Integration Landscape

Actuate connects to the security ecosystem through 30+ integrations spanning video management systems, alarm receivers, cloud platforms, and partner APIs. This synthesis maps every integration by type, direction, and implementation layer.

## Integration Taxonomy

Integrations fall into four architectural categories:

1. **VMS Pullers (Inbound)** -- frame sources that feed the [[detection-pipeline|detection pipeline]]
2. **Alarm Senders (Outbound)** -- alert delivery to monitoring centers and end customers
3. **API Integrations (Inbound/Bidirectional)** -- partner-facing detection and management APIs
4. **Cloud-to-Cloud (Bidirectional)** -- platform-level integrations with other SaaS products

## Category 1: VMS Pullers (Inbound Frame Sources)

These integrations are implemented in [[actuate-pullers]] and instantiated by the [[connector-factory]] based on `integration_type` in the site settings. Each has a dedicated factory under `connector_factories/<integration>/` in [[vms-connector]].

| Integration | Puller Type | Auth Method | Topic |
|---|---|---|---|
| [[integration-rtsp]] | `UrlFramePuller` | Basic Auth / None | Generic [[rtsp-deep-dive|RTSP]] |
| [[integration-milestone]] | `MilestoneJpgFramePuller` | HTTP API | Milestone XProtect |
| [[integration-avigilon]] | VMS-specific | API Token | Avigilon ACC |
| [[integration-exacq]] | VMS-specific | DB Credentials | Exacq exacqVision |
| [[integration-eagle-eye]] | VMS-specific | OAuth2 | Eagle Eye Networks |
| [[integration-digital-watchdog]] | VMS-specific | HTTP API | Digital Watchdog |
| [[integration-hikcentral]] | VMS-specific | API Token | [[hikcentral-components|HikCentral]] Professional |
| [[integration-genetec]] | VMS-specific | HTTP API | Genetec Security Center |
| [[integration-luxriot]] | VMS-specific | HTTP API | Luxriot EVO |
| [[integration-openeye]] | VMS-specific | HTTP API | OpenEye OWS |
| [[integration-orchid]] | `OrchidJpgFrameQueuePuller` | HTTP API | IPConfigure Orchid |
| [[integration-salient]] | VMS-specific | HTTP API | Salient CompleteView |
| [[integration-video-insight]] | VMS-specific | HTTP API | [[video-insight-components|Video Insight]] |
| [[integration-kvs]] | `KVSFramePuller` | AWS IAM | Amazon [[aws-kvs-entity|Kinesis Video Streams]] |
| [[integration-autopatrol-integration]] | AutoPatrol-specific | Backend API | AutoPatrol scheduling |
| [[integration-vch]] | VCH-specific | Backend API | VCH (Video Camera Hub) |
| [[integration-adpro]] | `UrlFramePuller` ([[rtsp-deep-dive|RTSP]] variant) | Basic Auth | ADPRO / Xtralis |
| [[integration-ajax]] | VMS-specific | API Token | [[ajax-components|Ajax Systems]] |
| [[integration-lisa]] | VMS-specific | API Token | LISA alarm receiver |

The [[actuate-integration-calls]] library provides VMS API client wrappers for [[ajax-components|Ajax]], AutoPatrol, Avigilon, Digital Watchdog, Eagle Eye, Exacq, [[hikcentral-components|HikCentral]], LISA, and Milestone.

## Category 2: Alarm Senders (Outbound Alert Delivery)

These are implemented in [[actuate-alarm-senders]] (27 sender classes) and consumed by [[actuate-connector-observers]] at the end of the [[detection-pipeline|detection pipeline]]. Some senders dispatch directly (HTTP, SMTP, TCP); others write to SQS FIFO queues consumed by [[queue-consumer]] containers on ECS.

| Sender | Target | Protocol | Delivery Path | Topic |
|---|---|---|---|---|
| `ImmixAlertSender` | [[integrations/immix/_summary|Immix]] | SMTP | SQS -> queue_consumer | Primary partner |
| `SentinelAlertSender` | [[integration-sentinel]] | HTTP | SQS -> queue_consumer | Monitoring center |
| `PatriotAlertSender` | [[integration-patriot]] | HTTP | SQS -> queue_consumer | PSIM |
| `SureviewAlertSender` | [[integration-sureview]] | HTTP | SQS -> queue_consumer | Immix variant |
| `SoftguardAlertSender` | [[integration-softguard]] | SMTP | SQS -> queue_consumer | Latin America |
| `BoldAlertSender` | [[integration-bold]] | SMTP | Direct | UK/EU |
| `MilestoneAlertSender` | [[integration-milestone]] | HTTP | SQS -> queue_consumer | Bidirectional |
| `EvalinkAlertSender` | [[integration-evalink]] | HTTP REST | SQS -> queue_consumer | Swiss ARC |
| `EagleEyeAlertSender` | [[integration-eagle-eye]] | HTTP | SQS -> queue_consumer | Bidirectional |
| `LisaAlertSender` | [[integration-lisa]] | HTTP | SQS -> queue_consumer | Alarm receiver |
| `HikcentralAlertSender` | [[integration-hikcentral]] | HTTP | Direct | VMS event |
| `AvigilonAlertSender` | [[integration-avigilon]] | HTTP | Direct | VMS event |
| `GenetecAlertSender` | [[integration-genetec]] | HTTP | Direct | VMS event |
| `DWAlertSender` | [[integration-digital-watchdog]] | HTTP | Direct | VMS event |
| `WebhookAlertSender` | [[integration-webhook]] | HTTP POST | Direct | Generic |
| `AutoPatrolAlertSender` | [[integration-autopatrol-integration]] | Internal | Direct | AutoPatrol/Immix |
| `TCPAlertSender` | TCP targets | TCP socket | Direct | Legacy |
| `SesAlertSender` | Email recipients | AWS SES | Direct | Email alerts |
| `SmsAlertSender` | Phone numbers | AWS SNS | Direct | SMS alerts |
| `SnsTopicAlertSender` | SNS topics | AWS SNS | Direct | Internal routing |
| `CommandCentralAlertSender` | Motorola CC | HTTP | Direct | Public safety |
| `CrisisGoAlertSender` | CrisisGo | HTTP | Direct | Schools |
| `StagesAlertSender` | Stages | HTTP | Direct | Events |
| `EnveraAlertSender` | Envera | HTTP | Direct | Monitoring |
| `UsMonitoringAlertSender` | US Monitoring | HTTP | SQS -> queue_consumer | US market |
| `VerifierAlertSender` | Human verifier | AWS SNS | Direct | Internal |
| `SysAidAlertSender` | SysAid (CHM only) | HTTP | Direct | Ticketing |

## Category 3: API Integrations (Partner-Facing)

The [[external-api/_summary|External API Initiative]] initiative exposes APIs for partners who want to consume Actuate's AI capabilities programmatically rather than through the VMS puller model.

| API | Consumer | Direction | Status |
|---|---|---|---|
| v5 Detection API | [[integrations/ebus/_summary|EBUS]] (Accellence Technologies) | Inbound frames, outbound detections | In development |
| Schedule Management | [[alarmwatch-customer]] (Crosbies, NZ) | Bidirectional | PR merged, testing |
| Image Ingestion (SMTP alt) | [[alarmquip-customer]] (AU) | Inbound frames | To Do |
| Arm/Disarm Per Site | [[alarmwatch-customer]] | Inbound control | To Do |

These share a common auth pattern: AWS API Gateway -> [[rust-lambda-authorizer]] -> K8s pods (via VPC Link + ALB). The [[inference-api/_summary|Actuate Inference API]] (FastAPI on Lambda) serves the v5 detection endpoints.

## Category 4: Cloud-to-Cloud Integrations

| Integration | Partner | Direction | Status | Topic |
|---|---|---|---|---|
| [[integrations/morphean/_summary|Morphean]] Track A | Morphean/VIDEOR | Bidirectional ([[rtsp-deep-dive|RTSP]] in, alerts out) | Draft | 30 countries, 170+ resellers |
| [[integrations/morphean/_summary|Morphean]] Track B | VIDEOR edge hardware | Inbound (edge deployment) | Investigation | Toradex/DeepX |
| [[integrations/ebus/_summary|EBUS]] Phase 2 | Accellence EBUS | Bidirectional (clips in, alerts back) | Future | German market |

## Bidirectional Integrations

Several integrations serve as both frame sources and alert destinations:

- **Milestone** -- puller pulls [[rtsp-deep-dive|RTSP]]/JPEG frames; alarm sender pushes events back to XProtect
- **Eagle Eye** -- puller ingests cloud streams; alarm sender pushes alerts to EEN cloud
- **[[hikcentral-components|HikCentral]]** -- puller ingests VMS streams; alarm sender pushes events
- **Avigilon** -- puller pulls from ACC NVR; alarm sender pushes analytics events
- **Genetec** -- puller connects to Security Center; alarm sender pushes back
- **Digital Watchdog** -- puller ingests DW Spectrum; alarm sender pushes events

## Infrastructure Implications

Each integration type requires distinct infrastructure consideration:

- **VMS pullers** run inside [[vms-connector]] pods, one pod per site. Memory scales at `cameras * 32MB + 500MB base`. The [[connector-deployer]] manages K8s resource lifecycle.
- **SQS-based alarm senders** require dedicated FIFO queues and [[queue-consumer]] ECS containers. The one-container-per-integration model provides isolation but adds operational overhead.
- **API integrations** route through API Gateway and Lambda, with a planned migration to K8s for cost and latency optimization (see [[lambda-to-k8s-migration]]).
- **Cloud-to-cloud** integrations like [[integrations/morphean/_summary|Morphean]] add OAuth2/API-key authentication layers and require tenant isolation within the Actuate platform.

## Scale

As of April 2026: 19+ VMS puller types, 27 alarm sender implementations, 6 API workstreams, and 2 cloud-to-cloud tracks -- totaling 30+ distinct integration points. The [[actuate-alarm-senders]] library and [[queue-consumer]] service are the two most integration-dense components in the platform, and any new outbound integration adds work to both.
