---
title: "Partner API Credential Runbook"
type: concept
topic: external-api
tags: [runbook, api-key, credentials, partner-onboarding, process]
jira: "ENG-126"
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
incoming:
  - topics/external-api/notes/concepts/2026-04-30_v5-detect-quick-reference.md
  - topics/external-api/notes/entities/ebus-partner-access.md
  - topics/inference-api/notes/concepts/api-key-lifecycle.md
  - topics/personal-notes/notes/daily/2026-04-17.md
  - topics/personal-notes/notes/daily/2026-04-23.md
  - topics/runbooks/_backlog.md
  - topics/runbooks/_summary.md
incoming_updated: 2026-05-01
---

# Partner API Credential Runbook

Mint and deliver API keys for external partners and internal test accounts on the inference-api. Use this runbook every time a new partner (e.g., EBUS), an internal staging account, or a customer rep needs credentials against v5 detect + Swagger docs. The flow is identical across dev and prod stages — only the account, region, and target table differ.

## When to Use

- New external partner onboarding (EBUS, AlarmWatch, etc.)
- Internal test or staging account setup
- Customer representative getting temporary docs access
- Any case where credentials reach beyond your organization boundary

## Prerequisites

- Cloned `aegissystems/actuate-inference-api` repo with `generate_api_key.py` at the root
- AWS SSO profile configured for the target account with admin rights:
  - **Dev inference-api:** account `388576304176`, region `us-west-2`, table `InferenceAPIAuth-dev`, usage plan ID `y36ojh`
  - **Prod inference-api:** account `388576304176`, region `us-west-2`, table `InferenceAPIAuth-prod`
  - **EU dev (if needed):** account `558106312574`, region `eu-west-1`
  - Verify with `aws sts get-caller-identity --profile <profile>` before running anything destructive
- Ability to run `uv run --project=inference_api python generate_api_key.py …`

## Step-by-Step

**1. Decide the `name` identifier.** Kebab-case, includes partner name + stage, e.g. `ebus-dev`, `verisure-prod`, `alarmwatch-staging`. Becomes both the DynamoDB row key and the Swagger Basic Auth username. No spaces or uppercase.

