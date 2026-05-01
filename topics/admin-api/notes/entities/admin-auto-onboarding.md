---
title: "admin-auto-onboarding"
type: entity
topic: admin-api
tags: [onboarding, cameras, nvr, admin, fastapi, vpn, automation]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/core-repo-suite.md
incoming_updated: 2026-05-01
---

# admin-auto-onboarding

A microservice and CLI tool that automatically onboards cameras to the Actuate Admin system using NVR (Network Video Recorder) camera lists. It compares cameras auto-added from NVRs (stored in `inframap_nvrcameras`) against the Admin database and performs bulk updates, additions, or onboarding operations.

**Repo:** `aegissystems/admin-auto-onboarding` (GitHub, private)
**Description:** Scripts to automatically onboard cameras from NVR camera list
**Language:** Python (FastAPI)
**Contact:** Slack @Tati
**Last updated:** 2026-04-08

## How It Works

The main work endpoint is `/action` (documented at `/docs`). The service can also be driven from the command line via `python -m auto_onboarding` with flags for stage (`-s`), customer type (`-c`), and action (`-a`). Supported actions include `preview` (dry run), `update` (force update existing cameras), and `onboard` (add new cameras from federated sources).

## VPN Checker

The repo includes a VPN health checker (`src.vpn_checker.vpn_checker`) that monitors site VPN connections. It uses Nmap to ping configured IP targets and automatically attempts tunnel refreshes on failure, with a 20-minute cooldown between refresh attempts. This is important because camera onboarding requires network connectivity to on-premise NVRs through VPN tunnels.

## Deployment

Built as a Docker image, pushed to ECR via GitHub Actions with semver tagging (`#patch`, `#minor`, `#major` in commit messages). Deployed as a Kubernetes CronJob, with image tags managed in the [[kubernetes-deployments]] repo. Uses `uv` for dependency management with a private CodeArtifact index for internal packages.

## Related Repos

- **[[actuate-admin-rds|actuate_admin]]** -- the main Django repo for the Camera Admin database that this service writes to.
- **connector-tools** -- downloads data from NVRs and updates the NVR camera list that auto-onboarding consumes.
- **[[kubernetes-deployments]]** -- contains the CronJob manifest for scheduling auto-onboarding runs.

## Operational Notes

Credentials are stored in AWS Secrets Manager. The service currently has no automated tests (noted as a known gap in the README). Documentation is available on the internal wiki at `kb.actuateui.net/camera-admin/admin-auto-onboarding/`.
