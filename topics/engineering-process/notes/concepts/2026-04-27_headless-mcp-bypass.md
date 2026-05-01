---
title: "Headless MCP-bypass auth flow (NR + Atlassian REST wrappers)"
type: concept
topic: engineering-process
tags: [automation, mcp, new-relic, atlassian, headless, subagent, cron, runbook]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-05-01
---

# Headless MCP-bypass auth flow

Stdlib-only Python wrappers under `~/.claude/lib/` that let subagents and `claude -p` cron jobs talk to [[new-relic|New Relic]] + Atlassian without going through MCP. Bypasses the OAuth callback flow that doesn't work in non-interactive contexts.

See `mark-todos.md §13` for the workstream this implements.

## Why

MCP servers (NR, Atlassian) authenticate per-Claude-Code-subprocess. Each subagent and each headless `claude -p` cron run gets a fresh MCP session that needs an interactive OAuth handshake. Subagents can't satisfy interactive prompts → they hang indefinitely. Cron `claude -p` runs without MCP creds → they fail with "tool unavailable."

Failure modes that motivated this: 2026-04-27 morning daily-scope fan-out — three NR-touching subagents stalled 600s before kill; same morning the `overnight-check.service` and `jira-sync.service` cron jobs both wrote FAILED stubs.

## What

Two single-file Python scripts, stdlib only (no `requests`, no extra deps):

- **`~/.claude/lib/nr_query.py`** — NerdGraph REST wrapper.
  - Reads NRAK User API key from `~/.config/nr/api-key` (0600).
  - Default account `3421145` (Connector-EKS); `--account N` for others.
  - Library: `from nr_query import nrql; rows = nrql("FROM ... SINCE 1 hour ago")`.
  - CLI: `python3 ~/.claude/lib/nr_query.py "<NRQL>"` → prints JSON array of rows.

- **`~/.claude/lib/atlassian_query.py`** — Jira REST wrapper.
  - Reads `{email, token, site}` JSON from `~/.config/atlassian/api-token` (0600).
  - HTTP Basic auth (no MCP). Cursor pagination via `/rest/api/3/search/jql`.
  - Library: `from atlassian_query import search_jira, get_issue`.
  - CLI: `python3 ~/.claude/lib/atlassian_query.py search "<JQL>" --fields summary,status,priority,issuetype,project --max-results 50`.
  - CLI: `python3 ~/.claude/lib/atlassian_query.py issue CS3-31`.

## Setup (one-time, per machine)

### NR User API key

1. Visit <https://one.newrelic.com/api-keys> → **Create a key** → type **User**, name e.g. `claude-code-headless`.
2. Save:
   ```bash
   mkdir -p ~/.config/nr && chmod 700 ~/.config/nr
   printf '%s' 'NRAK-XXXXXXXXXXXXXXX' > ~/.config/nr/api-key
   chmod 600 ~/.config/nr/api-key
   ```
3. Verify:
   ```bash
   python3 ~/.claude/lib/nr_query.py "SELECT count(*) FROM Log SINCE 1 minute ago"
   ```
   Should return `[{"count": <number>}]` within ~1s.

### Atlassian (Jira) API token

1. Visit <https://id.atlassian.com/manage-profile/security/api-tokens> → **Create API token** (label e.g. `claude-code-jira-sync`).
2. Save (replace the placeholders):
   ```bash
   mkdir -p ~/.config/atlassian && chmod 700 ~/.config/atlassian
   cat > ~/.config/atlassian/api-token <<'EOF'
   {"email": "<your-actuate-email>", "token": "ATATT3xFfGF0...", "site": "https://actuate-team.atlassian.net"}
   EOF
   chmod 600 ~/.config/atlassian/api-token
   ```
3. Verify:
   ```bash
   python3 ~/.claude/lib/atlassian_query.py issue CS3-31 | jq '.fields.summary'
   ```

## Bridges

### `nrql-investigator` agent

- `~/.claude/agents/nrql-investigator.md` has `Bash` in its tools list and a "How to Run NRQL" section that defaults to the wrapper.
- MCP NRQL tools are kept as fallback for **interactive parent-context only** — they hang in subagent / cron contexts.
- Non-NRQL MCP tools (`list_recent_issues`, `analyze_*`, `get_entity`, etc.) have no wrapper yet; they remain MCP-only and gracefully degrade in headless contexts.

**Caveat:** Claude Code caches agent definitions per session. After editing the agent file, an existing session keeps the old tools list — `/clear` or a fresh session is required for the running session to pick up new tools. Cron `claude -p` invocations always start fresh and pick up edits automatically. Daily `/daily-scope` runs in fresh sessions too.

### `overnight-check.service` cron

- Script: `~/bin/overnight-check.sh`. Delegates NR queries to `nrql-investigator` subagent — picks up the wrapper through the updated agent definition.

### `jira-sync.service` cron

- Script: `~/bin/jira-sync.sh`. Prompt directly invokes the wrapper via Bash:
  ```
  python3 /home/mork/.claude/lib/atlassian_query.py search "..." --fields ... > /tmp/jira-sync.json
  ```
  No MCP. Verified working 2026-04-27.

## Verification

End-to-end smoke test (anyone; no parent-context needed):

```bash
# NR
python3 ~/.claude/lib/nr_query.py "FROM K8sContainerSample SELECT count(*) WHERE clusterName = 'Connector-EKS' AND reason = 'OOMKilled' FACET containerName SINCE 24 hours ago LIMIT 5"

# Atlassian (Mark's open queue)
python3 ~/.claude/lib/atlassian_query.py search "assignee = currentUser() AND statusCategory != Done" --max-results 5 | jq -r '.[] | "\(.key) \(.fields.summary)"'

# Subagent path (general-purpose, since nrql-investigator may need /clear)
# In Claude Code: spawn a Task agent with the wrapper command in the prompt.
```

Expected: results within ~1s for NR, ~2s for Atlassian, no auth prompts, no stalls.

## Failure modes + handling

- **`NR API key not found at ...`** — credential file missing; redo Setup.
- **`NR HTTP 401`** — key revoked / mistyped; mint a new one and replace.
- **`NR HTTP 429`** — rate limited (NerdGraph quotas); retry with backoff. Not common at our query volumes.
- **`NR returned null nrql block (account access?)`** — the API key user lacks query access to the account; check NR account permissions.
- **`Jira HTTP 401`** — token expired (Atlassian tokens don't expire automatically, so this means it was revoked) or wrong email. Re-mint.
- **`Jira HTTP 403`** — account lacks Jira access; not normal for an Actuate engineer.

## Related

- [[automation-overnight-check]] — cron service that benefits from this
- [[automation-jira-sync]] — cron service that benefits from this
- [[skill-daily-scope]] — morning fan-out; uses `nrql-investigator` subagents
- `mark-todos.md §13` — workstream
- `mark-todos.md §11e` — minipc cronify-friendly refactor; this wrapper is what §11e referenced as `nr_query.py`
- [[nr-connector-query-cookbook]] — query templates that work with the wrapper unchanged
- [[security-hardening-checklist]] — credential file perms (0600) follow this guidance
