---
title: "Reusable GitHub Actions"
type: entity
topic: infrastructure
tags: [ci-cd, github-actions, docker, ecr, base-images, runner, sonar]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Reusable GitHub Actions

Central repository for shared CI/CD workflows, reusable GitHub Actions, and Docker base images used across the Actuate organization. Prevents duplication by providing standard building blocks that other repos reference.

**Repository:** `aegissystems/reusable-github-actions`
**Primary language:** Shell / YAML / Dockerfile

## Reusable Workflows

Located in `.github/workflows/`:

| Workflow | Purpose |
|----------|---------|
| `python-test.yml` | Standard Python test pipeline |
| `k8s-deploy.yml` | Kubernetes deployment via ArgoCD |
| `build-lambda.yml` | Lambda function build and deploy |
| `sonar.yml` | SonarQube code analysis |
| `sonar-auto-remediation.yml` | Automated Sonar issue remediation |
| `set-sonar-version.yml` | Version tagging for Sonar |
| `build-base-images.yml` | Multi-arch Docker base image builds |

## Docker Base Images

### GitHub Actions Runner (`actuate-runner`)

Custom Kubernetes-based GitHub Actions runner images:
- `:base` -- runner base image (tracks upstream `actions/runner` releases).
- `:pyci` -- Python CI image with rye, tox, twine for library publishing.

### Application Base Images (`actuate-base`)

A layered hierarchy of pre-built images that downstream services extend:

- **`:latest`** -- Python 3.12 slim-bookworm + UV + AWS CLI v2 + common system deps. Used by connector-tools, terminator, robomladen.
- **`:ffmpeg`** -- extends `:latest` with FFmpeg (static, multi-arch) and media libraries. Used by queue_consumer, frame_receiver_smtp.
- **`:nginx`** -- extends `:ffmpeg` with Nginx, python3-opencv, nmap, libgeos. Used by actuate_admin, actuate_ailink, actuate_monitoring_api.

All images are pushed to ECR at `388576304176.dkr.ecr.us-west-2.amazonaws.com`.

## Build Process

Images are automatically built on push to `main` when Dockerfile changes are detected. Manual builds can be triggered via the Actions UI, selecting which images to build (`base,ffmpeg,nginx,runner,pyci` or `all`). Builds run on both `ubuntu-latest` (x86) and self-hosted ARM64 runners in parallel, then create multi-arch manifests.

Local builds use `just` commands (e.g., `just build`, `just build-app-base`, `just build-runner`) and require cross-platform emulators for multi-arch support.

## CI Scripts

The `ci/` directory contains helper scripts including `dispatch-sonar-remediation-events.sh` and `run-cursor-sonar-remediation.sh` for automated code quality workflows.
