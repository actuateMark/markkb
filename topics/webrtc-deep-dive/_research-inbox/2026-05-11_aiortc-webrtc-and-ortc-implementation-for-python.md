---
title: "aiortc: WebRTC and ORTC Implementation for Python"
type: source
topic: webrtc-deep-dive
tags: [webrtc, ortc, python, asyncio, real-time-communication]
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
status: research-draft
origin: "https://github.com/aiortc/aiortc"
---
# aiortc: WebRTC and ORTC Implementation for Python

aiortc is a Python library for WebRTC and ORTC, built on asyncio, providing a Pythonic API for real-time communication.

## Overview

aiortc is a library for Web Real-Time Communication (WebRTC) and Object Real-Time Communication (ORTC) in Python. It is built on top of asyncio, Python's standard asynchronous I/O framework.

The API closely follows its Javascript counterpart while using pythonic constructs:

* promises are replaced by coroutines
* events are emitted using pyee.EventEmitter

aiortc allows you to exchange audio, video and data channels and interoperability is regularly tested against both Chrome and Firefox. Here are some of its features:
* SDP generation / parsing
* Interactive Connectivity Establishment, with half-trickle and mDNS support
* DTLS key and certificate generation
* DTLS handshake, encryption / decryption (for SCTP)
* SRTP keying, encryption and decryption for RTP and RTCP
* Pure Python SCTP implementation
* Data Channels
* Sending and receiving audio (Opus / PCMU / PCMA)
* Sending and receiving video (VP8 / H.264)
* Bundling audio / video / data channels
* RTCP reports, including NACK / PLI to recover from packet loss

The main WebRTC and ORTC implementations are either built into web browsers, or come in the form of native code. While they are extensively battle tested, their internals are complex and they do not provide Python bindings.

## Key claims

- aiortc is a library for Web Real-Time Communication (WebRTC) and Object Real-Time Communication (ORTC) in Python.
- aiortc is built on top of asyncio, Python's standard asynchronous I/O framework.
- aiortc allows you to exchange audio, video and data channels and interoperability is regularly tested against both Chrome and Firefox.

## Open questions

- How does aiortc handle error propagation in asynchronous operations?
- What are the performance implications of using aiortc in high-load scenarios?

