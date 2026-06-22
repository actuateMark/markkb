---
title: "Genesis no-alerts incident 2026-05-24 — Milestone Security token invalid + NAT correlation"
type: concept
topic: operational-health
tags: [incident, genesis, milestone, vms, token, nat, customer-impact, observability-gap, restart-didnt-help, s3-token-cache, post-mortem-pending]
created: 2026-05-24
updated: 2026-05-24
author: mark
incoming:
  - topics/integrations/milestone/_summary.md
  - topics/integrations/milestone/notes/entities/milestone-components.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-27
---

# Genesis no-alerts incident 2026-05-24

## TL;DR

Customer **Genesis** reports zero alerts across all their sites. Two of 24 Genesis connector pods (`genesis-70078`, `genesis-75705` — both Milestone-VMS sites for **Genesis Schools**) receive `<connected>no</connected><errorreason>Security token invalid</errorreason>` from the recording server at **172.16.254.103** at ~250 rejections/5-min/pod, flat. Pod restarts (targeted + fleet-wide rollout-restart of all 24 deployments) did NOT resolve.

**ACTUAL ROOT CAUSE (resolved 2026-05-25 00:41 UTC):** OUR **NAT Instance Proxy - EKS** (EC2 `i-05cf6dc283800e05d`, t3.micro, IP 10.10.1.54, VPC vpc-045d45f32ad2de278) hung at 14:04 UTC today. Symptoms in CloudWatch: `SSM PingStatus: ConnectionLost` from 14:04 UTC; `NetworkOut` flatlined at 0.0 bytes for 12 hours; `StatusCheckFailed (Instance)` = 1.0 from 15:00 UTC onward; CPU pinned at ~0.17% (no work). The OS-level instance status checks were failing — the box was effectively zombied (TCP listener still bound but no app processing). The admin-auto-onboarding-schools cronjob routes its outbound TLS traffic to Genesis Schools' management server **through this proxy**, so once the proxy died our cronjob's HTTPS POST silently terminated with `SSL_UNEXPECTED_EOF_WHILE_READING` at the network layer. Mark + Tatiana rebooted the proxy at ~00:40 UTC; SSM PingStatus → Online and the next 5-min cronjob run succeeded (S3 token timestamp advanced to `2026-05-25T00:41:45Z`).

**Misleading earlier signal:** From inside a Genesis K8s pod (`genesis-70078`), we could TCP-connect to `172.16.254.103:443` and saw a half-completed TLS handshake — initially interpreted as "Genesis's server has a broken TLS endpoint." That was wrong: K8s pod egress and [[admin-auto-onboarding]] cronjob egress take **different routing paths**, and only the cronjob path goes through the dead NAT proxy. The pod-level TLS half-handshake was likely a stale connection-tracking entry or different ACL behavior — not the actual cronjob failure mode. **Lesson: do not assume egress topology is consistent across namespaces/clusters without verifying.**

**Original (now superseded) hypothesis section follows — kept for the diagnostic record of what we observed before identifying the proxy:**

Their Milestone management server at `172.16.254.103:443` is broken at the TLS layer. The K8s cronjob `admin-auto-onboarding-schools` (namespace `admin-auto-onboarding`, runs every 5 min) is the token writer. Since ~14:06 UTC every run has failed with:

```
SSLError(SSLEOFError(8, '[SSL: UNEXPECTED_EOF_WHILE_READING]
  EOF occurred in violation of protocol (_ssl.c:1010)'))
```

TCP to port 443 succeeds; the TLS handshake starts; the server sends EOF mid-handshake before completing. Independently confirmed with `openssl s_client` from inside a Genesis pod: TLS connects but `Cipher is (NONE)` and no certificate is returned. Compare to the working Convention Center mgmt server at `172.16.250.114:443`, which returns a proper TLSv1.2 cipher and cert `subject=CN=GSS-SRV-MPMS-01.genesis.local`. **This is server-side at Genesis** — broken cert, broken TLS config, broken proxy in front of the server, or similar. The recording server on the SAME IP at `:7563` is also offline (Connection refused from two different pods on different nodes). Likely tied to the NAT incident on Genesis's network 2026-05-23, but the proximate failure is at the TLS/server layer, not the routing layer.

