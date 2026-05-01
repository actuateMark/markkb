---
title: "CHM Phase 3: Cross-Camera Correlation -- NVR and Network Failure Detection"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, diagnostics, proposal, phase-3]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase2-stream-probe.md
incoming_updated: 2026-05-01
---

# CHM Phase 3: Cross-Camera Correlation -- NVR and Network Failure Detection

## Problem

Today, every camera is diagnosed independently. When an NVR serving 50 cameras goes down, CHM creates 50 independent "Camera offline" incidents and sends 50 separate emails. The root cause -- a single NVR failure -- is invisible. Operators must manually correlate timestamps and camera names to realize the failures share a common cause.

This problem is equally severe for WireGuard tunnel failures (all cameras behind a tunnel go down together), network switch failures (all cameras on a /24 subnet disappear simultaneously), and temporal patterns (midnight reboots, DHCP renewal cycles, DST transitions causing brief mass disconnects).

The current [[chm-diagnostics-architecture|CHM architecture]] processes cameras in parallel via `BaseHealthcheckCamera.start_healthcheck()` using a thread pool, then calls `send_healthcheck_results()` to iterate results and fire alerts one camera at a time. There is no aggregation step between result collection and alert dispatch.

## Proposed Solution

Insert a correlation post-processing step into `BaseHealthcheckCamera.send_healthcheck_results()` that groups failures by shared infrastructure before dispatching alerts. When a group of cameras sharing the same NVR, WireGuard tunnel, or subnet all fail, the system emits a single consolidated alert identifying the root cause instead of N individual camera alerts.

## Detailed Design

### Correlation Engine

A new `CorrelationEngine` class in `healthcheck/alerts/diagnostics/tools/correlation_engine.py` performs multi-dimensional grouping:

```python
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set
import ipaddress
import logging

@dataclass
class CorrelationGroup:
    """A set of cameras sharing a failure root cause."""
    group_type: str                    # "nvr", "wireguard_tunnel", "subnet", "temporal"
    group_key: str                     # e.g. "192.168.1.100", "tunnel-site-alpha", "10.0.5.0/24"
    camera_ids: List[str] = field(default_factory=list)
    cameras_failed: int = 0
    cameras_total: int = 0
    failure_ratio: float = 0.0
    suggested_alert_topic: Optional[str] = None
    summary: Optional[str] = None      # human-readable description

class CorrelationEngine:
    """Groups camera failures by shared infrastructure to identify root causes."""

    NVR_FAILURE_THRESHOLD = 0.5       # >50% of cameras on an NVR must fail
    SUBNET_FAILURE_THRESHOLD = 0.8    # >80% of cameras on a /24 must fail
    MIN_GROUP_SIZE = 2                # need at least 2 cameras to form a group

    def __init__(self, wg_dao=None):
        self._wg_dao = wg_dao
        self._wg_tunnels = None       # lazy-loaded

    def correlate(self, job_data: dict, config) -> List[CorrelationGroup]:
        """Run all correlation checks and return identified groups.

        Args:
            job_data: Dict[puller_name, HealthcheckDataPacket] from healthcheck run.
            config: BaseConnectorConfig with camera_streams for NVR grouping.

        Returns:
            List of CorrelationGroup, sorted by cameras_failed descending.
        """
        groups = []
        groups.extend(self._correlate_nvr(job_data, config))
        groups.extend(self._correlate_wireguard(job_data))
        groups.extend(self._correlate_subnet(job_data, config))
        # Sort by impact: largest groups first
        groups.sort(key=lambda g: g.cameras_failed, reverse=True)
        return groups
```

### NVR Correlation

Groups cameras by `base_url` or `server_ip` from their camera stream configuration. If more than 50% of cameras sharing an NVR fail, the group is flagged as an NVR-level failure.

```python
def _correlate_nvr(self, job_data, config) -> List[CorrelationGroup]:
    # Build NVR -> camera mapping from config
    nvr_groups: Dict[str, List[str]] = {}
    for stream in config.camera_streams:
        base_url = getattr(stream.camera, 'base_url', None)
        if not base_url:
            continue
        # Normalize: strip protocol, trailing slashes
        server_key = base_url.split("//")[-1].rstrip("/").split(":")[0]
        nvr_groups.setdefault(server_key, []).append(stream.camera.admin_camera_id)

    results = []
    for server_key, camera_ids in nvr_groups.items():
        if len(camera_ids) < self.MIN_GROUP_SIZE:
            continue
        failed = [cid for cid in camera_ids
                  if cid in job_data and self._is_connectivity_failure(job_data[cid])]
        ratio = len(failed) / len(camera_ids) if camera_ids else 0

        if ratio >= self.NVR_FAILURE_THRESHOLD and len(failed) >= self.MIN_GROUP_SIZE:
            group = CorrelationGroup(
                group_type="nvr",
                group_key=server_key,
                camera_ids=failed,
                cameras_failed=len(failed),
                cameras_total=len(camera_ids),
                failure_ratio=ratio,
                suggested_alert_topic="nvr",
                summary=f"NVR at {server_key} is down ({len(failed)}/{len(camera_ids)} cameras affected)"
            )
            results.append(group)
            logging.info(f"NVR correlation: {group.summary}")
    return results
```

