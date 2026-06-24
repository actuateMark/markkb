---
title: "WebRTC deep-dive — implementations for live streaming / frame transport"
type: summary
topic: webrtc-deep-dive
tags: [webrtc, live-streaming, frame-transport, moc]
updated: 2026-06-24
author: kb-bot
---

# WebRTC deep-dive

Focused research deep-dive (5 notes) on WebRTC server/client implementations, evaluated for **live streaming + low-latency frame transport** (camera-ui live view, the KVS/WebRTC frame plane, fleet-arch frame transport).

## Implementations surveyed
- [[notes/concepts/2026-05-18_janus|Janus]] — C WebRTC server (multistream, JSON signaling).
- [[notes/concepts/2026-05-18_aiortc|aiortc]] — Python WebRTC/ORTC.
- [[notes/concepts/2026-05-18_pion-webrtc|pion]] — Go WebRTC.

## How this fits
Feeds the live-streaming plan ([[vms-connector/_summary]] §live-streaming, the `enable-live-streaming` flag) and the fleet-arch frame-transport comparison ([[fleet-architecture/_summary]]). For KVS-WebRTC as a fleet frame plane see the video-processing bridge syntheses ([[video-processing/_summary]]).
