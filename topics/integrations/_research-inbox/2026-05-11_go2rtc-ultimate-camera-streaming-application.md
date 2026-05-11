---
title: "go2rtc: Ultimate Camera Streaming Application"
type: source
topic: integrations
tags: ['camera-streaming', 'web-interfaces', 'home-assistant', 'docker', 'binary-installation']
created: 2026-05-11
updated: 2026-05-11
author: kb-bot
status: research-draft
origin: "https://github.com/AlexxIT/go2rtc"
---
# go2rtc: Ultimate Camera Streaming Application

go2rtc is a comprehensive camera streaming application supporting multiple formats and protocols, offering integration options for Home Assistant and Docker.

## Overview

Ultimate camera streaming application with support for dozens formats and protocols.

Download binary or use Docker or Home Assistant add-on or integration

Open web interface: http://localhost:1984/

Add streams to config

Developers: integrate HTTP API into your smart home platform.

The application is compiled with the latest versions of the Go language for maximum speed and security. Therefore, the minimum OS versions depend on the Go language.

The Docker containers alexxit/go2rtc and ghcr.io/alexxit/go2rtc support multiple architectures including 386, amd64, arm/v6, arm/v7 and arm64.

## Home Assistant Add-on

To install the go2rtc Home Assistant add-on, navigate to Settings > Add-ons > Plus > Repositories > Add and enter `https://github.com/AlexxIT/hassio-addons`.

Once installed, start the add-on by going to go2rtc > Install > Start.

## Home Assistant Integration

WebRTC Camera custom component can be used on any Home Assistant installation. It can automatically download and use the latest version of go2rtc, or connect to an existing version. Addon installation in this case is optional.

The simplest config looks like this:

streams:
 hall-camera: rtsp://admin:password@192.168.1.123/cam/realmonitor?channel=1&subtype=0

by default go2rtc will search go2rtc.yaml in the current work directory

api server will start on default 1984 port (TCP)

rtsp server will start on default 8554 port (TCP)

webrtc will use port 8555 (TCP/UDP) for connections

## Key claims

- go2rtc supports dozens of formats and protocols.
- Docker containers for go2rtc are available with support for multiple architectures.
- The application is compiled with the latest versions of the Go language.
- Navigate to Settings > Add-ons > Plus > Repositories > Add
- Enter `https://github.com/AlexxIT/hassio-addons` in the repository field
- Start the add-on by going to go2rtc > Install > Start
- WebRTC Camera custom component can be used on any Home Assistant installation.
- go2rtc can automatically download and use the latest version, or connect to an existing version.
- Addon installation is optional.

## Open questions

- How does go2rtc handle different camera formats and protocols internally?
- What are the performance implications of using Docker versus a binary installation?
- How does go2rtc's web interface interact with the Home Assistant integration?
