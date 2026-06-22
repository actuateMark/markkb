---
title: "Draft: Inquiry to Immix on StreamFinished semantics"
type: data
topic: autopatrol
tags: [draft, immix, partner-comms, streamfinished, outbound]
created: 2026-05-06
updated: 2026-05-06
author: kb-bot
status: draft
---

# Draft: Inquiry to Immix on `StreamFinished`

Pre-send draft of an outbound to Immix engineering, asking whether there's a vendor-callable surface for `StreamFinished` (or whether they can derive it server-side from graceful websocket close).

**Context cross-refs**:
- [[2026-05-06_immix-streamfailed-worker-lifespan]] — the operational symptom + DeviceWorker log evidence (forwardable / external-safe)
- [[immix-vendor-api]] — entity note confirming no `StreamFinished` write surface in the OpenAPI 3.0.1 spec
- [[2026-05-06_bugfix-stream-id-history-iteration]] — companion connector-side fix shipped today (different problem, same surface)
- Reference run: patrol `A188AC1E-89C9-4B58-5FCD-08DEA10F17AF`, 2026-05-06 14:15Z UTC. Correlated logs both sides confirm full-clip received and HTTP 200 on raise + Finished.

**OpenAPI spec archived**: `topics/autopatrol/notes/data/2026-05-06_immix-vendor-api-openapi-spec.json`

## Engineer-to-engineer version

> **Subject:** [[immix-vendor-api|AutoPatrol Vendor API]] — `StreamFinished` semantics
>
> Hi [contact],
>
> A quick question on the [[immix-vendor-api|AutoPatrol Vendor API]] around stream lifecycle reporting.
>
> **Background:** every no-detection patrol we run is being labeled `streamfailed` on your side. Looking at our connector logs and your DeviceWorker logs together, the chain is:
>
> 1. We `GET /Patrols/{id}/Device/{id}/videostream?Duration=10` to allocate a session.
> 2. Your DeviceWorker spins up with a 10-second hard life-span (`Worker has a hard life-span and is therefore not reusable. Life span limit set to 10 seconds`).
> 3. We connect to the websocket and consume video for the full 10s.
> 4. Your Worker hits its lifespan and force-kills (`Worker life span limit hit. Signaling the worker to close. Force closing worker due to life-span expiry`) — apparently regardless of whether our websocket closed cleanly first.
> 5. The forced-kill exit becomes `streamfailed` in your reporting, even though we received the full clip we asked for and got HTTP 200 on `PUT /Patrols/{id}/raise` and `PUT /Patrols/{id}` → `Finished`.
>
> A screenshot from your docs shows an `AutoPatrolActionType` enum that includes `StreamFinished` as a sibling to `StreamFailed`, which suggests there's a clean-exit path we're not triggering. We've reviewed the OpenAPI 3.0.1 spec for the Vendor API (`autopatrol-api.developer.azure-api.net`) and the partner-facing surface has no endpoint to set stream state — `PatrolStatus` (`Pending`/`Started`/`Finished`) is patrol-level, and `VideoStreamModel` has no status field.
>
> **Two questions:**
>
> 1. Is there an undocumented or upcoming endpoint that lets a vendor POST a `StreamFinished` action against a `deviceStreamId`? (Same shape question for `AudioClipFinished`, since those values are also in the enum but no audio-clip endpoints exist in the spec.)
>
> 2. If `StreamFinished` is server-derived rather than partner-callable: would you consider deriving it from observed Worker behavior — specifically, the websocket being closed cleanly by the consumer before the lifespan timer fires — and labeling those runs `StreamFinished` instead of `StreamFailed`? Currently every vendor that runs to its full requested duration ends up labeled `streamfailed` because the lifespan timer always fires last.
>
> If neither (1) nor (2) is feasible, we'd appreciate guidance on how vendors should signal clean stream termination so the labeling reflects success rather than failure.
>
> Happy to share our investigation notes (correlation of your DeviceWorker log with our connector log for a specific run) if useful.
>
> Thanks,
> Mark

## Send checklist

- [ ] Replace `[contact]` with actual recipient name
- [ ] Decide whether to attach: (a) the streamfailed synthesis as PDF, (b) the OpenAPI spec we reviewed, (c) just the patrol_id + timestamps for them to look up
- [ ] Pick channel: email / Slack / shared partner ticket queue (whatever your usual route is)
- [ ] After send: log outbound date + recipient back here; flip `status: draft` → `status: sent`

## After-send hooks

- If they confirm option (1) — undocumented endpoint exists: add a §N workstream item to extend `actuate-integration-calls` once they share the endpoint shape, plus a wiring task in `actuate-pullers` to call it from `AutopatrolWebSocketStreamPuller.run_healthcheck()` after `consume_stream` returns.
- If they confirm option (2) — server-side derivation: nothing for us to ship; just verify the labeling change after they roll, and update [[2026-05-06_immix-streamfailed-worker-lifespan]] to mark the issue as resolved.
- If they say neither: park the labeling concern as cosmetic, document in the synthesis that `streamfailed` on no-detection patrols is the expected state and not actionable on our side.
