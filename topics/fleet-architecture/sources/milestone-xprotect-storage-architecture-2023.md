---
title: "Source: Milestone XProtect Storage Architecture and Recommendations (2023-09)"
type: source
topic: fleet-architecture
tags: [source, milestone, vms, storage-architecture, pre-buffer, archiving, retention, gop, pdf-inbox]
url: "file:///home/mork/Documents/worklog/knowledgebase/_research-inbox/milestone-xprotect-storage-architecture-2023-09.pdf"
original_url: https://doc.milestonesys.com/wp/pdf/en-US/XProtectStorageArchitectureAndRecommendations_2023-09.pdf
ingested: 2026-04-21
author: kb-bot
---

# Milestone XProtect Storage Architecture and Recommendations (2023-09)

White paper by John Rasmussen (Platform Architect), September 2023. Covers XProtect VMS media database design, storage tiers, pre-buffer mechanics, archive grooming, GOP/codec considerations, differentiated per-device retention. **The most detailed publicly available on-premise VMS storage architecture document from a major vendor.**

## Storage Tier Architecture: Recording DB → Archive DB

XProtect uses a two-tier (or multi-tier) storage model. Live media streams from cameras first written to **Recording Database** — hot tier on fast disks, optimized for high-concurrency random writes across many simultaneous camera streams. When configured retention time is reached (or on archive schedule, recommended every 4 hours), recordings move to **Archive Database** on slower, cheaper, larger disks. Archive access is sequential, so slower disks perform well. **This tier-split is the structural model for our recording-db (in-cluster) / archive-db (S3) separation.**

## Pre-Buffer: Memory-First, Event-Triggered Flush

Pre-buffer holds media in RAM (up to 15 seconds; disk-based if longer) before any recording trigger occurs. When a triggering event fires, pre-buffer contents are flushed to Recording Database. **If no trigger occurs, pre-buffer is discarded.** With VMD triggering 20% of the time, storage system load is reduced by **80%** (savings inversely proportional to recording percentage). **This is the direct analog of our in-cluster blob accumulation with conditional S3 promotion.** Memory-based pre-buffering is preferred; disk-based keeps storage load permanently high.

## Differentiated Retention: Per-Device Storage Configurations

Multiple storage configurations can be defined on a single recording server and assigned per-device. UI example shows "1 Day" config and "30 Days" config assigned to different cameras. **Validates per-stream retention tiering as a standard VMS pattern** — relevant to Proposal D/E's selective promotion where high-value streams get longer cloud retention.

## GOP Length and Framerate Reduction During Archiving

For MPEG/H.264/H.265, the keyframe (I-frame) dominates GOP storage: **in low-motion surveillance scenes, the I-frame uses 50–80% of total GOP storage.** MPEG video can only be reduced to keyframe-interval granularity during framerate reduction (default 1 FPS = every-second keyframe in XProtect). Shorter GOP (e.g., 0.5s) enables finer reduction but increases keyframe frequency and storage load. **For our in-process encoding (§11): clip boundaries must align to I-frames; short GOPs reduce clip-start latency but increase per-clip overhead.**

## Non-Sequential Write Load as the Core Storage Challenge

XProtect explicitly calls out that recording many cameras in parallel causes high-concurrency **non-sequential (random) writes** — the primary reason standard IT storage underperforms in VMS workloads. **This framing directly parallels our current ~22 S3 API calls/window problem: the issue is not data volume but write operation concurrency and count.**

## Relevance to Fleet Proposals

- **A** (per-frame S3): Milestone's architecture explicitly solves the same problem (high-concurrency random writes) by using a fast local hot tier. A is the anti-pattern Milestone's architecture was designed to avoid.
- **B** (in-process clip encoding): GOP/I-frame alignment guidance directly applicable — clip start must be on an I-frame; GOP length controls granularity.
- **C** (pre-buffer + conditional flush): **The memory-based pre-buffer IS Proposal C's design.** 15-second RAM buffer, event-triggered flush, discard if no trigger. Near-identical semantics.
- **D** (in-cluster blob + selective promotion): Two-tier recording/archive DB architecture is the reference implementation. Per-device storage config is the retention-tiering mechanism.
- **E** (hybrid): Differentiated retention time validates E's selective cloud promotion for high-value streams.

## Relevance to Frame-Storage Design Directions

- **In-process encoding (§11)**: GOP structure and I-frame alignment are load-bearing for clip encoding. I-frame = clip-start boundary. GOP length tuning (shorter = finer granularity, higher overhead) is the key parameter. Keyframe-reduction-on-archive is the grooming analog for aged clips.
- **In-cluster blob + conditional promotion (§12)**: **Pre-buffer architecture is THE canonical model.** Memory-first, event-triggered, discard-if-no-trigger. The 80% storage-load reduction at 20% recording rate is a concrete benchmark for what conditional promotion can achieve.
- **API-call cost structure**: Milestone's non-sequential random write framing validates our API-call-count diagnosis. Solution (hot tier absorbs random writes; archive tier uses sequential bulk moves) maps to in-cluster blob absorbing per-frame writes, S3 receiving only bulk clip uploads.

## Source
file:///home/mork/Documents/worklog/knowledgebase/_research-inbox/milestone-xprotect-storage-architecture-2023-09.pdf

Canonical URL: https://doc.milestonesys.com/wp/pdf/en-US/XProtectStorageArchitectureAndRecommendations_2023-09.pdf
