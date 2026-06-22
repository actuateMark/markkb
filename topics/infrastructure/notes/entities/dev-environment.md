---
title: "dev-environment"
type: entity
topic: infrastructure
tags: [onboarding, developer-tools, aws, eks, macos]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/branch-conventions.md
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/ai-models/notes/entities/ds-server-container.md
  - topics/engineering-process/notes/concepts/2026-04-17_local-testing-strategies-per-repo.md
  - topics/engineering-process/notes/entities/dev-test-tooling-pattern.md
  - topics/engineering-process/notes/syntheses/2026-05-20_local-ap-e2e-test-stack-plan.md
  - topics/personal-laptop/notes/syntheses/2026-04-23_firebat-minipc-as-claude-dev-box.md
incoming_updated: 2026-05-27
---

# dev-environment

A developer onboarding repository that provides setup scripts, AWS SSO configuration profiles, Kubernetes access config, and helper scripts to get a new Actuate engineer productive quickly. Targets macOS environments.

## Tools Installed

The `tools/install-darwin.sh` script installs the following via Homebrew (idempotent -- skips already-installed tools):

- **Homebrew** -- package manager (bootstraps itself if missing)
- **Git** -- version control
- **Curl** -- HTTP client
- **AWS CLI v2** -- installed from the official `.pkg` installer, validates it is v2
- **kubectl** -- Kubernetes CLI (via `kubernetes-cli` brew formula)
- **UV** -- fast Python package manager; also installs UV-managed tools: **ruff** (linter/formatter), **tox** (with tox-uv plugin), **pre-commit** (with pre-commit-uv plugin)
- **Just** -- command runner (like make)
- **JQ** -- JSON processor
- **YQ** -- YAML processor
- **Libraries**: `jpeg-turbo`, `geos` (geospatial) -- common native dependencies for Python packages

## AWS SSO Profiles

The `aws/` directory contains pre-configured AWS SSO config files for different IAM roles:

- `AdministratorAccess-DS.config` -- full admin for the data science account
- `AdministratorAccess-EKS-Admin.config` -- EKS cluster admin access
- `DataScientist.config` -- scoped data science role

Setup involves copying the appropriate config to `~/.aws/config` based on the engineer's assigned SSO role. A backup of any existing config is taken first.

## Kubernetes / EKS Access

The `kubernetes/kubeconfig` file provides pre-configured kubeconfig for all Actuate EKS clusters. Copied to `~/.kube/config` during setup, it enables immediate `kubectl` access once AWS SSO login is complete.

## CodeArtifact Login

The `codeartifact/actuate-codeartifact-login.sh` script is installed to `/usr/local/bin/actuate-codeartifact-login`. It authenticates against AWS CodeArtifact (Actuate's private Python/npm package registry) and writes credentials to `~/.aws/codeartifact.env`. The README recommends aliasing `ca-login` in the shell profile for convenience.

## ECR Login

The `ecr/actuate-ecr-login.sh` script is installed to `/usr/local/bin/actuate-ecr-login`. It authenticates Docker against the Actuate ECR registry so engineers can pull and push container images.

## Typical Onboarding Flow

1. Run `./tools/install-darwin.sh` to install all tools.
2. Copy the appropriate AWS SSO config from `aws/` to `~/.aws/config`.
3. Copy `kubernetes/kubeconfig` to `~/.kube/config`.
4. Install CodeArtifact and ECR login scripts to `/usr/local/bin/`.
5. Run `actuate-codeartifact-login` and `actuate-ecr-login` to authenticate.
