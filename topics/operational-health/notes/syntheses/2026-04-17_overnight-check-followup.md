---
title: "Overnight Check Follow-Up 2026-04-17: Verified Status & Actions"
type: synthesis
topic: operational-health
tags: [overnight-check, operational-health, incident-followup, connector, evalink, autopatrol, eks-capacity]
created: 2026-04-17
updated: 2026-04-17
author: kb-bot
status: active
---

# Overnight Check Follow-Up 2026-04-17

Follow-up verification (~11:00 EDT re-check) of [[2026-04-17_overnight-check|2026-04-17 overnight check]]. Confirms current state, isolates root causes, and prescribes concrete action owners.

## Status Summary

| Issue | Current Status | Severity | Owner Suggestion |
|-------|---|---|---|
| [[evalink-components|Evalink]] HTTP 400 (deviceId length) | **ACTIVE & ACCELERATING** — 88 errors/1h (vs 24/hr overnight baseline) | **P1** | Ops / Customer Success |
| VMS relay `relay-us-dal-1-prod-dp` outage | Subsiding on connector-11202; emerging on 32220 | P2 | On-call / VMS Support |
| connector-deploy restart loop (site 14170) | Subsided; new WARNING signature appeared | P2 | On-call / R&D |
| EKS node CPU pressure | **ESCALATED** — two-node anomaly became fleet-wide (70–86% avg) | **P1** | Infra / Platform |
| AutoPatrol skill failed (headless run) | FIXED in overnight-check.sh; interactive use unaffected | P3 | Monitoring |

## Per-Issue Deep Dives

### Issue 1: Evalink Alert Delivery Dropping (HTTP 400)

**Root cause identified:** Camera "SOLAR SENTINEL 7" at connector-44815 / "CVG CONSTRUCTION SITE" (company `89b2cef7-87e8-4a26-8ec0-da0c46b23a95`) has a `deviceId` field with **11 characters**. The [[evalink-components|Evalink]] API `/api/alarm-service/alarms` requires exactly 32 characters. Every alert for this camera returns `HTTP 400 Bad Request` and is **silently dropped** — no retry, no DLQ entry, no customer notification.

**Current status:** Still active and *accelerating*. Re-check at 11:00 EDT showed 88 errors in the last 1 hour, vs ~24/hr baseline overnight. This camera is firing alerts faster this morning.

