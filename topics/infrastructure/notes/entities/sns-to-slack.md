---
title: "SNS to Slack"
type: entity
topic: infrastructure
tags: [lambda, python, sns, slack, redis, sam, notifications, monitoring]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/infrastructure/notes/entities/new-relic.md
incoming_updated: 2026-05-01
---

# SNS to Slack

AWS Lambda that receives messages from SNS topics and forwards them to Slack channels via webhooks. Provides Redis-based message deduplication to prevent notification spam.

**Repository:** `aegissystems/sns_to_slack`
**Runtime:** Python 3.9
**IaC:** AWS SAM (`template.yaml` + `samconfig.toml`)

## How It Works

The Lambda is triggered by SNS topic subscriptions. When a message arrives, the function:

1. Checks Redis for duplicate messages to avoid re-sending.
2. Formats the message for Slack.
3. Posts to the appropriate Slack channel via webhook.
4. Records the message in Redis for future dedup checks.

The function runs inside a VPC to access the Redis cache and uses a custom Redis Lambda layer for connectivity.

## Slack Channels

Messages are routed to different channels based on type:
- `#eng_connector_warnings` -- primary operational warnings.
- `#eng_connector_audit_trail` -- audit trail events.
- `#test_warnings_formatting` -- test channel for message format validation.

## Deployment

### Environments

| Environment | Function Name | Stack | Branch Trigger |
|-------------|--------------|-------|----------------|
| Dev | `sns_to_slack_dev` | `sns-to-slack-stack-dev` | Push to `develop` |
| Production | `sns_to_slack` | `sns-to-slack-stack-prod` | Push to `main` |

### Methods

- **SAM CLI** -- `sam build && sam deploy` (uses `samconfig.toml` for environment config).
- **GitHub Actions** -- `develop.yml` and `main.yml` workflows auto-deploy on branch push. Both use OIDC with the `GitHubActionLambdaSAMDeploy` IAM role.

## Configuration

| Variable | Purpose |
|----------|---------|
| `ADMIN_URL` | Admin interface URL for customer links in messages |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL |

## IAM Roles

- **Deployment role** (`GitHubActionLambdaSAMDeploy`) -- used by GitHub Actions for CloudFormation stack management and Lambda deployment.
- **Execution role** (`sns_to_slack-role-8jaks69s`) -- runtime permissions for SNS, CloudWatch, and Redis access.

## Monitoring

CloudWatch logs at `/aws/lambda/sns_to_slack` (prod) and `/aws/lambda/sns_to_slack_dev` (dev). Logs can be tailed via `sam logs -n SnsToSlackFunction --stack-name <stack> --tail`.
