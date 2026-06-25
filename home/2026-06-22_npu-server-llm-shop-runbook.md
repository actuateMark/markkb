---
type: concept
topic: actuate-platform
tags: [npu-server, llm-shop, runbook, offboarding, local-llm, watchman]
created: 2026-06-22
updated: 2026-06-22
author: kb-bot
incoming:
  - topics/engineering-process/notes/syntheses/2026-06-22_actuate-footprint-handoff.md
  - topics/engineering-process/notes/syntheses/2026-06-22_dead-mans-checklist.md
  - topics/engineering-process/notes/syntheses/2026-06-22_offboarding-plan.md
  - topics/offboarding-overview.md
  - topics/offboarding/notes/concepts/2026-06-22_manual-action-checklist.md
incoming_updated: 2026-06-24
---

# npu-server / LLM-shop operations runbook

Operating runbook for the internal local-LLM service ("the LLM shop") on `npu-server`. Written for Mark's offboarding (last day Fri 2026-06-26) so the team can keep the value running after his company access dies. Part of the [[2026-06-22_offboarding-plan|offboarding plan]] (Workstream D). Hardware is company-owned and stays; what must be re-homed is Mark's Tailscale identity on the box (see § Offboarding).

> **Verification note (2026-06-22):** the box was **unreachable from this session** — `ssh npu-server.tail9b2a4e.ts.net` returned `Permission denied (publickey,password)` (the laptop's key for the box was not loaded in this non-interactive session). So **no facts below were confirmed against the live box today.** Everything is reconstructed from the source-controlled deployment tree at `local_network_scripts/files/llm-shop/` (systemd units, README, harness code) and the §24 KB syntheses. Where a fact is install-time-measured rather than re-verified, it is flagged. **Re-verify the live state with the health checks in § Operate before relying on this.**

---

## 1. What it is and why it exists

The LLM shop is an internal, **tailnet-only** suite of locally-served LLMs exposed as task-specific HTTP endpoints ("harnesses"). It runs on company-shared compute (`npu-server`) alongside the [[watchman-repo|Watchman]] test service, and is consumed by Mark's laptop tooling, Claude Code subagents, and KB-ingest skills.

**Why it exists — three drivers:**

1. **Local code-task delegation.** A subagent (`llm-shop-delegate`) hands discrete, well-scoped grunt work (refactor, test-gen, explain, review, boilerplate) to a local 14B model instead of spending Anthropic tokens. Quality bar is "good draft for review," not "production-correct first try."
2. **KB intake automation.** URL → drafted KB source note, with local-model summarization + topic classification + frontmatter generation. Closes the Obsidian-clipper question. Can run overnight against a reading-list/dive-queue.
3. **Coworker amplifier.** Other team members with tailnet boxes can both consume the shop and (designed-for, not yet built) contribute harnesses via a federation/`/catalog` pattern.

**What breaks if the box is offline:** callers fall back to Anthropic (Claude). The `llm-shop-delegate` subagent surfaces a 502/connection failure and tells the parent to "handle directly or retry later"; `kb-intake`/batch jobs fail the affected items and leave reading-list lines unprocessed. **No production Actuate service depends on the shop** — it is a token-saving convenience layer, not a hard dependency.

---

## 2. Host facts

Full host entity: [[host-npu-server]].

| Fact | Value |
|---|---|
| Tailnet FQDN | `npu-server.tail9b2a4e.ts.net` |
| Tailnet IP | `100.71.153.1` |
| Canonical SSH (from Mark's laptop) | `ssh npu-server` (alias in `~/.ssh/config`, `IdentityFile ~/.ssh/npu-server`, port 22) |
| Fallback SSH (external, candidate for shutoff) | `ssh -i ~/.ssh/npu-server -p 3327 actuate@158.106.215.138` |
| OS-level hostname (cosmetic OEM default) | `actuate-Default-string` (referred to as `npu-server` everywhere) |
| OS | Ubuntu 24.04 LTS, kernel 6.17.0-14-generic (at install) |
| Operating user | `actuate` (uid 1000); in groups `docker`, `render`, `video` |
| CPU | Intel Core Ultra 7 155H (Meteor Lake), 22 logical cores |
| iGPU | Intel Arc Xe-LPG (`8086:7dd5`), `xe` driver — used by SYCL llama.cpp |
| NPU | Intel NPU 3720 (`8086:7d1d`), `intel_vpu` driver, `/dev/accel/accel0` — used by OpenVINO TinyLlama |
| RAM | 30 GiB (+ 8 GiB swap) |
| Disk | 937 GB NVMe |

**Co-tenant — DO NOT DISTURB.** The box's primary tenant is the **[[watchman-repo|Watchman]] test service** (`~/actuate-watchman/`, a continuously-running process), plus benchmark scaffolding. All LLM-shop work is confined to `~/llm-shop/`. The shop is deliberately a *polite tenant* (RAM-capped, CPU-yielding) so it never starves [[watchman-repo|Watchman]]. Never modify `~/actuate-watchman/`, `~/intel/`, `~/venvs/`, `~/model_cache/`, or the benchmark scripts without coordinating with whoever owns Watchman dev.

---

## 3. The model serving layer

There are **three serving backends**, each on its own port, plus harness services that sit in front of them. All run as systemd **`--user`** units (`systemctl --user ...`) under the `actuate` account, sourced from `~/llm-shop/systemd/` (mirror: `local_network_scripts/files/llm-shop/systemd/`).

### Backends

| Backend | Port | Engine | Model(s) | Notes |
|---|---|---|---|---|
| **SYCL llama.cpp** (iGPU) | `:8200` | `ghcr.io/ggml-org/llama.cpp:server-intel` Docker container | `qwen2.5-coder:14b-instruct-sycl` (Q4 GGUF) | **The real iGPU-accelerated workhorse.** ~1.5 tok/s warm (degrades to 0.5–0.7 under load). 4096 ctx (`-c 4096`), all layers on iGPU (`--n-gpu-layers 99`), `--jinja` chat template. Container runs via `sg docker -c` because the user unit doesn't inherit the `docker` group. |
| **Ollama** (CPU) | `:11434` (bound `0.0.0.0`) | Ollama 0.23.0 user-mode at `~/llm-shop/bin/ollama` | 6 models on disk (below) | **CPU-only fallback** (`OLLAMA_VULKAN` is deliberately OFF — Vulkan produces garbage tokens on Meteor Lake, see [[2026-05-05_ollama-vulkan-broken-on-meteor-lake]]). Slow (1–3 tok/s on 14B). Also exposes the **OpenAI-compat API at `:11434/v1`** for IDE tools. `OLLAMA_MAX_LOADED_MODELS=2`, `OLLAMA_KEEP_ALIVE=10m`, `OLLAMA_CONTEXT_LENGTH=16384`. |
| **OpenVINO NPU** | `:8090` (bound `0.0.0.0`) | OpenVINO GenAI pipeline pinned to `NPU` device | `tinyllama-1.1b-int4-ov` (Intel-published OV-IR INT4) | Always-on small model for sub-second triage/classify. ~8 tok/s on the NPU 3720. Uses **zero iGPU time** — pure win when [[watchman-repo|Watchman]] wants the iGPU. First load ~5s (graph compile). |

**Models on disk (Ollama, `~/llm-shop/models/`):** `qwen2.5-coder:1.5b` (986 MB), `qwen2.5-coder:7b-instruct` (4.7 GB), `qwen2.5-coder:14b-instruct` (9.0 GB), `qwen2.5-coder:32b-instruct` (19 GB), `llama3.1:8b` (4.9 GB), `deepseek-coder-v2:16b` (8.9 GB). NPU side (`~/llm-shop/models-ov/`): `tinyllama-1.1b-int4-ov` (served) and a self-converted `qwen-1.5b` (NPU-incompatible, kept as CPU fallback).

**iGPU mutual exclusion:** there is only ~5–9 GiB of iGPU memory free after [[watchman-repo|Watchman]], so **only one SYCL container runs at a time.** The 7B (`:8201`) and 8B (`:8202`) SYCL ports are pre-wired in the proxy routing table but **the systemd units were never shipped** — only the 14B SYCL service exists.

### Harness / front-end services

| Service | Port | What it does | Default backend |
|---|---|---|---|
| `llm-shop-status` | `:8080` | Dashboard + `/api/status`, `/api/health`, `/api/proxy/chat` (model-routed), `/api/proxy/routes`, `/api/warm-up`. Serves the Status / Playground / Catalog / Peers UI. | n/a (routes to all three) |
| `llm-shop-npu` | `:8090` | NPU TinyLlama wrapper. `POST /api/generate` `{prompt, max_new_tokens}` → `{text, elapsed_ms, device}`. | OpenVINO NPU |
| `llm-shop-code-delegate` | `:8100` | `POST /code-delegate` `{task, context?, task_type?, max_tokens?}`. `task_type` ∈ `general\|refactor\|explain\|test-gen\|review`. | **SYCL `:8200`** (`qwen2.5-coder:14b-instruct-sycl`) — see correction below |
| `llm-shop-kb-intake` | `:8110` | `POST /kb-intake` `{url, topics, hint_topic}` → drafted source note. Timeout 600s. | **SYCL `:8200`** (`qwen2.5-coder:14b-instruct-sycl`) — see correction below |
| `llm-shop-ollama` | `:11434` | Ollama server + OpenAI-compat `/v1`. | CPU |
| `llm-shop-sycl-14b` | `:8200` | The SYCL llama.cpp container itself. | iGPU |
| `llm-shop-pull-models` | (oneshot) | Sequential `ollama pull` of the 6 models. | n/a |
| `llm-shop-kb-batch@<run-id>` | (oneshot, templated) | Overnight batch runner; `%i` is the run-id. Imports `kb_deep_intake.run`. | SYCL + Ollama-CPU per phase |

> **⚠ Correction to the `llm-shop-delegate` agent doc (stale).** The agent definition (`~/.claude/agents/llm-shop-delegate.md`) says `:8100/code-delegate` is backed by "Ollama Qwen2.5-Coder-14B." Per the **actual systemd unit** (`llm-shop-code-delegate.service`), both `code-delegate` (`:8100`) and `kb-intake` (`:8110`) default to **SYCL `:8200`** (`OLLAMA_URL=http://127.0.0.1:8200`, model `qwen2.5-coder:14b-instruct-sycl`). To fall back to CPU-Ollama set `OLLAMA_URL=http://127.0.0.1:11434` and the model env (`CODE_DELEGATE_MODEL` / `KB_INTAKE_MODEL`) to `qwen2.5-coder:14b-instruct`. The endpoint contract the agent uses is still correct; only the named backend is out of date.

---

## 4. How `llm-shop-delegate` routes (the agent contract) + harnesses

### The Claude Code subagent

`llm-shop-delegate` (`~/.claude/agents/llm-shop-delegate.md`, model `haiku`, tools `Read, Bash`) is invoked via the `Agent` tool from inside a Claude Code session to offload grunt code work without spending Anthropic tokens. It calls the shop with `curl` and returns the model's output verbatim to the parent.

**Routing rubric (from the agent):**

1. **Quick lookup / classify / explain a <10-line snippet** → NPU TinyLlama at `:8090/api/generate`. Sub-second to ~5s.
2. **Substantial code work** (refactor, test-gen, review, multi-paragraph explain) → `:8100/code-delegate` with the matching `task_type`.
3. **Hardest / overnight quality** → `/code-delegate` with a `model: "qwen2.5-coder:32b-instruct"` override (slow, CPU-Ollama, reserve for genuinely hard tasks).

**When NOT to delegate:** multi-step reasoning across files/repos, Claude-grade tool use (git/filesystem ops, structured planning), "open the PR end-to-end," or anything needing post-2024 knowledge. The agent declines out-of-scope tasks rather than guessing.

**Known model quirks (baked into the agent):** the 14B flips directionality on technical claims it lacks ground truth for (always pass the actual code as `context`, not a paraphrase); it always wraps code in markdown fences (strip them); it invents tag/format conventions unless given an example.

### The KB-intake / deep-intake / batch harnesses

| Harness / tool | Surface | What it does |
|---|---|---|
| `kb-intake` (single-pass) | `POST :8110/kb-intake` or laptop `~/bin/kb-intake <url>` | One LLM call: fetch → readability → draft → `_research-inbox/`. For ad-hoc "ingest this one URL now." |
| **kb-deep-intake** (multi-pass) | Python module `~/llm-shop/harnesses/kb_deep_intake/`, CLI `~/llm-shop/bin/kb-deep-intake` | 5-phase planner→workers→composer→linker pipeline producing KB-quality 800–1500-word multi-section notes. Planner+composer on SYCL Qwen-14B, section workers on Ollama llama3.1:8b (16K ctx). Design: [[2026-05-07_kb-deep-intake-architecture]]. The generalized pattern: [[2026-05-07_long-running-multi-agent-pattern]]. |
| **overnight batch** | Laptop `~/bin/kb-batch-submit` / `kb-batch-pull` / `kb-batch-status` / `kb-batch-watch`; box `llm-shop-kb-batch@<run-id>.service` | Laptop submits a reading-list → box runs to completion overnight (survives laptop sleep) → laptop pulls + merges drafts in the morning. Run dirs at `~/llm-shop/research-output/<run-id>/`. `flock` prevents concurrent runs (single SYCL backend). 7-day on-box retention. Design: [[2026-05-07_overnight-batch-pattern]]. |
| `kb-todo-scan` / `kb-todo-research` | Laptop `~/bin/kb-todo-*` | Broken-wikilink target → drafted stub via code-delegate. |

There is **no `code-delegate` for full PRs** — that stays a Claude responsibility. Harnesses are stateless, single-shot, no agentic loops (>3 model turns ⇒ it's a Claude problem). The harness contribution pattern (dir layout, Pydantic output schema, eval goldens, systemd + Caddy registration) is in [[harness-pattern]].

---

## 5. How to operate

All commands run on the box as `actuate` (`ssh npu-server`). Services are **`systemctl --user`** units — `--user` is mandatory; without it you'll get the wrong (system) scope.

### Check health

```bash
# Whole-shop status JSON (host vitals, watchman activity, loaded models, peers)
curl -s http://npu-server.tail9b2a4e.ts.net:8080/api/status | jq

# Liveness probes per service
curl -s http://npu-server.tail9b2a4e.ts.net:8080/api/health      # status/dashboard
curl -s http://npu-server.tail9b2a4e.ts.net:8090/api/health      # NPU harness

# Smoke-test each backend
curl -sS -X POST http://npu-server.tail9b2a4e.ts.net:8090/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"def fib(n):","max_new_tokens":32}'

curl -sS -X POST http://npu-server.tail9b2a4e.ts.net:8100/code-delegate \
  -H 'Content-Type: application/json' \
  -d '{"task":"explain this","context":"x = [i for i in range(3)]","task_type":"explain"}'

# Browser: http://npu-server.tail9b2a4e.ts.net:8080/  (Status / Playground / Catalog / Peers)
```

### See what's running / restart

```bash
ssh npu-server
systemctl --user list-units 'llm-shop-*' --type=service     # all shop units + state
systemctl --user status  llm-shop-sycl-14b.service          # one unit
systemctl --user restart llm-shop-sycl-14b.service          # restart the SYCL container
systemctl --user restart llm-shop-code-delegate.service     # restart a harness
systemctl --user daemon-reload                               # after editing a unit file
```

Start/stop order matters: harnesses depend on their backend (`code-delegate` After/Wants `llm-shop-ollama`; `kb-intake` After/Wants `llm-shop-sycl-14b`). Restarting a backend does not auto-restart dependents; restart the harness too if a backend was down.

### Logs

```bash
ssh npu-server 'journalctl --user -u "llm-shop-*" -f'         # tail everything
ssh npu-server 'journalctl --user -u llm-shop-sycl-14b -n 100 --no-pager'
# Per-batch logs/manifests: ~/llm-shop/research-output/<run-id>/{log.jsonl,manifest.json}
```

### Warm a model (skip cold-load)

```bash
curl -X POST http://npu-server.tail9b2a4e.ts.net:8080/api/warm-up \
  -d '{"model":"qwen2.5-coder:14b-instruct"}'
```

### Add / swap a model

- **New Ollama model:** add the tag to `~/llm-shop/bin/pull-models.sh`, run `~/llm-shop/bin/ollama pull <tag>` (or rerun the pull-models unit). Note (install lesson): some families use the bare size tag as the instruct variant — `llama3.1:8b` and `deepseek-coder-v2:16b` are the instruct models; the `-instruct` suffixed tags 404. Pulls saturate office bandwidth — stop them before running `uv sync` for unrelated deps.
- **Swap a harness's backing model:** it's a one-line env change in the harness's systemd unit (`CODE_DELEGATE_MODEL` / `KB_INTAKE_MODEL` + `OLLAMA_URL`), then `daemon-reload` + `restart`. Callers never see the model name.
- **New SYCL model (e.g. the reserved 7B/8B):** add a GGUF, copy `llm-shop-sycl-14b.service` to a new unit (change the volume mount, `-p <port>:8080`, `--alias`), add `Conflicts=` against the 14B unit (single iGPU), add a row to `SYCL_PORTS` in `harnesses/_status/server.py`, restart status.

### Deploy convention (edit a file)

Source of truth is git: `local_network_scripts/files/llm-shop/` mirrors the deployed `~/llm-shop/` tree. Edit there → commit → `scp` the changed file(s) to `actuate@npu-server.tail9b2a4e.ts.net:~/llm-shop/...` → `systemctl --user restart <unit>`. Excluded from the mirror: `.venv/`, `models/`, `models-ov/`, `uv.lock`. Python deps are managed with **uv** (`uv sync`, never raw pip/venv); `bin/install.sh` is the idempotent installer.

---

## 6. Offboarding notes

The hardware and the deployment tree survive Mark's departure. The thing that **breaks silently** is the box's network identity, which is currently tied to Mark's Tailscale account.

| Item | Current state | Action for the team |
|---|---|---|
| **Tailscale node ownership** | `npu-server` is registered on the aegissystems tailnet **under Mark's user (`mark@`), with no tags** (SSO device-auth, no auth key). When Mark's account is deactivated, an untagged user-owned node can lose tailnet access. | **Re-auth the box with a tagged auth key so it becomes tailnet-owned.** Per the offboarding plan: confirm `tag:server` (or `tag:llm-shop`) exists in the ACL, mint a tagged auth key, then on the box: `sudo tailscale up --authkey=tskey-… --advertise-tags=tag:server`. **Do this with console/physical access — a bad re-auth can drop SSH.** This is Workstream A in [[2026-06-22_offboarding-plan]] (highest risk, external lead time). |
| **SSH access** | `ssh npu-server` works only from Mark's laptop (key `~/.ssh/npu-server`). Firebat's pubkey was never pushed. Password auth for `actuate` still on (port 3327 external). | Push a team member's / firebat's SSH pubkey to `actuate@npu-server:~/.ssh/authorized_keys` before Friday, or you lose key access when the laptop goes. The external `:3327` fallback + `actuate` password still works as a break-glass path (see credential note). |
| **`actuate` user password** | Shared account; password is in a credential manager (not stored in KB). **It was leaked in a Claude chat session on 2026-05-04** and should be rotated. | Rotate when the team coordinates (rotation affects everyone who SSHes via the public IP). |
| **Auth on the harness endpoints** | **None.** The shop is tailnet-only and currently unauthenticated ("reachable from this laptop without auth (yet)"); the bearer-token + Caddy-TLS layer was designed but never shipped (HTTPS-via-tailscale-cert deferred, needs tailnet admin). | Fine while tailnet-only and WireGuard-encrypted. If the box stays on the tailnet under the team's control, no creds to hand off. If you want auth, the Caddy/bearer-token design is in [[harness-pattern]] / the architecture ADR. |
| **[[watchman-repo|Watchman]] co-tenant** | Unaffected by the shop. | Keep treating `~/actuate-watchman/` as load-bearing; the shop's RAM/CPU caps protect it. |
| **What it costs to do nothing** | Shop is a token-saving convenience, no prod dependency. | If the Tailscale re-home is missed and the node drops, callers simply fall back to Anthropic. Worst case is higher token spend, not an outage. |

**Source control already safe:** the deployment tree is committed in `aegissystems/local_network_scripts` (`files/llm-shop/`), so the code, systemd units, harnesses, and dashboard survive regardless. Only the on-box runtime state (`.venv`, model blobs) is machine-local and re-creatable via `bin/install.sh` + `bin/pull-models.sh`.

---

## Cross-references

- [[2026-06-22_offboarding-plan]] — the parent plan (Workstream D = this runbook; Workstream A = the Tailscale re-home)
- [[host-npu-server]] — full host entity (hardware, access, deferred hardening)
- [[harness-pattern]] — what a harness is, contribution flow, per-harness routing table
- [[2026-05-07_kb-deep-intake-architecture]] — the 5-phase KB-intake pipeline
- [[2026-05-07_overnight-batch-pattern]] — overnight batch transport
- [[2026-05-07_long-running-multi-agent-pattern]] — the generalized planner-worker-composer pattern
- [[2026-05-05_using-the-llm-shop]] — day-to-day usage reference (Pi, OpenAI-compat, curl recipes)
- [[2026-05-05_ollama-vulkan-broken-on-meteor-lake]] — why iGPU runs SYCL llama.cpp, not Ollama+Vulkan
- [[2026-05-06_model-routed-proxy]] — `/api/proxy/chat` model-name routing
- [[2026-05-04_phase-1-installed]] — install record + measurements
