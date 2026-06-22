---
title: "Host: actuate-dev (Aziz's tailnet box)"
type: entity
topic: compute-fleet
tags: [compute-fleet, actuate-dev, tailnet, coworker, federation-candidate]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
status: peer-only
owner: aziz.yousif
incoming:
  - topics/compute-fleet/_summary.md
incoming_updated: 2026-05-05
---

# Host: actuate-dev (Aziz's tailnet box)

Linux dev box owned by Aziz Yousif on the company tailnet `tail9b2a4e.ts.net`. Mark has **no SSH access** — this entity exists as a catalog reference and as a candidate peer for Phase 3 [[llm-shop/_summary|LLM shop]] federation testing once the shop pattern is proven on [[host-npu-server]].

## What we know

| Field | Value |
|---|---|
| Tailnet IP | `100.69.143.76` |
| Tailnet hostname | `actuate-dev` (not the Mark-laptop "actuate-dev" — that was a coincidence of OEM defaults; this one is Aziz's) |
| Tailnet user | `aziz.yousif@` |
| OS | Linux |
| Status | Online as of 2026-05-04 |
| SSH access for Mark | None |
| Tags | None observed |

## Why catalog it

- **Phase 3 federation test target.** When the [[llm-shop/_summary|LLM shop]] pattern proves out on `npu-server`, the next step is "do peer shops discover each other and share harnesses?" `actuate-dev` is the first real second-host candidate. We can verify discovery without needing Aziz to actually run a shop — just confirm `tailscale status --json` filtered by `tag:llm-shop` would find his box if the tag existed.
- **Awareness hygiene.** When a coworker's tailnet box appears in `tailscale status`, we want it in this catalog rather than a mystery row.

## What this entity is NOT

- Not under our administration
- Not a place to install anything
- Not load-bearing for anything Mark runs

## Cross-references

- [[compute-fleet/_summary|fleet topic]]
- [[host-npu-server]] — the box where `tailscale status` first showed `actuate-dev` to us
- [[llm-shop/_summary]] — the federation pattern that may eventually engage with this box

## Note: name collision

Earlier in the sketching session (2026-05-04), there was a moment of confusion: my prior assumption was that "actuate-dev" referred to Mark's laptop (it's a hostname Mark sometimes uses for project-internal context). The tailnet entry is unrelated — Aziz has a different machine with the same generic name. Keep the names distinct in conversation: this entity is *Aziz's `actuate-dev`*, not Mark's laptop (see [[host-laptop]]).
