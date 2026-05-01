---
title: "CHM Phase 1: NetworkProbe -- Root Cause Diagnosis for Connectivity Failures"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, diagnostics, proposal, phase-1, rtsp]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-end-to-end-flow.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase2-stream-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase3-cross-camera-correlation.md
  - topics/integrations/rtsp/notes/entities/rtsp-enhancement-issues.md
  - topics/integrations/rtsp/notes/syntheses/rtsp-robustness-enhancement-plan.md
  - topics/personal-notes/notes/daily/2026-04-20.md
incoming_updated: 2026-05-01
---

# CHM Phase 1: NetworkProbe -- Root Cause Diagnosis for Connectivity Failures

## Problem

When a camera goes offline today, CHM tells operators THAT it is down but not WHY. The root cause is invisible, and operators receive a generic "Camera offline" email with no actionable remediation path.

The current [[rtsp-components|RTSP]] diagnostics implementation (`RTSPDiagnostics.test_rtsp_connection()`) performs an HTTP GET to the camera's `base_url` -- a fundamentally wrong protocol for [[rtsp-deep-dive|RTSP]] cameras that communicate over TCP port 554 using the [[rtsp-deep-dive|RTSP]] DESCRIBE/SETUP/PLAY handshake. The HTTP GET will fail on any camera that does not also serve an HTTP interface, producing a misleading `ConnectionRefused` or timeout error that says nothing about the actual [[rtsp-deep-dive|RTSP]] reachability.

Worse, 24 integrations fall through to [[chm-diagnostics-architecture|DummyDiagnostics]] in the `DiagnosticRunner.get_runner()` dispatch -- a complete no-op that returns `healthcheck_data` unchanged. Every integration besides Digital Watchdog, Exacq, Milestone, Avigilon, and [[rtsp-deep-dive|RTSP]] receives zero diagnostic enrichment. This includes high-volume integrations like [[salient-components|Salient]], [[hikcentral-components|HikCentral]], [[eagle-eye-components|Eagle Eye]], [[genetec-components|Genetec]], [[orchid-components|Orchid]], [[kvs-components|KVS]], and all alarm-sender-only types.

The result: operators cannot distinguish between DNS failure, firewall blocking, WireGuard tunnel death, credential expiry, or the camera itself being powered off. Every failure mode presents identically as "Camera offline."

## Proposed Solution

Introduce a `NetworkProbe` shared utility class at `healthcheck/alerts/diagnostics/tools/network_probe.py`. This class provides protocol-correct, layered network diagnostics that any `BaseDiagnostics` subclass can invoke when a connectivity failure is detected. It uses only Python standard library modules (`socket`, `ssl`, `subprocess`) plus the existing [[actuate-wireguard]] `WireGuardDAO` for tunnel health queries.

## Detailed Design

### NetworkProbe Class Interface

```python
from dataclasses import dataclass, field
from typing import Optional, List
import socket
import ssl
import subprocess
import ipaddress
import time
import logging

@dataclass
class ProbeResult:
    """Result of a single probe step."""
    step: str                          # e.g. "dns", "tcp_554", "ping", "wireguard", "tls"
    success: bool
    latency_ms: Optional[float] = None
    error_type: Optional[str] = None   # "timeout", "refused", "unreachable", "dns_fail", "stale_handshake"
    error_detail: Optional[str] = None
    data: dict = field(default_factory=dict)  # step-specific payload

@dataclass
class NetworkProbeReport:
    """Aggregated results from the full diagnostic cascade."""
    hostname: str
    resolved_ip: Optional[str] = None
    results: List[ProbeResult] = field(default_factory=list)
    root_cause: Optional[str] = None   # human-readable summary
    suggested_alert_topic: Optional[str] = None  # "dns", "firewall", "wireguard_tunnel", "service_down", "credentials"

class NetworkProbe:
    """Shared network diagnostic utility for CHM connectivity failures."""

    def __init__(self, wg_dao=None, cache_ttl_seconds: int = 300):
        self._wg_dao = wg_dao
        self._cache = {}          # ip -> (timestamp, ProbeResult)
        self._cache_ttl = cache_ttl_seconds

    def dns_resolve(self, hostname: str, expected_ip: str = None) -> ProbeResult: ...
    def tcp_probe(self, ip: str, port: int, timeout: float = 5.0) -> ProbeResult: ...
    def ping(self, ip: str, count: int = 3) -> ProbeResult: ...
    def wireguard_check(self, camera_ip: str) -> ProbeResult: ...
    def tls_check(self, ip: str, port: int = 443) -> ProbeResult: ...
    def run_cascade(self, hostname: str, rtsp_port: int = 554, expected_ip: str = None) -> NetworkProbeReport: ...
```

