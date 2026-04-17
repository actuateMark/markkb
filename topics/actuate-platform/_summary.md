---
title: Actuate Platform Overview
type: summary
topic: actuate-platform
tags: [platform, architecture, overview]
confluence: "https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497319963"
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Actuate Platform

Actuate is an **AI-powered video surveillance analytics platform** that processes camera feeds in real-time to detect threats (people, vehicles, weapons, fire, loitering, crowd, slip-and-fall) and deliver alerts to security monitoring centers and end customers.

## Core Architecture

```
Camera Streams (RTSP/SMTP/AILink/19+ VMS types)
    |
    v
VMS Connector (K8s pods, one per site, rearchitecture namespace)
    |-- Frame ingestion via actuate-pullers
    |-- FDMD motion detection via actuate-movement
    |-- YOLO inference via actuate-inference-client -> model-svc (K8s, ds-model-prod)
    |-- Post-processing: actuate-filters (confidence, IOU, ignore zones, stationary, blacklist)
    |-- Observers: intruder, loiterer (BoTSORT tracking), line crossing, blacklist
    |-- Sliding window confirmation
    |
    v
Alert Pipeline
    |-- actuate-alarm-senders (25+ sender types: Immix, Milestone, Sentinel, webhooks, etc.)
    |-- SQS FIFO -> queue_consumer -> customer systems
    |-- DynamoDB (WindowIds, DetectedV2, EnrichedFrame, ImageData, CameraStatus, etc.)
    |-- S3 (frames, clips, settings)
    |
    v
User Interfaces
    |-- alert-ui / camera-ui (web dashboards)
    |-- actuate_admin (Django REST API + admin portal)
    |-- actuate-inference-api (external partner API, FastAPI on Lambda)
```

## Key Services

| Service | Tech | Deployment | Purpose |
|---------|------|------------|---------|
| [[vms-connector]] | Python CLI | K8s Deployment/CronJob | Frame processing pipeline |
| [[admin-api]] | Django 6.0 + DRF | ECS | Configuration, CRUD, integrations |
| [[inference-api]] | FastAPI + Mangum | Lambda (container) | External partner detection API |
| Model servers | Rust (YOLO) | K8s (ds-model-prod) | ML inference |
| queue_consumer | Python | K8s | SQS alert delivery |
| connector_deployer | Python | K8s | Connector lifecycle management |

## Shared Libraries

[[actuate-libraries]] -- 41 Python packages in a UV workspace monorepo, published to AWS CodeArtifact. See topic for full catalog.

## AWS Infrastructure

- **Account:** 388576304176
- **Primary region:** us-west-2
- **EU region:** eu-west-1 (GDPR)
- **Orchestration:** EKS (ArgoCD GitOps)
- **Data stores:** DynamoDB, S3, SQS, SNS, PostgreSQL (RDS), ElastiCache
- **Monitoring:** New Relic, CloudWatch, Datadog

## Products

| Product | Detection Type | Model |
|---------|---------------|-------|
| Intruder | Person detection | intruder-384h-512w-svc (v5), int07-actuate003-v8 (v8, rolling out) |
| Intruder+ | Person + vehicle (7 classes) | Same model, different label filtering |
| Vehicle | Vehicle classes only | Same model, label-filtered |
| Weapon | Firearm detection | weapon-v8-XL-736 (deploying) |
| Loitering | Person/vehicle dwell time | Intruder model + BoTSORT tracking |
| Line Crossing | Directional crossing | Intruder model + TrajectoryManager |
| Motion+ | Motion-triggered detection | Intruder model + FDMD |
| Fire/Smoke | Fire detection | Dedicated fire model |
| Crowd | Proximity detection | Intruder model |
| Fall | Slip-and-fall | Aspect ratio analysis |
| Blacklist | Re-identification | Blacklist model |
| CHM | Camera health | Scene change (SIFT), connectivity, recording status |

## Strategic Direction

- **Current:** B2B2B via monitoring center partners (Immix, EMCS, Sentinel, etc.)
- **Next:** [[watchman]] -- B2B direct to commercial businesses (AI-powered virtual security operator)
- **Near-term:** [[external-api]] initiative exposing partner-facing APIs (EBUS, AlarmWatch, Alarmquip)