**Engineering observation:** Each failed cronjob run **already publishes to SNS topic `customer-warnings`** — the same SNS topic the DjangoQ CPU alarm fired through 2026-05-22. **No PagerDuty subscription on it. No human was watching.** Same observability gap, second incident in 3 days. Wiring PD to this SNS would have paged the team at ~14:11 UTC instead of finding it from a customer call at ~23:00 UTC — a 9-hour detection delay.

## Timeline

| Time (UTC) | Event |
|---|---|
| 2026-05-22 19:00 | First evidence: NR logs show `ConnectTimeoutError` / `No route to host` from genesis pods toward `172.16.254.103`. Surfaced during djangoq CPU incident triage ([[2026-05-22_djangoq-cpu-spike-v8-rollback-verify-scan]]). Deferred at the time. |
| 2026-05-23 | **NAT incident on Genesis side** — exact details captured in user's working memory, NOT yet in KB. **TODO: backfill this section** with what happened (NAT change? Outage? Reconfig?), timing, and who reported it. |
| 2026-05-24 (today) | Genesis customer reports "no alerts whatsoever, customer-wide." |
| 2026-05-24 ~23:00 | Initial NR triage: network-layer connectivity to `172.16.254.103` is restored (TCP accepts again). New failure mode: every camera connection rejected with `Security token invalid` from Milestone. `genesis-70078` (~1,300-1,370 rejections per camera over 24h on 14 cameras), `genesis-75705` (18,981 rejections over 24h on 15 cameras). |
| 2026-05-24 23:33 | Targeted pod restart on `genesis-70078-fcdb6586d-hgcct` and `genesis-75705-7c557b48d5-m8bbf`. New pods Ready in ~36s. NR re-check at 23:36 confirms token rejections returned at flat ~250/5min on each. |
| 2026-05-24 23:42 | **Fleet-wide rollout restart on all 24 Genesis deployments** (per user direction — "if they're complaining this much, restart all of them"). All pods Ready within ~3 min. |
| 2026-05-24 23:46 | Token rejections still flat at ~250/5min — no recovery. Confirmed: restart does nothing because the rejection is at Milestone's server. |
| 2026-05-24 23:47 | **S3 token freshness check:** `s3://actuate-settings/genesis/token.txt` last modified `2026-05-24T14:06:01Z`. TTL=14400s (4h), registration_time=`1779631559.0` → token expired at **2026-05-24T18:05:59Z**. Currently ~6h past expiry. The other three Milestone S3 paths (`genesis_convention_center`, `genesis_federated`, `connector-8959`) all modified within the last 5-15 min — refresher is alive and healthy for them. Only Schools path stale. |
| 2026-05-24 23:50 | Token writer hunt: no S3-upload code found in `actuate-libraries`, `vms-connector`, `actuate_admin`, `autopatrol-server`. `refresh-token-handler` Lambda is Eagle Eye only (verified by reading `handler.py` source). Stale ECS log groups `/aws/ecs/containerinsights/genesis/performance` + `/logs/actuate_nyc_milestone` long dead. |
| 2026-05-24 23:55 | **Writer identified: `prod_camera_admin` ECS service** (us-west-2, EC2-backed, NR firelens logs not CloudWatch). Specific module: the `nvrcamera` / `update_camera_list.py` subprocess invoked via the camera-admin app. Last successful Genesis Schools refresh at **13:58:02 UTC**, output included `milestone : INFO : Uploaded token to genesis/token.txt`. All subsequent invocations for customer 14920 return `{'success': None, 'output': ''}` — empty stdout, no exception, no structured error log. Failure is completely silent. The other 3 Genesis-owned customer paths (`genesis_convention_center`, `genesis_federated`, `connector-8959`) continue refreshing successfully every cycle. |
| 2026-05-24 23:55 | **Tatiana (`tatiana`) was already in admin** between 23:35-23:45 UTC running `refresh_camera_list` + `refresh_preview` on Genesis Schools and at 23:56 UTC attempted to undeploy `connector-template-14920`. She is aware of the issue and was actively investigating in parallel. |
| 2026-05-24 23:58 | **Settings file mystery resolved.** The customer-level template `connector-14920/settings.json` showing `cameras: 0` is just because per-site configs are nested differently — actual pod configs live at `s3://actuate-settings/genesis_<site_id>/settings.json` (e.g., `genesis_70078/settings.json` 16 cameras under 1 recording server; `genesis_75705/settings.json` 15 cameras). Per-site configs are normal. |
| 2026-05-25 00:07 | **Network probes from inside Genesis pod (genesis-70078):** DNS for `gss-clu-mgmtedu.genesis.local` → NXDOMAIN (our pods can't resolve this FQDN, but that's fine — the SOAP call uses the IP directly per `milestone_service.py`). TCP to `172.16.254.103:443` → OK. TCP to `172.16.254.103:7563` (recording server) → **Connection refused on multiple pods on different nodes** (the recording server has gone offline since the customer first complained). TCP to the OTHER three management servers `:443` → all OK. TLS handshake to `172.16.254.103:443` returns `CONNECTED` but `Cipher is (NONE)` and no cert — abnormal. Same TLS test to `172.16.250.114:443` returns proper TLSv1.2 cipher + cert `CN=GSS-SRV-MPMS-01.genesis.local`. `curl https://172.16.254.103:443/ManagementServer/ServerCommandService.svc` returns `code=000`, exit 35 (SSL connect error). `curl http://172.16.254.103:80/` returns `200 OK`. **Conclusion: server is up on port 80 but TLS on port 443 is broken at the handshake level.** |
| 2026-05-25 00:35 | **User points at custom NAT Instance Proxy EC2.** AWS EC2 instance `i-05cf6dc283800e05d`, name tag `NAT Instance Proxy - EKS`, t3.micro launched 2023-03-01, VPC `vpc-045d45f32ad2de278`, private IP `10.10.1.54`. Inspection: `SSM PingStatus: ConnectionLost` since `2026-05-24T10:04:31-04:00` = **14:04 UTC** (within 2 min of the cronjob's last successful refresh at 14:06 UTC). `NetworkOut` flatlined at 0.0 bytes for the entire 12h. `StatusCheckFailed_Instance = 1.0` from 15:00 UTC onward continuously. CPU at ~0.17% average — instance "running" but the OS or proxy daemon is hung. This is the proximate cause of the cronjob's TLS failures. |
| 2026-05-25 00:40 | **Mark + Tatiana reboot the NAT proxy.** |
| 2026-05-25 00:41 | **RECOVERY confirmed via dual independent signals**: (1) NAT proxy EC2 state running, SSM PingStatus → Online; (2) S3 token timestamp on `genesis/token.txt` advanced from `2026-05-24T14:06:01Z` (stale) to `2026-05-25T00:41:45Z` (fresh). The 5-min schools cronjob tick after the reboot succeeded and uploaded a fresh token. Connectors pick it up automatically on next read cycle (~1 min). No pod restart needed for recovery. |
| 2026-05-25 00:13 | **Writer identification corrected and confirmed.** Per user input, the writer is **NOT** the `prod_camera_admin` ECS service — it is the K8s cronjob `admin-auto-onboarding-schools` (namespace `admin-auto-onboarding`, image `admin-auto-onboarding:1.1.23`, schedule `1-59/5 * * * *`). Sibling cronjobs exist for each Genesis customer type: `-federated`, `-gun`, `-group-site`, `-vpn-checker`. The Schools cronjob calls `auto_onboarding.py` → `camera_comparison.update_camera_list()` → HTTPS POST to `https://172.16.254.103:443/ManagementServer/ServerCommandService.svc`. Last 12 pods (from 2 most-recent job runs) all `Error`. Exception captured from `admin-auto-onboarding-schools-29661126-vm8dw` log: `RuntimeError: Camera list refresh failed with: Failed to update camera list (HTTPSConnectionPool(host='172.16.254.103', port=443): Max retries exceeded with url: /ManagementServer/ServerCommandService.svc (Caused by SSLError(SSLEOFError(8, '[SSL: UNEXPECTED_EOF_WHILE_READING] EOF occurred in violation of protocol (_ssl.c:1010)'))))`. **Definitively a server-side TLS failure on Genesis Schools' management server, not a route or NAT issue.** Each failed run publishes to SNS topic `customer-warnings` (per log line `Published to customer-warnings: {'MessageId': ...}`). The SNS topic is the same one the 2026-05-22 DjangoQ CPU alarm fired through — email-only, no PagerDuty, no human caught it for 9+ hours. |

## The four Milestone customers ("Genesis"-prefixed S3 paths) — all Genesis-owned

Per Mark 2026-05-24: `genesis_convention_center` and `genesis_federated` are also Genesis-owned (not separate customers). So the four hardcoded paths in `milestone_service.py` are:

| S3 path | Management Server IP | Customer | Token freshness 2026-05-24T23:47Z | Status |
|---|---|---|---|---|
| `genesis/` | `172.16.254.103` (`gss-clu-mgmtedu.genesis.local`) | Genesis Schools | **9h42m stale (last write 14:06:01Z)** | 🔴 broken — token expired 18:05Z |
| `genesis_convention_center/` | `172.16.250.114` | Genesis Convention Center | 7 min old (23:40:58Z) | 🟢 healthy |
| `genesis_federated/` | `172.16.254.91` | Genesis Federated | 14 min old (23:34:15Z) | 🟢 healthy |
| `connector-8959/` | `172.16.250.235` | (specific Milestone-bridged site) | 8 min old (23:40:04Z) | 🟢 healthy |

Implication: the writer process runs and successfully refreshes 3 of 4 paths every cycle but silently skips/fails on the Schools path. Either (a) the Schools management server is unreachable from the writer host (NAT/route issue), (b) the Schools SOAP credentials in admin DB are stale, or (c) the writer's per-customer error handling swallows the exception silently and continues to the next customer.

## Genesis architecture (from existing KB)

Genesis is a hybrid customer with two distinct connection paths:

1. **36-bridge [[rtsp-deep-dive|RTSP]] frame fetching** via `GenesisUrlFramePuller` (`actuate-pullers/genesis_url_puller.py`). Random bridge selection across `172.16.254.11-46` for failover. Bypasses `quick_probe`. 60-second retry. Used by most of the 24 connector pods for raw camera frame ingestion.
   - Ref: [[rtsp-components]] § GenesisUrlFramePuller
2. **Milestone XProtect integration** for alert delivery and (for some sites) frame fetching via the Milestone Image Server protocol. Uses **S3-based token sharing** — `retrieve_file_token_milestone()` downloads token files from S3 for specific hardcoded Genesis/federated server IPs, rather than performing a live SOAP `Login`.
   - Ref: [[milestone-components]] § Token lifecycle, [[integrations/milestone/_summary]] § S3 token fallback
3. **Special Genesis gun-detection event path** — Milestone alert sender uses a simplified payload with `event_name="Actuate Gun Detection"` and no bounding boxes for Genesis-lead detections.
   - Ref: [[milestone-components]]

**`172.16.254.103` is NOT in the bridge pool** (.11-.46) — it's the Milestone recording server. Different role, different protocol layer.

## What we know is broken vs what we know is healthy

**Our side — healthy:**
- All 24 connector pods Running 1/1, 0 restarts (pre-deletion), chatty in NR (~2,500 lines/5min each)
- Camera frame ingestion via [[rtsp-deep-dive|RTSP]] bridges (`172.16.254.11-46`) appears to be working (the 22 non-Milestone pods are running normally; no widespread bridge-pool failures in NR)
- Alert pipeline (`drain_alert_executors`) is active
- Pod restarts complete cleanly; new pods are 1/1 Ready within 30-60s

**Our side — broken** (revised diagnosis after S3 timestamp check):
- `s3://actuate-settings/genesis/token.txt` last refreshed at `2026-05-24T14:06:01Z`. TTL of 14400s + registration at 14:05:59Z means the token **expired at 18:05:59Z**, ~6 h before the customer complaint.
- The token-refresh writer (a scheduled process on our infra — most likely `prod-job-scheduler` ECS service, logs route to NR via firelens) refreshes 3 of 4 Genesis-owned Milestone S3 paths fine in the same window. Only Schools (`genesis/`) silently stops being written.
- Pod logic in `actuate-libraries/actuate-integration-calls/.../milestone_service.py:142` keeps reading the expired token from S3 and presenting it to Milestone — no fallback to a live SOAP login for hardcoded customers. The result is the steady-state thrash loop we see.

**Customer side — broken (likely root cause of the writer's silent skip):**
- NAT incident on Genesis network 2026-05-23. The writer's SOAP-login call to `gss-clu-mgmtedu.genesis.local` (the Genesis Schools management server) probably fails — network unreachable, ACL denial, or auth credential drift. Other 3 management servers (172.16.250.114, 172.16.254.91, 172.16.250.235) sit on different /24s and presumably different VPN tunnels or NAT routes — they remained reachable.
- Note: Milestone recording server at `172.16.254.103` ITSELF is reachable from our connector pods (TCP accepts; we get an XML rejection back). The problem is just that the token we present is past TTL.

## Diagnostic experiments performed

| Experiment | Result |
|---|---|
| Pod restart on `genesis-70078` + `genesis-75705` (targeted) | New pods spawned, immediately re-entered token-rejection loop at same rate |
| Fleet-wide `kubectl rollout restart deployment/...` on all 24 Genesis deployments | All pods Ready within 3 min, two Milestone pods still rejected at same rate, no fleet-wide alert flow observed in first 4 min |
| `renice` of the offending process | Not applicable here (not relevant) |

Both restarts produced **zero successful Milestone connections** — proof that the failure is at the Milestone application layer, not in our pods.

## Open questions — fill these in

1. **NAT incident 2026-05-23** — what happened, exact timing, who reported, what was the scope? Mark has this context — needs to be captured here for the Monday handoff. Specifically: which Genesis subnet was affected; was Genesis Schools management server (`gss-clu-mgmtedu.genesis.local`) routing different from the other 3 management servers; were any of OUR outbound IPs / NAT-gateway IPs whitelisted on Genesis's side that may have changed.
2. **Is the customer's "no alerts customer-wide" claim accurate?** We confirmed two pods (`genesis-70078`, `genesis-75705`) are visibly broken via Milestone rejection. The other 22 Genesis pods are running and presumably ingesting frames via the 172.16.254.11-46 [[rtsp-deep-dive|RTSP]] bridge pool — but we did NOT fleet-audit alert emissions per pod before/after restart (NR query cancelled mid-execution in favor of mass restart). Post-restart monitor at 13min showed `alerts_last_15m=0` across the fleet — consistent with customer's claim but not conclusive (new pods only have ~13 min of logs). Worth running post-incident.
3. **Token writer identification** — confirmed it's on our side (bucket is ours, 3 of 4 paths refresh fine). The exact host/service was NOT conclusively identified during this session. Strong candidates: `prod-job-scheduler` ECS service (1 running task, NR-only logs); `prod-camera-admin` ECS service. Search method: NR query for any container writing `Refreshing milestone token` / `milestone_service` / S3 PUT operations to `genesis/token.txt`.

## What needs to happen next

**To force-recover the customer immediately** (engineering, executable from any pod or workstation with right network reachability):

1. Locate the writer process (NR log search above) and inspect why it skipped/failed Genesis Schools at ~14:06 UTC. Most likely: per-customer try/except in the writer swallows the SOAP exception silently, logs nothing structured, continues to next customer.
2. If the writer is a Python script using the same `milestone_service.py` SOAP-login path, attempt the SOAP login manually with the Genesis Schools credentials (in admin DB) against `https://gss-clu-mgmtedu.genesis.local:<ssl_port>/ManagementServer/ServerCommandService.svc`. If it returns a token: upload the three files (`token.txt`, `token_registration_time.txt`, `token_ttl.txt`) to `s3://actuate-settings/genesis/`. Connector pods will pick up the fresh token on their next read cycle (no restart needed — the refresh loop in `milestone_service.py` polls S3).
3. If the SOAP login itself fails (NAT-side issue): escalate to Genesis IT to restore the network path from our writer host to `gss-clu-mgmtedu.genesis.local`. Provide them the writer's outbound IP (NAT-gateway public IP for that subnet) so they can re-allowlist.

**On Genesis's side (customer-side action even if we work around above):**

- Confirm NAT-restoration is complete for the path to our writer's outbound IP (whatever that is — depends on which ECS/EKS the writer runs from).
- Check Milestone management server side: any auth/credential resets after the NAT event? Stale account binding to old IP?

**Engineering follow-ups (seeded in mark-todos for next week):**

- **Structured token-staleness alarm.** A CloudWatch alarm on `s3://actuate-settings/genesis/token.txt` LastModified > 30 min would have paged us hours before the customer call. Cheap to add — same shape for all 4 S3 paths.
- **Per-customer error visibility in the writer.** Whatever process refreshes tokens must emit a structured WARN per failing customer (`milestone_token_refresh_failed customer=genesis_schools reason=<exception>`), not silently continue. This is the missing signal that turned "minor route blip" into "5h customer-impact incident."
- **Pod-restart playbook gate.** When token-rejection signature is present, skip restart and escalate to token-refresh-pipeline diagnostics directly. Tonight we restarted 24 pods for nothing.
- **Token freshness drift NRQL panel** in the dashboard. Add to `operational-health` topic.
- **Fleet-wide alert-emission audit** to confirm customer's "no alerts customer-wide" claim — the audit query was cancelled mid-investigation. Run it once token is restored to compare pre/post.

## Auto-detection + auto-restart design (APPLIED 2026-05-25 ~00:50 UTC)

**Status: LIVE in production.** Both CloudWatch alarms created and verified. Initial state `INSUFFICIENT_DATA` (normal for new alarms); transitions to OK as datapoints accumulate.

Active alarms in us-west-2 / acct 388576304176:
- `NAT-Instance-Proxy-EKS-InstanceStatusFailed-AutoReboot` — StatusCheckFailed_Instance ≥ 1 for 2× 5-min periods → reboot
- `NAT-Instance-Proxy-EKS-NetworkOutZero-AutoReboot` — NetworkOut < 1024 for 6× 5-min periods → reboot

Both alarm actions: `arn:aws:automate:us-west-2:ec2:reboot` + `arn:aws:sns:us-west-2:388576304176:customer-warnings`.



**Goal:** detect a NAT-proxy hang within ~10 min and auto-reboot, capping customer-impact at ~15-20 min instead of the ~10.5h we saw tonight.

**Detection signals (any one triggers auto-recovery):**

| Signal | Tonight's behavior | Threshold | Alarm shape |
|---|---|---|---|
| `StatusCheckFailed_Instance` ≥ 1 | 1.0 sustained from 15:00 UTC | 2 consecutive 5-min datapoints ≥ 1 | Primary — leading indicator within ~1h |
| `NetworkOut` < 1KB | 0 bytes for 12h | 6 consecutive 5-min datapoints < 1024 bytes (30 min sustained zero traffic) | Secondary — catches "OS healthy but proxy daemon dead" |
| `StatusCheckFailed_System` ≥ 1 | (not seen tonight — hypervisor-level) | 1 datapoint | Tertiary — already covered by EC2 Auto-Recovery if enabled |

**Auto-restart mechanism:** CloudWatch alarm `AlarmActions` set to the AWS-managed EC2 reboot action ARN: `arn:aws:automate:us-west-2:ec2:reboot`. No Lambda, no SSM Automation needed. AWS recognizes this ARN as a special alarm action and reboots the EC2 instance dimensioned in the alarm.

**Concrete alarm specs:**

```bash
# Alarm 1: instance-level status check failures → reboot
aws cloudwatch put-metric-alarm --region us-west-2 \
  --alarm-name "NAT-Instance-Proxy-EKS-InstanceStatusFailed-AutoReboot" \
  --alarm-description "Auto-reboot NAT Instance Proxy when OS-level instance status checks fail. Driving incident: 2026-05-24 Genesis Schools no-alerts (10.5h MTTR)." \
  --metric-name StatusCheckFailed_Instance \
  --namespace AWS/EC2 \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 2 \
  --datapoints-to-alarm 2 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=InstanceId,Value=i-05cf6dc283800e05d \
  --alarm-actions "arn:aws:automate:us-west-2:ec2:reboot" "arn:aws:sns:us-west-2:388576304176:customer-warnings" \
  --treat-missing-data breaching

# Alarm 2: zero network throughput for 30+ min → reboot
aws cloudwatch put-metric-alarm --region us-west-2 \
  --alarm-name "NAT-Instance-Proxy-EKS-NetworkOutZero-AutoReboot" \
  --alarm-description "Auto-reboot NAT Instance Proxy when NetworkOut is essentially zero for 30 min — proxy daemon may have died while OS keeps the listener bound. Driving incident: 2026-05-24 Genesis Schools." \
  --metric-name NetworkOut \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --evaluation-periods 6 \
  --datapoints-to-alarm 6 \
  --threshold 1024 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=InstanceId,Value=i-05cf6dc283800e05d \
  --alarm-actions "arn:aws:automate:us-west-2:ec2:reboot" "arn:aws:sns:us-west-2:388576304176:customer-warnings" \
  --treat-missing-data notBreaching
```

**Both alarms publish to SNS `customer-warnings`** — the same topic the admin-auto-onboarding-schools failures already publish to. Once that SNS topic gets the PagerDuty subscription (per mark-todos next-week item), every NAT-proxy hang AND the downstream cronjob failures both page.

**Recovery time budget after rollout:**
- Detection: ~10 min (alarm threshold)
- EC2 reboot: 2-4 min
- Cron tick to refresh token: up to 5 min
- Connectors pick up fresh token: ~1 min (next read cycle)
- **Total: ~15-20 min** vs tonight's **10.5 hours**

**Risks / caveats:**
- `arn:aws:automate:<region>:ec2:reboot` requires the alarm to have a single InstanceId dimension. If we ever broaden to multiple proxies, each gets its own alarm.
- The "NetworkOut < 1024 for 30 min" alarm could false-positive during a planned maintenance window when traffic is intentionally drained. Mitigate by `actions enable/disable` via tag or by adding a maintenance-window suppression Lambda.
- t3.micro is the smallest burstable EC2 type. Tonight wasn't a CPU/burst-credit exhaustion (CPU was 0.17%) but worth checking. Consider upsizing to t3.small if root cause investigation shows resource exhaustion as the trigger.

**Followup (post-implementation):** monitor MTBF on the NAT proxy reboots. If we end up auto-rebooting it more than once a week, the underlying daemon is the real problem and we should replace the t3.micro NAT-instance pattern with something more durable (AWS-managed NAT Gateway with a private VIF, or a containerized proxy with K8s self-healing).

## Quick-reference commands to watch the recovery

**Check if Genesis Schools TLS endpoint has recovered** (run from a Genesis K8s pod since the route is VPN-only):
```bash
POD=$(kubectl get pods -n rearchitecture --no-headers | awk '/^genesis-70078/ && $3 == "Running" {print $1; exit}')
kubectl exec -n rearchitecture $POD -- timeout 10 curl -sk -o /dev/null -w "code=%{http_code} time=%{time_total}s\n" --max-time 8 \
  https://172.16.254.103:443/ManagementServer/ServerCommandService.svc
```

- `code=200` or `code=400` → TLS handshake succeeded → server is back, refresh should resume on next cron tick
- `code=000` → still broken (SSL connect error)

**Check S3 token freshness** (definitive recovery signal):
```bash
AWS_PROFILE=prod aws s3api head-object --bucket actuate-settings --key genesis/token.txt --query LastModified --output text
```
If newer than the previous "broken" value (`2026-05-24T14:06:01+00:00`), the cronjob succeeded and connectors will pick up the fresh token on their next read cycle (no restart needed).

**Check cronjob run status** (look for non-Failed in latest 2 jobs):
```bash
kubectl get jobs -n admin-auto-onboarding --sort-by=.metadata.creationTimestamp 2>/dev/null | grep schools | tail -3
```

**Tail the latest cronjob attempt's logs** for the actual exception (server-side error class):
```bash
LATEST=$(kubectl get pods -n admin-auto-onboarding --sort-by=.metadata.creationTimestamp 2>/dev/null | awk '/schools/ {print $1}' | tail -1)
kubectl logs -n admin-auto-onboarding $LATEST --tail=40
```

**Restart a Genesis connector pod** (only useful AFTER token has refreshed — otherwise futile):
```bash
kubectl delete pod -n rearchitecture genesis-70078-xxxxx-xxxxx
```

## Confirmed-server-side diagnostics record (2026-05-25 00:07-00:14 UTC)

From inside `genesis-70078-56564fcd69-htl87`:

| Probe | Genesis Schools (172.16.254.103) | Convention Center (172.16.250.114) |
|---|---|---|
| TCP :443 | OK | OK |
| TCP :7563 (recording server) | **Connection refused** | not tested |
| TLS handshake (:443) | CONNECTED but `Cipher is (NONE)`, no cert | CONNECTED, TLSv1.2 `ECDHE-RSA-AES256-GCM-SHA384`, cert `CN=GSS-SRV-MPMS-01.genesis.local` |
| curl HTTPS :443/Management... | code=000 (exit 35, SSL connect error) | code=200 |
| curl HTTP :80/ | code=200 (server alive on cleartext port) | not tested |

The cronjob exception:
```
RuntimeError: Camera list refresh failed with: Failed to update camera list
(HTTPSConnectionPool(host='172.16.254.103', port=443):
 Max retries exceeded with url: /ManagementServer/ServerCommandService.svc
 (Caused by SSLError(SSLEOFError(8,
  '[SSL: UNEXPECTED_EOF_WHILE_READING]
   EOF occurred in violation of protocol (_ssl.c:1010)'))))
```

## NR query templates for future runs

**Fleet-wide alert emissions per Genesis pod (last 2h):**
```nrql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'genesis-%'
  AND (message LIKE '%raise_patrol_alert%'
       OR message LIKE '%alert sent%'
       OR message LIKE '%motion detected%')
SINCE 2 hours ago
FACET container_name
LIMIT 30
```

**Milestone token rejection rate by pod:**
```nrql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name LIKE 'genesis-%'
  AND message LIKE '%Security token invalid%'
SINCE 30 minutes ago
FACET container_name
TIMESERIES 1 minute
```

**Successful Milestone connections (the recovery signal to [[watch-entity|watch]] for after Genesis fixes their server):**
```nrql
SELECT count(*) FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name IN ('genesis-70078', 'genesis-75705')
  AND message LIKE '%connected>yes%'
SINCE 30 minutes ago
TIMESERIES 1 minute
```

## Related

- [[2026-05-22_djangoq-cpu-spike-v8-rollback-verify-scan]] — original surface where the Genesis `172.16.254.103` unreachable was first noted (during a different incident's triage; deferred at the time)
- [[rtsp-components]] § GenesisUrlFramePuller — Genesis 36-bridge architecture
- [[milestone-components]] — Milestone token lifecycle + S3 fallback path
- [[integrations/milestone/_summary]] — Milestone integration overview
- [[2026-04-15_milestone-xprotect-api-and-actuate-integration]] — Milestone API reference; describes S3-based token sharing for "genesis, convention center, federated deployments"
- [[mark-todos]] — incident reference for next-week prevention follow-ups
