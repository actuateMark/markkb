---
title: "AIT Phase 3 — `ait audit-tier-emissions <deployment_id>`"
type: synthesis
topic: engineering-process
tags: [tooling, actuate-integration-tools, ait, audit, new-relic, tier, autopatrol, roadmap]
created: 2026-05-19
updated: 2026-05-19
author: mark
[]
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-extensions-spec.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-1-diff.md
  - topics/engineering-process/notes/syntheses/2026-05-19_ait-phase-2-validate.md
  - topics/personal-notes/notes/daily/2026-05-19.md
incoming_updated: 2026-05-20
---

# AIT Phase 3 — `ait audit-tier-emissions <deployment_id>`

Closes the gap between **config-time tier** (what the parsed config says the patrol *should* emit) and **runtime tier** (what NR logs say the patrol *actually* emitted). Catches drift caused by library bumps that haven't reached every fleet, customer admin re-deploys that haven't reached the pod yet, or library bugs that silently mis-tier.

## Why this is Phase 3

It's the most complex of the Tier 1 set — needs a new NR query layer in the tool — but it's also the highest-payoff diagnostic for the class of bug the entire VCH/tier work was about: **"the config says one thing, the wire says another."**

The actuate-pr-reviewer agent explicitly flagged the stream-fetch tier surface as a validation gap on PR #1699 — today, `autopatrol_api.get_patrol_stream` doesn't log the `Tier=N` query param it sends to Immix's `/videostream` endpoint, so we have no NR visibility into one of the two tier-bearing API surfaces. Phase 3 partially closes that gap by checking `raise_patrol_alert` payloads (which are logged) and surfacing the asymmetry.

## CLI shape

```bash
# Default: last 24h of raise_patrol_alert log lines, expected vs actual tier diff
ait audit-tier-emissions <deployment_id>

# Wider window for sites that fire rarely
ait audit-tier-emissions <deployment_id> --since "7 days ago"

# JSON output for piping
ait audit-tier-emissions <deployment_id> --json

# Fleet-wide drift sweep (all AutoPatrol cronjobs)
ait audit-tier-emissions --fleet --integration autopatrol --since "24h ago"
```

## What it checks

1. **Predicted tier:** parse the deployment's settings.json through the production `actuate-config` library (current `:stage` or `:rearchitecture` pin) and compute `highest_tier_for(configured_detection_codes)`.
2. **Observed tier from `raise_patrol_alert` payloads:** NR query for `"Raising patrol alert"` log lines from the deployment's container, extract the `tier` field from the JSON payload.
3. **Comparison:** if any observed tier ≠ predicted, surface the patrol_id + camera + tier mismatch.

Edge cases the tool needs to handle:

- **CNCTNFAIL alerts:** these are pre-fix-style emissions and might legitimately have `tier: 1` even when the configured set is Tier 3. Treat as expected unless explicitly checked.
- **Empty result:** "no alerts fired in the window" is not a failure — `info` severity output, not `error`.
- **Stale image:** if the deployment's pod is on an old image (e.g. `:rearchitecture` not yet promoted), observed tier may legitimately be the old hardcoded value. Surface the image tag from NR's `container_image` attribute as context.

## Required infrastructure

New module: `src/actuate_integration_tools/nr_client.py` — thin wrapper for NerdGraph queries.

Two design options:

**Option A: Direct NerdGraph queries via `requests` or `gql`** with an API key from env (`NEW_RELIC_API_KEY`). Pros: lightweight, fast, no subagent spawn. Cons: duplicates a bit of the existing `nrql-investigator` agent's logic.

**Option B: Subprocess the `nrql-investigator` agent** via the Anthropic CLI. Pros: reuses the agent's knowledge. Cons: subagent spawn is heavy (~10-30s per invocation), kills the snappy-CLI ergonomics.

Default to A. The `nrql-investigator` agent stays the right tool for ad-hoc, multi-step NR investigations; the CLI is for the single-question "did this deployment's last 24h of alerts have the expected tier?".

## TODOs (Phase 3)

### NR client foundation

