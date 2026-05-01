---
title: "CHM Phase 7: Historical Trending -- Degradation Detection"
type: synthesis
topic: camera-health-monitoring
tags: [synthesis, chm, diagnostics, proposal, phase-7, dynamodb]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
incoming:
  - topics/camera-health-monitoring/notes/syntheses/chm-phase5-frame-probe.md
incoming_updated: 2026-05-01
---

# CHM Phase 7: Historical Trending -- Degradation Detection

## Problem Statement

Current CHM is entirely point-in-time. Each healthcheck run evaluates whether a camera is healthy NOW against fixed thresholds: blur metric below 15 = blurry, FPS below minimum = low FPS, entropy below 1.5 = blank frame. This binary pass/fail model catches acute failures but is blind to gradual degradation.

Real-world camera health degrades slowly. A lens accumulates dust and grime, causing the blur metric to creep from 25 to 18 over six weeks -- still above the threshold of 15, but trending toward failure. An aging network switch develops increasing packet loss, causing frame interval jitter to grow from 0.05s to 0.3s over months. An NVR disk fills up, causing recording gaps to widen from zero to 30 seconds to 5 minutes before finally triggering the gap threshold. In each case, the camera passes every healthcheck until the day it suddenly fails -- and by then, the root cause has been compounding for weeks.

Operators receive a "Camera offline" or "Blurry camera" email with no context about whether this is a sudden failure (likely hardware/network event) or the culmination of a long decline (likely environmental or wear). The distinction matters for remediation: a sudden failure warrants immediate troubleshooting, while a gradual trend warrants a scheduled site visit for cleaning or maintenance.

## Proposed Solution: Time-Series Healthcheck Metrics with Rolling Baseline Comparison

Store per-camera healthcheck metrics as a time series in DynamoDB. On each healthcheck run, compare the current metric values against a rolling 7-day baseline. Flag cameras where metrics have degraded beyond a statistical threshold for 3 consecutive runs.

### Metrics to Trend

The following metrics are selected because they are already computed during healthcheck runs (Phases 1-5) and are meaningful when tracked over time:

| Metric | Source | Unit | Degradation Signal |
|--------|--------|------|--------------------|
| `blur_score` | [[actuate-blur\|BlurHandler]].detect_blur_fft_image() | float | Lens fouling, defocus drift |
| `entropy` | BlurHandler.calculate_entropy() | float (bits) | Progressive video loss, signal degradation |
| `frame_interval_avg` | StreamProbe (Phase 2) | seconds | Recording gaps widening |
| `fps_actual` | StreamQualityPacket.fps | float | Encoder degradation, bandwidth contention |
| `bandwidth_kbps` | StreamProbe / BandwidthTracker | float | Network path degradation |
| `connectivity_latency_ms` | NetworkProbe (Phase 1) TCP probe | int | Network path degradation |
| `decode_error_rate` | StreamProbe (Phase 2) | float (0-1) | Packet loss, stream corruption |
| `edge_density` | FrameProbe (Phase 5) | float (0-1) | Lens fouling, defocus drift |
| `color_chi_squared` | FrameProbe (Phase 5) | float | Hardware degradation, cable corrosion |

### DynamoDB Storage Design

A new DynamoDB table `HealthcheckMetricsTrend` stores the time series:

| Attribute | Role | Type |
|-----------|------|------|
| `camera_id` | Partition key | String (custcam_id) |
| `timestamp` | Sort key | Number (epoch seconds) |
| `metrics` | Metric snapshot | Map |
| `ttl` | Auto-expiry | Number (epoch seconds, current + 90 days) |

Each healthcheck run writes one item per camera containing all trended metrics as a nested map. The 90-day TTL ensures automatic cleanup without manual intervention. At one run per hour per camera, this produces ~2,160 items per camera over 90 days. For a fleet of 50,000 cameras, this is ~108 million items -- within DynamoDB's comfortable operating range with on-demand capacity.

**Query pattern**: The primary query is `camera_id = X AND timestamp BETWEEN (now - 7d) AND now`, which returns ~168 items (hourly runs for 7 days). This is a single-partition query that completes in under 50ms.

### Baseline Calculation

The rolling baseline for each metric is computed as the **7-day median** per metric per camera. Median is preferred over mean because it is robust to outlier runs (e.g., a single failed healthcheck returning 0 for all metrics should not drag down the baseline).

Baseline calculation happens at the start of each healthcheck run as a preprocessing step:

1. Query `HealthcheckMetricsTrend` for the target camera, last 7 days.
2. For each metric, collect all non-null values into an array.
3. Compute `numpy.median()` for each metric array.
4. Store the baseline in memory for comparison against the current run's results.

If fewer than 24 data points exist (camera newly enrolled or recently re-enabled), skip trending analysis and report `"trending_status": "insufficient_data"`.

### Degradation Alert Threshold

A metric triggers a degradation alert when:

```
current_value > 2x baseline_median  (for metrics where higher = worse)
current_value < 0.5x baseline_median  (for metrics where lower = worse)
```

This 2x threshold must persist for **3 consecutive runs** to trigger an alert. The consecutive-run requirement filters out transient spikes (temporary network congestion, momentary camera obstruction) while catching true trends.

