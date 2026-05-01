---
title: "Dev Deployment Issues: DynamoDB Type and API GW Redeployment"
type: concept
topic: inference-api
tags: [deployment, dynamodb, api-gateway, authorizer, debugging]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Dev Deployment Issues (April 2026)

Two issues prevented the v5 dev deployment from working after merge.

## Issue 1: DynamoDB `roles` Field Type

**Symptom:** [[rust-lambda-authorizer|Rust Lambda authorizer]] returns `{"errorType":"Unauthorized"}` with `FunctionError: "Unhandled"`. API Gateway returns 500 to client.

**Root cause:** The Rust authorizer's `DynamoDBItem` struct expects `roles: HashSet<String>` which maps to DynamoDB's `SS` (String Set) type. The API key record had `roles` stored as `S` (plain String) — `"full_access"` instead of `["full_access"]`.

**Fix:** Update DynamoDB record to use `SS` type:
```bash
aws dynamodb update-item --table-name InferenceAPIAuth-dev \
  --key '{"api_key": {"S": "KEY"}}' \
  --update-expression "SET #r = :roles" \
  --expression-attribute-names '{"#r": "roles"}' \
  --expression-attribute-values '{":roles": {"SS": ["full_access"]}}'
```

**Prevention:** When creating/updating API keys in DynamoDB, always use `SS` type for roles, not `S`. The Rust authorizer's type definition enforces this at the code level but the error message is opaque.

## Issue 2: Stale API Gateway Deployment

**Symptom:** Authorizer succeeds (checked via direct invocation and CloudWatch logs) but Lambda is never invoked. API Gateway returns `{"message":null}` 500.

**Root cause:** The API Gateway stage deployment was from March 30. Terraform's deployment triggers in `api-gw.tf` only track changes to API Gateway resources (methods, integrations, authorizers) — not Lambda function updates. Since the Lambda ARN didn't change (just the image digest), terraform didn't create a new deployment.

**Fix:** Force a redeployment:
```bash
aws apigateway create-deployment --rest-api-id ID --stage-name dev --region us-west-2
```

**Prevention:** This may need a terraform fix — either add the Lambda image digest to the deployment triggers, or add a `timestamp()` trigger that forces redeployment on every apply.

## Debugging Approach

1. Direct Lambda invocation (`aws lambda invoke`) — confirmed v5 code works
2. Direct authorizer invocation — found DynamoDB type error
3. CloudWatch logs — confirmed authorizer runs but Lambda isn't invoked
4. API Gateway stage inspection — found stale deployment from March 30
