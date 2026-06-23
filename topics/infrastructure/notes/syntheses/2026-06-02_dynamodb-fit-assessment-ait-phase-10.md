---
title: "DynamoDB MCP Tool Fit Assessment — AIT Phase 10 & Broader Ecosystem"
type: synthesis
topic: infrastructure
tags: [dynamodb, mcp, ait, data-modeling, phase-10, schema-design, assessment]
jira: null
confluence: null
created: 2026-06-02
updated: 2026-06-02
author: kb-bot
incoming:
  - topics/infrastructure/_summary.md
incoming_updated: 2026-06-19
---

# DynamoDB MCP Tool Fit Assessment

## Verdict: Low-effort, high-optionality

The [[dynamodb-mcp-tool|DynamoDB Data Modeling MCP]] is worth adding to the toolbox **as a productivity aide for table design**, not a load-bearing integration. Most valuable near-term use: design the [[2026-05-22_actuate-testing-toolkit-overview#Phase 9/10|AIT Phase 10 dump-catalog table]] *before* implementing the S3 sink, so access patterns drive the storage choice rather than the reverse.

## Current DynamoDB footprint

**[[autopatrol-cleanup-lambda|AutoPatrol cleanup Lambda]]** ([[autopatrol-cleanup-lambda]]) uses DynamoDB per-schedule counters (the "no patrols" emit accumulator, window reads, repeat-offender scans). That's our clearest existing DynamoDB surface. Beyond that, [[admin-api/_summary|Actuate Admin API]] and [[inference-api/_summary|Actuate Inference API]] may have DDB tables (API key lookups, rate-limit state), and [[actuate-platform/_summary]] should clarify current usage.

## AIT Phase 10 fit — the concrete opportunity

[[2026-05-22_actuate-testing-toolkit-overview]] outlines AIT Phases 9–10:
- **Phase 9** — production crash-hook dumps land in S3.
- **Phase 10** — S3 sink + the `ait dumps overnight` / `ait dumps fetch connector-XXX <crash_identifier>` commands.

Those commands are textbook DynamoDB access patterns:
- `ait dumps overnight` → query dumps by **date/recency** (what crashed overnight?).
- `ait dumps fetch` → get by **connector_id + crash_identifier**.
- Plausible secondary: list-by-exception-type, list-by-connector.

Today those are presumably S3 list-and-prefix-filter: O(bucket scans). A DynamoDB dump-catalog index (e.g., PK=connector_id, SK=crash_timestamp#exception, GSI keyed on date for overnight sweeps) would make them O(query) instead.

**The MCP tool is exactly built to:**
1. Take that enumerated access-pattern list (already in the Phase 10 spec).
2. Produce a candidate table design + GSI + monthly cost estimate.
3. Document the design rationale so we can argue whether it's worth it.

**Recommended flow:** Run the MCP tool conversation during Phase 10 design, before implementing the S3 sink. The output feeds straight into Terraform. This is a **design-time choice**, not a surprise infrastructure addition.

## Why Phase 10, not Phase 12?

AIT Phase 12 (`ait sweep` for QA parameter search) produces results JSON — no persistent storage needed. The use case fits neither DynamoDB nor S3 dump-catalog indexing. (Phase 12 output is ephemeral-per-sweep.)

## Honest caveats (critical to include)

1. **Not a full integration.** The MCP tool outputs markdown. We still build and deploy the Terraform ourselves. The tool is a design aide, not a runtime component.

2. **Fits AIT prospectively, not today.** Phase 10 isn't shipping yet. For modest crash volumes, S3 + a manifest may be simpler than DynamoDB. Don't add DDB prematurely; let access patterns and volume justify it *after* Phase 9 lands.

3. **More broadly useful.** The real leverage is **any new/existing DynamoDB table** — not just Phase 10. If we design the autopatrol counter tables or any future admin-api / v5 DynamoDB work, this MCP server is a productivity win.

4. **No runtime guarantee.** We already run Claude Code, so adding the MCP server is trivial (low cost to trial). But if Phase 10 data ends up in S3 only, nothing breaks — the MCP-assisted design just isn't implemented.

## Recommendation

**Add the MCP server to the toolbox now.** It's:
- Low friction (already MCP-compatible with Claude Code).
- Optional (integrating the output is a design choice, not mandatory).
- Reusable (any DynamoDB table design benefits from the expertise encoded in the tool).
- Defensive (we've captured the opportunity if Phase 10 or future work justifies DynamoDB).

Trigger: Next time you're designing a DynamoDB table (Phase 10 or otherwise), invoke the MCP tool conversation before writing Terraform. The cost is ~30 minutes of conversation; the payoff is confidence that the schema matches the access patterns.

## Related context

- [[2026-05-22_actuate-testing-toolkit-overview]] — AIT Phase 10 access-pattern spec.
- [[autopatrol-cleanup-lambda]] — existing DynamoDB use case (counter tables).
- [[dynamodb-mcp-tool]] — the tool entity reference.
- [[llm-shop/_summary]] — broader local-LLM + MCP tooling landscape.
- [[actuate-platform/_summary]] — overall platform architecture (likely where admin-api and inference-api DDB tables are documented).

## Acceptance criteria (if Phase 10 chooses DynamoDB)

1. Phase 10 design doc includes: table schema, GSI layout, monthly cost estimate, access-pattern→index mappings.
2. All mappings rationales are documented (from MCP tool output or manually if tool isn't used).
3. Terraform module for the table follows [[ds-terraform-eks-v2]] conventions.
4. `ait dumps fetch` / `ait dumps overnight` tests verify index query patterns before production rollout.

---

*This note synthesizes findings from the AWS Database Blog (2026-06-02 read) with Actuate's AIT roadmap and current DynamoDB footprint. Updated 2026-06-02.*
