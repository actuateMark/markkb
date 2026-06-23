---
title: "DjangoQ CPU High alarm 2026-05-22 — v8 rollback-verify scan saturated admin EC2"
type: concept
topic: operational-health
tags: [incident, cloudwatch, alarm, admin, ec2, pagerduty-gap, observability-gap, intruder-v8, rollback]
created: 2026-05-22
updated: 2026-05-23
author: mark
incoming:
  - topics/operational-health/notes/concepts/2026-05-24_genesis-no-alerts-milestone-token-rejection.md
  - topics/personal-notes/notes/daily/2026-05-22.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-27
---

# DjangoQ CPU High alarm 2026-05-22 — v8 rollback-verify scan saturated admin EC2

## TL;DR

CloudWatch alarm `DjangoQ CPU High` (us-west-2 / acct 388576304176 / instance `i-035d255c2c64bb324` = "Actuate Admin UI Prod") fired at 2026-05-23 00:01 UTC. **Root cause: an engineer's ad-hoc bash scan (`xargs -P 16 aws s3 cp …`) inside a long-lived `admin-scripts` screen session.** The scan was verifying completion of an `intruder-v8 → intruder` model rollback by checking every connector's S3 settings.json for the old model string. Sixteen parallel `aws cli` subprocesses (Python startup + auth per call) saturated the 8-vCPU `t3a.2xlarge` for ~1.5 hours. Mitigated by `renice +19` + `ionice -c 3 idle` on the scan process group; admin web tier had zero 5XX through the spike. Alarm was manually deleted by another engineer at 00:57 UTC rather than waiting for the natural OK transition.

## Timeline (UTC)

| Time | Event |
|---|---|
| earlier 2026-05-22 | Rollback engineer runs `STAGE=prod uv run manage.py swap_ai_model --old-model "EKS to EKS Slicing Microservice (intruder-v8)" --new-model "EKS to EKS Slicing Microservice (intruder)" --skip-deploy --change-reason "Intruder V8 rollback"` from the `admin-scripts` screen on `i-035d255c2c64bb324`. Admin DB swap completes; S3 settings.json files are NOT regenerated (per `--skip-deploy`). |
| 23:22:04 | Same engineer opens a separate `actuate-admin-rollback-v8-slice` screen and fires `./find_v8_sites.sh` — a bash script wrapping `xargs -a /tmp/connector_keys.txt -P 16 -I{} sh -c 'aws s3 cp "s3://actuate-settings/$key" - 2>/dev/null \| grep -q "EKS to EKS intruder-v8" && echo "$key" \| sed -E "s\|^connector-([0-9]+)/.*\|\1\|"'`. Input file: 28,020 keys, sorted lexicographically. |
| 23:16 | First CloudWatch CPU datapoint over threshold: 56.4%. |
| 23:35 | CPU hits 99.9%, stays pinned. |
| 00:01 | Alarm `DjangoQ CPU High` transitions OK → ALARM. Email-only notification via SNS topics `customer-warnings` + `Engineering-Alarms`. Mark receives the email; no PagerDuty. |
| 00:10 | Mark begins investigation; nrql-investigator initially mis-identifies the cause as DjangoQ pod restarts (the NR `container_name = 'djangoq'` is a label on the EKS Django Q workers, completely unrelated to this EC2 host). |
| 00:20 | CloudWatch `describe-alarms` reveals the metric is `AWS/EC2 CPUUtilization` on `i-035d255c2c64bb324` — not Kubernetes. Pivot to SSM. |
| 00:21 | SSM diagnostic reveals the box has no Docker. Top consumers are `python2 /bin/aws s3 cp s3://actuate-settings/connector-NNNNN/settings.json -` processes — dozens concurrent. Load avg 19.6 on 8 vCPU. |
| 00:23 | Process tree traces back to `xargs -P 16` inside `screen -R admin-scripts` (78 days old). Bash history reveals the `swap_ai_model` rollback + `find_v8_sites.sh` chain. Not a runaway — intentional rollback verification. |
| 00:25 | `sudo renice +19 -g $PGID` on the xargs process group; `sudo ionice -c 3 -P $PGID`. All current children inherit the niceness. Admin/Django services (NI=0) now preempt scan workers. |
| 00:35 | Recovery check via NR fails — admin EC2 host has no NR agent. Falls back to CloudWatch ALB metrics: AdminUIHttps target group had **2 total requests in 3 hours** (Saturday evening floor). Zero 5XX errors across the entire spike. |
| 00:55 | Scan completes. Load avg drops 19.62 → 2.82 (1-min). Output file has **701 connector IDs** still matching "EKS to EKS intruder-v8" — not a rollback failure, just the S3 lag from `--skip-deploy` (those connectors will pick up the new model on their next deploy cycle). |
| 00:57 | **Alarm manually deleted via the AWS console** (AdministratorAccess SSO). State at delete: still ALARM. No prior OK transition. |
| 01:42 | Monitor detects alarm no longer exists (`MetricAlarms: []`). |

## What the renice actually did (and didn't)

