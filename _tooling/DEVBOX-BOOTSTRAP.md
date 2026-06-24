# Dev-box bootstrap — run Mark's KB + Claude-Code workflow on your own machine

> The umbrella guide: stand up the **whole workflow** (the Obsidian KB + the Claude-Code skills/agents/hooks + the daily rituals) on a fresh laptop/box, so a successor can work the way Mark did. It *composes* the other setup docs rather than repeating them. KB-only? use [[SETUP|_tooling/SETUP.md]] instead.

## What you get
- The **Obsidian KB** (this vault) with cost-ordered retrieval + ingestion + maintenance skills.
- The **Claude-Code config** — 30 skills, subagents, hooks, global rules (the `/daily-scope` morning ritual, `/kb-*`, `/dashboard-check`, release skills, etc.).
- Pointers to the **firebat** automation host and the **npu-server** LLM shop if you want the full tier-1 stack.

## Prereqs (install once)
```bash
# uv (Python), gh (GitHub), aws-cli, jq, node, ripgrep
curl -LsSf https://astral.sh/uv/install.sh | sh
# + your OS package manager for gh / awscli / jq / nodejs / ripgrep
# Claude Code CLI: per https://docs.claude.com/claude-code
# Obsidian (desktop): https://obsidian.md
```

## Steps
1. **Clone the two core repos** (org-owned, durable):
   ```bash
   git clone git@github.com:aegissystems/claude-config.git ~/.claude          # skills/agents/hooks/rules
   git clone git@github.com:aegissystems/actuate-kb.git    ~/Documents/worklog/knowledgebase   # the KB vault
   ```
   - `~/.claude` **is** the Claude-Code config dir — cloning claude-config there installs all skills/agents/hooks/`CLAUDE.md`/`lib` at once. (If `~/.claude` already exists, merge or back it up first.)
   - Open the KB folder as an Obsidian vault.
2. **KB tooling** — follow [[SETUP|_tooling/SETUP.md]] for the bits that live in the vault: the `obsidian` CLI (`_tooling/bin/obsidian` → `~/.local/bin/`, **x86-64 Linux**; rebuild from source elsewhere) and any vault-side scripts. *(The `kb-*` skills themselves come from claude-config in step 1 — `_tooling/skills/` is the standalone-mirror copy; don't double-install.)*
3. **Adjust paths.** The skills/scripts assume Mark's layout (`~/Documents/worklog/knowledgebase`, user `mork`). `grep -rl '/home/mork' ~/.claude ~/Documents/worklog/knowledgebase/_tooling` and fix to yours.
4. **Credentials** — only what the workflow you'll use needs. Follow the consolidated **[[2026-06-24_secrets-refresh-runbook]]**: AWS SSO/CodeArtifact, `gh`, New Relic, Atlassian, Anthropic key. *(Local KB use — `/kb-ask`, `/kb-lookup`, `/daily-scope` reading — needs none of the cloud creds.)*
5. **Clone the work repos** you'll touch (see [[core-repo-suite]] for the canonical list): `vms-connector`, `actuate-libraries`, `actuate_admin`, `actuate-inference-api`, `autopatrol_onboarder`, etc. into `~/work/`.
6. **(Optional) the automation tier.** This box can act as a **tier-2 fallback** in the three-tier routine-check pattern ([[2026-04-30_three-tier-routine-check-pattern]]) — the same `~/bin` scripts the firebat tier-1 host runs, deployed from `aegissystems/actuate-dev-toolkit`. The always-on **tier-1** is firebat ([[2026-06-22_firebat-operations-runbook]]); the **llm-shop** is npu-server (`actuate-dev-toolkit/files/llm-shop/CLAUDE.md`).

## Verify
- `~/.local/bin/obsidian vault` → vault responds.
- In Claude Code: `/kb-ask what does the kb say about <topic>` and `/daily-scope` run.
- `gh auth status`, `AWS_PROFILE=… aws sts get-caller-identity` if you set up cloud creds.

## How it all fits (the durable map)
- **Content + KB tooling:** `aegissystems/actuate-kb` (this repo; `_tooling/` = clone-and-run).
- **Claude config:** `aegissystems/claude-config`.
- **Automation hosts:** `aegissystems/actuate-dev-toolkit` (firebat phases + llm-shop + scripts).
- **Start-here map:** [[2026-06-22_actuate-footprint-handoff]]. **If it breaks:** [[2026-06-22_dead-mans-checklist]].

## Related
- [[SETUP]] (KB-only instance) · [[2026-06-24_secrets-refresh-runbook]] · [[2026-06-22_actuate-footprint-handoff]] · [[core-repo-suite]] · [[2026-04-30_three-tier-routine-check-pattern]]
