#!/usr/bin/env python3
"""Headless Atlassian (Jira) REST wrapper.

Bypasses the Atlassian MCP (which requires interactive auth that subagents and
`claude -p` headless runs cannot satisfy). Reads {email, token, site} from
~/.config/atlassian/api-token and uses HTTP Basic auth.

Library use:
    from atlassian_query import search_jira, get_issue
    issues = search_jira("assignee = currentUser() AND statusCategory != Done")
    issue = get_issue("CS3-31")

CLI use:
    python3 ~/.claude/lib/atlassian_query.py search "<JQL>"
    python3 ~/.claude/lib/atlassian_query.py search "<JQL>" --fields summary,status,priority
    python3 ~/.claude/lib/atlassian_query.py issue CS3-31
"""
from __future__ import annotations

import base64
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CRED_PATH = Path.home() / ".config" / "atlassian" / "api-token"
TIMEOUT = 30
DEFAULT_FIELDS = ["summary", "status", "priority", "issuetype", "assignee", "updated"]


def _creds() -> dict:
    try:
        return json.loads(CRED_PATH.read_text())
    except FileNotFoundError:
        sys.exit(f"Atlassian creds not found at {CRED_PATH}. See mark-todos §13.")


def _auth_header(creds: dict) -> str:
    raw = f"{creds['email']}:{creds['token']}".encode("utf-8")
    return "Basic " + base64.b64encode(raw).decode("ascii")


def _request(path: str, params: dict | None = None) -> dict:
    creds = _creds()
    url = creds["site"].rstrip("/") + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": _auth_header(creds),
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"Jira HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:500]}")


def search_jira(
    jql: str,
    fields: list[str] | None = None,
    max_results: int = 50,
    cap: int = 500,
) -> list[dict]:
    """Run a JQL search via /rest/api/3/search/jql (cursor-paginated). cap is a
    hard upper bound on issues returned across pages."""
    fields = fields or DEFAULT_FIELDS
    out: list[dict] = []
    next_page_token: str | None = None
    while True:
        params = {"jql": jql, "fields": ",".join(fields), "maxResults": max_results}
        if next_page_token:
            params["nextPageToken"] = next_page_token
        data = _request("/rest/api/3/search/jql", params)
        out.extend(data.get("issues", []))
        if len(out) >= cap:
            return out[:cap]
        if data.get("isLast"):
            return out
        next_page_token = data.get("nextPageToken")
        if not next_page_token:
            return out


def get_issue(key: str) -> dict:
    return _request(f"/rest/api/3/issue/{key}")


def main() -> None:
    import argparse

    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("search", help="run a JQL search")
    s.add_argument("jql")
    s.add_argument("--fields", default=",".join(DEFAULT_FIELDS))
    s.add_argument("--max-results", type=int, default=50)
    s.add_argument("--cap", type=int, default=500)

    i = sub.add_parser("issue", help="fetch one issue by key")
    i.add_argument("key")

    args = ap.parse_args()
    if args.cmd == "search":
        rows = search_jira(
            args.jql,
            fields=args.fields.split(","),
            max_results=args.max_results,
            cap=args.cap,
        )
        print(json.dumps(rows, indent=2))
    elif args.cmd == "issue":
        print(json.dumps(get_issue(args.key), indent=2))


if __name__ == "__main__":
    main()