**2. Decide the role scope.** Choose one:
- `--full_access` — wildcard access to all current and future models (internal testing only)
- Explicit per-model flags — `--intruder --intruder_plus --intruder_plus_with_vehicle --weapon --pet --motion_plus --sliced_intruder_plus_with_vehicle` (recommended for partners; future-added models don't leak in)

**3. Run the script.** From the repo root:
```bash
uv run --project=inference_api python generate_api_key.py \
  --aws_profile <profile> \
  --aws_region <region> \
  --stage <dev|prod> \
  --username <name> \
  <role-flags>
```

The script creates an API Gateway key, binds it to the stage's usage plan, and writes the DynamoDB row (`roles` as `SS` type) in one transaction. On success, it prints the `api_key` value.

**4. Verify immediately.**
```bash
KEY='<api_key from script>'
curl -sw 'HTTP %{http_code}\n' -H "X-API-Key: $KEY" https://<base-url>/v5/models
curl -u "<name>:$KEY" -sw 'HTTP %{http_code}\n' https://<base-url>/docs -o /dev/null
```

Both should return 200. If `/v5/models` returns `403 Forbidden` with `x-amzn-errortype: ForbiddenException`, wait 5–10s and retry — API Gateway key propagation is eventually consistent.

**5. Record the credential location.** Write a KB entity note at `topics/external-api/notes/entities/<partner>-partner-access.md`. Use [[ebus-partner-access]] as the template. Include:
- DynamoDB row location (account, region, table, `name` field)
- API Gateway Key ID
- Enabled roles
- How the partner uses it
- Rotation/revocation procedure
- **Never include the api_key value itself**

**6. Produce the handoff block** using the template below. Deliver via appropriate secure channel (Slack DM, 1Password share, encrypted email, Jira comment if the ticket is internal-only).

## Handoff Block Template

```
=== <PARTNER> — Actuate Inference API (<STAGE>) ===

Base URL:       https://<base-url>
Environment:    <stage>
Created:        YYYY-MM-DD

--- API Access ---
Header:         X-API-Key
Key:            <api_key>
Endpoints:      GET  /v5/models
                POST /v5/detect
Models:         <comma-separated model IDs caller can access>

--- Swagger / OpenAPI Docs (HTTP Basic Auth) ---
URL:            https://<base-url>/docs
OpenAPI spec:   https://<base-url>/openapi.json
Username:       <name>
Password:       <api_key>  # same value as the API key

--- Quick-start curl ---
curl https://<base-url>/v5/models \
  -H "X-API-Key: <api_key>"

curl -X POST https://<base-url>/v5/detect \
  -H "X-API-Key: <api_key>" \
  -H "Content-Type: application/json" \
  -d '{"model_id":"intruder","frames":["<base64 JPEG>"],"data":{"sensitivity":"medium"}}'

--- Notes ---
Throttle:       <burst>/<rps> (<stage> plan)
Rotation:       contact <platform owner> — rotates via generate_api_key.py script
                in actuate-inference-api repo (DDB InferenceAPIAuth-<stage>)
```

**Stage defaults:**
- Dev base URL: `https://dev-api.actuateui.net`; throttle 500 burst / 1000 rps
- Prod base URL: `https://api.actuateui.net` (verify in Terraform)

## Gotchas

**AWS profile naming is a trap.** Historically the local `prod` profile points at `388576304176` (where both dev and prod inference-api run), while `dev` points at `558106312574` (EU account). Never trust profile names — always verify with `aws sts get-caller-identity --profile <name>`.

**DDB `roles` must be `SS` (String Set), not `S` (String).** The script gets this right. If anyone hand-edits a row in the AWS console, double-check the type — the Rust authorizer silently fails deserialization and returns opaque "Unauthorized" otherwise. See [[api-key-lifecycle]].

**API Gateway key propagation is eventually consistent.** First calls after key creation often return `403` for 5–10 seconds while the usage-plan binding replicates. Retry is normal; if still `403` after 60s, verify the key is in the usage plan with `aws apigateway get-usage-plan-keys --usage-plan-id <id>`.

**Script can leave orphan keys if it fails midway.** If the script crashes (e.g., API Gateway key created but DDB write fails), clean up the orphan with `aws apigateway delete-api-key --api-key <id>` and rerun.

**Role-flag drift.** The script's argparse flags must stay in sync with `AcceptedRoles` in `api/security/check_api_key.py`. The script last was aligned 2026-04-17 when `motion_plus`, `pet`, and `sliced_intruder_plus_with_vehicle` flags were added. Running an older checkout will silently omit those roles.

**Docs Basic Auth reuses the same DDB row.** No separate docs-only credential exists. The partner's API key IS their docs password. If you need docs-only access for a reviewer who shouldn't hit the API, mint a key with zero model roles (it will have `docs` in the roles set for consistency, but the app layer doesn't check `docs` — it has no effect on model endpoints). See [[api-key-lifecycle]].

## Revocation

**Immediate disable (fastest):**
```bash
aws apigateway update-api-key --api-key <id> \
  --patch-operations op=replace,path=/enabled,value=false
```

Takes effect within seconds; cached authorizer entries expire within 1 hour.

**Full delete (clean teardown):**
```bash
aws apigateway delete-api-key --api-key <id>
# Also delete the corresponding DynamoDB row
```

**Revoke one role only:**
Rerun `generate_api_key.py` with the same `--username` and a reduced set of role flags. The script detects the existing row and updates the `roles` set in place.

## Related

- [[ebus-partner-access]] — first application of this runbook; entity-note template
- [[api-key-lifecycle]] — auth flow, why `SS`, how Basic Auth works for docs
- [[rust-lambda-authorizer]] — authorizer internals and caching
- [[inference-api/_summary]] — topic context
- [[external-api/_summary]] — initiative umbrella
