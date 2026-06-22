---
title: "Runbooks"
type: topic
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
---

Central index for operational runbooks — recipes for diagnosing and fixing recurring or familiar production issues in Actuate systems.

## Scope

Runbooks here are cross-cutting fixes that don't belong to a single service topic. Service-specific runbooks may live in their service topic but should be cross-linked here for discoverability. A runbook follows the pattern: symptom → diagnose → fix → verify → prevent.

## Scattered Runbooks (Future Consolidation)

These exist elsewhere in the KB; future work may move them here:

- [[2026-04-20_cleanup-lambda-runbook]] (autopatrol topic) — cleanup Lambda morning checks
- [[2026-04-20_lambda-creation-and-tuning-playbook]] (engineering-process topic) — post-hoc lambda build/tune recipe
- [[partner-api-credential-runbook]] (external-api topic) — partner credential rotation

## Runbooks in This Topic

- [[2026-04-29_iam-access-denied-missing-resource-arn]] — Diagnosing and fixing IAM AccessDeniedException for missing GSI or resource ARN
- [[2026-04-29_credential-expiry-recovery]] — Batch recovery for expired AWS SSO + MCP-server sessions (Atlassian, [[new-relic|New Relic]], kubefwd, GitHub)
- [[2026-04-29_iac-live-drift-discovery]] — Finding & remediating live AWS resources that exist outside Terraform
- [[2026-04-30_stage-cleanup-vch-verify]] — 24h soak verify for vms-connector PRs touching `emit_no_patrols_signal` (DDB scan + dashboard-history check)
- [[2026-04-30_connector-oomkill-oneoff-bump]] — Per-incident triage for a single connector pod OOMKilling (raise `limits.memory`); §18 is the fleet-wide fix
- [[2026-04-30_detecting-jira-sync-staleness]] — Detecting + recovering when the daily jira-sync cron wedges and mark-todos's Jira queue silently drifts
- [[2026-04-30_camera-ui-login-tsx-audit-flag]] — Decision tree for retiring the recurring `camera-ui main` dirty `Login.tsx` audit-flag
- [[2026-06-02_rds-extended-support-upgrade-runbook]] — End-to-end upgrade of three PostgreSQL databases (12.22, 13.20) off AWS RDS Extended Support surcharges to PG16. Covers pre-flight, single-step major upgrade, post-upgrade validation, and rollback plan (~$613/mo savings total).

## Backlog

[[_backlog|Candidate runbooks not yet written]] — keep short, capture while fresh, write on second hit. Includes operational (OOMKill bumps, cleanup-Lambda DLQ), investigation (NRQL gotchas, NR deep-links), deploy/release (stage rollback, [[argocd|ArgoCD]] out-of-sync), IaC (Terragrunt apply-from-stage, state surgery), and process items.

## Pattern (every runbook follows this shape)

1. **When this applies** — scan-friendly trigger description so future-you can identify the right runbook fast
2. **Symptoms** — concrete failure modes with example error strings or log lines
3. **Diagnose** — commands to identify the specific cause
4. **Fix** — the actual recovery steps, with rollback baseline if destructive
5. **Verify** — how to confirm the fix worked
6. **Prevent** — what to add (signal, preflight, guard) so the next instance is caught earlier or auto-handled
7. **Cross-refs** — back to topic summary, related runbooks, source incidents
