#!/usr/bin/env python3
"""Headless NR NerdGraph wrapper.

Bypasses the NR MCP (which requires interactive OAuth callback that subagents
and `claude -p` headless runs cannot satisfy). Reads a NRAK User API key from
~/.config/nr/api-key and posts NRQL via NerdGraph.

Library use:
    from nr_query import nrql
    rows = nrql("FROM Log SELECT count(*) WHERE cluster_name = 'Connector-EKS' SINCE 1 hour ago")

CLI use:
    python3 ~/.claude/lib/nr_query.py "FROM ..."
    python3 ~/.claude/lib/nr_query.py --account 1234567 "FROM ..."

Default account: 3421145 (Connector-EKS).
"""
from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

NERDGRAPH_URL = "https://api.newrelic.com/graphql"
DEFAULT_ACCOUNT = 3421145
KEY_PATH = Path.home() / ".config" / "nr" / "api-key"
TIMEOUT = 30


def _api_key() -> str:
    try:
        return KEY_PATH.read_text().strip()
    except FileNotFoundError:
        sys.exit(f"NR API key not found at {KEY_PATH}. See mark-todos §13.")


def nrql(query: str, account_id: int = DEFAULT_ACCOUNT) -> list[dict]:
    gql = (
        "query($account: Int!, $nrql: Nrql!) { "
        "actor { account(id: $account) { nrql(query: $nrql) { results } } } "
        "}"
    )
    body = json.dumps(
        {"query": gql, "variables": {"account": account_id, "nrql": query}}
    ).encode("utf-8")
    req = urllib.request.Request(
        NERDGRAPH_URL,
        data=body,
        headers={"Content-Type": "application/json", "API-Key": _api_key()},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            payload = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"NR HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:500]}")
    if "errors" in payload:
        sys.exit(f"NR GraphQL errors: {json.dumps(payload['errors'])[:500]}")
    nrql_block = payload["data"]["actor"]["account"]["nrql"]
    if nrql_block is None:
        sys.exit(f"NR returned null nrql block (account {account_id} access?): {json.dumps(payload)[:500]}")
    return nrql_block["results"]


def main() -> None:
    import argparse

    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("query", help="NRQL query string")
    ap.add_argument("--account", type=int, default=DEFAULT_ACCOUNT)
    args = ap.parse_args()
    print(json.dumps(nrql(args.query, account_id=args.account), indent=2))


if __name__ == "__main__":
    main()
