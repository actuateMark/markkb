---
title: "Connector Tools"
type: entity
topic: vms-connector
tags: [connector, tools, kubernetes, eks, camera-management, axis, mobotix, ecr]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Connector Tools

A collection of command-line utilities that support the VMS connector ecosystem. These tools are invoked as Kubernetes jobs by [[connector-deployer]] (which is itself triggered by actuate_admin), providing camera management, diagnostics, and configuration capabilities.

**Repository:** `aegissystems/connector-tools`
**Runtime:** Python 3.12

## Execution Lifecycle

```
admin -> connector-deployer -> connector-tools (K8s job)
```

Admin calls connector_deployer, which creates Kubernetes jobs in EKS that run connector-tools scripts.

## Available Tools

- **upload_camera_samples.py** -- Refreshes camera preview images used by Admin.
- **update_camera_list.py** -- Refreshes the auto-add camera list for a site.
- **check_streams.py** -- Pulls one frame from each configured RTSP stream to detect connectivity or credential issues.
- **check_configuration.py** -- Verifies TCP motion configuration on cameras.
- **configure_cameras.py** -- Writes motion-over-TCP settings to cameras (Axis only for settings-based config). Supports forced motion pings with `-m` flag.
- **update_camera_names.py** -- Updates motion signal camera names after renaming.
- **milestone_connection** (`utils.milestone_connection`) -- Compares Milestone server cameras against the admin database.
- **check_yolo_instances.py** -- Sends blank images to inference instances to detect caching or response issues.

Supported camera models: **Axis** (`utils/axis.py`) and **Mobotix** (`utils/mobotix.py`), each providing API interaction functions.

## Branches and Deployment

| Branch | Target | Notes |
|--------|--------|-------|
| `main` | ECR `connector-tools` | Production |
| `develop` | ECR `connector-tools-dev` | Dev (tagged with commit SHA) |
| `ec2` | EC2 instances | Frozen pre-library-upgrade code for old OpenSSL 1.0 compatibility |

Merging to `main` with `#major`, `#minor`, or `#patch` in the commit message triggers a new semver release to ECR (defaults to `#patch`). After ECR push, the image tag must be manually updated in `deployments/configmap.yaml` and applied with `kubectl apply` so that connector-deployer picks up the new version.

## Testing

A `kubernetes/job.yaml` template lets you manually run a job in the cluster before updating the configmap version, providing a pre-release validation step. A `job-dev.yaml` variant exists for dev images.
