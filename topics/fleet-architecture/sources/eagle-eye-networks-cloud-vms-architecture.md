---
title: "Source: Eagle Eye Networks — Cloud VMS Architecture"
type: source
topic: fleet-architecture
tags: [source, eagle-eye, cloud-vms, edge-compression, motion-detection, conditional-upload, vendor-architecture]
url: https://www.een.com/product/cloud-vms-architecture/
ingested: 2026-04-21
author: kb-bot
---

# Eagle Eye Networks — Cloud VMS Architecture

Eagle Eye Networks is a cloud-native VMS vendor. Their published architecture page describes the most specific publicly available implementation of edge-compression-before-cloud-sync in a commercial surveillance product. Their Bridge/CMVR appliance model closely parallels the in-cluster blob direction.

## Edge Appliance: Compress-Analyze-Encrypt Before Sync

The Eagle Eye Bridge/CMVR onsite appliance performs three operations locally before any cloud interaction: (1) motion analysis, (2) video compression, (3) 256-bit AES encryption. Only after this pipeline does data transit to the cloud. **Direct precedent for the "compress + filter BEFORE storage write" pattern in §12:** the appliance acts as the in-cluster node, cloud sync is the conditional promotion.

## Motion-Triggered Selective Upload

Architecture supports selective transmission — motion analysis at the edge drives what gets prioritized for cloud sync. During bandwidth-constrained conditions, the Bridge caches video locally and synchronizes when bandwidth is available ("Intelligent Bandwidth Management"). **Structurally identical to our conditional-promotion trigger: eventfulness (motion/detection) gates the cloud write.**

## Flex Storage: Per-Device Storage Tiering

"Flex Storage" allows CMVR customers to choose whether video is stored in cloud or on the local device. Per-device, per-stream storage configuration — **directly analogous to our per-camera retention policy need in Proposals C/D.** Existence of a commercial product offering this as a customer-configurable option validates architectural viability.

## Gaps and Limitations of This Source

Eagle Eye architecture page is marketing-level, not engineering-level. Key details NOT disclosed: specific API surface for storage promotion, internal buffer size limits, how motion confidence scores gate upload decisions, what happens at the boundary between local-only and cloud-synced footage. "Intelligent Bandwidth Management" branding obscures actual upload-triggering logic. **Cannot directly crib API shapes from this source** — it confirms the pattern is viable but does not document the mechanism.

## Alignment with Our Cost Framing

Eagle Eye's architecture implicitly validates the core thesis: **S3/cloud API calls are expensive relative to local storage, so the right boundary is at the edge appliance, not the cloud API.** Their compress-at-edge / sync-to-cloud model is a production instantiation of collapsing per-frame cloud writes into batched clip uploads.

## Relevance to Fleet Proposals

- **A** (per-frame S3): Eagle Eye's architecture explicitly avoids this pattern — their bridge compresses and batches before any cloud write.
- **B** (in-process encoding): Motion analysis + compression at bridge is the edge-side equivalent. Moderate relevance; different deployment topology (appliance vs in-cluster).
- **C** (pre-buffer + conditional flush): **High relevance** — local cache + bandwidth-triggered sync is the Eagle Eye model. Direct architectural precedent.
- **D** (in-cluster blob): **High relevance** — Bridge-as-in-cluster-node with selective cloud promotion is structurally identical to D.
- **E** (hybrid): Flex Storage per-device tiering validates hybrid cloud/local retention as a viable product pattern.

## Relevance to Frame-Storage Design Directions

- **In-process encoding (§11)**: Edge compression before cloud sync is the vendor analog. Eagle Eye does this at bridge hardware; we would do it in-process in the connector. Pattern is validated.
- **In-cluster blob + conditional promotion (§12)**: **This is the primary alignment.** Eagle Eye's bridge IS an in-cluster blob store with conditional cloud promotion. Motion-gated sync is exactly the conditional-promotion trigger in §12.
- **API-call cost structure**: Eagle Eye implicitly proves the point — their architecture exists specifically to avoid per-frame cloud API call costs. "Intelligent Bandwidth Management" is the product name for "don't call the cloud API unless you have to."

## Source
https://www.een.com/product/cloud-vms-architecture/
