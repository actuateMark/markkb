---
type: concept
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
---

# ArgoCD GitOps Workflow

All Kubernetes deployments at Actuate are managed through a GitOps model using ArgoCD. The [[kubernetes-deployments]] repository is the single source of truth -- every change to cluster state flows through a Git commit, and ArgoCD continuously reconciles the live cluster to match the declared state.

## App-of-Apps Pattern

The repository uses ArgoCD's **app-of-apps** pattern. A single bootstrap Application is manually applied once per cluster (`kubectl apply -f bootstrap.yaml`). This root Application watches the Git repository and recursively creates two child Application sets:

- **`applications`** -- business workloads: [[vms-connector]], queue-consumer, autopatrol-server, deployer, clips, connector-tools, and 15+ other services.
- **`cluster-services`** -- infrastructure components: ArgoCD itself, Karpenter, Istio, cert-manager, ingress-nginx, Prometheus stack, New Relic, Kyverno, VPA, and others.

Three ArgoCD Projects enforce RBAC separation: `argo-cd-deployments` (bootstrap only), `argo-cd-applications` (business apps, restricted permissions), and `argo-cd-cluster-services` (full cluster permissions for infrastructure).

## Cluster Environments

Configurations exist for two AWS accounts (`388576304176` and `558106312574`) across `eu-west-1` and `us-west-2`. Each cluster has a dedicated directory at `env/{account_id}/{region}/{cluster_name}/` containing:

- **`cluster-values.yaml`** -- all per-cluster overrides: image tags, domain names, AWS ARNs, feature flags, replica counts. Values are namespaced under the `actuate:` key and override Helm chart defaults.
- **Bootstrap YAML** -- the one-time root Application manifest.

## Sync Model

ArgoCD polls the Git repository on a default ~3 minute interval. When it detects drift between the declared state and the live cluster, it reconciles automatically. The flow from code change to running pods is:

1. **Developer pushes** a service change (e.g., to [[vms-connector]]) and merges to the appropriate branch.
2. **CI builds** a Docker image and pushes to ECR with a deterministic tag (`:stage`, `:latest`, or `:<branch-name>`).
3. **Developer updates** `cluster-values.yaml` in [[kubernetes-deployments]] with the new image tag (or the tag is already convention-based).
4. **ArgoCD detects** the Git change on the next poll cycle.
5. **ArgoCD applies** the updated Helm templates, which produce new Kubernetes manifests.
6. **Kubernetes rolls out** the new pods via the Deployment's rolling update strategy.

For services that use convention-based tags (`:stage`, `:latest`), the ECR push alone triggers a new rollout if the Deployment's `imagePullPolicy` is set to `Always`.

## Rollback Process

Rollback is a Git revert. Because the entire cluster state is declared in version control, reverting a commit in [[kubernetes-deployments]] and letting ArgoCD sync restores the previous state. For urgent rollbacks, ArgoCD's UI also supports manual sync to a specific Git revision, bypassing the poll interval. There is no imperative `kubectl` rollback in normal operations -- the Git history is the authoritative record of what should be running.

## Long-Term Direction

The team plans to split [[kubernetes-deployments]] into two repositories: a **Helm charts repo** (reusable chart templates) and a **deployments repo** (ArgoCD Application manifests and values files only). This would decouple chart development from deployment configuration.
