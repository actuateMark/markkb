---
title: "actuate-network"
type: entity
topic: actuate-libraries
tags: [library, utility, networking, subnet-validation, vpn, aws, vpc]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

## Purpose

actuate-network (v1.0.4) provides VPC-wide network conflict validation. It checks for subnet overlap between tunnels, against reserved ranges, and against AWS Site-to-Site VPN routes. This library is framework-agnostic (raises `ValueError`, not Django exceptions) and is consumed by both the Django admin backend and standalone services like the WireGuard autoconf service.

## Public API

### Validation Functions

- **`validate_subnet_list(value)`** -- Validates that a value is a list of valid CIDR strings. Normalises `None` and `[]` to empty lists. Raises `ValueError` for invalid formats.

- **`check_subnets_no_internal_overlap(subnets)`** -- Checks that subnets within a list do not overlap each other.

- **`check_subnets_no_reserved_overlap(subnets)`** -- Checks that subnets do not overlap with any entry in `RESERVED_SUBNET_RANGES` (defined in `constants.py`).

- **`check_subnets_no_external_overlap(new_subnets, existing_subnets_by_tunnel)`** -- Checks that new subnets do not overlap with subnets from other existing tunnels/routes. Takes a dict mapping tunnel labels to their subnet lists.

- **`check_subnets_no_vpn_overlap(subnets, region, vpn_cidrs)`** -- Checks against AWS Site-to-Site VPN static routes. Fetches VPN CIDRs from AWS (with caching) or accepts pre-fetched CIDRs for testing.

- **`suggest_next_available_subnet(prefix_length, existing_subnets, candidate_pools)`** -- Finds the first non-overlapping IPv4 subnet of a given CIDR size. Searches through RFC1918 candidate pools by default, skipping reserved and existing ranges. Used for auto-assigning subnets to new tunnels.

### AWS VPN Integration

- **`get_site_to_site_vpn_cidrs(region)`** -- Fetches VPN CIDRs from AWS EC2 API (cached).
- **`clear_vpn_cidr_cache()`** -- Clears the VPN CIDR cache.

### Constants

- **`RESERVED_SUBNET_RANGES`** -- List of `IPv4Network` objects representing ranges that must not be used (e.g., VPC CIDRs, management networks).
- **`DEFAULT_SUBNET_SUGGESTION_POOLS`** -- RFC1918 ranges to search when suggesting new subnets.

## Dependencies

- **boto3** >=1.35.20 -- for AWS VPN route fetching.

## Consumers

actuate-wireguard (imports all validation functions and uses them in WireGuardDAO), Camera Admin Django backend (catches ValueError and converts to Django ValidationError).

## Notable Patterns

- **Framework-agnostic validation**: All functions raise `ValueError`, making them usable from Django, FastAPI, or plain scripts. The consuming Django code wraps them with try/except to convert to `ValidationError`.
- **Layered validation**: The check functions are composable -- callers can run internal, reserved, external, and VPN overlap checks independently or all together, depending on context.
- **Efficient subnet search**: `suggest_next_available_subnet` uses a cursor-based scan with sorted blocked ranges, running in O(n log n) rather than brute-force iteration.
