#!/usr/bin/env python3
"""
kb-recap — generate a categorized recap of KB files changed in a date range.

Port of ~/.claude/skills/kb-recap/SKILL.md to a standalone Python script so
it runs from cron / systemd timer / prebuild step without spinning up Claude.
The procedure is pure find + categorize + emit markdown — no LLM reasoning.

Usage:
    kb-recap                         today, default options
    kb-recap 2026-04-23              a specific day
    kb-recap 2026-04-20..2026-04-24  inclusive range
    kb-recap --summary-only          only counts, no per-file listings
    kb-recap --include-automated     include jira-sync / overnight-check files
    kb-recap --include-binaries      include .pdf/.png/.jpg/.webp
    kb-recap --bytes                 sizes in bytes (default: KB)

Env:
    KB_ROOT   Override KB path. Default: /home/mork/Documents/worklog/knowledgebase
              (may be a symlink — we follow it).
"""
from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path


def birthtimes(paths: list[Path]) -> dict[Path, float | None]:
    """Batch-query birth-time via `stat -c %W`. ext4 supports it; returns
    None where the filesystem doesn't. One subprocess call for the whole set."""
    if not paths:
        return {}
    cmd = ["stat", "-c", "%W", "--"]
    cmd.extend(str(p) for p in paths)
    try:
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return {p: None for p in paths}
    result: dict[Path, float | None] = {}
    for p, line in zip(paths, out.splitlines()):
        line = line.strip()
        if line in ("", "0", "-", "?"):
            result[p] = None
        else:
            try:
                result[p] = float(line)
            except ValueError:
                result[p] = None
    return result


def parse_args():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("date", nargs="?", default=None,
                   help="Single date YYYY-MM-DD or range YYYY-MM-DD..YYYY-MM-DD. Default: today.")
    p.add_argument("--include-binaries", action="store_true")
    p.add_argument("--include-automated", action="store_true")
    p.add_argument("--summary-only", action="store_true")
    p.add_argument("--bytes", dest="bytes_unit", action="store_true")
    return p.parse_args()


def date_window(arg: str | None) -> tuple[dt.date, dt.date]:
    today = dt.date.today()
    if not arg:
        return today, today
    if ".." in arg:
        s, e = arg.split("..", 1)
        return dt.date.fromisoformat(s), dt.date.fromisoformat(e)
    d = dt.date.fromisoformat(arg)
    return d, d


EXTS_TEXT = {".md", ".base"}
EXTS_BIN = {".pdf", ".png", ".jpg", ".webp"}
EXCLUDED_PATH_FRAGMENTS = ("/.obsidian/", "/.git/", "/.trash/")

BUCKETS_ORDER = [
    "Daily note",
    "Mark-todos",
    "Source note",
    "Concept note",
    "Synthesis note",
    "Entity note",
    "Topic summary",
    "Reading list",
    "Staging / scratch",
    "Automated — jira-sync",
    "Automated — overnight-check",
    "Research inbox",
    "Top-level",
    "Other",
]

# Bucket headings that use "(N new, M edited)" per the skill spec.
NEW_EDIT_HEADINGS = {"Source note", "Concept note", "Synthesis note"}
# Automated buckets hidden unless --include-automated.
AUTO_BUCKETS = {"Automated — jira-sync", "Automated — overnight-check"}


def classify(rel_posix: str) -> str:
    """Bucket a relative-to-KB-root POSIX path. First match wins."""
    def fm(pat):
        return fnmatch.fnmatchcase(rel_posix, pat)
    if fm("topics/personal-notes/notes/daily/*.md"): return "Daily note"
    if rel_posix == "topics/personal-notes/notes/entities/mark-todos.md": return "Mark-todos"
    if fm("topics/*/sources/*.md") or fm("topics/*/*/sources/*.md"): return "Source note"
    if fm("topics/*/notes/concepts/*.md") or fm("topics/*/*/notes/concepts/*.md"): return "Concept note"
    if fm("topics/*/notes/syntheses/*.md") or fm("topics/*/*/notes/syntheses/*.md"): return "Synthesis note"
    if fm("topics/*/notes/entities/*.md") or fm("topics/*/*/notes/entities/*.md"): return "Entity note"
    if fm("topics/*/_summary.md"): return "Topic summary"
    if fm("topics/*/reading-list.md"): return "Reading list"
    if fm("topics/*/_pilot-*.md") or fm("topics/*/_staging-*.md") or fm("topics/*/_dive-queue.md"):
        return "Staging / scratch"
    if fm("topics/operational-health/notes/syntheses/*_jira-sync.md"):
        return "Automated — jira-sync"
    if fm("topics/operational-health/notes/syntheses/*_overnight-check.md"):
        return "Automated — overnight-check"
    if rel_posix.startswith("_research-inbox/"):
        return "Research inbox"
    if rel_posix.startswith("_") or rel_posix.startswith("bases/") or rel_posix.endswith(".base"):
        return "Top-level"
    return "Other"


def topic_of(rel_posix: str) -> str:
    parts = rel_posix.split("/")
    if parts[0] == "topics" and len(parts) >= 2:
        return parts[1]
    return parts[0] or "(root)"


