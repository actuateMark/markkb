---
title: "Source: Duplicate Image Detection with Perceptual Hashing (Ben Hoyt)"
type: source
topic: fleet-architecture
tags: [source, deduplication, perceptual-hash, dhash, bk-tree, frame-storage, pre-save-dedup]
url: https://benhoyt.com/writings/duplicate-image-detection/
ingested: 2026-04-21
author: kb-bot
---

# Duplicate Image Detection with Perceptual Hashing

## Algorithm: dHash

dHash converts an image to grayscale, resizes to 9×8 (or 9×9), encodes gradient direction between adjacent pixels as individual bits. Full row+column variant produces a **128-bit hash**. Compact, fast-to-compute fingerprint; robust to minor re-encoding artifacts, JPEG quality changes, small perspective shifts — all relevant to video frame streams.

## Optimal Hamming Distance Threshold

At 200,000+ images, the article identifies **Hamming distance ≤ 2** as the practical "near-duplicate" threshold. Distance of 4–5 bits begins generating false positives: visually distinct images that hash similarly due to flat color regions or low-contrast content. For pre-save deduplication of surveillance frames, ≤2 is the safe threshold.

## BK-Tree for Scalable Lookup

Naive all-pairs comparison is O(N²). A **BK-tree** (Burkhard-Keller tree) indexes hashes by Hamming distance, enabling approximate nearest-neighbor queries in **O(log N)** time. Python: `pybktree`. Combined with `dhash` for hash computation, a full dedup pipeline is ~50 lines of Python.

## Applicability to Pre-Save Frame Deduplication

For a stationary camera pulling frames at high fps (our common case), consecutive frames in a detection window will often be **near-identical** — scene hasn't changed meaningfully. dHash would assign near-zero Hamming distances. Dropping frames with distance ≤2 from the preceding kept frame before S3 write is a viable pre-save dedup strategy that would materially reduce frame count per window.

**Estimated reduction:** In a 10-fps pull with slow-moving subject, a detection window of 1–3 seconds (10–30 raw frames) might retain 3–6 unique frames at Hamming ≤2 — a **50–70% reduction** in write count. For fully stationary scenes, reduction could reach 90%+.

**Caveat:** article does not address video frame dedup or stationary-camera scenarios. 200k-image dataset was a general photo library. False-positive risk is **higher** in surveillance contexts because two truly distinct events (person A vs person B in same position) may produce similar hashes if subject is small relative to frame. Hamming threshold may need tightening to ≤1 for surveillance.

## Performance Characteristics

At 200k images, BK-tree lookup is fast enough for batch processing; article does not benchmark real-time streaming. For in-process frame dedup before each S3 write, per-frame overhead is a single 128-bit hash computation (~microseconds) plus one BK-tree lookup. **Negligible compared to the S3 PUT latency it avoids.**

## Relevance to Fleet Proposals

- **A** (status quo per-frame S3): Direct application — drop duplicate frames before PUT to reduce API call count.
- **B** (in-process encoding): Less relevant — video encoding inherently handles temporal redundancy via inter-frame compression (P/B frames). dHash dedup would be redundant if encoding adopted.
- **C** (in-cluster blob + conditional promotion): Useful at in-cluster accumulation stage to reduce blob size and frame count before promotion decision.
- **D** (hybrid): Relevant for keyframe selection — dHash identifies which frames carry new information worth retaining.
- **E** (edge): Could run on-edge before network transmission, reducing bandwidth and storage cost simultaneously.

## Relevance to Frame-Storage Design Directions

- **In-process encoding (§11)**: Low additional value — codec's temporal compression subsumes dHash dedup. Could be used as a fast pre-filter before encoder to skip frames with negligible change, saving encoder CPU.
- **In-cluster blob + conditional promotion (§12)**: **High value as a pre-accumulation filter.** Reduces in-cluster blob volume and sharpens eventfulness signal used for promotion decision (mostly near-duplicate frames → likely uneventful).
- **API-call cost structure**: Directly reduces API call count. If pre-save dedup halves frame count per window (10 → 5 writes), **cuts API cost contribution of frame PUTs by 50% at zero infrastructure change.**

## Source
https://benhoyt.com/writings/duplicate-image-detection/
