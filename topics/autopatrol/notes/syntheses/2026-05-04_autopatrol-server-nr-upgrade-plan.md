---
title: "Plan: AutoPatrol Server New Relic instrumentation upgrade"
type: synthesis
topic: autopatrol
tags: [autopatrol, autopatrol-server, new-relic, observability, instrumentation, dashboard, plan]
jira: "ENG-"
created: 2026-05-04
updated: 2026-05-05
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-05-04.md
  - topics/personal-notes/notes/daily/2026-05-05.md
incoming_updated: 2026-05-08
---

## 2026-05-05 update — dashboard monitoring landed; structured-logging scope reassessed

**Done today:**
- Three dashboard signals (`autopatrol_server_patrol_summary_rate`, `_error_rate`, `_cnctnfail_rate`) synced to Firebat's `~/.claude/skills/dashboard-check/config/signals.json` and verified rendering — first dashboard run that includes them returned green/4, green/0, green/0 respectively.
- `_error_rate` NRQL hardened: was `WHERE level='ERROR'` only (which would have returned 0 forever — see investigation below); now `WHERE (level='ERROR' OR message LIKE '% - ERROR - %')`. Dual-match means the signal works today via the text-format prefix and stays correct after structured logging ships.
- `_cnctnfail_rate` LIKE patterns verified against the actual emit strings in `patrol_aggregation/patrol_summarizer.py:172,176` — correctly wired; the 0 reflects no real connection failures in the 24h window, not a pattern miss.

