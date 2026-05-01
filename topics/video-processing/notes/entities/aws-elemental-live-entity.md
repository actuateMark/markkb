---
title: AWS Elemental Live (on-prem)
type: entity
topic: video-processing
tags: [aws, elemental, on-prem, encoder, broadcast, hardware-appliance]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/entities/aws-mediaconvert-entity.md
  - topics/video-processing/notes/entities/aws-medialive-entity.md
  - topics/video-processing/notes/syntheses/aws-video-services-decision-matrix.md
incoming_updated: 2026-05-01
---

# AWS Elemental Live (on-prem)

## What it is

The **on-prem** live encoder from the Elemental family — distinct from [[aws-medialive-entity]]. AWS Elemental Live is shipped either as:

- a **hardware appliance** — 1U/2U rack server with bundled encode/decode acceleration, marketed for broadcast facilities; or
- a **software variant** that runs on customer-supplied servers (with optional GPU hardware acceleration) under an Elemental software licence.

Elemental Technologies was an independent broadcast-encoder company (founded 2006) acquired by AWS in 2015. The full **Elemental family** today:

- **Elemental Live** — on-prem live encoder (this note).
- **Elemental Server** — on-prem file-based transcoder (the on-prem cousin of [[aws-mediaconvert-entity]]).
- **Elemental Conductor** — orchestration / management plane for fleets of Elemental Live + Server appliances.
- **Elemental Statmux** — statistical multiplexer for broadcast multiplexes.
- **Elemental Delta** — origin / packager (the on-prem cousin of [[aws-mediapackage-entity]]).
- **Elemental Link** — small contribution-encoder hardware that pushes into [[aws-medialive-entity|MediaLive]] in the cloud.

The cloud Media* services ([[aws-medialive-entity|MediaLive]] / [[aws-mediaconvert-entity|MediaConvert]] / [[aws-mediapackage-entity|MediaPackage]]) are descendants of Live / Server / Delta respectively, with the same underlying codec engine wrapped in AWS APIs.

## API / management surface

- **REST API** on each appliance — XML-based, predates the cloud-style JSON era. Documented per major version.
- **Web UI** for manual job submission, channel configuration, monitoring.
- **Conductor** for fleet management (group of N Live appliances behind a load-balancing job dispatcher with redundancy).
- **SNMP** / syslog / SMPTE health-monitoring hooks for broadcast NOCs.

The integration model is fundamentally different from cloud services — you operate the box, you patch its firmware/software, you wire its physical SDI / IP / ASI inputs.

## Heritage matters

Even if you never deploy Elemental Live, its heritage explains a lot of the cloud Media* services' shape:

- The job-spec JSON of [[aws-mediaconvert-entity|MediaConvert]] directly mirrors the on-prem Server job XML, just translated.
- [[aws-medialive-entity|MediaLive]]'s input list (RTP, [[rtmp-and-srt|SRT]], MediaConnect, AWS CDI, SMPTE 2110, MULTICAST) is broadcast-shaped because Elemental's customer base was broadcast.
- The redundant-pipelines model in [[aws-medialive-entity|MediaLive]] ("Standard channel = pipeline A + B") matches Elemental Live's hardware redundancy model.

This is why Media* services feel powerful but heavy — they were born to encode CNN, not surveillance feeds.

## Pricing model

- **Hardware appliance**: capex purchase + annual support contract.
- **Software licence**: per-server, perpetual or subscription, usually paired with a maintenance fee.
- AWS does not publish list pricing — sold via field sales, with discounts for volume/multi-year commitments. Substantially more expensive than running [[ffmpeg-entity|ffmpeg]] on a decent server, but rated for 24/7 broadcast SLA.

## When to reach for it

- ✅ **High-density on-prem encoding** — broadcast facilities encoding many feeds in a single room.
- ✅ **Air-gapped / low-bandwidth-uplink contexts** — government, defense, regional broadcasters, sports venues.
- ✅ **Broadcast contracts that require Elemental** by spec (it happens — incumbent broadcasters write specs around what they already operate).
- ✅ **Hybrid contribution** — Elemental Live on-site → MediaConnect → [[aws-medialive-entity|MediaLive]] in cloud.

## When not to reach for it

- Anything cloud-native — use [[aws-medialive-entity]] / [[aws-mediaconvert-entity]] / [[aws-mediapackage-entity]] instead.
- Hobbyist / startup-scale workloads — cost and operational complexity are absurd for non-broadcast.
- Anywhere [[ffmpeg-entity|ffmpeg]] or [[gstreamer-entity|GStreamer]] in a Linux server already does the job.

## Actuate touchpoints

**Not relevant to current architecture.** Actuate is cloud-first on AWS EKS; on-prem encoding hardware would be a strategic departure, not a tactical choice.

The reason this note exists in the topic: **the entire Elemental family lives at AWS**, and engineers researching [[aws-medialive-entity|MediaLive]]/[[aws-mediaconvert-entity|MediaConvert]]/[[aws-mediapackage-entity|MediaPackage]] repeatedly run into Elemental references in the docs and discover the cloud services are descendants of these on-prem boxes. Having this note prevents the "wait, is Elemental Live the same as [[aws-medialive-entity|MediaLive]]?" wheel-reinventing every time someone reads AWS docs.

There is one narrow scenario where Elemental could enter the picture: **partner sites with strict on-prem-encode contractual requirements** (government / defense). If a future enterprise customer wrote "all video encoding must terminate on-prem" into their contract, Elemental Live + Conductor would be the path of least friction relative to a homegrown on-prem encoder cluster — assuming the customer's compliance team is satisfied by AWS-branded hardware. This is purely hypothetical at present and would warrant its own design discussion.

For reference and context only:

- See [[aws-medialive-entity]] for the cloud successor.
- See [[aws-mediaconvert-entity]] for the file-based cloud cousin.
- See [[reading-list]] under "AWS-specific reading" for AWS Elemental Server / Conductor / Statmux references.
