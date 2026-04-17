---
title: "Source: Helm Chart Strategy and Karpenter Workflow"
type: source
topic: infrastructure
tags: [worklog, helm, karpenter, argocd, gitops, kubernetes, nodepools]
ingested: 2026-04-14
author: kb-bot
---

# Helm Chart Strategy and Karpenter Workflow

Source: internal notes on Helm chart organization and the Karpenter nodepool management workflow.

## Helm Values File Strategy

Break values files into two tiers:
1. **Defaults** -- values that generally do not change between projects.
2. **Per-project overrides** -- the subset that always needs customization.

Multiple values files can be layered:
```
helm template test charts/mychart --values ci/test-values.yaml,ci/prod-values.yaml
```

## Karpenter Nodepool Management

- **Helm chart location**: `/helm/karpenter-nodepools/` -- a template chart generating all YAML for nodepools and nodeclasses from input values.
- **Generated manifests**: `/kubernetes/prod-cluster/karpenter-nodepools/generated-manifests/` -- output of `template.sh`, which runs `helm template` for each values file in the `values/` directory (currently 4 releases, each producing its own YAML file).
- **Current workflow**: manifests are applied manually via `kubectl apply -f <file>` (often using the VS Code Kubernetes extension's right-click apply).
- **Target workflow**: ArgoCD will manage Helm charts directly, eliminating the need to template and commit generated manifests.

## Repo Split Plan

The long-term vision is to split into:
- **Helm charts repo** -- reusable charts in a single location.
- **Deployments repo** -- ArgoCD application manifests + values files that reference charts.

For Helm-based deployments, the deployments repo would contain only the ArgoCD Application manifest and a `values.yaml` -- no templated output. This aligns with [ArgoCD Helm integration](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/).

## Reference

- Terraform EKS repo: `ds-terraform-eks`
- Helm best practices article: [Develop Helm Charts Like a Pro](https://betterprogramming.pub/develop-helm-charts-like-a-pro-a9fea5a33fe5)
