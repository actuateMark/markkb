---
title: "Runbook: IaC vs live-AWS drift discovery & remediation"
type: concept
topic: runbooks
tags: [runbook, terraform, terragrunt, iam, iac-drift, import, ds-terraform-eks-v2]
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
---

# IaC vs live-AWS drift discovery & remediation

## When this applies

A live AWS resource exists in production but isn't managed by any Terraform module — typically a role, policy, or bucket built years ago via the AWS console / Visual Editor that was never reconciled when the team adopted IaC for that concern. Symptoms are usually invisible: the resource works, but changes to it can't be PR-reviewed, drift accumulates, and missing-permission incidents (like the 2026-04-29 [[2026-04-29_iam-access-denied-missing-resource-arn|MotionFrame GSI gap]]) take time to detect because there's no canonical source-of-truth diff to inspect.

## Symptoms

- `grep` for the resource name in your IaC repo finds **only consumers** (e.g., `kubernetes-deployments/.../cluster-values.yaml`) and **no Terraform definition**
- The shared module that *should* manage this kind of resource creates a sibling with a different name (e.g., `${name_prefix}foo-role` vs the live `foo-role`)
- The live policy has `VisualEditor0/1/2` Sids — strong signal it was hand-built in IAM Visual Editor
- `terraform state list | grep <resource>` returns nothing in any stage

## Diagnose

1. **Enumerate the live shape.** For an IAM role:
   ```bash
   AWS_PROFILE=prod aws iam list-attached-role-policies --role-name <name>
   AWS_PROFILE=prod aws iam list-role-policies --role-name <name>
   AWS_PROFILE=prod aws iam get-role-policy --role-name <name> --policy-name <policy>
   ```
   Save the policy document to a file (`/tmp/<resource>-policy-before.json`) — this is your rollback baseline.

2. **Identify the canonical IaC home.** Per [[knowledgebase/topics/actuate-platform/notes/entities/core-repo-suite|core-repo-suite]], `ds-terraform-eks-v2` owns IAM. Find the shared module file that handles this concern (`modules/eks-irsa/<service>.tf`).

3. **Compare structure, not just contents.** Even if the resources look "similar," check: managed-policy attachment vs inline policy, prefixed vs bare names, hard-coded ARNs vs `${var.region}` interpolation. These STRUCTURAL differences determine whether a simple `import` will succeed or whether you need a parallel resource block. See [[2026-04-29_iam-tf-import-pattern]] for full pattern.

## Fix

Two paths, depending on what diagnosis revealed:

### Path A — module shape matches live (rare)

If the shared module would produce structurally-identical output (same managed-vs-inline, same name pattern, same general policy shape), enable the module flag in the right stage and `terragrunt run -- import`. Plan should be near-no-op.

### Path B — module shape differs from live (typical)

Add a **parallel gated resource** in the same module file, gated by a new `enable_<feature>_<scope>` flag (default `false`). Only the target stage flips it true; existing stages are structurally insulated. See [[2026-04-29_iam-tf-import-pattern]] for the full convention and the [aegissystems/ds-terraform-eks-v2#77](https://github.com/aegissystems/ds-terraform-eks-v2/pull/77) reference example.

Cleanup at import time: drop obvious typos (e.g., malformed ARNs), rename Sids semantically, alphabetize Action / Resource arrays. Do **NOT** drop ARNs you don't fully understand — even ones that look "dev-ish" in a prod policy may be actively exercised.

## Verify

After `terragrunt run -- plan`:

- **Expected**: only the cleanup deltas (Sid renames, sorted arrays, dropped malformed ARNs)
- **Red flag**: any "destroy + create" or any ARN that's listed as "removed" beyond the malformed ones
- **Red flag**: a different `name` value (would mean recreating the role with a new name → breaks the consumer's ServiceAccount annotation)

If the plan looks right, `terragrunt run -- apply`. Then re-fetch the live policy with `aws iam get-role-policy` and confirm it matches what Terraform claims to have applied.

## Prevent

- **Catch hand-built drift early.** Add a generic dashboard signal that flags the symptom of the absent IaC (e.g., `iam_access_denied_cluster_wide` catches missing-grants which often correlate with hand-built roles missing newer ARNs). See `~/.claude/skills/dashboard-check/config/signals.json`.
- **Bring under IaC at the moment of fixing.** When you hotfix a live resource, file a follow-up to import — same-day if possible, since you already have the policy state in front of you.
- **Audit pass periodically.** Walk consumers (cluster-values.yaml, helm charts, deployment manifests) to find IAM/AWS-resource references; cross-check against Terraform `state list` to find anything referenced-but-not-managed.

## Cross-refs

- [[2026-04-29_iam-tf-import-pattern]] — the canonical pattern for parallel-gated-resource imports
- [[2026-04-29_iam-access-denied-missing-resource-arn]] — the runbook for the typical incident class that surfaces drift
- [aegissystems/ds-terraform-eks-v2#77](https://github.com/aegissystems/ds-terraform-eks-v2/pull/77) — worked example
- [[runbooks/_summary|Runbooks]]
