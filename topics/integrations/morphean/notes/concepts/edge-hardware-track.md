---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [morphean, edge, hardware, deepx, toradex, integration]
jira: "PROD-67"
incoming:
  - topics/actuate-platform/notes/concepts/multi-region-deployment.md
  - topics/fleet-architecture/notes/concepts/2026-06-01_terminology-conflict-watchman-ambiguity.md
  - topics/integrations/morphean/notes/concepts/cloud-to-cloud-architecture.md
  - topics/personal-laptop/notes/concepts/2026-04-23_firebat-minipc-network-setup.md
  - topics/product-roadmap/notes/concepts/revenue-drivers.md
incoming_updated: 2026-06-02
---

# Edge Hardware Track (Morphean)

Track B of the [[integrations/morphean/_summary|Morphean]] -- deploying Actuate analytics on edge devices co-located with cameras, specifically designed for **legacy cameras** that cannot upload video to the cloud.

## Problem Statement

Not all cameras in Morphean/VIDEOR's install base support cloud video streaming. Many legacy analog or older IP cameras are behind constrained networks or lack the firmware to push [[rtsp-deep-dive|RTSP]] streams to a cloud endpoint. The [[cloud-to-cloud-architecture]] (Track A) requires cameras to stream to Morphean's VideoProtector cloud, which is not feasible for these legacy deployments.

Track B solves this by bringing Actuate's inference to the camera's network edge, processing video locally and only sending alert metadata (detections, thumbnails) upstream.

## Hardware Platform

The edge deployment targets **VIDEOR's edge devices** built on:

- **Toradex Verdin** -- An ARM-based system-on-module (SoM) designed for industrial and embedded applications. The Verdin platform provides a compact, power-efficient compute base suitable for deployment alongside camera infrastructure (in server rooms, network closets, or on DIN rails).
- **DeepX AI acceleration** -- A dedicated AI inference accelerator that provides the compute needed to run YOLO-based models locally without a GPU. DeepX chips are designed for low-power edge AI, making them suitable for always-on video analytics at the camera site.

The combination of Toradex Verdin + DeepX allows running Actuate's detection models (intruder, vehicle, fire, etc.) directly on the edge device, with the local VMS providing camera feeds over the LAN.

## Architecture

The edge device runs a local variant of the Actuate processing pipeline:

1. **Local VMS integration** -- The edge device connects to cameras via the on-premises VMS (or directly via [[rtsp-deep-dive|RTSP]] on the local network).
2. **Local inference** -- Frames are processed by Actuate models running on the DeepX accelerator. No video leaves the local network.
3. **Alert upstream** -- Only detection metadata and alert thumbnails are sent to Actuate's cloud (or to Morphean's platform) for alerting and dashboard display.

This architecture has significant advantages for **data sovereignty** and **bandwidth**: full video frames never leave the customer's premises, which aligns with European privacy regulations (GDPR) and reduces cloud ingestion costs.

## Relationship to Track A

Tracks A and B are complementary, not competing:

- **Track A (Cloud-to-Cloud):** For modern cameras already streaming to Morphean's VideoProtector cloud.
- **Track B (Edge Hardware):** For legacy cameras or privacy-sensitive deployments where video cannot leave the premises.

A Morphean partner like VIDEOR might deploy both tracks across their install base, using cloud-to-cloud for newer sites and edge hardware for legacy retrofits.

## See Also

- [[cloud-to-cloud-architecture]] -- Track A, the cloud-based approach
- [[integrations/morphean/_summary|Morphean]] -- parent topic
- [[multi-region-deployment]] -- Actuate's cloud regions including EU (eu-west-1)
