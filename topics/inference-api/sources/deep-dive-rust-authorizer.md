---
type: source
topic: inference-api
author: kb-bot
ingested: 2026-04-15
---

# Deep Dive: Rust Lambda Authorizer

The `authorizer_inference_rs/` crate contains two Rust Lambda binaries that serve as API Gateway custom authorizers. They validate API keys against DynamoDB and return IAM policy documents with role context for downstream [[deep-dive-filter-chain]] RBAC.

## Crate Structure

- **`src/lib.rs`** -- Shared types: `DynamoDBItem`, `AuthResponse`, `AuthPolicyDocument`, `AuthStatement`, `PolicyContext`.
- **`src/bin/authorize_inference.rs`** -- Main inference authorizer (X-API-Key header).
- **`src/bin/authorize_docs.rs`** -- Swagger UI authorizer (Basic Auth header).

## DynamoDB Schema

Table: `InferenceAPIAuth-{stage}` (provisioned via `terraform/authorizer-ddb.tf`).

| Attribute | Type | Description |
|-----------|------|-------------|
| `api_key` | `S` (hash key) | The raw API key string used as partition key |
| `name` | `S` | Human-readable name (customer/partner identifier) |
| `roles` | `SS` (String Set) | Set of role strings: `full_access`, `intruder`, `weapon`, `intruder_plus`, etc. |

Billing mode: provisioned (1 RCU / 1 WCU). Tagged with `Environment`, `Project`, `Name`.

## Inference Authorizer Flow (`authorize_inference.rs`)

1. Extract `authorization_token` from `ApiGatewayCustomAuthorizerRequest` (this is the `X-API-Key` value, mapped via API Gateway `identity_source = "method.request.header.x-api-key"`).
2. Extract `method_arn` and parse into a wildcard resource ARN: `arn:aws:execute-api:{region}:{account}:{api-id}/{stage}/*/*`.
3. Call `check_auth(token)` -- DynamoDB `GetItem` on the `api_key` partition key with projection `api_key, name, roles`.
4. Deserialize via `serde_dynamo::from_item` into `DynamoDBItem { name: String, roles: HashSet<String> }`.
5. Join roles into comma-separated string (e.g., `"full_access,intruder,weapon"`).
6. Return `AuthResponse` with IAM Allow policy and `PolicyContext { name, roles, token }`.

On failure at any step, returns `Err("Unauthorized")` which API Gateway translates to a 401.

## Docs Authorizer Flow (`authorize_docs.rs`)

1. Extract `Authorization` header, decode Base64 Basic Auth to get `username:password`.
2. Use `password` as the DynamoDB lookup key (same table).
3. Verify `result.name == username` -- both name and key must match.
4. Return policy for `/GET/docs` and `/GET/openapi.json` resources only (scoped, not wildcard).

## Role Extraction in FastAPI

The authorizer context flows through API Gateway into the Lambda event. [[deep-dive-filter-chain]] Mangum places it at `request.scope["aws.event"]["requestContext"]["authorizer"]`. The `CheckRoles` class in `api/security/check_api_key.py` extracts and parses the comma-separated `roles` string.

## Caching

API Gateway caches authorizer results. TTL is configurable via Terraform variable `authorizer_result_ttl_in_seconds` (default 3600s = 1 hour). Cache key is the identity source header value (the API key itself for inference, the Basic Auth header for docs).

## Dependencies

Rust crate uses: `aws-lambda-events`, `aws-sdk-dynamodb`, `lambda_runtime`, `serde_dynamo`, `base64`, `tokio`. The Lambda functions are named `InferenceAPIAuthRS-{stage}` and `InferenceAPIBasicAuthRS-{stage}` and are referenced as data sources in [[deep-dive-terraform-infra]].
