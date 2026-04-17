---
title: "layers"
type: entity
topic: infrastructure
tags: [lambda, aws, python, lambda-layers, requests]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# layers

A repository containing pre-built **AWS Lambda layer** artifacts. Lambda layers provide shared runtime dependencies that can be attached to multiple Lambda functions, avoiding the need to bundle common libraries into every function's deployment package.

## Contents

The repo holds a single layer focused on HTTP client dependencies for Python 3.12 Lambda functions:

- **`requests.zip`** -- the packaged layer archive ready for upload to AWS Lambda.
- **`python/`** -- the unpacked layer contents following the Lambda layer directory convention (`python/` at the root so Lambda can find the packages on the Python path).

## Bundled Packages

The layer includes the `requests` HTTP library and its full dependency tree, all built for Python 3.12 on x86_64 Linux:

| Package | Version | Purpose |
|---|---|---|
| **requests** | 2.32.5 | HTTP client library -- the primary reason this layer exists |
| **urllib3** | 2.5.0 | Low-level HTTP connection pooling (requests dependency) |
| **certifi** | 2025.11.12 | Mozilla CA certificate bundle for TLS verification |
| **charset-normalizer** | 3.4.4 | Character encoding detection (includes compiled `.so` extensions) |
| **idna** | 3.11 | Internationalized domain name handling |

The `charset_normalizer` package includes compiled native extensions (`md.cpython-312-x86_64-linux-gnu.so`), confirming the layer is built targeting the `x86_64` Lambda runtime architecture.

## How It Is Deployed

The layer is managed by the `lambda-layers` Terraform module in the `ds-terraform-eks-v2` repository. That module uploads the zip archive to AWS and creates a Lambda Layer Version resource. Individual Lambda functions (provisioned via the `core-lambdas` module) reference this layer ARN so they can `import requests` without including it in their own deployment packages.

## Relationship to Core Lambdas

The `core-lambdas` Terraform module deploys functions such as `lambda_sns_to_slack`, `lambda_inference_api_authrs`, `lambda_create_detection_window`, and others. These functions depend on the requests layer for outbound HTTP calls to Slack webhooks, internal APIs, and third-party services. The layer is attached via the `layers` parameter in the Lambda function Terraform resource.

## Maintenance

When upgrading `requests` or its dependencies, the `python/` directory should be rebuilt (typically via `pip install requests -t python/` on an Amazon Linux container or equivalent), then re-zipped into `requests.zip` and the Terraform module re-applied to publish a new layer version.
