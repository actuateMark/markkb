---
title: "Gmail tier-1 digest — design for passive inbox surfacing"
type: synthesis
topic: personal-laptop
tags: [gmail, tier-1, firebat, digest, productivity, design]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
outgoing:
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/engineering-process/notes/syntheses/2026-04-30_three-tier-routine-check-pattern.md
[]
incoming:
  - topics/personal-notes/notes/daily/2026-05-12.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-13
---

# Gmail tier-1 digest — design

> **Status (2026-05-12):** Designed. Not yet built. Triggering use case is a "slightly dead thread" about v5 inference-api testing that the user wants to keep better tabs on; the broader goal is passive surfacing of critical-but-quiet email.
> **Mark-todos:** §31 (new).
> **Tier:** Tier-1 firebat script — zero tokens per check, runs nightly via systemd `--user` timer, writes digest to disk for morning ritual consumption.

## Problem

User has email threads that go quiet but remain action-required — replies-pending from external partners, dead threads about active workstreams (e.g., v5 inference-api testing), un-acked invoices/contracts. Manual Gmail-check is unreliable when the inbox is heavy. Need passive surfacing that converts inbox state into a structured digest in the morning ritual.

## Existing pattern this slots into

Per [[2026-04-30_three-tier-routine-check-pattern]], tier-1 routine checks live on `mork-firebat`:

- Script at `~/bin/<name>` (deployed via `local_network_scripts/files/`).
- Systemd `--user` timer fires it on schedule.
- Output written to `~/.local/state/claude-jobs/<name>/`.
- Dashboard / morning ritual reads from there. Zero token cost per check.

The Gmail digest is a natural fit: API-bounded, idempotent, summary-shaped output, daily cadence.

## Scope — v1

**In:**
- Authenticated Gmail API access (read-only scope).
- Classify recent threads into three buckets:
  1. **Awaiting-my-reply** — inbox threads where the last message is from someone else AND > N hours old.
  2. **Stale-and-mine** — threads where my last message is > 7 days old AND no reply has landed.
  3. **Critical-sender** — anything from a configurable allow-list (e.g., Anthropic, Aziz, Brad, Tatiana) in the last 24h regardless of bucket.
- Filter rules to suppress noise: marketing labels, GitHub notifications, automated digests, Calendar invites already accepted.
- Output: a single markdown digest written to `~/.local/state/claude-jobs/gmail-digest/YYYY-MM-DD.md` plus a JSON state file under `~/.local/state/claude-jobs/gmail-digest/state.json`.
- Integration: extend `/daily-scope` to read the previous-day digest as a briefing input.

**Out (v2+):**
- Drafting replies. v1 surfaces only.
- Search-by-keyword on-demand. v1 is daily-digest only — for ad-hoc queries the answer is "add a Gmail MCP later if needed."
- Labeling / archiving emails. Read-only first.
- Calendar / Tasks / Drive — Gmail only for v1.

## Auth — OAuth desktop flow

Use Google's OAuth desktop app flow with the `gmail.readonly` scope (or `gmail.metadata` if we can do the classification without full bodies — TBD per inspection).

1. Create a Google Cloud project (or reuse an existing one).
2. Configure OAuth consent screen as "Internal" if `actuate.ai` workspace supports it; else "External" with the user as the only allowed tester.
3. Create an OAuth client of type "Desktop app". Download `credentials.json`.
4. On first run, `google-auth-oauthlib` opens a browser for consent → exchanges for refresh token → cache as `~/.config/gmail-digest/token.json` (`chmod 600`).
5. Subsequent runs are headless (refresh token handles re-auth).

Token storage is laptop-only initially; firebat copy lives at `~/.config/gmail-digest/token.json` and is provisioned out-of-band (scp from laptop after first auth, or repeat the consent flow on firebat directly via SSH X-forward). Add to the laptop-config portability backup story ([[mark-todos]] §10).

## Implementation outline

```
~/bin/gmail-digest                    # entrypoint shell wrapper
~/.config/gmail-digest/
    credentials.json                  # OAuth client config
    token.json                        # cached refresh token (chmod 600)
    config.yaml                       # critical-senders list, lookback windows, etc.
~/.local/state/claude-jobs/gmail-digest/
    YYYY-MM-DD.md                     # daily digest output
    state.json                        # last-seen message IDs to avoid re-surfacing
~/.config/systemd/user/
    gmail-digest.service              # oneshot
    gmail-digest.timer                # OnCalendar=*-*-* 06:00:00 (or pre-morning-prep)
local_network_scripts/files/
    gmail-digest.py                   # source-controlled
    gmail-digest.service              # source-controlled unit
    gmail-digest.timer                # source-controlled unit
    deploy-gmail-digest.sh            # firebat deploy script
```

