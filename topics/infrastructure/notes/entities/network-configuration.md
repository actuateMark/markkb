---
title: "Network Configuration"
type: entity
topic: infrastructure
tags: [vpn, aws, terraform, fastapi, nat, argocd, networking, github-app]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-05-01
---

# Network Configuration

An internal web tool for managing AWS VPN configurations with CIDR conflict detection. Provides a UI-driven workflow for creating VPN connections to customer sites, with a split execution model: simple VPN operations run directly via AWS API, while infrastructure changes (new NAT instances) go through Terraform PRs for review.

**Repository:** `aegissystems/network-configuration`
**Runtime:** Python (FastAPI + uvicorn)
**URL:** `https://network-config.internal.actuateui.net`

## Capabilities

### Direct AWS API Operations
- **Customer Gateway** creation with customer's gateway IP.
- **VPN Connection** creation with static routes (propagated via VGW).
- **CloudWatch log group** creation for VPN tunnel monitoring.
- **VPN config download** -- AWS-generated device configuration documents.
- **Read-only queries** -- list NAT instances, VPN connections, customer gateways, route tables, and validate CIDR conflicts.

### Terraform PR Workflow (New NAT Instances)
When a dedicated NAT is needed, the service generates Terraform code and creates a PR in `ds-terraform-eks-v2` via the Actuate Applications GitHub App. After merge, CI/CD runs `terraform apply`. Resources created: customer gateway, fck-nat instance, elastic IP, security group, VPN connection, route table entries, and CloudWatch alarms.

The GitHub App integration uses short-lived tokens: the service generates a JWT signed with the app's private key, exchanges it for an installation access token (~1 hour), and triggers a `create-terraform-pr.yml` workflow dispatch.

## Deployment

Deployed via [[argocd|ArgoCD]] to the `network-configuration` namespace on EKS. Uses IRSA (IAM Roles for Service Accounts) for AWS permissions including EC2 describe/create operations and CloudWatch log management.

## Configuration

Key environment variables: `VPC_ID`, `VPC_CIDR`, `VPN_GATEWAY_ID` for AWS targeting; `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, and `GITHUB_APP_PRIVATE_KEY` (base64-encoded) for Terraform PR creation; `GITHUB_TERRAFORM_REPO` (defaults to `aegissystems/ds-terraform-eks-v2`). Local development can run with `AWS_ENABLED=false` to disable AWS integration.

## Design Rationale

The split between API-direct and Terraform-PR operations is intentional: VPN creation is an operational task equivalent to console actions, while NAT instances and route table modifications are core infrastructure that require peer review via IaC.
