---
title: "Runbook: Credential & MCP-server expiry recovery"
type: concept
topic: runbooks
tags: [runbook, auth, aws, sso, mcp, atlassian, newrelic, github, kubefwd, preflight]
created: 2026-04-29
updated: 2026-04-29
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-29.md
  - topics/runbooks/_backlog.md
  - topics/runbooks/_summary.md
  - topics/runbooks/notes/concepts/2026-04-30_detecting-jira-sync-staleness.md
incoming_updated: 2026-05-01
---

# Credential & MCP-server expiry recovery

## When this applies

A previously-working tool call fails with an auth-related error — typically at the start of the day, after lunch, after a session restart, or mid-fan-out when a previously-fresh credential ages out. Hits are frequent enough that the morning routine has a dedicated **preflight step** ([[skill-daily-scope]] Step 2bb) to catch them up-front.

## Symptoms

| Tool / source | Failure mode |
|---|---|
| `aws <anything> --profile prod` | `Error when retrieving token from sso: Token has expired and refresh failed` |
| `mcp__atlassian__*` calls | "No matching deferred tools found" (MCP detached) or 401 |
| `mcp__newrelic__*` calls | MCP detached / NRQL returns auth error |
| `mcp__kubefwd__*` calls | Connection refused / MCP not connected |
| `gh ...` | `gh auth status` shows expired token |
| Atlassian MCP read-only failed mid-fan-out | Server-side session expired |

## Diagnose

Identify which credential is the problem. The 30-second batch:

```bash
AWS_PROFILE=prod aws sts get-caller-identity 2>&1 | head -3
gh auth status 2>&1 | head -10
```

For MCP servers, attempt a low-cost call (e.g. `mcp__atlassian__atlassianUserInfo`, `mcp__newrelic__list_available_new_relic_accounts`, `mcp__kubefwd__get_quick_status`); failure means the server is detached or the underlying session expired.

## Fix

| Credential | Recovery command (run by user) |
|---|---|
| AWS prod SSO | `aws sso login --profile prod` |
| AWS dev-eu SSO | `aws sso login --profile dev-eu` |
| GitHub | `gh auth login` |
| Atlassian MCP | `/mcp` in the Claude Code prompt to reconnect (re-auths in browser) |
| [[new-relic|New Relic]] MCP | `/mcp` to reconnect; if that fails, restart the MCP server config |
| Kubefwd MCP | Start kubefwd locally; ensure `mcp__kubefwd__*` tools list returns |

**Order of operations when multiple are stale:** batch the asks. The user runs all the SSO logins / `/mcp` reconnects in one go before resuming the work. Don't drip-feed remediation requests; the cost of a 30-second batched fix is much lower than running fan-out work, hitting an expiry, asking, retrying, hitting another, asking again.

## Verify

Re-run the tool that failed. For AWS SSO specifically:

```bash
AWS_PROFILE=prod aws sts get-caller-identity 2>&1
# Expect a JSON blob with the right account_id (388576304176 for prod)
```

For MCP, attempt the same low-cost call as in *Diagnose* — should return data.

## Prevent

The morning routine ([[skill-daily-scope]] Step 2bb) preflights every credential the day's planned fan-out items will need. User directive 2026-04-23: *"we do NOT want failed tasks we could mitigate by following a simple checklist."* Run the preflight even if the day's work "looks like it won't need much."

The minipc cache ([[skill-daily-scope]] Step 2ba) reduces NR-MCP dependency for routine morning health checks — if the cache is fresh (<65 min), skip the NR-MCP preflight entirely. See [[2026-04-24_skills-audit-script-candidates]] for why.

If a session repeatedly hits expiry mid-fan-out, the operational gap is in the schedule, not the recovery — surface to the user that "we should probably preflight broader at session start" rather than adding more reconnect logic.

## Cross-refs

- [[skill-daily-scope]] Step 2bb (preflight checklist) and Step 2ba (cache-as-primary)
- [[2026-04-24_skills-audit-script-candidates]] — why the minipc cache exists
- [[runbooks/_summary|Runbooks]]