### Method Details

**`dns_resolve(hostname)`** -- Calls `socket.getaddrinfo(hostname, None)` with timing. Measures resolution latency in milliseconds. If `expected_ip` is provided, compares the resolved address against it to detect DNS hijacking or stale records. Returns `error_type="dns_fail"` on `socket.gaierror`.

**`tcp_probe(ip, port, timeout)`** -- Uses `socket.create_connection((ip, port), timeout)` to test port reachability. Classifies the socket error into three categories: `ConnectionRefusedError` -> `"refused"` (service not running on that port), `socket.timeout` -> `"timeout"` (firewall drop or network congestion), `OSError` with errno -> `"unreachable"` (no route to host, network down). Measures connection latency.

**`ping(ip, count=3)`** -- Runs `subprocess.run(["ping", "-c", str(count), "-W", "3", ip])`, parses stdout for round-trip min/avg/max/stddev and packet loss percentage. Returns RTT stats and jitter. Used only when TCP probe times out, to distinguish between port-level filtering and full IP unreachability.

**`wireguard_check(camera_ip)`** -- Queries [[actuate-wireguard]] `WireGuardDAO.get_all_tunnels()`, matches the camera IP against each tunnel's `subnets` list using `ipaddress.ip_address(camera_ip) in ipaddress.ip_network(subnet)`. If a matching tunnel is found, checks `WireGuardTunnel.last_handshake`: if `last_handshake` is `None` or older than 180 seconds from now, the tunnel is considered stale. Returns the tunnel name, last handshake age, and tunnel status from the `tunnel_status` field.

**`tls_check(ip, port, hostname=None)`** -- Creates an `ssl.SSLContext` (default context, system CA bundle), connects, and inspects:
- **Certificate validity window and expiry** (`notBefore` / `notAfter`) -- flags certs expiring within 30 days
- **Hostname match** against `servername` / SNI (wildcards honored) -- emits `TLS_HOSTNAME_MISMATCH`
- **Chain completeness** -- requests the full chain from the server; if chain length is 1 (leaf only) AND verification fails with `SSL_ERROR_VERIFY_FAILED` / "unable to get local issuer certificate" / "unable to verify the first certificate", emits `TLS_CHAIN_INCOMPLETE` and records the leaf's issuer (usually a commercial intermediate CA that the server is failing to serve)
- **Trust path** -- on verification failure not covered above: distinguishes `TLS_SELF_SIGNED`, `TLS_EXPIRED`, `TLS_NOT_YET_VALID`, `TLS_UNKNOWN_CA`
- **Clock skew guard** -- records local system time; flags `TLS_CLOCK_SKEW` if cert is "not yet valid" but the server's `Date` header (from a side-channel HTTP HEAD if needed) is fine

Emits a `classification` token (one of `TLS_OK`, `TLS_EXPIRED`, `TLS_CHAIN_INCOMPLETE`, `TLS_SELF_SIGNED`, `TLS_HOSTNAME_MISMATCH`, `TLS_CLOCK_SKEW`, `TLS_UNKNOWN_CA`) so third-party escalation tickets can carry a machine-readable root-cause fingerprint instead of "TLS failed."

**Relevant for:** HTTPS-based NVR APIs (DW, Milestone, Exacq), WSS stream endpoints routed via third-party providers (e.g. `dev.powerplus.com` -- see case study in [[chm-enhanced-diagnostics-proposal]] and [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]]).

### Diagnostic Cascade

The `run_cascade()` method executes probes in dependency order, short-circuiting when a root cause is identified:

