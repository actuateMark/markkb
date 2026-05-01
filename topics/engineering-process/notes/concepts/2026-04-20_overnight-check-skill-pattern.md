---
title: "Pattern: Building an Overnight-Check Skill Per Project/Repo"
type: concept
topic: engineering-process
tags: [pattern, skills, claude-code, ops, health-check, observability, playbook]
created: 2026-04-20
updated: 2026-04-20
author: kb-bot
incoming:
  - topics/autopatrol/notes/entities/autopatrol-cleanup-lambda.md
  - topics/engineering-process/notes/concepts/2026-04-23_release-acceptance-criteria.md
incoming_updated: 2026-05-01
---

# Pattern: Building an Overnight-Check Skill Per Project/Repo

For any non-trivial Actuate service — Lambda, pod, cronjob, API — build a dedicated "[[automation-overnight-check|overnight check]]" skill that wraps the essential health-verification commands into a single invocation. Captures the ops knowledge in a reusable, repeatable form, and makes it easy to run from any Claude Code session.

**Canonical examples:**
- `/autopatrol-check` (`~/.claude/skills/autopatrol-overnight-check/SKILL.md`) — patrol pipeline health (cronjobs, connector pods, SQS flow, server errors)
- `/autopatrol-cleanup-lambda-check` (`~/.claude/skills/autopatrol-cleanup-lambda-check/SKILL.md`) — the newer stale-schedule cleanup Lambda pipeline

When you build a new service or Lambda, build its check skill alongside. Thirty minutes upfront saves hours of re-deriving queries later.

## Why a skill and not just a runbook

A runbook is a KB note humans read. A skill is a prompt Claude Code executes. Both matter:
- **Runbook** (KB concept note) — command reference, explanations, troubleshooting prose. Good for deep-dive reading.
- **Skill** — the executable version. Runs the checks, formats the output. Good when you just want "is it healthy right now?"

Build the runbook first; the skill is a structured wrapper around it. They evolve together — updates to one should update the other.

## Anatomy of a good overnight-check skill

Looking at `/autopatrol-check` + `/autopatrol-cleanup-lambda-check`, the pattern that works:

### Frontmatter

```yaml
---
name: <repo-or-service>-check
description: >
  Health check for <service>. Use when user asks "<trigger phrases>",
  "<overnight phrasing>", "<service name> health", etc. Distinct from
  /<sibling-skill> which covers <related-scope>.
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Agent
  - mcp__newrelic__execute_nrql_query
  # + whatever tools the checks use (kubectl → Bash; AWS CLI → Bash; etc.)
---
```

Put enough trigger phrases in `description` that any phrasing of "check X" resolves the skill. Name distinctions from sibling skills explicitly so the model doesn't confuse them.

### Environment config table

Every Actuate service exists in at least two envs (stage + prod). Usually also EU. Spell out:

| Environment | Account | Region | Queue/DB/endpoint | Image tag |
|---|---|---|---|---|

User-facing commands and NRQL queries refer to `<env>` — the skill picks the right account/queue/table per `<env>` arg.

### Arguments

Conventional argument handling:
- No arg or default (usually stage) — the safest default
- `prod`/`staging`/`dev` — explicit env
- Specific identifier (site id, schedule id, pod name) — focus mode

Keep args few. Defaults matter.

### Checks in order, independent ones parallel

Enumerate checks as numbered sections. Each section has:
1. A one-line purpose
2. The actual command(s) — AWS CLI, `kubectl`, NRQL via `mcp__newrelic__execute_nrql_query`, etc.
3. "Healthy" criteria in plain English
4. "Flag if" criteria

Where checks are independent (e.g. queue depth + Lambda config + DDB state), tell the model to run them in parallel. The skill runtime supports it.

### Output format

Prescribe a markdown report skeleton. Consistent format = easier for user to eyeball daily.

```markdown
## <Service> Health Check — <date> (<env>)

### <Topic 1>
<data>

### <Topic 2>
<data>

### Issues found
- [list concerns, or "No issues found — healthy"]
```

Include threshold guidance under each table so the user doesn't need to memorize "what counts as healthy?"

### Interpretation section

"What does X mean?" context that isn't obvious from the numbers alone. Examples:
- "Immix returns patrolStatus=Failed even on success — compare internal patrol_status instead"
- "CNCTNFAIL is Immix-side, not our pipeline"
- "Patrol_exit vs site_disabled mix — the former is ~3500/day baseline, the latter rare"

This lets the model surface issues intelligently instead of just dumping metrics.

## Content checklist

Before committing a new check skill, it should cover:

### Upstream inputs to the service
- What SHOULD be arriving (counts, rates, sources)?
- How to measure did-arrive (log counts, queue depth, events)?

### The service itself
- Invocation count / pod count / job count over 24h
- Error rate
- Duration / throughput baseline
- Config snapshot (env vars, feature flags, kill switches)

### Downstream outputs
- What SHOULD the service produce (messages, API calls, DB writes)?
- How to verify (DLQ state, downstream log counts, DB row deltas)?

### Correlation
- Upstream count vs service invocations vs downstream outputs — all three should roughly equal each other (modulo batching/dedup). Gaps indicate loss.

### Alarm and escalation state
- Is the alarm armed? Has it fired recently?
- DLQ count (always 0 is the bar)

### Known-good baselines
- Specific numbers from NR 7-day or 30-day queries — not "should be high" but "should be ~3500/day"
- Expected day-over-day variance

## Maintenance

- **Update when the service changes**: adding a new env var, new bucket, new signal type → add check for it
- **Re-baseline every ~3 months**: what was 3500/day yesterday might be 5000/day today
- **Fold in new failure modes**: any incident you'd wish the check had caught → add it

## Cross-session re-use

A well-written check skill is invokable from any Claude Code session without context. The user types `/my-service-check` and gets a fresh report. No need to remember NRQL syntax, ARNs, or thresholds. That's the whole win.

## Related

- `/autopatrol-check` — first canonical example
- `/autopatrol-cleanup-lambda-check` — recent application of this pattern to a new service
- [[2026-04-20_cleanup-lambda-runbook]] — the runbook the cleanup-check skill wraps
- [[2026-04-20_lambda-creation-and-tuning-playbook]] — broader Lambda-ops playbook; this pattern is one practice within it