For metrics where directionality varies:
- **Higher = worse**: `frame_interval_avg`, `connectivity_latency_ms`, `decode_error_rate`, `color_chi_squared`
- **Lower = worse**: `blur_score`, `entropy`, `fps_actual`, `bandwidth_kbps`, `edge_density`

### Implementation Architecture

**TrendCollector** (`healthcheck/alerts/diagnostics/tools/trend_collector.py`): Responsible for writing metric snapshots after each healthcheck run and querying historical data for baseline computation.

**TrendAnalyzer** (`healthcheck/alerts/diagnostics/tools/trend_analyzer.py`): Computes baselines, compares current values, tracks consecutive-run degradation counts, and emits degradation alerts.

**Integration point**: `BaseHealthcheckCamera.send_healthcheck_results()` calls `TrendCollector.record_metrics()` after all diagnostic runners complete. `TrendAnalyzer.check_degradation()` is called during the same post-processing step, after `record_metrics()` writes the current snapshot.

### Degradation Alert Data Model

Degradation alerts use a new `alert_topic = "degradation"` in the healthcheck packet:

```python
healthcheck_data.diagnostics["trending"] = {
    "trending_status": "degradation_detected",  # or "healthy", "insufficient_data"
    "degraded_metrics": [
        {
            "metric": "blur_score",
            "current": 16.2,
            "baseline_median": 24.8,
            "ratio": 0.65,
            "consecutive_runs": 3,
            "direction": "decreasing",
            "likely_cause": "Lens fouling or progressive defocus",
        }
    ],
    "baseline_window_days": 7,
    "data_points_available": 168,
}
```

### Dashboard: New Relic NRQL Queries

Trending data logged to [[new-relic|New Relic]] enables visualization and fleet-wide degradation queries:

```sql
-- Cameras with blur degradation over last 7 days
SELECT average(blur_score) FROM HealthcheckMetric
WHERE camera_id = 'X' FACET dateOf(timestamp, 'day') SINCE 7 days ago

-- Fleet-wide degradation hotspots
SELECT count(*) FROM HealthcheckMetric
WHERE trending_status = 'degradation_detected'
FACET site_name SINCE 1 day ago

-- Bandwidth degradation across a site
SELECT average(bandwidth_kbps) FROM HealthcheckMetric
WHERE site_id = 'Y' FACET camera_name TIMESERIES 1 hour SINCE 14 days ago
```

### Use Cases

**Lens fouling**: A camera's blur_score decreases from 28 to 22 to 18 over 3 weeks. Each individual run passes the blur threshold of 15, but the trend analyzer detects a 35% decline from the 7-day baseline and flags degradation after 3 consecutive runs. The alert recommends a scheduled lens cleaning.

**Network degradation**: connectivity_latency_ms increases from 15ms to 45ms to 120ms over 2 weeks. Frame delivery remains functional (TCP retransmits compensate) but the upward trend indicates a failing network path. The alert fires before the latency causes actual frame loss.

**NVR disk filling**: frame_interval_avg grows from 1.0s to 1.5s to 3.0s as the NVR begins dropping frames to manage disk pressure. The 3x increase from baseline triggers a degradation alert well before the gap threshold triggers a recording incident.

**Bandwidth contention**: bandwidth_kbps drops from 2048 to 1200 to 800 during business hours as a shared network link becomes congested. The pattern is time-of-day correlated and the trend analysis captures it as a sustained decline.

### Integration with Watchman

Trending data feeds into the [[watchman-site-context-agent|Site Context Agent]] for proactive health awareness. The agent receives a daily summary of all cameras in degradation state per site, enabling it to correlate degradation patterns (e.g., "5 cameras at Site X all show increasing latency -- likely a shared network issue") and recommend preventive action before failures occur.

## Cost Estimate

DynamoDB on-demand pricing for 108M items with 90-day TTL: ~$25/month for writes (one write per camera per run), ~$5/month for reads (one query per camera per run). Total incremental cost: ~$30/month. Negligible relative to the existing CHM DynamoDB spend.

## Effort Estimate

1-2 weeks. Breakdown: 2 days for DynamoDB table creation, TrendCollector, and metric recording. 2 days for TrendAnalyzer baseline computation and degradation detection logic. 1 day for `BaseHealthcheckCamera` integration and alert generator wiring. 1-2 days for [[new-relic|New Relic]] logging and NRQL dashboard queries. 2-3 days for threshold tuning, consecutive-run logic testing, and production validation across a representative camera sample.

## Related

- [[chm-enhanced-diagnostics-proposal]] -- parent proposal defining Phase 7 scope
- [[chm-diagnostics-architecture]] -- BaseHealthcheckCamera.send_healthcheck_results() integration point
- [[chm-phase5-frame-probe]] -- FrameProbe metrics (edge_density, color_chi_squared) as trending inputs
- [[chm-phase4-generic-diagnostics]] -- GenericDiagnostics providing metrics for trending
- [[chm-phase6-smtp-ailink-diagnostics]] -- SMTP/AILink metrics as trending inputs
- [[watchman-site-context-agent]] -- consumes trending data for proactive site awareness
- [[performance-optimization-landscape]] -- DynamoDB cost and capacity considerations
