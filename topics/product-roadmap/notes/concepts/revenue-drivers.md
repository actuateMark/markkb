---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [revenue, business, strategy, partnerships, immix]
incoming:
  - topics/integrations/evalink/evalink-integration/notes/concepts/alarm-push-pattern.md
  - topics/integrations/morphean/notes/concepts/cloud-to-cloud-architecture.md
  - topics/product-roadmap/notes/concepts/active-risks.md
  - topics/product-roadmap/notes/syntheses/improvement-opportunities.md
  - topics/team-structure/notes/entities/brian-leary.md
incoming_updated: 2026-05-01
---

# Revenue Drivers

Actuate's revenue strategy as of April 2026 rests on three primary drivers, each targeting a different market segment and integration model.

## 1. VCH / AutoPatrol via Immix (~$800K / 12 months)

This is the **current primary revenue driver**. VCH (Video Content Hosting) combined with the [[autopatrol/_summary|AutoPatrol (H1.2)]] product is delivered through **Immix**, a monitoring center integration platform. Immix is one of 25+ alarm sender types supported by the `actuate-alarm-senders` service (see [[data-flow-architecture]]).

The ~$800K figure over 12 months represents contracted or projected revenue from monitoring centers that use Immix to receive Actuate alerts. AutoPatrol (H1.2 initiative, project AUTO) is the most active product initiative with 50+ open Jira issues, and its features -- [[flex-ignore-zones|flex ignore zones]], VLM-powered false positive reduction, automated patrol schedules -- directly drive this revenue by improving alert quality and reducing operator fatigue.

Key people on this track: [[mark-barbera]] (prototype), [[tatiana-hanazaki]] (backend), [[brad-murphy]] (frontend), [[victoria-peccia]] (QA).

## 2. Morphean / VIDEOR (30 Countries, 170+ Resellers)

The [[integrations/morphean/_summary|Morphean]] represents a **high-leverage partnership**: Morphean is a Hanwha cloud private labeller operating VideoProtector (VSaaS), and VIDEOR is a major European security distributor. The strategic value is "one integration equals many customers" -- integrating with Morphean's platform gives Actuate access to VIDEOR's network of **170+ resellers across 30 countries**.

This integration has two tracks: cloud-to-cloud (VideoProtector REST API v2.54.0, see [[cloud-to-cloud-architecture]]) and edge hardware (Toradex Verdin + DeepX, see [[edge-hardware-track]]). Status is DRAFT as of April 2026, with a QA checklist recently created.

The revenue potential here is multiplicative -- rather than signing individual customers, Actuate gains distribution through an existing channel. However, the integration is still in early stages, making this a medium-term revenue driver.

## 3. Watchman (New Market Category)

[[watchman/_summary|Actuate Watchman]] represents Actuate's push into a **new market segment**: direct B2B sales to small commercial businesses with 4-30 cameras. Unlike the existing B2B2B model (Actuate sells to monitoring centers who sell to end customers), [[watchman-repo|Watchman]] positions Actuate as an **AI-powered virtual security operator** sold directly.

Key facts: ASAP priority, multi-agent architecture, targeting 10-20 beta sites. [[brian-leary|Brian Leary]] authored the PRD, [[laura-reno|Laura Reno]] leads MVP requirements. A mobile app shell (PROD-239, iOS + Android) is in the upcoming work pipeline.

[[watchman-repo|Watchman]] is strategically important because it diversifies Actuate away from dependence on monitoring center partnerships, but it also requires building direct sales, support, and billing capabilities that the current B2B2B model doesn't need.

## Risk Context

Revenue concentration in VCH/AutoPatrol via Immix creates dependency risk. The Morphean and [[watchman-repo|Watchman]] tracks are both pre-revenue as of April 2026, meaning near-term revenue remains tied to the Immix channel. See [[active-risks]] for related concerns about integration failures in the support queue (including Immix).

## See Also

- [[autopatrol/_summary|AutoPatrol (H1.2)]] -- the product behind the primary revenue driver
- [[integrations/morphean/_summary|Morphean]] -- the European distribution play
- [[watchman/_summary|Actuate Watchman]] -- the new market category
- [[active-risks]] -- risks to these revenue streams
