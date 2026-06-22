---
title: "HTTPS via Tailscale-issued certs"
type: concept
topic: llm-shop
tags: [llm-shop, https, tls, tailscale, caddy, lets-encrypt]
created: 2026-05-04
updated: 2026-05-04
author: kb-bot
status: deferred
incoming:
  - topics/compute-fleet/notes/entities/host-npu-server.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/concepts/2026-05-04_phase-1-installed.md
  - topics/llm-shop/notes/syntheses/2026-05-04_llm-shop-initial-architecture.md
incoming_updated: 2026-05-06
---

> **Status (2026-05-04): deferred.** Mark is not a tailnet admin and cannot enable "HTTPS Certificates" in the admin console (precondition for `tailscale cert`). Interim approach: serve harnesses on plain HTTP within the tailnet — tailnet wire is already WireGuard-encrypted, so this is fine for tailnet-only services. When admin enables HTTPS Certificates, switching to HTTPS is a single Caddy config change + `tailscale cert npu-server.tail9b2a4e.ts.net`. The architecture below remains the target.

# HTTPS via Tailscale-issued certs

The [[llm-shop/_summary|LLM shop]]'s harnesses are served over HTTPS even though they're tailnet-only. Reasoning: browser tools (the [[2026-05-04_status-dashboard-sketch|status dashboard]]) want browser-trusted certs; coworker tools shouldn't have to disable cert verification; and the cost of HTTPS-via-Tailscale is zero.

## How it works

Tailscale issues real Let's Encrypt certs for tailnet hostnames via DNS-01 challenge. The tailnet admin console must have HTTPS enabled (Settings → DNS → enable HTTPS Certificates). Once enabled:

```bash
sudo tailscale cert npu-server.<tailnet>.ts.net
# → npu-server.<tailnet>.ts.net.crt + .key in current dir
```

Cert is valid for 90 days; auto-renews when re-requested. Caddy and `caddy-tailscale` plugin handle the renewal loop automatically.

## Recommended deployment: Caddy + caddy-tailscale

[`caddy-tailscale`](https://github.com/tailscale/caddy-tailscale) is an official Caddy plugin that:
- Binds to the tailnet interface only (never `0.0.0.0`)
- Uses Tailscale-issued certs automatically (no `tailscale cert` step needed)
- Authenticates incoming connections via tailnet identity (caller's tailnet user)

Single Caddyfile drives the whole shop:

```caddyfile
{
    auto_https off  # caddy-tailscale handles certs internally
}

npu-server.<tailnet>.ts.net {
    bind tailscale/  # tailnet-only listener, plugin-provided

    # Catalog + status (anyone on tailnet)
    handle /catalog       { reverse_proxy 127.0.0.1:8000 }
    handle /api/status    { reverse_proxy 127.0.0.1:8001 }
    handle /              { root * /home/actuate/llm-shop/dashboard ; file_server }

    # Per-harness routes (loopback FastAPI services)
    handle /code-delegate*  { reverse_proxy 127.0.0.1:8101 }
    handle /kb-intake*      { reverse_proxy 127.0.0.1:8102 }
    handle /code-review*    { reverse_proxy 127.0.0.1:8103 }
    handle /code-explain*   { reverse_proxy 127.0.0.1:8104 }
    handle /pr-summarize*   { reverse_proxy 127.0.0.1:8105 }

    # Bearer-token check (shared across all harnesses)
    @authed header Authorization regexp ^Bearer\ tskey-shop-[A-Za-z0-9_]+$
    handle @authed { ... }
    handle { respond "401 Unauthorized" 401 }
}
```

(Sketch only — `bind tailscale/` exact syntax depends on the plugin version; the README is authoritative.)

## Build process

`caddy-tailscale` ships as a plugin, not in core Caddy. Build a custom Caddy binary with:

```bash
xcaddy build --with github.com/tailscale/caddy-tailscale
# produces ./caddy
```

(Requires Go ≥1.21.) Install the resulting `caddy` binary into `~/llm-shop/bin/caddy`. systemd `--user` unit runs it.

## Alternatives considered

| Alternative | Trade-off |
|---|---|
| **Plain HTTP on tailnet** | Tailnet already encrypts wire traffic. But: browsers don't trust HTTP, can't enforce mixed-content rules, status-dashboard JS gets dev-mode flags. Reject. |
| **Self-signed certs** | Browser warnings, every coworker has to install root cert. Reject. |
| **Internal CA + step-ca** | Real solution, but ~2 hours of setup + ongoing renewal headaches. Tailscale gives this for free. Defer unless we go off-tailnet. |
| **Cloudflare Tunnel + zero-trust** | Fine for off-tailnet exposure. Not needed here. |
| **`tailscale cert` + Caddy without the plugin** | Works, but you have to copy the cert into Caddy's config dir, set up a renewal cron, restart Caddy. The plugin removes all of that. |

## Caveats

1. **Tailnet HTTPS must be enabled in the admin console.** If your tailnet admin hasn't done this, `tailscale cert` fails with "HTTPS certificates are not enabled for this tailnet." One-time toggle.
2. **MagicDNS must be enabled.** `npu-server.<tailnet>.ts.net` only resolves if MagicDNS is on. (Default for new tailnets.)
3. **First cert request is slow.** ~30 sec for the DNS-01 round-trip on first call. Subsequent renewals are background.
4. **Certs are per-host, not per-service.** Single cert for `npu-server.<tailnet>.ts.net` covers all paths (`/code-delegate`, `/kb-intake`, etc.). If we want per-harness subdomains (`code-delegate.npu-server.<tailnet>.ts.net`), each needs its own cert call. Keep it simple: one cert, paths.

## Cross-references

- [[2026-05-04_llm-shop-initial-architecture]] — D2 (this decision)
- [[host-npu-server]] — host onboarding plan includes the cert step
- [[llm-shop/_summary]]