**NR investigation findings (changes the scope of PR #2):**

A direct keyset/coverage check on `Log WHERE container_name='autopatrol-server'` over 24h showed:
- 2,583 records present — ingestion is fine
- `level` attribute is queryable on only 3 records (startup lines that happen to emit JSON); for app logs it's text-prefix only
- `patrol_id`, `site_id`, `camera_id` are not queryable as top-level attrs; they live inside `message`
- NR auto-detects and parses JSON stdout — confirmed by the 3 startup records having auto-promoted JSON keys
- Baseline: `create-detection-window` (Python service same cluster) emits JSON and has `level` queryable across 100% of records — **in-house precedent exists**; we wouldn't be the first
- `smtp-frame-receiver` is in the same text-only tier as autopatrol-server

**Implication for PR #2:** the original plan's framing ("With structured output, NR splits `level`, `patrol_id`, `site_id`, `camera_id` into queryable attributes") was half-right. A formatter-only change (swap `basicConfig` for `JsonFormatter`) gives:
- ✅ `level` queryable across 100% of records
- ✅ `message` clean of the timestamp/logger/level prefix
- ❌ Does NOT auto-promote `patrol_id`/`site_id`/`camera_id` — those are inside f-strings, stay embedded in `message`. Promoting them requires call-site changes (`logger.info("event", extra={"patrol_id": pid})`)

**Across-the-board status:** `vms-connector`, `actuate_admin`, `actuate-inference-api`, `actuate-libraries`, `autopatrol_onboarder` ALL use stdlib `logging.basicConfig` with text format. None use `python-json-logger` or `structlog`. PR #2 is therefore stack-wide tech debt, not a single-service fix.

**Revised PR #2 framing:** still ship `python-json-logger` formatter swap, but don't oversell it. Real gains: queryable `level`, clean `message`, easier to grep. The bigger structured-fields win is gated on call-site rewrites — defer to a follow-up PR or pick the highest-traffic call sites only.

## Why this exists

We shipped a patrol-summary fix in autopatrol-server (PRs #26 main, #27 dev/rev2 → image 0.1.25) on 2026-05-04. When verifying in production, we discovered NR coverage on [[autopatrol-server]] is **infra and stdout logs only** — no APM, no structured logging, no alerts, no dashboard signals. The CLAUDE.md note "no NR instrumentation" meant APM was missing entirely, not just light coverage. This workstream upgrades the whole observability layer.

## Blocker: NR license-key secret across namespaces

The `newrelic` secret (containing the license key) lives in namespace `newrelic` but autopatrol-server pod is in namespace `autopatrol-server`. Kubernetes can't read cross-namespace secrets directly. Options before coding:

1. **Reflector / External Secrets** — replicate the secret into `autopatrol-server` namespace via a controller
2. **SealedSecret duplication** — manually duplicate via SealedSecret in the target namespace (supported by [[kubernetes-deployments]])
3. **Check for existing copies** — other namespaces may already have a copied secret; leverage that pattern

**Blocker severity:** blocks PR #1. Investigate before starting work.

## Done in session (2026-05-04)

- Dashboard signals added to `~/.claude/skills/dashboard-check/config/signals.json`:
  - `autopatrol_server_patrol_summary_rate` (detector for silent breaks; threshold yellow<2/h, red<1/h). **Also serves as the deploy-acceptance-test** for PR #26 — first non-zero count in prod logs proves the fixed code path renders correctly.
  - `autopatrol_server_error_rate` (percent-based spike detector)
  - `autopatrol_server_cnctnfail_rate` (connection-failure spike detector)

**Cluster name oddity**: NR k8s integration tags `clusterName='Connector-EKS'` even though AWS cluster is `inference-eks-Ny9n` and region is us-west-2. Same physical EKS, single NR account 3421145. Don't hunt for a separate inference-eks NR account — there isn't one.

## Remaining work (multi-PR, each its own cycle)

Each ships separately through the release chain documented at [[2026-05-04_autopatrol-server-release-process]].

### PR 1: NR Python APM agent (blocked on secret cross-namespace decision)

Add `newrelic` to `pyproject.toml`. Wire `newrelic.agent.initialize()` in `server/app.py` **BEFORE Flask import**. Add env vars:
- `NEW_RELIC_LICENSE_KEY` (fetched from cross-namespace secret — **blocker above**)
- `NEW_RELIC_APP_NAME=autopatrol-server`
- `NEW_RELIC_LOG_LEVEL=warning`

**Blocker**: Resolve secret access pattern before implementing.

### PR 2: Structured logging (lowest-risk, ship first)

Swap `logging.basicConfig` for `python-json-logger` or `structlog`. NR Logs currently sees raw stdout strings. With structured output, NR splits `level`, `patrol_id`, `site_id`, `camera_id` into queryable attributes. Currently we LIKE-match on message bodies — brittle and expensive.

**Why first**: No cross-namespace blocker, immediately improves NR Logs query performance for PR #3 (alerts).

### PR 3: NR alert conditions (NR-side, possibly IaC)

Define alert conditions on NR:
- **Silent-break detector**: patrol-summary log rate drops to 0 over 30min (analog of [[2026-04-23_release-acceptance-criteria]])
- **Error-log spike**: ERROR lines exceed baseline
- **CNCTNFAIL spike**: connection-failure spike beyond threshold
- **Container restart count**: restart loop indicator

**Investigation step**: Check if NR alerts are managed via Terraform in `aegissystems/` repos (e.g., `terraform/newrelic/` or via Helm values in [[kubernetes-deployments]]). Don't open PRs until we know the IaC pattern — alerts may need to land in [[kubernetes-deployments]] (as Helm annotations) rather than a new repo.

### PR 4: Helm chart env vars (kubernetes-deployments)

Once PR #1 (APM agent) lands in main, update `deployments/applications/autopatrol-server/templates/deployment.yaml`. Currently that template has zero env vars — pure image+resources+nodeSelector. Need:

```yaml
env:
  - name: NEW_RELIC_LICENSE_KEY
    valueFrom:
      secretKeyRef:
        name: newrelic  # or the replicated secret name
        key: licenseKey
  - name: NEW_RELIC_APP_NAME
    value: autopatrol-server
  - name: NEW_RELIC_LOG_LEVEL
    value: warning
```

Also update the [[argocd|ArgoCD]] Application to trigger a new rollout.

## Order of operations

1. **Structured logging** (PR #2) — unblocked, immediate NR Logs improvement
2. **NR APM agent** (PR #1) — blocked until secret pattern decided; ship after secret works
3. **NR alerts** (PR #3) — blocked until IaC pattern identified; ship after investigation
4. **Helm chart env vars** (PR #4) — blocked until PR #1 lands to main; ship immediately after

## Cross-references

- [[autopatrol-server]] — entity, codebase architecture
- [[2026-05-04_autopatrol-server-release-process]] — two-repo release chain (code → ECR → k8s)
- [[2026-04-23_release-acceptance-criteria]] — silent-break pattern that motivated this workstream
- [[2026-05-04_autopatrol-server-patrol-summary-fix]] — the PR #26/27 that exposed the instrumentation gap
