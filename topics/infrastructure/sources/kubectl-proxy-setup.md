---
title: "Source: Kubectl Proxy and Port-Forwarding Setup"
type: source
topic: infrastructure
tags: [worklog, kubectl, kubernetes, proxy, port-forward, model-server, how-to]
ingested: 2026-04-14
author: kb-bot
---

# Kubectl Proxy and Port-Forwarding Setup

Source: internal how-to for accessing Kubernetes cluster services locally via kubectl proxy and port-forwarding.

## kubectl proxy

Run `kubectl proxy` in a terminal and leave it running. This opens a local proxy to the cluster API at `localhost:8001`.

Access any in-cluster service via:
```
http://localhost:8001/api/v1/namespaces/{NAMESPACE}/services/{SERVICE}:{PORT}/proxy/{ENDPOINT}
```

Example -- intruder model healthz:
```
http://localhost:8001/api/v1/namespaces/ds-model-prod/services/intruder-svc:8080/proxy/healthz
```

## Port Forwarding

For direct port-to-port mapping:
```
kubectl port-forward -n ds-model-prod service/model-svc 9999:8080
```

## Model Server Access Pattern

The base deployment exposes a single `model-svc` service that routes by path:
- `model-svc:8080/proxy/intruder/infer` -- intruder inference
- `model-svc:8080/proxy/weapon/infer` -- weapon inference

Model-specific services (e.g., `intruder-svc`) also exist but require a special header. The `model-svc` path-based routing is simpler and always works without header configuration.

## Local Development Config

For local model server testing, configure the model entry to point through the proxy:
```json
{
  "model_name": "EKS to EKS intruder",
  "model_ip": "localhost",
  "model_port": "8001/api/v1/namespaces/ds-model-prod/services/model-svc:8080/proxy/intruder",
  "model_id": 31
}
```
