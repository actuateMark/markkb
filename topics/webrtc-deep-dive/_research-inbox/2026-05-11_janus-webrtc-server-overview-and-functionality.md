---
title: "Janus WebRTC Server: Overview and Functionality"
type: source
topic: webrtc-deep-dive
tags: ['webrtc', 'server', 'multistream', 'communication', 'json-messages']
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
status: research-draft
origin: "https://janus.conf.meetecho.com/"
---
# Janus WebRTC Server: Overview and Functionality

Janus is a general-purpose WebRTC server developed by Meetecho, designed to facilitate communication with browsers, exchange JSON messages, and relay media streams.

## Introduction to Janus WebRTC Server

Janus is a WebRTC Server developed by Meetecho conceived to be a general purpose one. As such, it doesn't provide any functionality per se other than implementing the means to set up a WebRTC media communication with a browser, exchanging JSON messages with it, and relaying RTP/RTCP and messages between browsers and the server-side application logic they're attached to.

Any specific feature/application is provided by server side plugins, that browsers can then contact via Janus to take advantage of the functionality they provide. Example of such plugins can be implementations of applications like echo tests, conference bridges, media recorders, SIP gateways and the like.

## Key claims

- Janus is a WebRTC Server developed by Meetecho
- Janus is a general-purpose server
- Janus relays RTP/RTCP and messages between browsers and server-side application logic

## Open questions

- How does Janus handle scalability for high-traffic applications?
- What are the specific use cases for using Janus in a production environment?
