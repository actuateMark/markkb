---
title: "Remote Access Proxy (RAP)"
type: entity
topic: infrastructure
tags: [remote-access, kvs, mqtt, wireguard, rtsp, edge, streaming, ecs, eks]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Remote Access Proxy (RAP)

A system for remotely accessing and streaming video from on-premises cameras through a cloud relay. Consists of an edge controller deployed on-site and a cloud-side video ingestor, connected via MQTT for control and Kinesis Video Streams (KVS) for video transport.

**Repository:** `aegissystems/remote-access-proxy`
**Runtime:** Python (edge and cloud components)

## Architecture

### RAP Edge Controller (`rap_edge/`)

Runs on the edge device at the customer site. Responsibilities:

- **Network scanning** -- discovers cameras on the local network (ONVIF-based via `onvif_camera.py`).
- **MQTT command listener** -- subscribes to per-camera MQTT topics to receive start/stop stream commands. Topic pattern: `/site/{site}/camera/{id}/profile/{id}/control`.
- **KVS streaming** -- starts and stops GStreamer pipelines that push RTSP streams to Kinesis Video Streams. Requires a custom GStreamer build with the KVS producer plugin.
- **RTSP proxy** -- local RTSP proxy and server capabilities (`rtsp_proxy.py`, `rtsp_server.py`).

### KVS Ingestor (`rap_cloud/`)

Runs in the cloud as a Docker container (ECS or EKS). It:

- Polls KVS for active video streams.
- Pulls and decodes frames.
- Timestamps each frame.
- Saves frames to S3 (or optionally local disk).

A `rap_ui` sub-module provides a management interface.

### WireGuard Auto-Config Service (`wg-autoconf-service/`)

A systemd service and timer that automatically configures WireGuard VPN tunnels for edge-to-cloud connectivity. Deployed via `deploy_systemd.sh` with a pip-based Python environment authenticated against CodeArtifact.

### Supporting Components

- **SRT proxy** (`srt/`) -- C++ SRT-based stream proxy for low-latency transport.
- **Terraform** (`terraform/`) -- infrastructure scaffolding for cloud-side deployment.
- **Docker** (`docker/`) -- Dockerfiles for the KVS Ingestor and related images.
- **Pullers** (`pullers/`) -- stream pulling utilities.

## Build and Deployment

The KVS Ingestor Docker image is built from `docker/Kvs-Ingestor-Dockerfile` and pushed to ECR via `push_kvs_ingestor_docker.sh`. Terraform resources scaffold the cloud environment for end-to-end deployment.
