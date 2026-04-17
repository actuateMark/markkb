---
title: "Source: Local EKS Model Server Configuration"
type: source
topic: infrastructure
tags: [worklog, eks, model-server, local-dev, kubectl-proxy]
ingested: 2026-04-14
author: kb-bot
---

# Local EKS Model Server Configuration

Source: configuration snippet for pointing a local development environment at EKS-hosted model servers via kubectl proxy.

## Configuration

To run inference locally against the production EKS model servers, configure the model entry to route through kubectl proxy:

```json
{
  "models": [
    {
      "model_name": "EKS to EKS intruder",
      "model_ip": "localhost",
      "model_port": "8001/api/v1/namespaces/ds-model-prod/services/model-svc:8080/proxy/intruder",
      "model_id": 31
    }
  ]
}
```

## Prerequisites

- `kubectl proxy` must be running locally (exposes cluster API at `localhost:8001`).
- The `model-svc` service in `ds-model-prod` namespace handles path-based routing to specific model endpoints (intruder, weapon, etc.).

See also: [[kubectl-proxy-setup]] for the full proxy and port-forwarding setup guide.