**Action items:**
1. **Ops/Customer Success (P1 — urgent):** Update the `deviceId` field on the camera record for "SOLAR SENTINEL 7" at connector-44815 in the admin panel. This is a pure data-quality fix with zero code changes. Once corrected, in-flight alerts should route cleanly.
2. **R&D (P2):** Add input validation in `queue-evalink-consumer` before the [[evalink-components|Evalink]] API call. Refuse to call [[evalink-components|Evalink]] when `len(deviceId) != 32` and instead emit a structured WARNING log line (so future malformed configs don't fail silently into 400s). Consider a healthcheck endpoint that flags cameras with invalid `deviceId` on startup.

**Tracked:** [BACK-648](https://actuate-team.atlassian.net/browse/BACK-648) — actuate-admin bug covering investigation, fix, validation rule, and admin-DB audit. Assigned to Adam Kawczyński; Mark + Tati mentioned.

**Cross-link:** [[integrations/evalink/_summary|Evalink Integration]]

---

### Issue 2: VMS Relay `relay-us-dal-1-prod-dp.vmsproxy.com` Outage

**Overnight scope:** connector-11202 accumulated 6,970 read timeout errors (all ~20 cameras at the site uniformly) against this relay while fetching camera auth strings. Blast radius: single site.

**Current status (11:00 EDT re-check):** 
- connector-11202 now shows **zero hits** in the last hour. The relay has largely recovered.
- However, connector-32220 now shows **7 new errors** against the same relay — likely a straggler or newly onboarded site. Volume remains low (single digits).
- Pattern: both connectors are hitting the same geographic relay, so the outage is relay-scoped, not connector-scoped.

**Action items:**
1. **On-call (P2 — conditional):** Continue monitoring connector-32220 at the next hourly check. If error volume stays at low single digits, no action needed. If 32220 climbs to 100+ errors/hr, open a ticket with VMS support for relay-us-dal-1-prod-dp availability.
2. **Monitoring (P3):** Add this relay to the overnight-check's list of cross-checks for future outages (correlate other connector spikes against known relay failures).

**Follow-up thought:** The 6,970 errors from 11202 is loud but non-fatal — the connector's internal retry logic handles it. The real concern is that camera auth failed silently for a full 12h window; check customer-facing "camera unavailable" metrics for CVG CONSTRUCTION SITE to estimate user impact.

---

### Issue 3: connector-deploy Restart Loop (Site 14170)

**Overnight scope:** 11,372 errors / 12h, dominated by rate-limited self-reboot messages and VPA idempotency warnings ("already exists, patching").

**Current status (11:00 EDT re-check):** Subsided. Zero reboot messages in the last hour; the container is cycling shard children normally. **BUT:** a new WARNING signature appeared: `Query cloud device list fail` at ~500/hr (WARNING level, not ERROR). This signature is sustained and warrants investigation.

**Action items:**
1. **On-call (P2):** Monitor connector-14170 over the next cycle (e.g., at next check in ~2h). If `Query cloud device list fail` persists at ~500/hr or climbs, escalate to R&D with full logs to investigate VMS cloud API reachability for this site — could be credentials, endpoint config, or network path issue specific to site 14170.
2. **R&D (P2):** The rate-limited self-reboot loop is a known connector-deploy behavior when a site has persistent config errors. Consider adding an **upper-bound circuit breaker** — e.g., suppress reboot messages after N reboots in M minutes (e.g., 5 reboots in 30 minutes). This prevents a single misbehaving site from generating 11k log lines and drowning out other alerts.

---

### Issue 4: EKS Node CPU Pressure (ESCALATED)

**Overnight scope:** Two nodes (`ip-10-10-22-72`, `ip-10-10-22-132`) fired High CPU alerts, correlating with 7 "Deployment unavailable pods" issues across distinct connector deployments.

**Current status (11:00 EDT re-check):** Both original nodes are **GONE** from the node inventory (terminated/replaced by autoscaler or manual action). BUT the CPU pressure is now **FLEET-WIDE and PERSISTENT**:

- **Top 5 nodes by CPU usage:**
  - `ip-10-10-42-212`: 86% avg, 93% peak
  - `ip-10-10-60-203`: 86% avg, 88% peak
  - `ip-10-10-44-23`: 84% avg, 86% peak
  - `ip-10-10-22-100`: 83% avg, 88% peak
  - `ip-10-10-53-72`: 83% avg, 87% peak
- **10 additional nodes** in the 70–86% average range.
- **6 of 9 originally affected connector pods** (19501, 20274, 14299, 19503, 19504, 12183) show `restartCount=0` — stabilized. Three (20139, 41190, 705) appear to have been rescheduled under new pod names.

**Interpretation:** The two-node spike was a symptom, not the root cause. The underlying load is genuinely high across the fleet.

**Action items (P1 — ESCALATE):**
1. **Infra/Platform (urgent):** This is not a transient blip — 70–86% avg CPU across 15+ nodes with 88–93% peaks suggests the cluster is under sustained high load. Options:
   - **Scale out the Connector-EKS node group** — add 3–5 nodes to reduce per-node utilization to 50–60% range.
   - **Investigate workload spike:** Did connector shard cycling increase (new sites onboarded)? Is autopatrol running a burst job? Check if a specific workload is consuming disproportionate CPU.
   - **Tune VPA / resource requests:** Verify that pod resource requests are accurate. Misaligned requests can cause scheduler starvation.
2. **R&D / On-call (concurrent):** Pull logs from the top-5 high-CPU nodes to identify which workload(s) are consuming CPU — is it connector shards, queue consumers, autopatrol jobs, or something else?

---

### Issue 5: AutoPatrol Skill Failed (Headless Run)

**Root cause identified:** The `/autopatrol-overnight-check` skill uses `kubectl` and the `mcp__kubefwd__*` MCP tools. Neither is available to the headless `claude -p` process running under a linger'd systemd user service (`/home/mork/.config/systemd/user/overnight-check.service`):
- The service runs in a non-interactive environment with no tty → kubeconfig setup fails.
- The kubefwd MCP server disconnects when the parent process (the skill runner) exits.

**Current status: FIXED.** The overnight-check.sh script now **inlines NR-only queries** for autopatrol instead of invoking the skill. The skill definition itself is fine for interactive use (e.g., `/autopatrol-overnight-check prod` from the CLI).

**Concurrent fix (same edit):** Container-name drift in the alert-delivery step. The original spec used underscore names (`queue_immix_consumer`, `queue_consumer`, `webhook_listener`) which returned zero rows across 7 days. Replaced with canonical names: `queue-evalink-consumer`, `queue-eagle-eye-consumer`, `smtp-frame-receiver`, `cert-manager-webhook`, `clips-smtp-worker`.

**Action items:**
1. **Monitoring (P3):** Tomorrow's 08:03 run will exercise the new prompt. If autopatrol coverage comes back thin (missing CronJob status, pod lifecycle checks), consider a weekly interactive `/autopatrol-overnight-check` run to complement the headless automation and fill coverage gaps.
2. **Skill maintenance (P3):** Document the "headless-incompatible" constraint in the skill's README — skills that require kubectl or interactive MCP tools should note this explicitly.

---

## Concrete Action Items (Ordered by Priority)

1. **P1 — Ops**: Fix `deviceId` for SOLAR SENTINEL 7 at connector-44815 ([[evalink-components|Evalink]] alerts silently dropping).
2. **P1 — Infra**: Investigate fleet-wide EKS node CPU pressure (70–86% avg, 88–93% peaks). Scale or diagnose workload spike.
3. **P2 — R&D**: Add `deviceId` length validation in queue-evalink-consumer; emit structured WARNING instead of silent 400 drops.
4. **P2 — R&D**: Add circuit breaker to connector-deploy rate-limited reboot loop (suppress after N reboots in M minutes).
5. **P2 — On-call**: Monitor connector-32220 for VMS relay errors; escalate to VMS support if > 100/hr sustained.
6. **P2 — On-call**: Monitor connector-14170 `Query cloud device list fail` warnings; escalate to R&D if sustained > 500/hr.
7. **P3 — Monitoring**: Add VMS relay-us-dal-1-prod-dp to overnight-check cross-check list.
8. **P3 — Skill maintenance**: Document headless-incompatible skills in skill README templates.

---

## Process Improvements This Taught Us

- **Headless skill invocations need sandbox compatibility.** Rule of thumb: any skill called from an unattended systemd service (like overnight-check.service) must only use tools available to that service. No kubectl, no kubefwd-MCP, no interactive setup. Consider a "sandbox mode" flag in skill definitions.
- **Container name specs drift over time.** The alert-delivery container list in overnight-check.sh was 6+ months stale (underscore names). Add a periodic assertion or validation that the spec names resolve to non-zero rows before faceting; catch drift early.
- **Persistent systemd timers + network-online are robust.** The overnight-check.service has `Persistent=true` and `After=network-online.target`. When systemd caught a service crash overnight and restarted at 08:03, the service recovered cleanly and filed a complete report. `RestartSec=15min` is a good backstop for transient auth state.

---

## Related

- [[2026-04-17_overnight-check|2026-04-17 Overnight Check]] — parent automated report
- [[automation-overnight-check|Automation: Overnight Check]] — skill that produced the parent report
- [[integrations/evalink/_summary|Evalink Integration]] — external partner API details
- [[infrastructure/_summary|Infrastructure]] — EKS / node tuning reference
- [[knowledgebase/topics/autopatrol/_summary|AutoPatrol]] — product context
