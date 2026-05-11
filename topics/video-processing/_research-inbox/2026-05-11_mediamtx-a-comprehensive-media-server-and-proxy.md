---
title: "MediaMTX: A Comprehensive Media Server and Proxy"
type: source
topic: video-processing
tags: ['media-server', 'streaming', 'protocols', 'proxy', 'conversion']
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
status: research-draft
origin: "https://github.com/bluenviron/mediamtx"
---
# MediaMTX: A Comprehensive Media Server and Proxy

MediaMTX is a ready-to-use media server and proxy that supports various protocols for publishing, reading, proxying, recording, and playing back video and audio streams.

## Overview

MediaMTX is a ready-to-use and zero-dependency real-time media server and media proxy that allows to publish, read, proxy, record and playback video and audio streams. It has been conceived as a "media router" that routes media streams from one end to the other, with a focus on efficiency and portability.

Publish live streams to the server with SRT, WebRTC, RTSP, RTMP, HLS, MPEG-TS, RTP, using [[ffmpeg-entity|FFmpeg]], [[gstreamer-entity|GStreamer]], OBS Studio, Python , Golang, Unity, web browsers, Raspberry Pi Cameras and more.

Read live streams from the server with SRT, WebRTC, RTSP, RTMP, HLS, using FFmpeg, GStreamer, VLC, OBS Studio, Python , GStreamer, Unity, web browsers and more.

Streams are automatically converted from a protocol to another

Serve several streams at once in separate paths

Reload the configuration without disconnecting existing clients (hot reloading)

Serve always-available streams even when the publisher is offline

Record streams to disk in fMP4 or MPEG-TS format

Playback recorded streams

Authenticate users with internal, HTTP or JWT authentication

Forward streams to other servers

Proxy requests to other servers

Control the server through the Control API

Extract metrics from the server in a Prometheus-compatible format

Monitor performance to investigate CPU and RAM consumption

Run hooks (external commands) when clients connect, disconnect, read or publish streams

Compatible with Linux, Windows and macOS, does not require any dependency or interpreter, it's a single executable

## Key claims

- MediaMTX is a ready-to-use and zero-dependency real-time media server and media proxy.
- It supports various protocols for publishing, reading, proxying, recording, and playing back video and audio streams.
- Streams are automatically converted from one protocol to another.

## Open questions

- How does MediaMTX handle protocol conversion between SRT and WebRTC?
- What are the performance implications of using MediaMTX with high-definition video streams?