**Python deps:** `google-api-python-client`, `google-auth-httplib2`, `google-auth-oauthlib`, `pyyaml`. Manage via `uv` per global rules.

**Classification logic (sketch):**

```python
def classify_thread(thread, me_email, critical_senders, awaiting_hours, stale_days):
    messages = thread["messages"]
    last = messages[-1]
    last_from = header(last, "From")
    last_date = parsedate(header(last, "Date"))

    if any(s in last_from for s in critical_senders):
        return "critical"

    if me_email not in last_from:
        if hours_since(last_date) > awaiting_hours:
            return "awaiting_my_reply"

    my_last = next((m for m in reversed(messages) if me_email in header(m, "From")), None)
    if my_last is None:
        return None
    if days_since(parsedate(header(my_last, "Date"))) > stale_days:
        if me_email in header(messages[-1], "From"):
            return "stale_and_mine"

    return None
```

**Noise filters** — apply BEFORE classification:
- Skip if thread is fully under any of: `Label_PromotionsCategory`, `CATEGORY_PROMOTIONS`, `Label_SocialCategory`, `CATEGORY_SOCIAL`, `CATEGORY_FORUMS`.
- Skip if from a known automation sender list (GitHub, Jira, NewRelic, AWS, Atlassian).
- Skip if subject matches an exclude regex (configurable in `config.yaml`).

**Digest format:**

```markdown
# Gmail digest — 2026-05-12

## 🔴 Critical (3)
- **Aziz Akberkho** — "Re: cohort B cascade hook PR" (2026-05-12 09:14, thread #abc123)
- ...

## ⚠️ Awaiting your reply (5)
- **Tatiana** — "Cohort F unbilled-camera follow-up" (replied 2026-05-09; 3d ago, thread #def456)
- ...

## 💤 Stale threads of yours (2)
- "v5 inference-api testing requirements" — your last msg 2026-05-04 (8d), no reply
- ...

## Stats
- Threads scanned: 184 (inbox last 14d)
- Filtered as noise: 92
- Surfaced: 10
```

## Integration with morning ritual

Extend `/daily-scope` skill (at `~/.claude/skills/daily-scope/SKILL.md`) to add a pre-pick fan-out step:

```
- Read latest digest at ~/.local/state/claude-jobs/gmail-digest/$(date +%F).md
- Surface "Critical" and any "Stale of mine" matching active §N keywords as scope candidates
- "Awaiting your reply" surfaces as a Morning Follow-Ups verify line, not a scope pick
```

The digest is a passive input, not a scope-driver — user retains final say on what to pick up.

## Phasing (~2 hr total)

| Phase | Time | Output |
|---|---|---|
| 0 | 15 min | Google Cloud project + OAuth client + credentials.json |
| 1 | 30 min | Local `gmail-digest.py` skeleton + auth bootstrap (laptop, prove auth works) |
| 2 | 30 min | Classification + noise filters + digest writer |
| 3 | 15 min | systemd unit files + timer |
| 4 | 15 min | Deploy to firebat (one-time scp of `token.json` after laptop consent) |
| 5 | 15 min | `/daily-scope` integration — read digest, surface critical entries |

## Risks / open questions

- **Workspace policy:** does `actuate.ai` Google Workspace permit OAuth desktop apps? If gated by admin approval, may need to fall back to IMAP + app password.
- **Token refresh on firebat:** if the firebat copy of `token.json` expires while the laptop's is fine, we have a sync problem. v1 solution: refresh on laptop, scp to firebat (manual). v2: token rotation script.
- **Privacy:** the digest file contains subject lines + sender names of emails. `~/.local/state/claude-jobs/gmail-digest/` is on the firebat filesystem (private); KB sync should NOT include it. Add to `.gitignore` of any synced dir.
- **Critical-sender list maintenance:** start with ~10 names; user revisits monthly. Live in `config.yaml`, not in code.
- **Awaiting-reply threshold:** v1 default 48h; user tunes after first week of digests.

## Related

- [[2026-04-30_three-tier-routine-check-pattern]] — the pattern this slots into
- [[mark-todos]] §31 (new) — the workstream
- [[mark-todos]] §10 — laptop-config portability (credentials.json + token.json need to be in the bootstrap inventory)
- [[skill-daily-scope]] — the consumer of the digest