```python
def run_cascade(self, hostname, rtsp_port=554, expected_ip=None):
    report = NetworkProbeReport(hostname=hostname)

    # Check per-IP cache first
    cached = self._get_cached(hostname)
    if cached:
        return cached

    # Step 1: DNS resolution
    dns_result = self.dns_resolve(hostname, expected_ip)
    report.results.append(dns_result)
    if not dns_result.success:
        report.root_cause = f"DNS cannot resolve hostname '{hostname}'"
        report.suggested_alert_topic = "dns"
        self._cache_result(hostname, report)
        return report
    report.resolved_ip = dns_result.data.get("resolved_ip")

    # Step 2: TCP port probe (RTSP 554 or HTTP 80/443)
    tcp_result = self.tcp_probe(report.resolved_ip, rtsp_port)
    report.results.append(tcp_result)
    if tcp_result.success:
        # TCP reachable -- problem is above transport layer (credentials, RTSP handshake)
        # Caller should proceed with RTSP DESCRIBE
        report.root_cause = None
        self._cache_result(hostname, report)
        return report

    if tcp_result.error_type == "refused":
        report.root_cause = f"Port {rtsp_port} connection refused -- service not running"
        report.suggested_alert_topic = "service_down"
        self._cache_result(hostname, report)
        return report

    # Step 3: TCP timed out -- check WireGuard tunnel if applicable
    if self._wg_dao and tcp_result.error_type == "timeout":
        wg_result = self.wireguard_check(report.resolved_ip)
        report.results.append(wg_result)
        if wg_result.success is False and wg_result.error_type == "stale_handshake":
            tunnel_name = wg_result.data.get("tunnel_name", "unknown")
            report.root_cause = f"WireGuard tunnel '{tunnel_name}' is down (handshake stale)"
            report.suggested_alert_topic = "wireguard_tunnel"
            self._cache_result(hostname, report)
            return report

    # Step 4: Ping to distinguish IP unreachability from port filtering
    ping_result = self.ping(report.resolved_ip)
    report.results.append(ping_result)
    if not ping_result.success:
        report.root_cause = f"Camera IP {report.resolved_ip} is unreachable (100% packet loss)"
        report.suggested_alert_topic = "ip_unreachable"
    elif ping_result.data.get("avg_rtt_ms", 0) > 200:
        report.root_cause = f"Network path degraded (RTT: {ping_result.data['avg_rtt_ms']:.0f}ms)"
        report.suggested_alert_topic = "network_degraded"
    else:
        report.root_cause = f"Camera responds to ping but port {rtsp_port} is blocked (firewall likely)"
        report.suggested_alert_topic = "firewall"

    self._cache_result(hostname, report)
    return report
```

## Integration with Existing Architecture

### RTSPDiagnostics Changes

`RTSPDiagnostics.connectivity_diagnostics()` replaces the HTTP GET with a `NetworkProbe.run_cascade()` call. The current `test_rtsp_connection()` method is deprecated. If the cascade reports TCP reachability on port 554, the method additionally performs an [[rtsp-deep-dive|RTSP]] DESCRIBE via a lightweight socket send/recv to test RTSP-level authentication (401 -> `"credentials"` alert topic, 453 -> `"insufficient_bandwidth"`).

### GenericDiagnostics Replaces DummyDiagnostics

A new `GenericDiagnostics(BaseDiagnostics)` class is registered as the default fallback in `DiagnosticRunner.get_runner()` instead of `DummyDiagnostics`. `GenericDiagnostics.connectivity_diagnostics()` invokes `NetworkProbe.run_cascade()`, giving all 24 currently unserved integrations network-layer root cause diagnosis.

## Data Model

Diagnostic results are stored in the existing freeform `healthcheck_data.diagnostics` dict (the same pattern used by [[digital-watchdog-components|DW diagnostics]]):

```python
healthcheck_data.diagnostics["network"] = {
    "hostname": "192.168.1.50",
    "resolved_ip": "192.168.1.50",
    "dns_ok": True,
    "dns_latency_ms": 2.1,
    "tcp_554_ok": False,
    "tcp_554_error": "timeout",
    "tcp_554_latency_ms": None,
    "wireguard_tunnel": "site-alpha",
    "wireguard_handshake_age_s": 450,
    "wireguard_status": "stale",
    "ping_ok": True,
    "ping_rtt_avg_ms": 45.2,
    "ping_loss_pct": 0.0,
    "root_cause": "WireGuard tunnel 'site-alpha' is down (handshake stale)",
    "suggested_alert_topic": "wireguard_tunnel"
}
```

For TLS failures specifically (e.g. against a WSS stream endpoint):
```python
healthcheck_data.diagnostics["network"] = {
    "hostname": "dev.powerplus.com",
    "resolved_ip": "...",
    "dns_ok": True,
    "tcp_443_ok": True,
    "tls_ok": False,
    "tls_classification": "TLS_CHAIN_INCOMPLETE",
    "tls_leaf_subject": "CN=*.powerplus.com",
    "tls_leaf_issuer": "Sectigo Public Server Authentication CA DV R36",
    "tls_chain_length": 1,
    "tls_openssl_verify_code": 21,
    "tls_human_detail": "Server returned leaf cert only; Sectigo intermediate missing. Client cannot verify chain.",
    "root_cause": "TLS chain incomplete: dev.powerplus.com missing Sectigo DV R36 intermediate",
    "suggested_alert_topic": "tls_chain_incomplete"
}
```

This data is logged to [[new-relic|New Relic]] for fleet-wide queryability and used by alert generators for enriched email subjects.