### WireGuard Tunnel Correlation

Groups cameras by matching their IPs against [[actuate-wireguard]] tunnel subnets. If all cameras behind a tunnel fail and the tunnel's `last_handshake` is stale, the failure is attributed to the tunnel.

```python
def _correlate_wireguard(self, job_data) -> List[CorrelationGroup]:
    if not self._wg_dao:
        return []

    # Lazy-load tunnels once per correlation run
    if self._wg_tunnels is None:
        self._wg_tunnels = self._wg_dao.get_all_tunnels()

    results = []
    for tunnel in self._wg_tunnels:
        if not tunnel.subnets:
            continue
        networks = [ipaddress.ip_network(s, strict=False) for s in tunnel.subnets]
        tunnel_cameras = []
        tunnel_failed = []
        for cam_id, hc_data in job_data.items():
            cam_ip = self._extract_camera_ip(hc_data)
            if cam_ip and any(ipaddress.ip_address(cam_ip) in net for net in networks):
                tunnel_cameras.append(cam_id)
                if self._is_connectivity_failure(hc_data):
                    tunnel_failed.append(cam_id)

        if (len(tunnel_cameras) >= self.MIN_GROUP_SIZE
                and len(tunnel_failed) == len(tunnel_cameras)):
            # Check handshake staleness
            handshake_stale = self._is_handshake_stale(tunnel)
            if handshake_stale:
                group = CorrelationGroup(
                    group_type="wireguard_tunnel",
                    group_key=tunnel.name,
                    camera_ids=tunnel_failed,
                    cameras_failed=len(tunnel_failed),
                    cameras_total=len(tunnel_cameras),
                    failure_ratio=1.0,
                    suggested_alert_topic="wireguard_tunnel",
                    summary=f"WireGuard tunnel '{tunnel.name}' is down "
                            f"({len(tunnel_failed)} cameras affected, "
                            f"last handshake: {tunnel.last_handshake})"
                )
                results.append(group)
    return results
```

### Subnet Correlation

Groups cameras by /24 subnet. If 80% or more of cameras on a subnet fail but cameras on other subnets remain healthy, the failure is attributed to a switch or VLAN issue.

```python
def _correlate_subnet(self, job_data, config) -> List[CorrelationGroup]:
    subnet_groups: Dict[str, List[str]] = {}
    for cam_id, hc_data in job_data.items():
        cam_ip = self._extract_camera_ip(hc_data)
        if cam_ip:
            subnet_key = str(ipaddress.ip_network(f"{cam_ip}/24", strict=False))
            subnet_groups.setdefault(subnet_key, []).append(cam_id)

    results = []
    for subnet_key, camera_ids in subnet_groups.items():
        if len(camera_ids) < self.MIN_GROUP_SIZE:
            continue
        failed = [cid for cid in camera_ids
                  if self._is_connectivity_failure(job_data[cid])]
        ratio = len(failed) / len(camera_ids) if camera_ids else 0

        if ratio >= self.SUBNET_FAILURE_THRESHOLD and len(failed) >= self.MIN_GROUP_SIZE:
            group = CorrelationGroup(
                group_type="subnet",
                group_key=subnet_key,
                camera_ids=failed,
                cameras_failed=len(failed),
                cameras_total=len(camera_ids),
                failure_ratio=ratio,
                suggested_alert_topic="network_switch",
                summary=f"Subnet {subnet_key} down ({len(failed)}/{len(camera_ids)} cameras) -- "
                        f"likely switch or VLAN failure"
            )
            results.append(group)
    return results
```

### Temporal Correlation

Track timestamps of mass failures across runs. If failures consistently occur at midnight (NVR scheduled reboot), during DHCP lease renewal windows, or at DST transition boundaries, tag them with `group_type="temporal"` and suppress repeat alerts. This is a secondary enrichment applied to existing groups rather than a standalone grouping -- an NVR group that always fails at 00:00 gets annotated with `"likely_scheduled_reboot": True`.

## Implementation: Insertion Point in send_healthcheck_results()

The correlation step is inserted in `BaseHealthcheckCamera.send_healthcheck_results()` between result iteration and `alert_aggregator.run_sender()`:

