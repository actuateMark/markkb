---
type: concept
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
---

# Secrets Management

Secrets management at Actuate is split across two patterns: application-level secrets retrieved at runtime via AWS Secrets Manager, and Kubernetes-level secrets embedded in Git. The latter is a known critical security gap.

## Current State: Secrets in Git

Kubernetes workloads receive sensitive configuration through `cluster-values.yaml` files in the [[kubernetes-deployments]] repository. These files contain API keys, Snowflake credentials, database connection strings, and other secrets in plaintext, committed to version control. [[argocd|ArgoCD]] syncs these values into Helm templates that produce Kubernetes Secrets or inject values into pod environment variables.

This means anyone with read access to the repository can see production credentials. The blast radius of a repository compromise includes database access, third-party API keys, and internal service tokens. The values are also visible in Git history, so rotating a secret does not remove its prior value from the record.

## Application-Level Secrets (actuate-secrets)

For application code, the [[actuate-secrets]] library provides a wrapper around AWS Secrets Manager. Services like [[admin-api/_summary|Actuate Admin API]], [[actuate-daos]], and the autopatrol stack retrieve credentials at runtime using the naming convention `{stage}/actuate/{service}` (e.g., `prod/actuate/postgres`). This pattern is sound -- secrets are stored in a managed vault, access is controlled by IAM policies, and values are never in source code.

The gap is that this pattern only covers application-level secrets (database credentials, API tokens for third-party services). Infrastructure-level secrets (Helm values, [[argocd|ArgoCD]] configs, integration credentials passed to Kubernetes workloads) still live in `cluster-values.yaml`.

## Target State: External Secrets Operator

The planned remediation is to deploy the **External Secrets Operator (ESO)** into the EKS clusters. ESO creates Kubernetes `ExternalSecret` resources that reference secrets stored in AWS Secrets Manager. The operator periodically syncs the external secret values into native Kubernetes Secrets, which pods consume normally.

This would remove all plaintext secrets from `cluster-values.yaml`. The Git repository would contain only `ExternalSecret` manifests pointing to secret paths in AWS Secrets Manager -- no actual values. Secret rotation would happen in Secrets Manager, and ESO would propagate the new values to pods without a Git commit.

## Cognito Single-Client Gap

A related security concern is the **shared Cognito client**. Nineteen or more applications -- including [[admin-api/_summary|Actuate Admin API]], [[alert-ui]], camera-ui, and internal tools -- share a single Cognito app client. This means a configuration change to the client (scopes, callback URLs, token expiry) affects every application simultaneously. Cognito's update API is destructive (replaces the full client config), so a misconfigured update could break authentication across the entire platform.

The target state is **per-application Cognito client provisioning**, automated via Terraform or a management script. Each application would have its own client with tailored scopes, callback URLs, and token settings. This limits blast radius and allows independent lifecycle management.

Both the secrets-in-Git gap and the Cognito single-client issue are documented in the infrastructure summary as critical security gaps requiring remediation.
