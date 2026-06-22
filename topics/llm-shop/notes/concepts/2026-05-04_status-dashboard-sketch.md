---
title: "Status Dashboard Sketch"
type: concept
topic: llm-shop
tags: [llm-shop, dashboard, observability, frontend, fastapi, tailnet]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
incoming:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-04_https-via-tailscale-certs.md
  - topics/llm-shop/notes/concepts/2026-05-04_phase-1-installed.md
  - topics/llm-shop/notes/concepts/harness-pattern.md
  - topics/llm-shop/notes/syntheses/2026-05-04_llm-shop-initial-architecture.md
incoming_updated: 2026-05-06
---

# Status Dashboard Sketch

A small single-page web frontend served at `https://npu-server.<tailnet>.ts.net/` that gives anyone on the tailnet a one-glance view of the [[llm-shop/_summary|LLM shop]]'s health. Not for control, just for visibility. Inspired by the laptop's `[[skill-dashboard-check]]` operational dashboard but for LLM-serving signals.

## What it shows

```
┌─ npu-server llm-shop ──────────────────────────────┐
│ Uptime: 23 days  ·  Load: 0.4 / 0.3 / 0.2          │
│ RAM: 9.2 / 30 GB  ·  iGPU: 12% busy  ·  NPU: idle  │
│                                                     │
│ Watchman: running (3 procs, mediamtx alive)        │
│ LLM Shop: 18 GB cap, 3.4 GB in use                  │
│   • Loaded: qwen2.5-coder:14b (warm, 8m idle)       │
│   • Cold: deepseek-coder-v2-lite, qwen2.5-coder:1.5b│
│                                                     │
│ Recent requests (last 1h):                          │
│   /code-delegate ████████ 23                        │
│   /kb-intake     ███ 8                              │
│   /code-explain  █ 2                                │
│   /pr-summarize  · 0                                │
│                                                     │
│ Tailnet peers (tag:llm-shop): 1 (this box)          │
│                                                     │
│ Catalog: GET /catalog ↗                             │
└────────────────────────────────────────────────────┘
```

Refresh every 10s via JS polling `/api/status`.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Browser on tailnet  →  https://npu-server.<tailnet>.ts.net/ │
│                          (Caddy serves dashboard.html)        │
│                                                                │
│              browser polls /api/status every 10s              │
│                            ↓                                   │
│              Caddy → reverse proxy 127.0.0.1:8001              │
│                            ↓                                   │
│              FastAPI status service (~150 LOC)                 │
│              Aggregates:                                       │
│               • /proc/uptime, /proc/loadavg, /proc/meminfo     │
│               • /sys/class/drm/card0/gt_*  (iGPU)             │
│               • /sys/class/devfreq/.../load (NPU, if exposed) │
│               • pgrep -af watchman                             │
│               • curl localhost:11434/api/ps  (Ollama)          │
│               • tail -1000 ~/llm-shop/logs/requests-*.ndjson   │
│               • tailscale status --json                        │
│              Returns JSON                                      │
└─────────────────────────────────────────────────────────────┘
```

## File layout

```
~/llm-shop/
├── dashboard/
│   ├── index.html           # static, served by Caddy
│   ├── app.js               # ~80 LOC; polls /api/status, renders
│   └── style.css            # minimal, dark mode default
├── harnesses/
│   └── _status/
│       ├── server.py        # FastAPI on :8001
│       └── schema.py        # StatusResponse pydantic model
```

Status is a "harness" only by convention — it doesn't call a model. Reuses `shared/auth.py` for bearer-token validation (or skips auth for `/api/status` if everyone on tailnet should see it; decide later).

## Data sources

| Field | Source | Cost |
|---|---|---|
| Uptime | `/proc/uptime` | free |
| Load | `/proc/loadavg` | free |
| RAM | `/proc/meminfo` (`MemTotal`, `MemAvailable`) | free |
| iGPU busy% | `intel_gpu_top -J -s 1000` (one sample) **or** `/sys/class/drm/card*/gt_busy_pct` if exposed | minor (≤100ms) |
| NPU busy% | TODO — `intel_npu_top` if available, otherwise N/A | TBD |
| [[watchman-repo|Watchman]] procs | `pgrep -af watchman` count | free |
| [[watchman-repo|Watchman]] benchmarking | `pgrep -af` against the known-script regex (see [[host-npu-server]]) | free |
| Loaded models | `curl http://127.0.0.1:11434/api/ps` | minor |
| Recent request rates | tail of NDJSON request log, aggregate by harness for last 1h | free (mmap'd file read) |
| Tailnet peers | `tailscale status --json | jq '.Peer[] | select(.Tags // [] | any(. == "tag:llm-shop"))'` | free |

Total status-endpoint latency budget: <500 ms cold (initial poll), <100 ms warm.

## Federation hook

The dashboard pulls peer-shop info from `tailscale status --json`. For each peer:

```javascript
// app.js
for (const peer of peers) {
  fetch(`https://${peer.hostname}/api/status`)
    .then(r => r.json())
    .then(s => renderPeer(peer.hostname, s));
}
```

Each peer-shop publishes its own status, so the dashboard becomes a fleet view automatically. **Phase 3** — not part of MVP, but the API contract is set up to allow it.

## Authentication

| Route | Auth |
|---|---|
| `/` (dashboard HTML/JS/CSS) | No auth — anyone on tailnet sees the page |
| `/api/status` | No auth — public to tailnet (signals are non-sensitive) |
| `/catalog` | No auth — harness inventory is public |
| Harness endpoints (`/code-delegate`, etc.) | Bearer token required |

The principle: **status and catalog are observability, not control.** Anyone who can SSH the box can see this stuff anyway. Restricting it to tokens-only adds friction without adding security.

## Implementation phases

| Phase | What | When |
|---|---|---|
| MVP | Status FastAPI + static HTML/JS/CSS, single-host view | Build with first harness |
| Phase 2 | [[watchman-repo|Watchman]] activity panel (full pgrep cross-check vs benchmark scripts) | When iGPU contention shows up |
| Phase 3 | Federated peer view (tailnet-wide) | When 2+ shops exist |
| Phase 4 | Historical charts (sparklines from NDJSON logs) | If anyone asks |

## Anti-scope

- **Not a control plane.** No "stop model X" / "restart harness Y" buttons. Use SSH for ops.
- **Not a metrics platform.** No Prometheus, no Grafana, no time-series DB. Tail of NDJSON logs is enough.
- **Not authenticated.** See above — visibility, not control.
- **Not pretty.** Functional, fast, dark-mode by default. ~80 LOC of JS, no frameworks.

## Cross-references

- [[2026-05-04_llm-shop-initial-architecture]] — D6 (this decision)
- [[harness-pattern]] — `_status` is a harness-by-convention
- [[skill-dashboard-check]] — sibling concept on the laptop side; informs design
- [[host-npu-server]]
