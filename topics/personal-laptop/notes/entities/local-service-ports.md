---
title: "Local service port allocation"
type: entity
topic: personal-laptop
tags: [local-dev, ports, conventions, runbook]
created: 2026-05-20
updated: 2026-05-20
author: kb-bot
outgoing:
  - topics/admin-api/notes/concepts/2026-05-20_actuate-admin-local-bringup.md
incoming:
  - topics/admin-api/notes/concepts/2026-05-20_actuate-admin-local-bringup.md
  - topics/personal-notes/notes/daily/2026-05-21.md
incoming_updated: 2026-05-27
---

# Local service port allocation

Canonical port-allocation table for Actuate-related local services on this laptop. Use it to avoid the `Address already in use` collision when multiple Claude sessions run development servers in parallel.

## Allocation table

| Port | Service | Bind addr | Notes / source-of-truth |
|---|---|---|---|
| 4101 | vendor/system | `127.0.0.1` | system service — leave alone |
| 5432 | **Postgres** | `127.0.0.1` | host-native; shared by all Django + inference-api workloads. See [[actuate-admin-rds]] for restore tooling. |
| 6379 | **Redis** | `127.0.0.1` | host-native; [[actuate_admin]] uses db=3 |
| 6566 | vendor/system | `*` | system service |
| 8000 | **actuate-inference-api dev server** | `0.0.0.0` | uvicorn `inference_api/server.py` — its README's default. Often left running across sessions for v4/v5 endpoint dev. |
| 8001 | **[[actuate_admin]] runserver** | `127.0.0.1` | Django dev server — pass `localhost:8001` to avoid 8000 collision. See [[2026-05-20_actuate-admin-local-bringup]]. |
| 8002 | (reserved) | — | next slot for an additional Django/FastAPI workload |
| 8003-8009 | (reserved) | — | further dev servers as needed |
| 8554 | **rtsp_camera_simulator** | `0.0.0.0` | TCP+UDP, Docker container `rtsp-camera-simulator` |
| 8555 | [[rtsp-deep-dive|rtsp]] simulator (alt) | `0.0.0.0` | second sim port if running |
| 8765 | dev tool / IDE | `127.0.0.1` | leave alone |
| 11434 | **Ollama** | `127.0.0.1` | local LLM runtime |

## Convention

- **Inference-api (uvicorn) stays on 8000** — it's the upstream default and is often left running across Claude sessions for v4/v5 dev work.
- **[[actuate_admin]] (Django) → 8001** — explicit override; the README's default of 8000 collides. Document the override in any handoff that mentions running admin.
- **Future Django/FastAPI workloads → 8002+** — increment, don't reuse.
- **If a port is already in use,** check `ss -tlnp | grep :<port>` first — it may be a sibling Claude session's server worth keeping, not stale process to kill.

## Snapshot — currently bound ports (2026-05-20 reference)

This snapshot was taken during the §29 admin bring-up. Useful as a baseline diff later.

```
4101  - (system)
5432  - postgres
6566  - (system)
8000  - inference-api uvicorn (pid 2408375; left running across sessions)
8001  - actuate_admin Django runserver (pid 2610705; this session, §29)
8554  - rtsp_camera_simulator (Docker)
8765  - (dev tool)
11434 - Ollama
```

## Discovering what's on a port

```bash
ss -tlnp | grep :<port>                    # who's listening
lsof -i :<port>                            # alternative
ps -p <pid> -o pid,cmd                     # what command
```

For a Claude background process started in another session, the output file is at `/tmp/claude-1000/.../tasks/<bgid>.output` if you can find the bgid.

## Cross-references

- [[2026-05-20_actuate-admin-local-bringup]] — admin-specific bring-up runbook that anchors port 8001
- [[actuate-admin-rds]] — Postgres + Redis prereq (anchors 5432/6379)
- `topics/personal-laptop/_summary.md` — laptop topic overview
