---
title: AWS Elemental MediaPackage
type: entity
topic: video-processing
tags: [aws, mediapackage, packaging, hls, dash, cmaf, drm, jit-packaging]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# AWS Elemental MediaPackage

## What it is

**Just-in-time (JIT) video packaging** as a managed service. You send MediaPackage a single contribution feed (live or prerecorded segments); it emits whatever set of player-facing manifests + segments you've configured: [[hls-and-dash|HLS]], [[hls-and-dash|DASH]], MS Smooth, CMAF — for both live and VOD endpoints. It also handles DRM packaging (PlayReady / Widevine / FairPlay), ad-marker translation (SCTE-35 → [[hls-and-dash|HLS]] / [[hls-and-dash|DASH]] ad markers), time-shifted "live-to-VOD" windows, and origin caching with CDN-friendly cache headers.

The trick MediaPackage exists to solve: encode once, package many. Without MediaPackage, every output format/DRM combination needs a separate output group on the encoder. With MediaPackage you encode once into a CMAF-compatible feed and let MediaPackage repackage on the fly per requesting client.

## V1 vs V2

There are two distinct services, both in active use, with different APIs:

- **MediaPackage v1** — the original. "Channels" + "endpoints" model. Live (Channel + OriginEndpoint + HarvestJob) and VOD (PackagingGroup + PackagingConfiguration + Asset) sides have separate APIs. Mature, well-documented, but the API surface shows its age.
- **MediaPackage v2** — newer (2023+). Cleaner channel-group / channel / origin-endpoint model, lower JIT origin latency, native CMAF ingest, low-latency-[[hls-and-dash|HLS]] (LL-HLS) support. AWS is steering customers here for new builds. MediaStore is being deprecated in favor of v2 + S3.

Both are billed for ingress + egress + DRM operations.

## API surface

- `boto3.client("mediapackage")` (v1) and `boto3.client("mediapackagev2")` (v2).
- v1 live core: `create_channel` → `create_origin_endpoint` ([[hls-and-dash|HLS]] / [[hls-and-dash|DASH]] / MSS / CMAF variant per endpoint) → encoder pushes CMAF/[[hls-and-dash|HLS]] into the channel ingest URL → players pull from the origin endpoint URL.
- v1 VOD core: `create_packaging_group` → `create_packaging_configuration` (one per output format) → `create_asset` (points at a source MP4/[[hls-and-dash|HLS]] in S3) — MediaPackage packages on demand at request time.
- v2 lifecycle: `create_channel_group` → `create_channel` → `create_origin_endpoint`. Channel groups are the new top-level scoping primitive.
- DRM via the **SPEKE** keyserver protocol — you provide a SPEKE-compatible keyserver (AWS partners' or your own), MediaPackage requests keys per content key ID and packages encrypted segments.

Origin URLs are typically fronted by **CloudFront** for cache + edge geographic distribution. MediaPackage emits CDN-aware cache headers; the canonical reference architecture is encoder → MediaPackage → CloudFront → player.

## Pricing model

- **Ingress** per GB ingested into a channel.
- **Egress** per GB delivered to clients.
- **Live-to-VOD harvest jobs** per minute harvested.
- **DRM-encrypted output** per GB has a small uplift.
- Significant savings only kick in once you have **many concurrent viewers per source feed** — MediaPackage's value is repackaging, not encoding.

For a single viewer, MediaPackage is a strict cost addition over "encoder writes [[hls-and-dash|HLS]] straight to S3 + CloudFront". For hundreds-of-thousands of concurrent viewers, MediaPackage saves a huge amount of encoder work.

## When to reach for it

- ✅ **Live / VOD content served to many concurrent browser-native players.** This is the textbook fit.
- ✅ You need DRM (Widevine / FairPlay / PlayReady) and don't want to wire up a keyserver pipeline by hand — MediaPackage's SPEKE integration is the path of least resistance.
- ✅ You need both [[hls-and-dash|HLS and DASH]] (and maybe LL-HLS) from a single source feed.
- ✅ Time-shifted live ("watch from 30 minutes ago") with a moving DVR window.

## When not to reach for it

- ❌ Tiny audience — single operator viewing a single live feed at a time. Direct [[hls-and-dash|HLS]]-to-S3 + CloudFront is cheaper.
- ❌ Sub-second latency requirements — even LL-HLS is multi-second-ish; for true low-latency live use [[aws-ivs-entity]] or [[kvs-components|KVS]] [[webrtc-deep-dive|WebRTC]].
- ❌ Anything not delivered to player clients (i.e. internal pipelines).

## Actuate touchpoints

**Not used.** No `mediapackage` or `mediapackagev2` boto3 client invocations in any scouted library.

The plausible Actuate application is **clip-replay UI at scale**, when/if that ships:

- Today, alert evidence is JPEG sequences in S3 (`actuate-libraries/actuate-frames/src/actuate_frames/save_frame_meta.py:43`) — see [[actuate-clip-generation-flow]].
- A clip-replay UI for monitoring centers needs MP4 / [[hls-and-dash|HLS]] playback, not JPEG strips. The end-state architecture would be:
  1. Alert clip generated and stored in S3 (today).
  2. [[aws-mediaconvert-entity]] transcodes the JPEG sequence (or upstream raw clip) into a CMAF asset.
  3. MediaPackage v2 packages it on demand into [[hls-and-dash|HLS]] / [[hls-and-dash|DASH]] for whatever player the UI uses.
  4. CloudFront fronts MediaPackage for cache + geo distribution.

The "many concurrent viewers" property doesn't really hold for monitoring-center use (typically one operator at a time per alert). So MediaPackage is **plausible but not obviously cost-justified** versus pre-packaged [[hls-and-dash|HLS]] in S3. Worth flagging as the canonical path if Actuate needs DRM (we don't today) or partners require multi-format delivery.

For a public-facing customer dashboard with many concurrent viewers (hypothetical), MediaPackage becomes much more compelling.

Cross-references: [[aws-mediaconvert-entity]] (the upstream encoder that feeds it), [[aws-ivs-entity]] (the lower-latency alternative for live), [[hls-and-dash]] (the protocol primitives), [[reading-list]] for MediaStore deprecation context.
