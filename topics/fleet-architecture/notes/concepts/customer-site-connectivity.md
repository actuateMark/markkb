---
title: "Customer Site Connectivity — Topology Inputs to Fleet Design"
type: concept
topic: fleet-architecture
tags: [site-topology, networking, nat, vpn, wireguard, deployment, puller, needs-verification]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
status: incomplete
incoming:
  - _dive-queue.md
  - topics/fleet-architecture/_summary.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-a-minimal-split.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-b-stage-fleets.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-d-event-driven.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-e-hybrid-sidecar.md
  - topics/fleet-architecture/notes/syntheses/2026-04-22_proposal-b-prime-stateless-with-coordinator.md
  - topics/fleet-architecture/notes/syntheses/2026-05-01_ephemeral-run-pilot/paradigm-c.md
  - topics/fleet-architecture/reading-list.md
incoming_updated: 2026-05-27
---

# Customer Site Connectivity

> **Status: incomplete.** This note captures what we *think* is true about how connector pods reach customer VMS endpoints today. A deep-dive pass over `/home/mork/work/kubernetes-deployments/` and `/home/mork/work/connector_deployer/` is required to fill in authoritative details. See **Gaps & TODO** below.

Every fleet proposal (A–E) has a puller fleet of some shape. The puller's network path to the customer VMS determines where the puller pod can run, how many connections it can hold, and whether frames can be reassigned to a different pod without breaking auth/routing. This is a **critical input** to puller fleet design that is currently under-specified in the proposal notes.

## Known connectivity patterns (to verify)

From general platform knowledge (see [[vms-connector/_summary]], [[infrastructure/_summary]]):

### 1. Public / internet-accessible VMS
- VMS endpoint has a public IP or hostname reachable from AWS
- Examples: cloud VMS platforms (Eagle Eye, Genetec Cloud via their APIs), some [[rtsp-deep-dive|RTSP]] feeds with port-forwarded public exposure
- **Implication for fleet:** puller can run on any pod in any AZ. Cross-AZ is not a concern for connectivity; egress is via NAT gateway or VPC-native internet gateway.
- **Cost:** NAT gateway processing charges (~$0.045/GB) if egress goes via NAT. Consider VPC-native Internet Gateway for public VMS integrations to avoid NAT costs.

### 2. VPN-tunneled (WireGuard)
- Customer site is behind firewall; connector reaches it through a WireGuard tunnel
- Tunnel terminates inside the cluster (likely on a dedicated pod or node)
- **Implication for fleet:** puller must route through the tunnel pod. Either:
  - Every puller pod terminates its own tunnel (heavy, N tunnels for N pullers), OR
  - Centralized tunnel fleet with pullers routing via internal service mesh (adds latency and a new failure domain)
- **Critical for proposals C and E:** if cameras can be reassigned across pullers (or for C, workers hold full pipelines), tunnel identity must follow the assignment. This may make per-camera reassignment impossible without tunnel restart.

### 3. NAT-behind + outbound tunnel
- Customer site initiates outbound connection to AWS (reverse tunnel)
- Rare but exists
- **Implication for fleet:** camera-to-puller binding is determined by which AWS pod the tunnel lands on. Reassignment requires tunnel teardown/rebuild.

### 4. Direct VPN (customer-managed)
- Customer VPC peered or Transit Gateway-connected
- Site traffic routable as if internal
- **Implication for fleet:** puller can run on any pod, but must have a route via the Transit Gateway route table. AZ placement matters for latency to TGW attachment.

## Why this matters per proposal

| Proposal | Connectivity concern |
|----------|---------------------|
| A — Minimal Split | Puller fleet extracted; tunnel management concentrated there. Pipeline workers unaffected by site topology. |
| B — Stage Fleets | Same as A — tunnels live in puller fleet only. |
| C — Camera-Worker | **Cameras can reassign across workers any time.** If a camera sits behind a WireGuard tunnel, the receiving worker must have route access. Either all workers must terminate tunnels (heavy) or assignment must respect a tunnel-locality constraint. |
| D — Event-Driven | Same as A. |
| E — Hybrid Sidecar | Smart puller fleet owns tunnel termination; detection core doesn't touch customer network. |

**Proposal C is the most tunnel-sensitive.** If a meaningful fraction of sites use WireGuard, the assignment controller needs a constraint: "camera X can only be assigned to workers in tunnel class Y." This erodes the bin-packing freedom that makes C cost-efficient.

## Gaps & TODO (deep dive required)

Before we can finalize any proposal's puller section, we need to read the deployment repos:

1. **`/home/mork/work/kubernetes-deployments/`** — how are sites launched? One deployment-per-site? A single shared deployment? Per-integration?
2. **`/home/mork/work/connector_deployer/`** — the tool that creates/updates/deletes K8s resources per site. What does it know about connectivity type?
3. **Infer the distribution:** what fraction of sites are public / WireGuard / customer-VPN / NAT-out? Without this, we can't size any puller fleet.
4. **Tunnel termination pods:** where do WireGuard tunnels land today? How is traffic from a connector pod routed to the tunnel?
5. **Are there integrations with SPECIFIC connectivity requirements** (e.g., Genetec on-prem needing persistent sessions that can't be reassigned)?

### Questions for the deep-dive

- Are sites deployed as individual Helm releases? Kustomize overlays? Operator CRDs?
- Do tunnels terminate on dedicated WireGuard pods, on every connector pod, or on gateway nodes?
- How does IP address assignment work for outbound site-reachability (Elastic IPs on NAT gateways, BGP routes, etc.)?
- What's the failure story when a site's tunnel goes down? Does a single connector pod hold the session, or does it replay from a store?
- Is there per-site authentication state (API tokens, session cookies) that would need to migrate with a camera reassignment?

## Feeds into (once deep-dive is done)

- [[2026-04-16_proposal-a-minimal-split|Proposal A]] — puller pool strategy section
- [[2026-04-16_proposal-b-stage-fleets|Proposal B]] — puller pool strategy section
- [[2026-04-16_proposal-c-camera-worker|Proposal C]] — bin-packing constraints
- [[2026-04-16_proposal-d-event-driven|Proposal D]] — puller pool strategy section
- [[2026-04-16_proposal-e-hybrid-sidecar|Proposal E]] — smart puller fleet design
- [[2026-04-16_frame-transport-comparison|Frame transport comparison]] — cross-AZ cost assumptions change if tunnels pin pods to specific AZs

## Related

- [[vms-connector/_summary]] — supported integrations list; maps to connectivity pattern
- [[infrastructure/_summary]] — AWS, EKS, WireGuard reference
- `kubernetes-deployments` GitHub repo — authoritative source, needs KB ingestion (queued in `_dive-queue.md`)
- `connector_deployer` GitHub repo — launch orchestration, needs KB ingestion
