---
title: "Source: Hackathon Training Plan"
type: source
topic: actuate-platform
tags: [worklog, hackathon, training, fastapi, kubernetes, internal-tools]
ingested: 2026-04-14
author: kb-bot
---

# Hackathon Training Plan

Worklog notes for an internal hackathon designed to build prototype-level internal tools while giving team members hands-on development experience.

## Objective

Get internal tools to prototype level and internally hosted. Provide hands-on project experience to less experienced developers. The stack and objectives are pre-planned so development is implementation-focused (no design decisions required), suitable for junior-level work.

## Infrastructure

Each project runs in its own K8s container built from a template deployment schema. Projects are fully isolated with minimal permissions (extended as needed). Each lives behind the API gateway at `/<container>/` as its root, with all API paths becoming `/<container>/<path>`.

## Curriculum (Lecture Series)

1. **Introduce the stack** -- overview of the full toolchain
2. **Backend** -- explain routes, sessions, request/response lifecycle
3. **Frontend** -- explain templates, function calls, DOM interaction
4. **Database** -- walk through adding an endpoint, calling it from frontend, adding DB entries, adding new pages

## Schedule

- **Day Zero**: Students brainstorm project ideas, pitch to Mark for scope/feasibility signoff.
- **Day One**: Lecture on tools, walk through scaffolding, align scope with skill level.
- **Day Two**: Build. Walkthroughs for various skills. EOD progress sharing.
- **Day Three**: Present final websites and deliverables.

## Project Ideas

- **Script Toolbox** -- UI wrapper around CS utility scripts (bulk schedule updates, etc.)
- **RoboMladen** -- model inference tool (see [[worklog-robomladen-kickoff]])
- **EmailCMS** -- content management for SES-based emails
- **Model Inference Tool** -- upload video/image/livestream, run through models, output annotated results
- **S3 Image Viewer** -- grid-based image browser
- **Demo Data Synth** -- generate synthetic demo videos with threat overlays for sales presentations

## See Also

- [[worklog-robomladen-kickoff]] -- RoboMladen product vision that came out of this
