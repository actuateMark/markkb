---
type: source
topic: inference-api
author: kb-bot
ingested: 2026-04-15
---

# Deep Dive: Terraform Infrastructure

All infrastructure for the inference API is defined in `terraform/` using Terraform ~1.0 with the AWS provider ~5.100. Workspaces (`dev`, `prod`) handle stage separation. State is stored in S3 (`actuate-inference-api-terraform-state*`) with DynamoDB locking.

## Multi-Region / Multi-Account

Three deployment combinations managed via tfvars files in `terraform/environments/`:

| Account | Region | Profile |
|---------|--------|---------|
| `388576304176` | `us-west-2` | prod |
| `388576304176` | `eu-west-1` | prod |
| `558106312574` | `eu-west-1` | dev |

The `justfile` provides `tf-plan-all` / `tf-apply-all` commands that iterate all three.

## Lambda Function (`lambda.tf`)

- **Name:** `InferenceAPI-{stage}`
- **Package type:** Container image from ECR (`inference-api-lambda-{stage}:latest`)
- **Timeout:** 15 seconds
- **Memory:** 1024 MB
- **Tracing:** X-Ray Active
- **VPC:** Deployed into VPC subnets (required for model server access via kubefwd/internal networking)
- **Handler:** `newrelic_lambda_wrapper.handler` wrapping `inference_api.api.handler.handler` (Mangum)
- **Environment variables:** Model endpoint URLs (e.g., `INTRUDER_ENDPOINT_URL`), stage, Powertools config, New Relic config
- **IAM role:** `inference_api_lambda-{stage}-{region}` with VPC execution, SageMaker invoke, New Relic secret access. Prod additionally gets a deny-CloudWatch policy.

## API Gateway (`api-gw.tf`)

- **Type:** REST API (not HTTP API)
- **Name:** `inference_api_lambda_gw-{stage}`
- **Binary media:** `*/*` (all types, for multipart frame uploads)
- **Custom domain:** disabled execute API endpoint, uses Route53 custom domain
- **Throttling:** 500 burst, 1000 rate (both method-level and usage plan)
- **Resources:** Three proxy patterns:
  - `/docs` (GET) -- Basic Auth authorizer for Swagger UI
  - `/openapi.json` (GET) -- Basic Auth authorizer
  - `/{proxy+}` (ANY) -- X-API-Key authorizer for all other paths
  - Root `/` (ANY) -- no auth (health check)
- **Integration:** All routes use `AWS_PROXY` to the Lambda function
- **Usage plan:** Single plan with API key `inference_api_{stage}_test_key`

## Authorizers (`authorizer.tf`)

Two Lambda authorizers (not created by Terraform -- referenced as `data` sources):
- **`InferenceAPIAuthRS-{stage}`** -- validates `X-API-Key`, identity source: `method.request.header.x-api-key`. See [[deep-dive-rust-authorizer]].
- **`InferenceAPIBasicAuthRS-{stage}`** -- validates Basic Auth, identity source: `method.request.header.Authorization`.
- **Cache TTL:** configurable, default 3600s.
- **IAM role:** `api_gateway_auth_invocation-{stage}-{region}` with `AWSLambdaRole` for invoke permission.
- **Authorizer role policies:** DynamoDB read-only, Lambda basic execution, VPC access.

## DynamoDB (`authorizer-ddb.tf`)

- **Table:** `InferenceAPIAuth-{stage}` (configurable via `authorizer_dynamodb_table_name`)
- **Hash key:** `api_key` (String)
- **Capacity:** Provisioned, 1 RCU / 1 WCU
- **Lifecycle:** `ignore_changes` on `table_class`

## ECR (`ecr.tf`)

- **Repository:** `inference-api-lambda-{stage}`
- **Image tag:** `latest` (referenced by Lambda via digest)

## DNS (`dns.tf`)

Module `./modules/dns` creates Route53 records + API Gateway custom domain mapping. Domains: `api.actuateui.net` (prod), `dev-api.actuateui.net` (dev).

## CI/CD IAM (`cicd.tf`)

- **Role:** `GithubActionsInferenceAPI` (conditional on `create_cicd_iam_role`)
- **Trust:** OIDC federation with `token.actions.githubusercontent.com`, scoped to `repo:aegissystems/*`
- **Permissions:** Terraform state S3, ECR, Lambda, API Gateway, Route53, DynamoDB, IAM, CloudWatch, ACM, VPC read