## Alert Improvement

| Scenario | Before | After |
|----------|--------|-------|
| WireGuard tunnel down | "Camera offline" | "WireGuard tunnel 'site-alpha' is down (5 cameras affected)" |
| DNS failure | "Camera offline" | "DNS cannot resolve camera hostname 'cam-lobby.site.local'" |
| Firewall blocking | "Camera offline" | "Camera responds to ping but [[rtsp-deep-dive|RTSP]] port 554 is blocked" |
| Service crash | "Camera offline" | "Port 554 connection refused -- [[rtsp-deep-dive|RTSP]] service not running" |
| Credentials expired | "Camera offline" | "[[rtsp-deep-dive|RTSP]] authentication failed (HTTP 401)" |
| TLS chain incomplete | "Camera offline (37 days, no frames, healthcheck sentinel values)" | "TLS_CHAIN_INCOMPLETE: server missing intermediate (leaf signed by Sectigo DV R36); frame retrieval impossible until server serves full chain" |
| Cert expired / self-signed | "Camera offline" | "TLS_EXPIRED: leaf cert expired 2026-04-10" or "TLS_SELF_SIGNED: cert chain ends in self-signed leaf, not in any public root CA" |

## Performance Budget

- **Only runs on failures**: `NetworkProbe.run_cascade()` is invoked only when `healthcheck_data.connectivity.valid == False`. Healthy cameras incur zero overhead.
- **Per-IP caching**: Results are cached for `cache_ttl_seconds` (default 300s). Multiple cameras sharing the same NVR IP reuse the cached probe result within a single healthcheck run.
- **Timeouts**: DNS resolve 3s, TCP probe 5s, ping 9s (3 pings x 3s), WireGuard DB query <1s, TLS check 5s. Worst case cascade: ~23s. Typical (cache hit or early short-circuit): <5s.
- **No new threads**: All probes run synchronously within the existing per-camera healthcheck thread. The cascade short-circuits at the first identified root cause.

## Effort Estimate

3-5 days, broken down as:
- Day 1: `NetworkProbe` class with `dns_resolve`, `tcp_probe`, `ping` methods + unit tests
- Day 2: `wireguard_check` integration with [[actuate-wireguard]] `WireGuardDAO` + `tls_check` (including chain-completeness detection and `TLS_*` classification tokens per [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]] case study)
- Day 3: `run_cascade` logic, caching, `GenericDiagnostics` class
- Day 4: Wire into `RTSPDiagnostics`, update `DiagnosticRunner` fallback, integration test
- Day 5: Alert template updates, data model population, [[new-relic|New Relic]] logging

## Files to Create/Modify

### Create
- `vms-connector/healthcheck/alerts/diagnostics/tools/__init__.py`
- `vms-connector/healthcheck/alerts/diagnostics/tools/network_probe.py` -- `NetworkProbe`, `ProbeResult`, `NetworkProbeReport`
- `vms-connector/healthcheck/alerts/diagnostics/integrations/generic_diagnostics.py` -- `GenericDiagnostics(BaseDiagnostics)`
- `vms-connector/test_vms/test_network_probe.py`

### Modify
- `vms-connector/healthcheck/alerts/diagnostics/integrations/rtsp_diagnostics.py` -- replace `test_rtsp_connection()` with `NetworkProbe.run_cascade()`
- `vms-connector/healthcheck/alerts/diagnostics/core/diagnostic_runner.py` -- change `DummyDiagnostics` fallback to `GenericDiagnostics`
- `vms-connector/healthcheck/alerts/diagnostics/runners/connectivity_healthcheck_runner.py` -- populate `diagnostics["network"]` from probe report

## Related

- [[chm-enhanced-diagnostics-proposal]] -- parent proposal with full architecture overview
- [[chm-diagnostics-architecture]] -- current diagnostic dispatch and runner patterns
- [[chm-diagnostics-gap-analysis]] -- 24 integrations on DummyDiagnostics
- [[chm-phase2-stream-probe]] -- Phase 2: stream metadata surfacing
- [[chm-phase3-cross-camera-correlation]] -- Phase 3: NVR/subnet failure grouping
- [[actuate-wireguard]] -- WireGuardDAO, WireGuardTunnel model with `last_handshake` and `subnets` fields
- [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]] -- concrete case study for `tls_check`'s chain-completeness detection; 37-day misdiagnosis avoided by the TLS layer of this cascade
- [[mark-todos]] §2d -- AP/VCH alert-flow diagnostic-enhancement workstream; Phase 1 `tls_check` is the direct implementation of what that workstream needs for the PowerPlus case