- [ ] Create `src/actuate_integration_tools/nr_client.py` with `NRClient` class. `__init__` reads `NEW_RELIC_API_KEY` + `NEW_RELIC_ACCOUNT_ID` from env (fail loudly if missing).
- [ ] Implement `query_nrql(nrql: str) -> list[dict]` against `https://api.newrelic.com/graphql`.
- [ ] Implement `recent_patrol_alerts(deployment_id: str, since: str = "24 hours ago") -> list[PatrolAlert]` — wraps the specific NRQL pattern for `"Raising patrol alert"` log lines and parses the JSON payload.
- [ ] Add tests using `responses` library to mock NerdGraph responses.

### Audit command

- [ ] Add `ait audit-tier-emissions <deployment_id>` subcommand in `cli.py`.
- [ ] Predict tier via `highest_tier_for(configured_detection_codes)` (reuse Phase 1's parse layer).
- [ ] Pull recent alerts via `NRClient.recent_patrol_alerts(...)`.
- [ ] Compute mismatch table — predicted vs observed per patrol_id.
- [ ] Add `--since` flag with NR-style relative durations ("24 hours ago", "7 days ago", etc.).
- [ ] Add `--json` flag.

### CNCTNFAIL handling

- [ ] Define the "expected exceptions" table — alerts where observed tier may legitimately differ from predicted (CNCTNFAIL = Tier 1 always, healthcheck-flavoured codes = Tier 1).
- [ ] Output should surface "matched (within expected exceptions)" vs "mismatch" cleanly.

### Image-tag context

- [ ] Pull `container_image` from NR `K8sContainerSample` (or equivalent) for the deployment in the audit window. If the image is the prior `:rearchitecture` pre-tier-fix tag, downgrade severity from "mismatch" to "expected (stale image)".

### Fleet-wide drift sweep (stretch)

- [ ] `ait audit-tier-emissions --fleet` enumerates AutoPatrol deployments from the `actuate-settings` bucket and runs the audit against each. Bound the parallel-fetch + NR-query work carefully.
- [ ] Output: ranked list of mismatches by patrol_id.

### Real-customer validation

- [ ] Run against site 35831 (known-good, post-fix). Predicted = 3 (CROWD+PERSON+UPS), observed should match.
- [ ] Run against site 40799 (VCH-only). Predicted = 1 (HEALTHCHECK), observed CNCTNFAIL emissions should match.
- [ ] Run against any AutoPatrol cronjob whose image still reads `:rearchitecture` from before the 2026-05-18 promotion — should now match since the promotion landed at 17:29 UTC; if any pre-promotion windows still show in NR retention, those would be "expected mismatch (stale image)".

### Documentation

- [ ] Update [[actuate-integration-tools]] entity with the `audit-tier-emissions` command + the "config-vs-runtime drift" framing.
- [ ] Document the NR API key + account ID env requirements in `README.md`.
- [ ] Add a "Drift detection" section to [[2026-04-14_connector-library-deployment-lifecycle]] referencing this command as the post-deploy verification step.

## Estimate

~3-4h focused work for the core audit command + NR client. Fleet sweep adds another ~2h. Total ~5-6h.

## Adjacent: closing the `get_patrol_stream` Tier visibility gap

Phase 3 only audits `raise_patrol_alert` because that's what's currently logged. To also audit the `get_patrol_stream` Tier query param, we need a small library-side change:

- [ ] Add `logging.info(f"get_patrol_stream tier={tier} duration={duration} patrol={patrol_id}")` in `actuate-libraries/actuate-integration-calls/src/actuate_integration_calls/autopatrol/autopatrol_api.py` (line ~344, before the request). One-line patch in its own `[patch:actuate-integration-calls]` PR.

Once that logs, extend `NRClient.recent_patrol_alerts(...)` to also pull `"get_patrol_stream tier=..."` lines and audit both surfaces in `ait audit-tier-emissions`.

## Cross-references

- [[actuate-integration-tools]] — entity
- [[2026-05-19_ait-extensions-spec]] — parent spec (Phases 1–3 arc)
- [[2026-05-19_ait-phase-1-diff]] — Phase 1 (reused for parse layer)
- [[2026-05-19_ait-phase-2-validate]] — Phase 2 (sibling, independent) ✅ shipped 2026-05-20
- [[2026-05-20_ait-brain-in-jar-spec]] — Phases 4–10 (next arc — state capture + replay)
- [[2026-05-14_autopatrol-tier-api-cross-reference]] — the spec rule this command verifies
- [[2026-05-18_libav-decoder-warmup-frame-fix]] — original tier work
