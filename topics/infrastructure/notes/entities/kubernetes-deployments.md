---
title: "kubernetes-deployments"
type: entity
topic: infrastructure
tags: [argocd, gitops, kubernetes, helm, app-of-apps]
created: 2026-04-13
updated: 2026-04-14
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/core-repo-suite.md
  - topics/admin-api/notes/entities/admin-auto-onboarding.md
  - topics/ai-models/notes/entities/vlm-inference.md
  - topics/aws-cost/_summary.md
  - topics/aws-cost/notes/entities/actuate-cost-analysis.md
  - topics/data-science/notes/entities/ds-analysis-microservice.md
  - topics/external-api/notes/concepts/shared-auth-pattern.md
  - topics/inference-api/notes/concepts/lambda-to-k8s-migration.md
  - topics/infrastructure/notes/concepts/argocd-gitops-workflow.md
  - topics/infrastructure/notes/concepts/secrets-management.md
incoming_updated: 2026-05-01
---

# kubernetes-deployments

A GitOps repository that manages multi-cluster Kubernetes deployments using [[argocd|ArgoCD]]'s **app-of-apps** pattern. A single bootstrap Application per cluster watches this Git repo and recursively creates all child Applications, so the entire cluster state is declared in version control.

## Repository Structure

The repo has two top-level trees:

- **`argocd/`** -- [[argocd|ArgoCD]] Application definitions and per-cluster config.
  - `charts/app-of-apps/` -- the root Helm chart; creates two child apps (applications + cluster-services).
  - `charts/applications/` -- one [[argocd|ArgoCD]] Application template per business app.
  - `charts/cluster-services/` -- one [[argocd|ArgoCD]] Application template per infrastructure service.
  - `charts/inference/` -- dedicated charts for inference workloads (multimodel, slicing).
  - `env/{account_id}/{region}/{cluster_name}/` -- per-cluster `cluster-values.yaml` and bootstrap YAML.
- **`deployments/`** -- the actual Helm charts with Kubernetes manifests (`Deployment`, `Service`, `ConfigMap`, etc.) for both applications and cluster-services.

## Environments / Clusters

Configurations exist for two AWS accounts (`388576304176` and `558106312574`) across `eu-west-1` and `us-west-2`. Cluster names follow the pattern `inference-eks-XXXX`. Each cluster directory holds a bootstrap YAML (applied once via `kubectl apply -f`) and a `cluster-values.yaml` containing all overrides such as image tags, domain names, and AWS ARNs.

## Applications Managed

Business applications deployed through this repo include: **clips** (dev/prd), **deployer**, **vms-connector**, **queue-consumer** (dev/prd), **autopatrol-server**, **djangoq**, **connector-tools**, **cost-per-site**, **smtp-frame-receiver**, **sqs-frame-receiver**, **remote-link**, **wireguard-route-manager**, **timestamp-ocr**, **frames-near-timestamp**, **spegel-image-warmer**, **inference-multimodel**, **inference-slicing**, **classifyr**, **create-detection-window**, **monthly-reports**, and **internal-homepage**.

## Cluster Services

Infrastructure services managed via the cluster-services chart: **[[argocd|ArgoCD]]**, **AWS Load Balancer Controller**, **AWS EBS CSI Driver**, **AWS VPC CNI**, **Karpenter** (with CRDs and NodePools), **Istio** (base, istiod, CNI, ztunnel, Grafana, Jaeger addons), **Kiali**, **cert-manager**, **external-dns**, **ingress-nginx**, **Gateway API**, **CoreDNS**, **node-local-dns**, **Prometheus stack** (with Thanos, metrics-server, Prometheus adapter), **[[new-relic|New Relic]]**, **Kyverno** (with policies), **cluster-autoscaler**, **VPA**, **Spegel**, **SonarQube**, **RBAC**, **namespaces**, **Neuron** (AWS Inferentia), **NVIDIA device plugin**, **CHM node cordoner**, and **GitHub Actions Runner Controller** (ARM, x86, inference runners).

## How It Works

1. A bootstrap Application is manually applied once per cluster.
2. [[argocd|ArgoCD]] polls this repo (default ~3 min) and reconciles.
3. All values are namespaced under the `actuate:` key; cluster-values override chart defaults.
4. Three [[argocd|ArgoCD]] Projects enforce RBAC separation: `argo-cd-deployments` (bootstrap only), `argo-cd-applications` (business apps, restricted), and `argo-cd-cluster-services` (full cluster permissions).

## Deploying a New Microservice

No deployment keys are needed -- image builds and deployment configuration are fully separated:

1. **Build** -- the service repo builds a versioned Docker image and pushes to ECR.
2. **Deploy** -- commit a deployment manifest to this repo. Two options:
   - **Helm chart** (preferred): create an [[argocd|ArgoCD]] Application manifest with values inline, using the shared microservice chart. See `deployments/applications/internal-homepage`.
   - **Raw manifests**: write K8s YAML directly. See `deployments/applications/cost-per-site`.
3. [[argocd|ArgoCD]] reconciles automatically after merge.

## Helm Chart Strategy

Helm values files are organized in two tiers:

- **Chart defaults** -- values that rarely change between projects.
- **Per-project overrides** -- the subset that always needs customization.

Multiple values files can be layered: `helm template test charts/mychart --values ci/test-values.yaml,ci/prod-values.yaml`.

### Karpenter Nodepool Management

Karpenter nodepools are managed via a dedicated Helm chart at `/helm/karpenter-nodepools/`. A `template.sh` script runs `helm template` for each values file and outputs generated manifests, which are currently applied manually with `kubectl apply -f`. The target state is for [[argocd|ArgoCD]] to manage the Helm chart directly, eliminating the template-and-commit step.

### Long-Term Repo Split Plan

The vision is to split into two repos: a **Helm charts repo** (reusable charts) and a **deployments repo** ([[argocd|ArgoCD]] Application manifests + values files). For Helm-based deployments, the deployments repo would contain only the [[argocd|ArgoCD]] manifest and a `values.yaml`, with no templated output. Terraform EKS infrastructure lives in `ds-terraform-eks`.
