---
title: "Source: Alibi Billing Profile Redesign"
type: source
topic: actuate-platform
tags: [worklog, alibi, billing, sales-order, admin-ui, hierarchy]
ingested: 2026-04-14
author: kb-bot
---

# Alibi Billing Profile Redesign

Worklog notes on redesigning the billing profile system to use Sales Order numbers as the unique identifier, resolving duplication issues in billing reports.

## Problem

The previous billing system used user profiles as the organizing unit, which caused duplication in reports. Changing the unique identifier to the Sales Order (SO) number eliminated most duplication.

## Solution: Sales Order Profiles

The "User Profile" section is renamed to **"Sales Order Profile"**. Required fields are reduced to four:

1. **Billing ID**
2. **CC Code**
3. **SO Number** (unique, cannot be repeated)
4. **Billing Period**

All other fields are optional. The billing profile is automatically linked to the site created in the hierarchy. The SO number is displayed instead of the user's name in the billing profile list. Sites can be reassigned to different SO numbers via a dropdown.

## Hierarchy Dependency

This design relies on proper hierarchy management. Sites must be nested correctly so that only one SO number is associated with any specific site. The SO number must be associated with the **lowest-level site** that contains cameras. Associating it with higher-level parent sites causes reporting issues.

Example: If dealer "47002 Customer Security" has client "Five Star Medical" with multiple sub-sites each having different SO numbers, each SO must be on the leaf site, not the parent.

## See Also

- [[admin-api]] -- the system where billing profiles are managed
