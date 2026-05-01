---
title: "Lambda to Kubernetes Migration (Cancelled)"
type: concept
topic: inference-api
tags: [lambda, kubernetes, migration, infrastructure, eks, cancelled]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Lambda to Kubernetes Migration — CANCELLED

**ADR-001 Status: Denied (2026-04-13)**

The originally planned migration of the [[inference-api/_summary|Actuate Inference API]] from AWS Lambda to Kubernetes has been cancelled. The inference API will remain on Lambda permanently.

## Decision

The v5 API is an **extension of the existing API Gateway + Lambda setup**, not a migration. v1-v4 continue as-is, and v5 endpoints are added alongside them in the same Lambda function. There is no Dockerfile dual-mode, no uvicorn deployment, no VPC Link to K8s pods.

## Why Cancelled

The team determined that:
1. The v5 project scope is to unify and extend the current functionality, not migrate it
2. Dynamic K8s model discovery is not needed — models are dictated statically
3. The Lambda setup works well and doesn't need to change for v5
4. Hardening and infrastructure changes can happen later, independently

## What This Means

- No changes to deployment infrastructure (Lambda + API Gateway stays)
- No Helm charts for the inference API
- No VPC Link terraform
- Feature branches `feature/ed-32-inference-api-helm` ([[kubernetes-deployments]]) and `feature/ed-32-apigw-vpc-link` ([[ds-terraform-eks-v2]]) are no longer needed for this project
- The `actuate-libraries` branch `feature/ed-32-filter-annotations` is still relevant for filter consolidation

## Current Architecture (Permanent)

```
API Gateway -> Rust Lambda Authorizer -> Lambda (FastAPI/Mangum, container image)
    -> Model Servers (K8s, ds-model-prod) -> Post-processing filters -> Response
```

This architecture serves v1 through v5 endpoints from the same Lambda function.
