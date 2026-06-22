---
title: "Compute Fleet"
type: summary
topic: compute-fleet
tags: [compute-fleet, hardware, infra, tailnet, hosts]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
---

# Compute Fleet

Inventory of compute resources Mark uses across personal and company contexts. One entity per host, with hardware specs, role, access pattern, and tailnet identity. The companion topic [[llm-shop/_summary|llm-shop]] covers the LLM-serving service that runs on a subset of these hosts.

## Hosts

| Host | Owner | Role | Primary purpose | Tailnet status |
|---|---|---|---|---|
| [[host-laptop]] | personal (Mark) | laptop | day-to-day Claude Code, KB editing, Tier-3 LLM | `mork-thinkpad-p14s-gen-5.tail9b2a4e.ts.net` (`100.90.146.35`) |
| [[host-firebat]] | personal (Mark) | always-on devbox | Tier-1 cron jobs, dashboard, repo-scan, kb-recap | personal tailnet (specifics TBD on entity page) |
| [[host-npu-server]] | **company** (shared) | NPU/GPU server in office rack | [[watchman-repo|Watchman]] dev/test + LLM shop tenant | `npu-server.tail9b2a4e.ts.net` (`100.71.153.1`, since 2026-05-04, under `mark@` identity — no admin tags yet) |
| [[host-actuate-dev]] | coworker (Aziz Yousif) | linux dev box | (not under our admin; Phase 3 federation candidate) | `actuate-dev` (`100.69.143.76`) |

Catalog grows as more boxes come online. New peer-shop hosts (when [[llm-shop/_summary]] Phase 3 federation goes live) get a row here too.

## Discovery convention

Boxes on the tailnet announce themselves via Tailscale tags. The conventions we'll use:

| Tag | Meaning |
|---|---|
| `tag:llm-shop` | This host runs an [[llm-shop/_summary|llm-shop]] instance and exposes harnesses |
| `tag:devbox` | General dev / experimentation host (firebat, coworker boxes) |
| `tag:office` | Physically located in the office rack (geographic) |
| `tag:personal` | Personal compute, owned by Mark only |

Coworker boxes are visible via `tailscale status --json | jq '.Peer[] | select(.Tags // [] | any(. == "tag:llm-shop"))'`. We don't catalog coworker boxes here unless we actively rely on them.

## Cross-references

- [[llm-shop/_summary|llm-shop]] — the LLM service running on `host-npu-server`
- [[personal-laptop/_summary|personal-laptop]] — older topic covering laptop/firebat detail; will be migrated or cross-referenced over time
- [[engineering-process/_summary|engineering-process]] — three-tier routine pattern, KB conventions

## Open work

- [ ] Migrate or cross-link laptop content from `personal-laptop` topic
- [ ] Stub a `host-firebat` entity here for symmetry
- [ ] Add `tailnet:` field to each entity once tailnet auth is established