- **Did**: protect admin web/Q worker responsiveness. NI=0 services preempt NI=19 scan workers. The admin host was responsive to SSM, ALB health checks, and (had there been traffic) user requests throughout.
- **Did NOT**: reduce instance-level `AWS/EC2 CPUUtilization`. The CloudWatch metric measures total CPU consumed, not priority allocation. As long as any process was willing to consume CPU, the metric stayed near 100%. Hence the alarm did not transition OK on its own.

This is the right behavior — renice is for protecting foreground responsiveness, not for changing aggregate utilization metrics. The alarm threshold (50% over 45 min) is the wrong shape for this workload class.

## Three observability gaps surfaced

1. **No PagerDuty.** Alarm fires via SNS to email only. Email-as-pager works for solo work but fails the "is anyone awake" test. Both SNS topics (`customer-warnings`, `Engineering-Alarms`) need PD Events API v2 subscriptions. ~15-30 min wiring job. Tracked in [[mark-todos]] next-week block.
2. **No NR instrumentation on `i-035d255c2c64bb324`.** During recovery verification, the nrql-investigator subagent had nothing on this host to query — no infrastructure agent, no APM, no gunicorn log forwarding. The only NR signal for admin is the EKS-hosted Django Q workers, which don't run on this EC2 box at all. NR-based incident-response on admin is impossible until this is fixed. Trivial to add; needed regardless of any larger admin-tier-migration.
3. **Alarm threshold is wrong shape.** `t3a.2xlarge` at 99% CPU for 1h+ produced zero user impact tonight (zero 5XX, but also only 2 requests through the ALB — Saturday floor). A threshold tuned for "ad-hoc scan saturates admin → bad" needs to be a different metric (admin ALB target response time p95, or admin Q queue depth, or process-class CPU on the Django pods specifically). The current "EC2 CPU > 50% for 45 min" fires too easily and yet too late to be useful — it warns about a state that is sometimes benign (scan running) and sometimes critical (real load) without distinguishing.

## Prevention surfaces

Per [[mark-todos]] next-week block. Five options, mutually compatible:

1. **Sanctioned bulk-S3-scan helper.** A small Python script in admin's `scripts/` dir using boto3 with a shared `s3.Client` + `concurrent.futures.ThreadPoolExecutor`. Eliminates the per-call Python-startup + auth overhead that turned 28k object reads into a 1.5h CPU pin. ~half-day to write + test + document.
2. **Operational policy.** "`admin-scripts` screen on prod EC2 is for surgical commands only — bulk work goes on a utility box." Document in `actuate_admin/CLAUDE.md` or a similar root-level reference. Reduces blast-radius probability without infrastructure change.
3. **Move admin web tier off the single EC2.** ECS/EKS behind autoscaling. Eliminates the whole class of "one process pegs the admin tier" issues. Bigger lift, probably overlaps with [[mark-todos|§5 Fleet Architecture]] rethink.
4. **Better alarm shape.** Replace `EC2 CPUUtilization > 50% for 45 min` with `ALB TargetResponseTime p95 > X for 5 min` (or similar user-facing latency proxy) so the alarm correlates with actual user pain instead of "something is busy."
5. **NR infrastructure agent** on the EC2 host (item 2 in "observability gaps" above).

## The 701-line output — what it means

`/tmp/eks_v8_sites.csv` ended with 701 connector IDs whose S3 settings.json still contained "EKS to EKS intruder-v8" at the time of the scan. Pre-`swap_ai_model` baseline is unknown but presumably all ~28k carried the v8 string. After `swap_ai_model --skip-deploy`:

- **Admin DB is the source of truth** — it now reflects the new (`intruder`, not `intruder-v8`) model assignment for every site.
- **S3 settings.json is downstream artifact** — regenerated by the settings-generator on the next deploy. Without `--skip-deploy`, the swap would have triggered redeploys for every affected site.
- **701 / 28,020 = 2.5%** — these are connectors that haven't been redeployed since the swap. They will pick up the new model on their next normal deploy cycle (image bump, settings update, scheduled refresh, etc.).

If the rollback engineer needs the S3 state to converge faster, options are:
- Manual redeploy via the connector_deployer for the 701 affected sites
- Wait for natural redeploy cycles (typically days; varies by customer)
- Add a one-off "force S3 settings refresh" management command if this pattern recurs

Not an incident artifact. Just the inherent lag of `--skip-deploy`.

## Three engineers, one incident — coordination note

- **Rollback engineer** (running the v5 split-intruder + v8 rollback): ran the swap + verify scan from the prod admin EC2 shell.
- **Admin user**: deleted the alarm at 00:57 UTC while still in ALARM state — likely saw the page, eyeballed the box, judged safe, and dismissed it.
- **Mark**: paged at 00:01 UTC, investigated, applied the renice mitigation, wrote this note.

Monday Slack thread to align on:
- What v8 → intruder rollback was about (driver? cohort?)
- Whether the 701 lagging connectors need force-redeploy
- Whether the alarm should be recreated (and at what threshold)

## Related

- [[mark-todos]] § "Seeded for next week (2026-05-26 / 2026-05-27)" — PagerDuty wiring + ad-hoc-scan prevention follow-ups
- [[2026-05-22_gnome-terminal-focus-steal-fix]] — unrelated, but same day
- (participant names omitted per no-naming-in-incidents norm)
- [[2026-05-22|today's daily note]]