def walk_kb(root: Path, want_exts: set[str]) -> list[Path]:
    """Walk the KB, following the symlink at root but not random ones inside."""
    out: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=True):
        # prune
        dirnames[:] = [d for d in dirnames if d not in (".obsidian", ".git", ".trash")]
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            if any(f in p for f in EXCLUDED_PATH_FRAGMENTS):
                continue
            ext = os.path.splitext(fn)[1].lower()
            if ext in want_exts:
                out.append(Path(p))
    return out


def main() -> int:
    args = parse_args()
    kb = Path(os.environ.get("KB_ROOT", "/home/mork/Documents/worklog/knowledgebase")).resolve()
    if not kb.is_dir():
        print(f"kb-recap: KB root not found at {kb}", file=sys.stderr)
        return 3

    start, end = date_window(args.date)
    end_next = end + dt.timedelta(days=1)

    start_ts = dt.datetime.combine(start, dt.time.min).timestamp()
    end_next_ts = dt.datetime.combine(end_next, dt.time.min).timestamp()

    date_heading = str(start) if start == end else f"{start}..{end}"

    want_exts = EXTS_TEXT | (EXTS_BIN if args.include_binaries else set())
    all_files = walk_kb(kb, want_exts)

    # Files in range (by mtime)
    rows: list[tuple[Path, os.stat_result]] = []
    for p in all_files:
        try:
            st = p.stat()
        except FileNotFoundError:
            continue
        if start_ts <= st.st_mtime < end_next_ts:
            rows.append((p, st))

    # Batch-fetch birth-times for classify new vs edited (ext4 supports it).
    births = birthtimes([p for p, _ in rows])

    buckets: dict[str, list[tuple[str, Path, os.stat_result]]] = defaultdict(list)
    new_count = edited_count = unknown_count = 0
    total_bytes = 0

    for p, st in rows:
        rel = p.relative_to(kb).as_posix()
        birth = births.get(p)
        if birth is None or birth == 0:
            flag = "🔄"
            unknown_count += 1
        elif start_ts <= birth < end_next_ts:
            flag = "✨"
            new_count += 1
        else:
            flag = "✏️"
            edited_count += 1
        total_bytes += st.st_size
        buckets[classify(rel)].append((flag, p, st))

    # --- emit markdown ---
    out = [f"# KB Recap: {date_heading}"]

    total = len(rows)
    if total == 0:
        out.append("")
        out.append(f"_No KB files touched in {date_heading}._")
        out.append("")
        out.append("## Totals")
        out.append("- **0** KB files touched")
        sanity = len([p for p in all_files if p.suffix == ".md"])
        out.append(f"- Sanity: {sanity} md files exist under `{kb}`; none had an mtime in range.")
        print("\n".join(out))
        return 0

    def size_fmt(n: int) -> str:
        if args.bytes_unit:
            return f"{n} B"
        if n < 1024:
            return f"{n} B"
        return f"{round(n / 1024)} KB"

    for bucket in BUCKETS_ORDER:
        items = buckets.get(bucket, [])
        if not items:
            continue
        if bucket in AUTO_BUCKETS and not args.include_automated:
            continue

        n_new = sum(1 for f, _, _ in items if f == "✨")
        n_edit = sum(1 for f, _, _ in items if f == "✏️")
        n_unk = sum(1 for f, _, _ in items if f == "🔄")
        n_total = len(items)

        if bucket in NEW_EDIT_HEADINGS:
            header = f"## {bucket}s ({n_new} new, {n_edit} edited)"
        elif bucket == "Mark-todos":
            header = f"## Mark-todos ({n_total})"
        elif bucket.endswith("note") or bucket in ("Topic summary", "Reading list"):
            header = f"## {bucket}s ({n_total})"
        elif bucket in ("Daily note",):
            header = f"## Daily notes ({n_total})"
        elif bucket in ("Staging / scratch", "Research inbox", "Top-level", "Other"):
            header = f"## {bucket} ({n_total})"
        else:
            header = f"## {bucket} ({n_total})"

        out.append("")
        out.append(header)

        if args.summary_only:
            continue

        # group by topic → sort alphabetically
        by_topic: dict[str, list[tuple[str, Path, os.stat_result]]] = defaultdict(list)
        for flag, p, st in items:
            rel = p.relative_to(kb).as_posix()
            by_topic[topic_of(rel)].append((flag, p, st))

        for topic in sorted(by_topic.keys()):
            out.append("")
            out.append(f"### {topic}")
            out.append("")
            rows_sorted = sorted(by_topic[topic], key=lambda r: r[1].as_posix())
            for flag, p, st in rows_sorted:
                rel = p.relative_to(kb).as_posix()
                out.append(f"- {flag} `{rel}` ({size_fmt(st.st_size)})")

    out.append("")
    out.append("## Totals")
    out.append(f"- **{total}** KB files touched in {date_heading}")
    out.append(f"- **{new_count}** new, **{edited_count}** edited, **{unknown_count}** touched (birth-time unavailable)")
    out.append(f"- **{size_fmt(total_bytes)}** across all listed files")

    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
