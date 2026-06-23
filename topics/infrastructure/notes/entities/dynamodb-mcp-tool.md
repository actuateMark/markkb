---
title: "Amazon DynamoDB Data Modeling MCP Tool"
type: entity
topic: infrastructure
tags: [dynamodb, mcp, aws, data-modeling, ai-assisted, schema-design]
jira: null
confluence: "https://aws.amazon.com/blogs/database/introducing-the-amazon-dynamodb-data-modeling-mcp-tool/"
created: 2026-06-02
updated: 2026-06-02
author: kb-bot
incoming:
  - topics/infrastructure/_summary.md
  - topics/infrastructure/notes/syntheses/2026-06-02_dynamodb-fit-assessment-ait-phase-10.md
incoming_updated: 2026-06-19
---

# Amazon DynamoDB Data Modeling MCP Tool

AWS-published MCP server that uses Claude (or other reasoning LLMs) to design DynamoDB schemas through conversational requirements gathering and data modeling.

## What it does

Hosted as part of the broader [[aws-mcp-toolkit|AWS MCP server]] suite. Encodes DynamoDB access-pattern-first expertise to flatten the learning curve for new table designs.

**Two-phase workflow:**

1. **Requirements gathering** — conversational interview capturing entities, relationships, and access patterns (with estimated RPS per pattern).
2. **Model generation** — produces `dynamodb_data_model.md` documenting:
   - Table design (PKs, SKs, attributes)
   - Secondary indexes (GSI) and their coverage
   - Monthly cost projections
   - Per-access-pattern index mappings + reasoning

## Special capabilities

- **Fan-out detection** — flags access patterns that cause massive fan-out and recommends mitigation (complementary services like OpenSearch for full-text, async via Streams + Lambda).
- **Service offloading suggestions** — identifies when DynamoDB is the wrong tool (e.g., analytics → Redshift, search → OpenSearch).
- **Iterative refinement** — prompts clarify ambiguous requirements mid-conversation.

## Invocation

- **Automatic** — triggered when DynamoDB modeling is discussed in any MCP-compatible assistant.
- **Explicit** — mention "use my data modeling MCP tool" in Claude Code, Cursor, VS Code, Amazon Q Developer, or Kiro.
- **Model requirement** — works best with reasoning models (Claude 3.7 Sonnet, Claude 4 Sonnet, o3, Gemini 2.5). Claude Code runs Opus/Sonnet 4.x, which are compatible.

## Limitations

- **Design-time only** — produces markdown documentation, not running infrastructure. Terraform implementation is manual.
- **No deployment or load-testing** — the tool stops at the design doc; performance validation is your responsibility.
- **Iterative process** — not one-pass; expect 2–3 conversation rounds to converge on a good design.

## Where to find it

- **AWS Database Blog:** https://aws.amazon.com/blogs/database/introducing-the-amazon-dynamodb-data-modeling-mcp-tool/
- **GitHub** (if open-sourced): check the blog post for a repo link or AWS samples.
- **Availability:** MCP server installed locally for any Claude Code session targeting Actuate work (if configured).

## Related

- [[dynamodb-fit-assessment-ait-phase-10|DynamoDB fit assessment for AIT Phase 10]]
- [[autopatrol-cleanup-lambda]] — existing Actuate DynamoDB use case
- [[infrastructure/_summary]] — our current infrastructure
