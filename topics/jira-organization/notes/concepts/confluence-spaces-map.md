---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [confluence, documentation, tooling, organization]
---

# Confluence Spaces Map

An inventory of all Confluence spaces in the Actuate team instance, organized by activity level and purpose. Understanding the space layout is essential for finding existing documentation and deciding where new pages belong.

## Primary Spaces (Active)

### kb -- Engineering Knowledge Base (200 pages)
The largest and most active space. Contains engineering documentation, architecture decisions, runbooks, and technical reference material. This is the default destination for most engineering-authored documentation.

### EDOCS -- Auto-Synced GitHub Docs (78 pages)
Created on April 9, 2026, this space is populated automatically from GitHub repository documentation. The sync mechanism pulls markdown files from repos (likely via a GitHub Action or CI pipeline) and publishes them as Confluence pages. This is the newest major space and represents a shift toward docs-as-code.

### DS -- Data Science (33 pages)
Covers ML model documentation, evaluation methodology, training procedures, and model performance benchmarks. Relevant for understanding the YAM initiative, v5-to-v8 model migration, weapon model development, and VLM (Vision Language Model) work by [[alena-prashkovich]], [[carlos-torres]], and [[clarissa-herman]].

### PM -- Product Management (20 pages)
Product-level documentation including the [[watchman/_summary|Actuate Watchman]] PRD (authored by [[brian-leary|Brian Leary]]), infrastructure planning, and product strategy. Smaller than expected for a product team, suggesting some product docs live in other spaces (e.g., PR for roadmap).

### Integratio -- Integration Partner Docs (11 pages)
Documentation for partner integrations: [[integrations/morphean/_summary|Morphean]] (EBUS), [[evalink-components|Evalink]], and others. Despite having only 11 pages, this space is strategically important -- it contains the requirements docs and QA checklists that govern how Actuate connects to external platforms.

### CAJP -- Jira/Confluence Process (10 pages)
Meta-documentation about how the team uses Jira and Confluence. Home of the [[jira-reorg-proposal]] by [[jacob-weiss]].

### PR -- Product Roadmap (4 pages)
A minimal space holding high-level roadmap views. Most detailed product tracking happens in Jira projects (PROD, AUTO, CS3, SA, AIM) rather than in Confluence.

## Secondary/Inactive Spaces

Several additional spaces exist with lower activity:

| Space | Purpose |
|-------|---------|
| AO1 | Actuate Secure (on-prem product) |
| FD | Fire Detection product |
| IA | AutoPatrol (older documentation, superseded by AUTO project docs) |
| SAS | Settings Automation (older documentation) |

These secondary spaces likely contain historical documentation from earlier product phases. Some may have content that should be consolidated into the primary spaces as part of any documentation cleanup effort.

## Observations

- The **kb** space at 200 pages dwarfs everything else, suggesting engineering is the most documentation-heavy team.
- **EDOCS** at 78 pages in just days since creation (April 9) shows significant GitHub doc volume being synced.
- Integration documentation (Integratio, 11 pages) is thin relative to its business importance -- [[integrations/morphean/_summary|Morphean]] alone covers 30 countries and 170+ resellers.
- There is no dedicated QA or Support space; QA documentation likely lives in kb or alongside the relevant project.

## See Also

- [[jira-reorg-proposal]] -- the Jira side of tooling organization
- [[actuate-platform/_summary|Actuate Platform Overview]] -- the system these docs describe
