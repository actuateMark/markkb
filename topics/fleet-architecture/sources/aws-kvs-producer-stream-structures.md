---
title: "Source: AWS Kinesis Video Streams — Producer Reference: Stream Structures"
type: source
topic: fleet-architecture
tags: [source, kvs, aws, fragment-model, video-encoding, streaming, api-design]
url: https://docs.aws.amazon.com/kinesisvideostreams/latest/dg/producer-reference-structures-stream.html
ingested: 2026-04-21
author: kb-bot
---

# AWS Kinesis Video Streams — Producer Reference: Stream Structures

AWS KVS's Producer SDK models a video stream as a sequence of **fragments** — independently reproducible units of contiguous frames — packaged as MKV clusters. Closest publicly documented analog to our detection-window clip concept.

## Fragment Lifecycle and Duration

Fragments are bounded by key frames. Two fragmentation modes: `key_frame_fragmentation = true` (default) begins new fragment at every I-frame; `key_frame_fragmentation = false` waits for at least `fragment_duration` (default 2 s) then cuts on next key frame. Service enforces maximum fragment duration of 10 seconds. Practical operational range: **2–10 seconds per fragment.**

## MKV Cluster Representation

Each fragment = one MKV cluster. Frame timecodes within the cluster are **relative to cluster start** using a signed 16-bit value at configurable `timecode_scale` (default 1 ms, ~32 seconds relative). Service always stores fragments with **absolute timestamps**: relative cluster timecodes resolved via optional stream-start timestamp at `PutMedia` call time.

## Producer/Service Interface Boundary

`PutMedia` API is the write boundary — producer streams MKV-packaged fragments to the service. Service responds with **per-fragment ACKs** (`fragment_acks = true` by default) at two lifecycle points: buffered and **persisted**. Persisted ACK signals durable cloud storage; local producer buffer is trimmed to next fragment boundary. **Clean "local buffer → cloud durable" handoff with explicit acknowledgment.**

## Alignment with Our Detection-Window Model

KVS fragments are time-bounded and key-frame-aligned, whereas our detection windows are **event-bounded** (variable-length, per-detection). KVS has no native semantic/event-triggered fragmentation. However, the `PutMedia` / `GetMediaForFragmentList` API shape is directly cribable: a list of fragment identifiers (each covering a time range) can be fetched in a single call, **collapsing N per-frame fetches into 1–2 API calls**. The persisted-ACK buffer-trim pattern maps cleanly to our "promote on commit" design.

## Relevance to Fleet Proposals

- **A** (per-frame S3 writes): KVS fragment model is the direct counter-example. Strong negative evidence for A's approach.
- **B** (in-process clip encoding): Fragment = encoded clip. KVS's key-frame-triggered fragmentation and MKV packaging are the reference implementation of what B encodes in-process.
- **C** (pre-buffer + conditional flush): Memory-based local buffer with persisted-ACK trim is structurally identical to C's in-cluster accumulation with conditional promotion.
- **D** (in-cluster blob store): `PutMedia` streaming into a service-side durable store mirrors the in-cluster blob → S3 promotion pattern. ACK boundary is the promotion trigger.
- **E** (hybrid): Fragment list retrieval (`GetMediaForFragmentList`) demonstrates the indexed-retrieval pattern E relies on for selective S3 access.

## Relevance to Frame-Storage Design Directions

- **In-process encoding (§11)**: Direct reference — KVS fragments are MKV-packaged, key-frame-bounded clips. 2–10s duration range and `key_frame_fragmentation` mode map to our clip assembly logic. **Detection-window clip boundaries should align to I-frames.**
- **In-cluster blob + conditional promotion (§12)**: Persisted-ACK / buffer-trim semantics are the canonical model for "accumulate locally, promote on durability confirmation." The PutMedia→ACK→trim loop is a proven interface shape.
- **API-call cost structure**: **`GetMediaForFragmentList` collapses N per-frame S3 GETs into 1 list call.** Exactly the API-call-count reduction we need. KVS proves the pattern works at production scale.

## Source
https://docs.aws.amazon.com/kinesisvideostreams/latest/dg/producer-reference-structures-stream.html
