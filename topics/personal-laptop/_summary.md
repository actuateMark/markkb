---
title: "Personal Laptop"
type: summary
topic: personal-laptop
tags: [personal, thinkpad, ubuntu, hardware, configuration]
created: 2026-04-17
updated: 2026-04-29
author: kb-bot
---

Hardware: ThinkPad P14s Gen 5 running Ubuntu 24.04 (noble), kernel 6.17.0-20-generic HWE, NVIDIA RTX 500 Ada GPU.

Tracks operational state, incidents, and configurations specific to mork's personal development laptop. Also covers the always-on Firebat mini PC (`mork-firebat`) provisioned 2026-04-23 — its toolkit, dashboard app, and API surface live here.

## Scope

- **OS/driver state**: kernel upgrades, nvidia driver versions, DKMS vs prebuilt module strategies
- **Hardware quirks**: GPU suspend/resume, power management edge cases, peripheral compatibility
- **IT incidents**: crashes, boot failures, driver install failures, recovery procedures
- **Configuration tuning**: power/sleep settings, display setup, network tweaks
- **Diagnostics**: useful commands for troubleshooting laptop-specific issues
- **Minipc / mork-firebat**: provisioning toolkit, dashboard app architecture, API surface, observability cache

## For other Claude sessions: minipc API discovery

Live data the minipc already collects (dashboard signals, host metrics, KB query) is exposed at `http://mork-firebat/app/api/`. Start here:

- [[2026-04-29_minipc-api-surface]] — endpoint catalog with curl examples and architecture
- Live human-readable page: `http://mork-firebat/app/endpoints/` (top-nav tile on the minipc dashboard)
- Live Swagger UI: `http://mork-firebat/app/api/api-docs`

## Recent Incidents

- [[2026-04-17_nvidia-565-server-install-failure|NVIDIA 565-server install failure and recovery (2026-04-16)]]
