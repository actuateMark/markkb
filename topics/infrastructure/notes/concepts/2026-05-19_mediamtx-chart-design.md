---
title: "MediaMTX Helm chart — per-pod addressability + JWT + ICE-TCP"
type: concept
topic: infrastructure
tags: [mediamtx, helm, statefulset, ingress, webrtc, whep, jwt, ice-tcp, kubernetes-deployments, live-streaming, rtsp]
created: 2026-05-19
updated: 2026-05-19
author: kb-bot
sources:
  - https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/579862531
incoming:
  - topics/admin-api/notes/concepts/2026-05-19_streaming-monitoring-api.md
  - topics/personal-notes/notes/daily/2026-05-19.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-plan.md
  - topics/vms-connector/notes/syntheses/2026-05-19_live-streaming-v1-status.md
incoming_updated: 2026-05-20
---

# MediaMTX chart (kubernetes-deployments)

New Helm chart at `deployments/applications/mediamtx/`. Phase 2 of [[2026-05-19_live-streaming-v1-plan|Live Streaming v1]]. Background on the daemon itself: [[2026-05-18_mediamtx]].

## Topology — assigned-pod, not load-balanced

The hard constraint: **publisher and viewer must land on the same MediaMTX pod.** [[rtsp-deep-dive|RTSP]] publish goes to one pod; [[webrtc-deep-dive|WebRTC]] fan-out happens on that same pod. So the chart is *not* a "load balancer in front of pods" topology — it's an *assigned-pod* topology with each pod externally addressable by identity.

- **`StatefulSet` with `topologySpreadConstraints`** pins pods one-per-AZ in us-west-2a/b/c. `replicas` per AZ scales independently as load grows. Pod naming: `mediamtx-us-west-2a-0`, `mediamtx-us-west-2a-1`, etc.
- **Internal addressing (connector → MediaMTX [[rtsp-deep-dive|RTSP]]):** headless `Service` per AZ gives each pod stable DNS `mediamtx-us-west-2{a,b,c}-{ordinal}.streaming.svc.cluster.local`. [[rtsp-deep-dive|RTSP]] ingest on 8554. The connector publishes to a *specific pod*, named in the SQS push command from monitoring-api.
- **External addressing (browser → MediaMTX [[webrtc-deep-dive|WebRTC]]):** per-pod Ingress hostnames `mediamtx-us-west-2{a,b,c}-{ordinal}.stream.actuateui.net` → matching `subset` on the headless Service. WHEP on 8889. Wildcard TLS cert covers the pattern.
- **ICE UDP:** dedicated NLB for port 8189 (single-port UDP mode preferred). Backstop is the ICE-TCP path on the WHEP ALB:443 — see below.

## AZ-local data path invariant

`mediamtx_pod_id ∈ pods_in(camera.az)`. The expensive leg (camera count × bitrate) stays inside one AZ. Browser → MediaMTX may cross AZs (small egress; the customer's browser was crossing AZs anyway). This is enforced by monitoring-api's assignment logic, not the chart.

## ConfigMap (`mediamtx.yml`) — three notable settings

1. **`runOnDemand` / `runOnRead` / `runOnUnread` hooks** point at monitoring-api lifecycle endpoints (`/_internal/mediamtx/on-demand`, `/on-unread`). Webhook bodies are HMAC-signed with a shared secret from Secrets Manager.

2. **Read authentication: built-in JWT mode**, HS256 with a shared secret env-mounted via External Secrets Operator. MediaMTX validates the bearer token locally — no callback to monitoring-api per request. Claims `path` and `aud` must match the request. See [[2026-05-19_streaming-monitoring-api#jwt-claims]].

3. **Publish authentication: [[rtsp-deep-dive|RTSP]] basic auth** against `STREAMING_PUBLISHER_TOKEN`. The connector pod's puller assembles `rtsp://stream:{token}@{mediamtx_target}/cam/{camera_id}` when publishing.

## ICE-TCP as the v1 TURN substitute

[[webrtc-deep-dive|WebRTC]] needs a usable network path between operator browser and MediaMTX. The plan stages cheap fixes first; TURN is expensive and only deployed if data justifies it.

Three layers cover most networks without a relay:

1. **MediaMTX host candidates** — AZ-local pod IP behind the public Ingress
2. **ICE-TCP candidates enabled on MediaMTX**, TCP ICE port advertised through the existing WHEP ALB on 443. Works around UDP-blocking corporate firewalls and most symmetric-NAT cases.
3. **Implicit STUN** — MediaMTX's server-reflexive candidate via the public Ingress

ICE-TCP is wired in the chart's `mediamtx.yml`: `webrtcICEServers` + TCP candidate on the public ALB:443. Free at the v1 traffic level; defers ~$50–200/mo per AZ self-hosted coturn (or worse, $0.40–1.00/GB managed-TURN bills) until Phase 6 measures actual ICE failure rate.

**Trigger to add TURN** (decided in Phase 6 from `monitoring_api_stream_ice_failures_total / _total`):
- Sustained fleet rate **> 3 % over 7 days**, OR
- Any individual customer or site segment **> 10 %** over 7 days

Below those thresholds, TURN's cost exceeds its benefit. Pre-staging the `coturn` chart in Phase 5 is optional so Phase 6 can pull the trigger fast.

## Capacity envelope

From the Phase 0 spike (MediaMTX 1.18.1 in Docker):

- 1 publisher (15 fps, 5 Mbps), 0 readers: ~1.5 % CPU, ~33 MiB
- +0.9 % CPU per [[rtsp-deep-dive|RTSP]] reader, ~1 MiB per reader

A single 2-core pod handles ~80 publishers + ~150 viewers. Above that we increase `replicas` per AZ. [[webrtc-deep-dive|WebRTC]] (SRTP encrypt/decrypt) is ~1.5–2× per-viewer cost of plain [[rtsp-deep-dive|RTSP]] — pad capacity planning by 50 %.

At plan terminal scale (~2K avg concurrent viewers): ~48 cores aggregate, ~5–10 `c6i.2xlarge` pods across AZs.

## Per-AZ scale rebalance

When `replicas` changes per AZ, the consistent hash ring (camera_id → pod) shifts. monitoring-api's reconciliation worker recomputes affected `(camera_id, mediamtx_pod_id)` pairs, emits `idle` to old targets and `pushing` with new targets to the connector. Brief blackout (~1 [[gop-keyframe-fundamentals|keyframe interval]]). Viewers reconnect on the next 300 s token refresh.

## Operational

- `ServiceMonitor` for Prometheus scrape on `/metrics`
- `argocd/charts/mediamtx-app.yaml` — [[argocd|ArgoCD]] Application following the existing [[argocd-gitops-workflow|gitops pattern]]
- Istio sidecar injection on the connector namespace gives connector → MediaMTX mTLS for free if already enabled (verify in chart README)

## Related

- [[2026-05-19_live-streaming-v1-plan]] — umbrella plan
- [[2026-05-19_streaming-monitoring-api]] — assignment/JWT-issuing peer
- [[2026-05-18_mediamtx]] — daemon background
- [[argocd-gitops-workflow]] — chart deployment path
- [[secrets-management]] — ESO + Secrets Manager pattern for `STREAMING_PUBLISHER_TOKEN` + JWT signing key
- Confluence: EDOCS/579862531 §4 [[kubernetes-deployments]]
