---
type: entity
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [gitops, deployment, kubernetes, helm, continuous-delivery]
---

# ArgoCD

ArgoCD is Actuate's **GitOps deployment platform**, managing all Kubernetes workloads across multiple clusters through a declarative, Git-driven sync model. It is deployed as a cluster service and is the single mechanism for deploying both business applications and infrastructure services to production.

## App-of-Apps Pattern

Actuate uses ArgoCD's **app-of-apps** pattern, where a single bootstrap Application per cluster watches the [[kubernetes-deployments]] Git repository and recursively creates all child Applications. The hierarchy is:

1. **Bootstrap Application** -- manually applied once per cluster via `kubectl apply -f`.
2. **Root Helm chart** (`app-of-apps`) -- creates two child apps: `applications` (business workloads) and `cluster-services` (infrastructure).
3. **Child Applications** -- each business app and infrastructure service is its own ArgoCD Application, with values defined in the Git repo.

This pattern means the entire cluster state is declared in version control. No manual `kubectl apply` or `helm install` commands are needed after the initial bootstrap.

## Three Clusters

ArgoCD manages configurations across clusters in two AWS accounts (`388576304176` and `558106312574`) spanning `us-west-2` and `eu-west-1` regions. Cluster names follow the `inference-eks-XXXX` naming pattern. Each cluster has its own `cluster-values.yaml` containing environment-specific overrides (image tags, domain names, AWS ARNs).

## Sync Model

ArgoCD polls the [[kubernetes-deployments]] repository on a default 3-minute interval and reconciles any drift between Git state and cluster state. Three ArgoCD Projects enforce RBAC separation:

- **`argo-cd-deployments`** -- bootstrap-only access
- **`argo-cd-applications`** -- business applications (restricted permissions)
- **`argo-cd-cluster-services`** -- infrastructure services (full cluster permissions)

## Deployment Workflow

Engineers deploy by merging changes to the kubernetes-deployments repo. ArgoCD detects the change and reconciles automatically. See [[rollout-process]] for the full release validation workflow that wraps around ArgoCD syncs.

## See Also

- [[kubernetes-deployments]] -- the Git repo ArgoCD watches
- [[rollout-process]] -- release validation built on ArgoCD
- [[multi-region-deployment]] -- multi-cluster context
- [[ds-terraform-eks-v2]] -- EKS cluster provisioning (upstream of ArgoCD)
