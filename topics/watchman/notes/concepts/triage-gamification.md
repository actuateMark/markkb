---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [watchman, gamification, triage, engagement, learning-agent, ux]
---

# Triage Gamification

[[watchman]] incorporates an XP and streak system into its triage workflow to drive operator engagement. The core problem it addresses: if operators ignore alerts, the entire value proposition of proactive monitoring collapses. Gamification creates a lightweight incentive loop that rewards consistent, timely triage behaviour.

## The Engagement Problem

Watchman's target KPI is >70% of events triaged within 1 hour. Without engagement mechanics, alert fatigue sets in quickly -- operators learn to ignore notifications, and the system degrades to the same "cameras record but nobody watches" failure mode that Watchman exists to solve. The gamification layer is designed to make triage feel rewarding rather than burdensome.

## XP System

Operators earn experience points (XP) for triaging events. The system likely weights XP by:
- **Speed** -- faster triage earns more XP (incentivises the <1 hour target)
- **Consistency** -- daily engagement matters more than sporadic bursts
- **Quality** -- accurate triage feedback (confirmed threat vs false positive) contributes to the [[multi-agent-architecture|Learning Agent's]] accuracy model

XP accumulation is visible in the ghost tile dashboard -- the always-visible stats panel in Watchman's terminal-style UI. This gives operators a persistent sense of progress without requiring them to navigate away from the main workflow.

## Streak Mechanics

Streaks reward consecutive days (or shifts) of meeting triage thresholds. Breaking a streak creates a mild loss-aversion incentive to maintain engagement. This is a well-established pattern from consumer apps (Duolingo, fitness trackers) applied to a B2B security context.

The streak counter is likely displayed prominently in the dashboard and may factor into the daily AI-generated digest that Watchman produces for each site.

## Learning Agent Feedback Loop

The gamification system is tightly coupled to the [[multi-agent-architecture|Learning Agent]] (PROD-209). Every triage action -- confirming a threat, marking a false positive, reclassifying an event -- becomes training signal. The Learning Agent tracks:

1. **Triage outcomes** -- what the operator decided for each event
2. **Accuracy over time** -- whether the system's initial classification matched the operator's judgment
3. **Operator reliability** -- how consistently and quickly the operator responds

This creates a virtuous cycle: operators are incentivised to triage promptly and accurately (for XP and streaks), and their triage data makes the system smarter, which reduces false positives, which in turn makes triage less burdensome. The Learning Agent can also surface personalised feedback -- telling an operator their triage accuracy rate or how their engagement compares to benchmarks.

## UI Integration

The triage workflow uses Watchman's agentic-first terminal-style interface. Events appear in a queue; operators can triage via the terminal input bar (chat-style commands) or structured UI controls. The ghost tile dashboard surfaces XP, streak count, and engagement stats as persistent overlays, keeping the gamification layer visible without dominating the screen.

## Design Philosophy

Applying gamification to B2B security operations is unconventional. The design philosophy appears to be that small-business operators (Watchman targets businesses with 4-30 cameras) are not trained security professionals -- they are shop owners, property managers, and facility staff. The gamification meets them where they are, borrowing patterns from consumer software to make a professional tool feel approachable.
