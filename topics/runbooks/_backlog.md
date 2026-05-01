---
title: "Runbooks Backlog"
type: backlog
topic: runbooks
created: 2026-04-29
updated: 2026-04-30
author: kb-bot
---

# Runbooks Backlog

Candidate runbooks identified but not yet written. Keep this list short — write one when the situation comes up again, capture it while it's fresh, and tick it off here. Each row should follow the symptom→diagnose→fix→verify→prevent shape used in the existing runbooks.

Trigger to write: hitting the situation a 2nd time + recognising you'd already lost context once.

## Operational

- [ ] **VPA learning-loop drift detection** — how to spot when a pod's VPA recommendation has wandered below safe minima before it OOMs. Cross-link [[2026-04-23_oom-surge-connector-limit-drift]].
- [ ] **Connector deploy chain: env-var flip via [[kubernetes-deployments]]** — pattern for `AUTOPATROL_EMIT_CLEANUP_SIGNALS=true`-style flags that live in cluster-values.yaml, not the connector image. Cross-link §3 Step F.
- [ ] **Cleanup-Lambda DLQ drain** — what to do when `cleanup_lambda_dlq_depth` is non-zero. Cross-link `~/.claude/skills/dashboard-check/config/signals.json`.

## Investigation

- [ ] **NRQL LIKE-pattern gotchas** — escape rules, when to use `RLIKE`, common mistakes. Currently lives partially in CLAUDE.md; formalize as runbook.
- [ ] **NR deep-link broken — onenr.io short-codes** — `one.newrelic.com` URLs strip query params; use short codes or `staticChartUrl` PNGs instead. Currently in CLAUDE.md.
- [ ] **Atlassian / NR / kubefwd MCP detached mid-fan-out** — partially covered in [[2026-04-29_credential-expiry-recovery]] but worth a separate "what to do if it dies in the middle of a multi-step Jira write" runbook.

## Deploy / Release

- [ ] **Post-merge stage rollback** — when stage deploy goes red, how to revert (helm chart pin / [[kubernetes-deployments]] commit revert).
- [ ] **[[argocd|ArgoCD]] out-of-sync remediation** — `argocd_out_of_sync_count` signal goes yellow/red.
- [ ] **Library version pin shift after stable publish** — actuate-libraries main → CodeArtifact stable, downstream pins. Cross-link [[feedback_library_version_shift]].

## IaC

- [ ] **Terragrunt apply-from-stage** — the right invocation order, where state lives, what to watch out for. Currently scattered across PR comments.
- [ ] **Manual TF state surgery** — when import / state mv is required (rare, dangerous, document carefully).

## Process / Discipline

- [ ] **Mark-todos `[x]` accumulation** — pre-2026-04-27 pattern; how to do same-day distribution properly per the global Task Completion Ritual.

## Done — moved to topic

- ✅ [[2026-04-29_iam-access-denied-missing-resource-arn]] — IAM AccessDenied for missing GSI/resource ARN
- ✅ [[2026-04-29_credential-expiry-recovery]] — AWS SSO + MCP server expiry batch recovery
- ✅ [[2026-04-29_iac-live-drift-discovery]] — finding hand-built AWS resources outside IaC
- ✅ [[2026-04-30_stage-cleanup-vch-verify]] — 24h soak verify after VCH `no_patrols` emit changes
- ✅ [[2026-04-30_connector-oomkill-oneoff-bump]] — per-pod limit bump while §18 fleet fix is in flight
- ✅ [[2026-04-30_detecting-jira-sync-staleness]] — wedge detection + manual recovery for jira-sync cron
- ✅ [[2026-04-30_camera-ui-login-tsx-audit-flag]] — decision tree for the recurring `Login.tsx` dirty-tree

## Existing runbooks elsewhere (cross-linked, not moved)

- [[2026-04-20_cleanup-lambda-runbook]] (autopatrol topic) — cleanup Lambda morning checks
- [[2026-04-20_lambda-creation-and-tuning-playbook]] (engineering-process topic) — post-hoc lambda build/tune recipe
- [[partner-api-credential-runbook]] (external-api topic) — partner credential rotation

## Discipline

This file is the runway, not a contract — items can be added, removed, or de-prioritized as the operational landscape shifts. Write a runbook when you'd benefit from one, not when the list says you should.
