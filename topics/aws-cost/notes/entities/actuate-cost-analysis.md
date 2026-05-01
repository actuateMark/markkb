---
title: "actuate-cost-analysis"
type: entity
topic: aws-cost
tags: [cost-analysis, eks, infrastructure, docker, kubernetes]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/aws-cost/_summary.md
  - topics/aws-cost/notes/syntheses/2026-04-27_aws-cost-topic-spinoff.md
  - topics/aws-cost/notes/syntheses/cost-architecture.md
incoming_updated: 2026-05-01
---

# actuate-cost-analysis

An EKS cost analysis tool that provides visibility into Actuate's Kubernetes infrastructure spending. The repository produces a Docker image that is deployed to Kubernetes for ongoing cost monitoring and reporting.

**Repo:** `aegissystems/actuate-cost-analysis` (GitHub, private)
**Description:** Actuate EKS Cost Analysis Tool
**Last updated:** 2026-04-10

## Build and Deploy

The project uses a simple versioned release workflow:

1. **Version** -- bump the version number in the `VERSION` file.
2. **Build** -- run `just push-ci` to build and push the Docker image (uses a `justfile` for task automation).
3. **Deploy** -- update image tags in the [[kubernetes-deployments]] repository, which triggers [[argocd|ArgoCD]] reconciliation.

The README is minimal, indicating this is a focused operational tool rather than a developer-facing library.

## Purpose

EKS cost analysis is a critical operational concern for Actuate, which runs inference workloads across multiple Kubernetes clusters in multiple AWS regions. This tool likely aggregates and reports on compute, networking, and storage costs at the cluster, namespace, or workload level. The per-site cost CSVs consumed by the [[sales-dashboard]] (compute, inference, slicing, storage breakdowns) may originate from or be informed by this tool's output.

## Relationship to Other Services

- **[[kubernetes-deployments]]** -- deployment manifests for this tool live in the [[kubernetes-deployments]] GitOps repo, following the standard [[argocd|ArgoCD]] app-of-apps pattern.
- **[[sales-dashboard]]** -- the [[sales-dashboard|sales dashboard]] consumes S3 CSV cost data that represents per-site infrastructure cost. This cost analysis tool is a likely upstream producer of that data.
- **S3** -- cost data is stored as CSVs in S3 buckets for downstream consumption.

## Tech Stack

- Docker-based containerized deployment
- `just` task runner for build automation
- Deployed to EKS via [[argocd|ArgoCD]]