```python
def send_healthcheck_results(self, job_id):
    job_data = self.healthcheck_res_cache[job_id]

    for puller_name in self.puller_list:
        try:
            if puller_name in job_data:
                puller = self.puller_list[puller_name]
                healthcheck_data = job_data[puller_name]
                self.save_healthcheck(healthcheck_data, puller)
            else:
                logging.info(f"no hc data for {self.get_camera_name(puller_name)}")
        except Exception as e:
            logging.error(f"send result error: {e}", exc_info=True)

    # --- NEW: Cross-camera correlation ---
    correlation_engine = CorrelationEngine(wg_dao=self._get_wg_dao())
    groups = correlation_engine.correlate(job_data, self.config)
    for group in groups:
        # Tag each camera in the group with correlation data
        for cam_id in group.camera_ids:
            if cam_id in job_data:
                job_data[cam_id].diagnostics["correlation"] = {
                    "group_type": group.group_type,
                    "group_key": group.group_key,
                    "cameras_failed": group.cameras_failed,
                    "cameras_total": group.cameras_total,
                    "summary": group.summary,
                }
                # Override alert_topic so email templates use the group-level topic
                if group.suggested_alert_topic:
                    job_data[cam_id].connectivity.alert_topic = group.suggested_alert_topic
    # --- END correlation ---

    if self.config.customer.local:
        data = {}
        for cam_key in job_data:
            data[cam_key] = job_data[cam_key].json()
        data_dump(prefix=f"healthcheck_{self.config.customer.name}_{int(time.time())}", data=data)

    self.alert_aggregator.run_sender(job_data, self, self.puller_list)
```

### Alert Consolidation

The `alert_aggregator.run_sender()` method already receives the full `job_data` dict. With correlation data tagged on each `HealthcheckDataPacket`, the alert aggregator can group cameras by `diagnostics["correlation"]["group_key"]` and emit a single consolidated email per group instead of N individual emails.

| Scenario | Before | After |
|---|---|---|
| NVR down, 5 cameras | 5 emails: "Camera offline" x5 | 1 email: "NVR at 192.168.1.100 is down (5/8 cameras affected)" |
| WireGuard tunnel down, 12 cameras | 12 emails: "Camera offline" x12 | 1 email: "WireGuard tunnel 'site-alpha' is down (12 cameras affected)" |
| Subnet switch failure, 8 cameras | 8 emails: "Camera offline" x8 | 1 email: "Subnet 10.0.5.0/24 down (8/10 cameras) -- likely switch failure" |

### Edge Cases

**Mixed failures on an NVR**: If 3 of 8 cameras on an NVR are down (below the 50% threshold) and 2 others show degraded FPS, the NVR correlation does not fire. Each camera receives its own individual diagnostic from [[chm-phase1-network-probe|Phase 1 NetworkProbe]]. The threshold can be tuned per-site via `HealthcheckConfig`.

**Partial subnet failures**: If 4 of 10 cameras on a /24 are down (below the 80% threshold), no subnet correlation fires. This avoids false positives when individual cameras fail coincidentally on the same subnet.

**Overlapping groups**: A camera can match both an NVR group and a subnet group. The correlation engine assigns priority: NVR > WireGuard > subnet. Only the highest-priority group's `alert_topic` is applied. All groups are logged to `diagnostics["correlation"]` for full visibility.

**Single-camera NVRs**: Sites where each camera has a unique `base_url` will not form NVR groups (below `MIN_GROUP_SIZE=2`). These cameras fall through to individual diagnostics from Phase 1.

## Data Model

Stored in `healthcheck_data.diagnostics["correlation"]`:

```python
healthcheck_data.diagnostics["correlation"] = {
    "group_type": "nvr",
    "group_key": "192.168.1.100",
    "cameras_failed": 5,
    "cameras_total": 8,
    "failure_ratio": 0.625,
    "summary": "NVR at 192.168.1.100 is down (5/8 cameras affected)"
}
```

## Effort Estimate

2-3 days, broken down as:
- Day 1: `CorrelationEngine` class with NVR and subnet correlation, unit tests with mock `job_data` dicts
- Day 2: WireGuard tunnel correlation (integration with `WireGuardDAO`), insertion into `send_healthcheck_results()`, `alert_topic` override logic
- Day 3: Alert aggregator grouping for consolidated emails, temporal correlation annotation, integration test

## Files to Create/Modify

### Create
- `vms-connector/healthcheck/alerts/diagnostics/tools/correlation_engine.py` -- `CorrelationEngine`, `CorrelationGroup`
- `vms-connector/test_vms/test_correlation_engine.py`

### Modify
- `vms-connector/camera/shared/base_healthcheck_camera.py` -- insert correlation step in `send_healthcheck_results()` between `save_healthcheck` loop and `alert_aggregator.run_sender()`
- `vms-connector/healthcheck/alerts/alert_aggregator.py` -- group cameras by `diagnostics["correlation"]["group_key"]` for consolidated emails
- `vms-connector/healthcheck/alerts/diagnostics/runners/connectivity_healthcheck_runner.py` -- read `diagnostics["correlation"]` in `incident_analysis()` to set incident-level metadata

## Related

- [[chm-enhanced-diagnostics-proposal]] -- parent proposal with full architecture overview
- [[chm-phase1-network-probe]] -- Phase 1: per-camera network root cause diagnosis
- [[chm-phase2-stream-probe]] -- Phase 2: stream metadata surfacing
- [[chm-diagnostics-architecture]] -- current architecture, `send_healthcheck_results()` flow
- [[chm-rd-opportunities]] -- cross-camera correlation as R&D direction
- [[actuate-wireguard]] -- WireGuardDAO, WireGuardTunnel model with `subnets` and `last_handshake`
- [[chm-diagnostics-gap-analysis]] -- NVR grouping already implicit in DW/Milestone diagnostics
