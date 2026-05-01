---
title: "Config & Schedule Propagation — admin-api, ENG-96, Hot-Path Config"
type: concept
topic: fleet-architecture
tags: [config, admin-api, schedule, eng-96, propagation, site-context]
created: 2026-04-16
updated: 2026-04-16
author: kb-bot
---

# Config & Schedule Propagation

Every proposal needs config: camera settings, site settings, schedules, model thresholds, integration credentials. Today [[admin-api/_summary]] is the Django+DRF operational backbone producing a `settings.json` that the connector reads. Schedule evaluation is distributed — one evaluator per connector pod. This distribution causes [[vms-connector/_summary|ENG-96]]: concurrent pods race on midnight overrides, missing arming events.

This note captures the config/schedule question each proposal must answer.

## Today's data flow

```
admin-api (Django+DRF + PostgreSQL RDS)
    |
    +--> S3 settings.json per site  --(pull)-->  connector pod (reads on startup, re-reads on change)
    |
    +--> REST API  ----------------(HTTPS)---->  connector pod (for hot lookups)
    |
    +--> DynamoDB (schedules, flex_schedule, overrides)  <-- connector pod (reads for schedule eval)
```

Each site's connector pod:
1. On boot: pulls `settings.json` → binds into camera configs via `actuate-config`
2. Periodically: polls admin-api or re-reads settings for updates
3. Continuously: reads schedule state from DynamoDB; each pod evaluates independently

## The ENG-96 race

With the scaler replica count at 10-20 (band-aid for schedule propagation lag), multiple pods evaluate the same schedule around midnight cutovers. When a customer override (arm/disarm) is written right at the cutover, different pods may see different states and emit conflicting decisions. Band-aid: scaled replicas up 10→20 so the probability of seeing the update converged faster. Real fix: centralized evaluation.

## Config flow per proposal

### A — Minimal Split
- **Puller fleet:** reads settings + camera config on assignment, same pattern as today
- **Pipeline worker:** unchanged
- **Alert sender fleet:** reads integration credentials once per pod lifecycle
- **Schedule eval:** still per-pipeline-worker — **ENG-96 unchanged**
- **Config cache:** each fleet pod has an independent cache — consistency window unchanged

### B — Stage Fleets
- **Each of 5 fleets independently pulls config** — more cache copies, wider staleness window
- **Schedule eval:** a design choice — could centralize in observer fleet or leave distributed. Distributing across 5 fleets makes ENG-96 worse; centralizing requires a new service
- **Open question:** does B add a "config service" for cross-fleet coherence?

### C — Camera-Worker
- **Workers pull per-camera config on assignment** — each assignment triggers a settings read
- **Assignment controller is the natural place to centralize config** — treats config as part of the assignment payload. **Fixes ENG-96 by design** if schedule eval moves into the controller.
- **Risk:** controller becomes a busy service — needs HA and caching

### D — Event-Driven
- Same shape as B — distributed across fleets. Same ENG-96 concern.
- **Opportunity:** bake config into the NATS envelope per-frame (heavy). More practical: each fleet pulls config on its own schedule.

### E — Hybrid Sidecar — **fixes ENG-96 directly**
- **Site Context Service** is introduced explicitly to solve this. Centralized config cache + schedule evaluator + camera registry.
- Smart puller and detection core both read from site-context (gRPC or HTTPS).
- Schedule eval happens once per site in site-context, not per-pod.
- **This is a material advantage of E:** ENG-96 becomes a design property, not a fix.

## Centralized schedule evaluation — generalizable design

Regardless of proposal, a centralized schedule evaluator should look like:

```
admin-api writes schedule changes to DynamoDB
     |
     v
Site Context Service (or equivalent) watches DynamoDB stream
     |
     +-- maintains in-memory index of current state per camera
     |
     v
Connector pods (puller / worker / core) query site-context for "is camera X armed right now?"
```

Properties:
- Single authoritative evaluator per site — eliminates race
- Fallback: pods cache last-known-good with TTL in case site-context is unreachable
- Observable: emit metrics for cutover latency (time from admin-api write → pod observes change)

## Per-proposal verdicts on ENG-96

| Proposal | ENG-96 fix? | How |
|----------|:-----------:|-----|
| A | ❌ | Schedule eval unchanged — still per-pipeline-worker |
| B | ⚠️  | Depends on design — can be fixed if we centralize, not fixed by default |
| C | ✅ | Assignment controller naturally owns schedule context |
| D | ⚠️  | Same as B |
| E | ✅ | Site Context Service is the ENG-96 fix |

**E and C are the two proposals that address ENG-96 structurally.** Others require bolting on a new service.

## Hot-path config — what proposals must respect

- **Arm/disarm state** (ENG-96 territory): read per-frame essentially; must be fast + consistent
- **Camera zones** ([[ignore-zones|ignore zones]], detection zones): read per-frame; mostly static but support hot-reload
- **Model thresholds** (confidence, IOU): read per-inference; static most of the time
- **Integration credentials** (SMTP, API tokens): read per-alert; slow-changing; secrets-grade

All fleets have the same hot-path requirements. The question is whether config is local cache + pull, or pushed by a central service.

## Enhancement opportunities

- **Make `actuate-config` fleet-aware.** Today it binds a site's `settings.json`. For fleet architectures, extend it with a "context provider" abstraction — one impl reads local JSON (today), another queries site-context service (E), another receives assignment-payload (C).
- **Fix ENG-96 before the fleet migration lands.** A centralized schedule evaluator can be built today inside admin-api (e.g., a cron that resolves effective state into a tight DynamoDB write, polled by pods). Worth doing regardless of which proposal wins.
- **Add config-change visibility.** NR metric `actuate.config.cutover.latency.ms` — how long from admin-api write → pod observes change. Today this is invisible.
- **Stop the 20-replica band-aid.** Only lower replica count once the fix lands — otherwise regressions go undetected.

## References

- [[admin-api/_summary]]
- [[actuate-platform/notes/concepts/data-flow-architecture]]
- [[vms-connector/_summary]] — ENG-96 description
- [[actuate-libraries/_summary]] — `actuate-config` package
