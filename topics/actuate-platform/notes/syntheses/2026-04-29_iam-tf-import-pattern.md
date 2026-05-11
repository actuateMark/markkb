---
title: "Pattern: Importing a Hand-Built IAM Role into ds-terraform-eks-v2"
type: synthesis
topic: actuate-platform
tags: [terraform, terragrunt, iam, iac, pattern, ds-terraform-eks-v2, eks-irsa, import]
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
outgoing:
  - topics/personal-notes/notes/daily/2026-04-29.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/runbooks/notes/concepts/2026-04-29_iac-live-drift-discovery.md
incoming:
  - topics/autopatrol/notes/entities/autopatrol-deferred-backlog.md
  - topics/personal-notes/notes/daily/2026-04-29.md
  - topics/runbooks/notes/concepts/2026-04-29_iac-live-drift-discovery.md
incoming_updated: 2026-05-08
---

## When This Applies

A production IAM role exists but isn't under Terraform. Common origins: hand-built via IAM Visual Editor years ago, then the codebase grew a shared Terraform module for the same service later without reconciling the live role and the module. Result: drift becomes invisible to PR review, permission gaps (like the 2026-04-29 MotionFrame GSI access denied) take time to surface.

Symptom checklist:
- Policy Sids named `VisualEditor0`, `VisualEditor1`, etc. (Visual Editor artifact)
- No git history or PR record of when the role was created
- Missing ARNs discovered only when a workload hits AccessDenied
- Role name and structure don't match the Terraform module shape

## The Repo Convention: Parallel Gated Resource, Not Reshaped Existing

`ds-terraform-eks-v2` uses layered Terragrunt: shared modules in `modules/<concern>/`, per-stage environments in `stages/<env>/<region>/<concern>/terragrunt.hcl` that select a module and pass inputs. The `eks-irsa` module follows a one-file-per-role pattern (`autopatrol-microservice.tf`, `camera-admin.tf`, etc.), each gated by an `enable_<feature>` flag in `variables.tf` that stages toggle on/off.

**Pattern rule: Add a *parallel* resource block, don't reshape the existing one.**

Two reasons:

1. **Multi-stage blast radius.** The shared module is used by every stage calling it. Reshaping an existing resource block changes every role created from that block on next apply. Even stages that don't use the role (e.g., `prod-EU` with `autopatrolServer: enabled: false`) inherit the change, conflating concerns and complicating plan review.

2. **Semantic mismatch.** Hand-built roles and clean-sheet Terraform often diverge structurally (inline vs managed policy, bare role names vs prefixed names, region-specific ARNs vs interpolated). Forcing one shape onto the other either bloats the module with conditionals or breaks cleaner stages.

**Instead:** Create a new resource block in the same file, gated by a new flag like `enable_<feature>_<scope>` (default `false`). Only the target stage flips it true. The existing block is untouched. Module file becomes the canonical home for "all variants of this role" — readers see them side-by-side with clear comment headers explaining per-variant differences.

## Concrete Example: autopatrol-microservice (PR #77)

In `modules/eks-irsa/autopatrol-microservice.tf`:

**Existing (used by EU stages):**
```hcl
resource "aws_iam_role" "autopatrol_microservice_role" {
  name = "autopatrol-microservice-role"
  # ... trust policy, lifecycle config
  count = var.enable_autopatrol ? 1 : 0
}

resource "aws_iam_role_policy" "autopatrol_policy" {
  # ... managed policy with proper Sids
  count = var.enable_autopatrol ? 1 : 0
}
```

**New (hand-built import from us-west-2 prod):**
```hcl
resource "aws_iam_role" "autopatrol_microservice_role_uswest2_prod" {
  name = "autopatrol-microservice-role"
  # ... trust policy (shared from local.autopatrol_trust_statements)
  count = var.enable_autopatrol_uswest2_prod ? 1 : 0
}

resource "aws_iam_role_policy" "autopatrol_policy_uswest2_prod" {
  role = aws_iam_role.autopatrol_microservice_role_uswest2_prod[0].id
  # ... inline policy with cleaned-up Sids and complete ARNs
  count = var.enable_autopatrol_uswest2_prod ? 1 : 0
}
```

In `modules/eks-irsa/variables.tf`:
```hcl
variable "enable_autopatrol_uswest2_prod" {
  type    = bool
  default = false
}
```

Trust policy is factored to `local.autopatrol_trust_statements` — shared across both blocks, no duplication.

In `stages/prod/us-west-2/eks-irsa/terragrunt.hcl`:
```hcl
inputs = {
  enable_autopatrol_uswest2_prod = true
  # (all other _enable flags default false from variables.tf)
}
```

## Cleanup Applied at Import Time

While the policy is fresh in front of you:

1. **Drop obvious junk.** Example: `arn:aws:dynamodb:*:388576304176:table/arn:aws:dynamodb:us-west-2:388576304176:table/autopatrol-prompts` (malformed ARN from copy-paste). Drop it if the valid form is present elsewhere.

2. **Rename Sids semantically.** `VisualEditor0` → `DataPlaneAccess`, `VisualEditor1` → `S3AndSecretsManagement`. Easier to review and reason about in future PRs.

3. **Sort Actions and Resources alphabetically.** Stable diffs forever. AWS treats them as sets, so order doesn't matter operationally.

**Don't drop ARNs you don't understand,** even if they look "dev-ish". The live pod may depend on them. Example: `vlm-*.fifo`, `autopatrol_jobs_dev.fifo` were kept because logs showed the service actively exercising them.

## Operational Sequence

1. **PR ships code only** — the Terraform block and the new enable flag, with cleaned-up policy JSON.
2. **After merge**, from `stages/prod/us-west-2/eks-irsa/`:
   ```bash
   terragrunt run -- import aws_iam_role.autopatrol_microservice_role_uswest2_prod[0] arn:aws:iam::388576304176:role/autopatrol-microservice-role
   terragrunt run -- import aws_iam_role_policy.autopatrol_policy_uswest2_prod[0] autopatrol-microservice-role:autopatrol-policy
   ```
3. **Verify plan shows only cleanup deltas** (Sid renames, alphabetized arrays, dropped malformed ARNs) — no recreate, no unexpected drops.
4. **Apply the plan.**

## Cross-References

- [[2026-04-29_iam-access-denied-missing-resource-arn|Runbook: IAM AccessDenied — Missing Resource ARN]] — the incident class that motivated this pattern
- [[ds-terraform-eks-v2|ds-terraform-eks-v2 Entity]] — repo structure and module layout
- [aegissystems/ds-terraform-eks-v2#77](https://github.com/aegissystems/ds-terraform-eks-v2/pull/77) — the PR that established this pattern in production
