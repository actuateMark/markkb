---
title: "Runbook: IAM AccessDeniedException — missing resource ARN (e.g. GSI)"
type: concept
topic: runbooks
tags: [runbook, iam, dynamodb, access-denied, gsi]
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
incoming:
  - topics/actuate-platform/notes/syntheses/2026-04-29_iam-tf-import-pattern.md
  - topics/personal-notes/notes/daily/2026-04-29.md
  - topics/runbooks/_backlog.md
  - topics/runbooks/_summary.md
  - topics/runbooks/notes/concepts/2026-04-29_iac-live-drift-discovery.md
incoming_updated: 2026-05-01
---

## Symptom

NR logs show repeated `AccessDeniedException` or `not authorized to perform` errors for an AWS API call. Service remains partially functional — table-level operations succeed but queries against a specific index or resource fail. Errors appear in Connector-EKS logs after a deployment or config change.

## Diagnose

1. Find the exact Resource ARN mentioned in the error message or API call logs. For DynamoDB: look for table name and index name.
2. Dump the IAM role's policies:
   ```bash
   AWS_PROFILE=prod aws iam list-attached-role-policies --role-name <role>
   aws iam list-role-policies --role-name <role>
   aws iam get-role-policy --role-name <role> --policy-name <policy>
   ```
3. Compare the failed Resource ARN to the `Resource` array in the policy. GSI access requires the pattern: `arn:aws:dynamodb:<region>:<account>:table/<TableName>/index/<IndexName>` or wildcard `/index/*`.
4. Red flag: policy has `arn:aws:dynamodb:...:table/TableName` but no `/index/*` form. Sid prefix `VisualEditor*` indicates hand-built policy (IAM Visual Editor), not Terraform — no IaC diff will catch it.

## Fix

**Path A: Hotfix (AWS CLI, ~2 min)**
```bash
# Save current policy
aws iam get-role-policy --role-name <role> --policy-name <policy> \
  --query PolicyDocument > policy-before.json

# Edit the JSON: add the missing index ARN to the Resource array
# Example: ["arn:aws:dynamodb:us-west-2:388576304176:table/TableName",
#           "arn:aws:dynamodb:us-west-2:388576304176:table/TableName/index/*"]

# Deploy the update
aws iam put-role-policy --role-name <role> --policy-name <policy> \
  --policy-document file://policy-updated.json
```

**Path B: Terraform (persistent, ~PR)**
If the role is in `ds-terraform-eks-v2` under `modules/eks-irsa/<service>.tf`, add both table and index ARNs to the resource list. Pattern reference: see `Image_Data_2` grants both `/table/Image_Data_2` and `/table/Image_Data_2/*`.

## Verify

```
cluster_name = 'Connector-EKS' AND message LIKE '%AccessDeniedException%' AND container_name = '<service>' SINCE 5 minutes ago
```

Should return 0 within 1-2 minutes of policy update (token caching may add slight lag). No service restart needed.

## Prevent

Dashboard signal `iam_access_denied_cluster_wide` (added 2026-04-29) flags any Connector-EKS container hitting AccessDenied within 12h. If a service starts emitting these, `/dashboard-check` will surface it in the red bucket immediately.

## Known Follow-Up

The `autopatrol-microservice-role` (account 388576304176, us-west-2) currently uses inline policies with `VisualEditor*` sids — not yet under IaC. Separate task tracks bringing it under Terraform in [[ds-terraform-eks-v2]].

## References

- [[2026-04-29_overnight-check|Overnight Check]] — incident that surfaced this pattern
- [[runbooks/_summary|Runbooks]]
