---
title: "Minipc API surface — discovery + cross-session usage"
type: concept
topic: personal-laptop
tags: [minipc, api, fastapi, dashboard-check, observations, swagger, cross-session]
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
---

# Minipc API surface

Other Claude Code sessions on the LAN often need data the minipc already has — dashboard signals, host metrics, KB query — without re-querying NR / AWS. This note exists so future you (or another session) can find the API surface in one read.

## Source of truth (live)

- **`http://mork-firebat/app/endpoints/`** — human-readable catalog with curl examples. Stays current as endpoints are added (regenerates with the blog rebuild). Top-nav tile on the minipc dashboard.
- **`http://mork-firebat/app/api/api-docs`** — interactive Swagger UI; "Try it out" works because `servers` is set to `/app/api`.
- **`http://mork-firebat/app/api/openapi.json`** — raw OpenAPI 3.x spec.

If this note disagrees with `/app/endpoints/`, trust `/app/endpoints/`.

## What other sessions actually use

- **`GET /app/api/observations`** — every dashboard-check signal's latest value. Drop-in replacement for re-running NRQL / boto / radon. Top-level shape: `{ generated_at, summary: {n_signals, n_green, ...}, signals: { <id>: { value, status, baseline, unit, component, timestamp, age_minutes, source_skill, extras } } }`. Hourly cron.
- **`GET /app/api/observations/history?hours=N&signal_id=X`** — raw rows for a time-windowed query.
- **`GET /app/api/metrics.json`** + `metrics.txt` — the host's own load / mem / disk / uptime. 30s cadence.
- **`GET /app/kb/query`** + `POST /app/kb/query` — headless `/kb-ask` against the live vault. 5–20s.

## How it's wired

FastAPI app under `local_network_scripts/minipc-app/` (rsync'd to `~/minipc-app/` on the box). Runs as `minipc-app.service` (systemd --user) on `127.0.0.1:8081`. Caddy routes:

```
handle /app/kb/query*   → reverse_proxy 127.0.0.1:8081       (no strip — kb_query needs /app/...)
handle_path /app/api/*  → reverse_proxy 127.0.0.1:8081       (strips /app/api/ before forward)
```

The `handle_path` strip is why internal route paths look like `/observations` not `/app/api/observations`. The OpenAPI `servers: [{url: "/app/api"}]` field makes Swagger "Try it out" prepend the external prefix correctly.

### dashboard-check feeds /api/observations

`/dashboard-check` runs hourly (de-LLM cron — see [[2026-04-27_minipc-tooling-improvements]] §"De-LLM cron pattern"). `~/.claude/skills/dashboard-check/collect.py` writes to a sink JSONL at `~/Documents/worklog/dashboard/sink/observations.jsonl`. The FastAPI app's `/observations` route reads that JSONL and returns latest-per-signal. So:

- Sink (filesystem) is the durable record.
- API endpoint is a read-through cache.
- Adding a new signal lands in both with no extra wiring — see [[2026-04-27_dashboard-signal-cookbook]].

### Code-health signals (Phase 2 of /app/repos)

§12j Phase 2 added a `git_local` source class (per-repo metrics from `~/work/<repo>/`). As of 2026-04-29 that surfaces 8 signals visible at `/app/api/observations`:

| signal_id | what |
|---|---|
| `repo_todo_fixme_count` | TODO + FIXME hits per repo (rg) |
| `repo_actuate_frames_pin` / `_filters_pin` / `_pullers_pin` | per-repo pin specs (FACET version strings) |
| `repo_radon_cc_hotspots` | grade-C+ functions (CCN ≥ 11) per repo |
| `repo_ruff_unused_imports` | F401 violations per repo |
| `repo_vulture_dead_code` | likely-unused symbols per repo (noisy on Django) |
| `repo_mtm_days_p50` | median time-to-merge across last 50 merged PRs |

All emit FACET dicts keyed by repo name. Useful for cross-session "what's the state of repo X right now?" answers without spawning a fresh `/repo-scan` or running tools locally.

## Auth + access

LAN + Tailscale only. No bearer / API key. Caddy listens on the box's local interfaces; no public ingress. Treat the surface as trusted-network-only — fine for dashboards, not fine for any future destructive endpoint.

## Related

- [[2026-04-24_minipc-dashboard-static-gen-refactor]] — original static-gen architecture with the Caddy routing decisions
- [[2026-04-27_minipc-tooling-improvements]] — observations-cache pattern that powers `/api/observations`
- [[2026-04-27_dashboard-signal-cookbook]] — how to add a new signal end-to-end
- [[2026-04-28_handoff-repos-dashboard-phase-2-code-health]] — §12j Phase 2 signal queue + decisions
- [[2026-04-29_repos-dashboard-followups]] — backlog of next-pickup items for the dashboard / code-health stack
- mark-todos §12 (minipc dashboard app), §12j (architectural dashboard + code-health signals)
