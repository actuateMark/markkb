---
title: "Source: Kubernetes Microservice Deployment Guide"
type: source
topic: infrastructure
tags: [worklog, kubernetes, deployment, ecr, argocd, helm, gitops]
ingested: 2026-04-14
author: kb-bot
---

# Kubernetes Microservice Deployment Guide

Source: internal guide on how to deploy a new microservice to the Kubernetes cluster.

## Deployment Flow

No deployment keys are needed for repos -- everything is automated. The process:

1. **Build and push image** -- your repo builds a versioned Docker image and pushes it to ECR. This should already be set up via the template repo.
2. **Create deployment manifest** -- deployment is controlled separately in the `kubernetes-deployments` repo (GitOps).

## Two Approaches

### Helm Chart (Preferred)

Use the shared microservice Helm chart. Create an ArgoCD Application manifest with Helm values inline. Example reference: `kubernetes-deployments/deployments/applications/internal-homepage`.

### Raw K8s Manifests

Write Kubernetes manifests directly (Deployment, Service, ConfigMap, etc.) and place them in the deployments repo. Example reference: `kubernetes-deployments/deployments/applications/cost-per-site`.

## Review Process

Tag the infrastructure team for review on the deployment PR before merging to the `kubernetes-deployments` repo. ArgoCD will pick up and reconcile the changes automatically.

## Key Points

- Image building and deployment configuration are **fully separated** -- different repos, different concerns.
- ArgoCD handles reconciliation from Git state to cluster state.
- The `kubernetes-deployments` repo is the single source of truth for what runs in the cluster.
