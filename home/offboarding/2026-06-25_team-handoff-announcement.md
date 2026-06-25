---
title: "Team handoff announcement (Mark → team, 2026-06-25)"
type: concept
tags: [offboarding, handoff, announcement, home]
updated: 2026-06-25
author: kb-bot
---

# Team handoff announcement

> Drafted 2026-06-25 (Mark's last day Fri 2026-06-26) for posting to the team (Slack/email). Records where everything lives + the time-critical asks. Living detail is in [[offboarding-overview]] and the §A–§I [[2026-06-22_manual-action-checklist|manual checklist]].

---

**📦 Handoff: where everything lives now (Mark — last day Fri 6/26)**

**The knowledge base is now the team's, at `aegissystems/actuate-kb`** (private). ~1,070 notes on the platform, plus everything I know about our ops setup. Open it in Obsidian, or just read the Markdown on GitHub.

**👉 Start in the `home/` folder.** It's a self-contained orientation packet — read just that and you're oriented. `home/README.md` is the front door:
- **§1 Orientation** — `what-is-actuate`, `system-architecture`, `the-topic-landscape` ("I want to learn X → go here"), `how-to-use-this-kb`, `first-steps` (repos, dev setup, who owns what).
- **§2 Roadmaps** — forward-looking overviews of the next high-leverage work:
    - **Watchman + Fleet Architecture** (`home/roadmaps/watchman-fleet-architecture.md`) — the flagship; **Mike (ENG-300)** + **Paolo (ENG-383)** own it. Read this + the handoff doc before the walkthrough.
    - **AIT / Actuate Integration Tools** (`home/roadmaps/actuate-integration-tools.md`) — the `ait` testing toolkit; **needs an owner** (and a 1-day path-pin fix to be portable).
- **§4 Operations / §5 Offboarding** — the firebat mini-PC, the dashboard, the llm-shop, runbooks, and the full handoff checklist.

My Claude Code setup (skills/agents/hooks) is mirrored too, at `aegissystems/claude-config`.

**⚠️ Time-critical before the box changes hands (it self-maintains, but breaks without these):**
1. **Pick the automation identity** (ENG-376, §A in `home/offboarding/manual-action-checklist`) — firebat's GitHub/New Relic/Atlassian creds are still mine; the team needs to decide a machine/service identity so I can re-home them at handover.
2. **A tailnet admin** to re-tag the box to `tag:server` — without this, firebat goes dark when my Tailscale account ends. *(highest priority)*
3. **Jira:** handoff comments are on all open tickets; team lead to set assignees (don't-drop: CS3-31, CS3-537/323, ENG-300).
4. **Watchman walkthrough** (me + Mike + Paolo) before Friday — the irreplaceable part.
5. **Two doc PRs need a quick review** to merge: `vms-connector #1765` + `kubernetes-deployments #419` (docs-only, CI green).

Full detail + the §A–§I checklist: `home/offboarding/` in the KB. Ping me this week.

---

## Related
- [[README|home/ orientation packet]] · [[watchman-fleet-architecture]] · [[actuate-integration-tools]]
- [[2026-06-22_offboarding-plan]] · [[2026-06-24_offboarding-asks]] · [[2026-06-22_actuate-footprint-handoff]]
