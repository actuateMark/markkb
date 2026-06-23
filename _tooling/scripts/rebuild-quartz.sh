#!/usr/bin/env bash
#
# ~/bin/rebuild-quartz.sh — invoked by rebuild-quartz.service.
#
# 1. rsyncs vault topics/ into ~/quartz/content/ (copy, not symlink — lets us
#    add synthetic files without touching the vault, which round-trips via
#    Obsidian Sync to the laptop)
# 2. writes a synthetic _index.md landing page (Quartz doesn't auto-generate
#    one for the content root)
# 3. runs `npx quartz build` to a staging dir
# 4. atomically rotates staging → live (keeps .prev for one-level rollback)

set -euo pipefail

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

vault="$HOME/Documents/worklog/work/knowledgebase/topics"
content="$HOME/quartz/content"
out_staging="$HOME/.local/state/minipc-dashboard/quartz-staging"
out_live="$HOME/.local/state/minipc-dashboard/quartz-output"
quarantine="$HOME/.local/state/minipc-dashboard/quartz-quarantine"

if [[ ! -d "$vault" ]]; then
  echo "rebuild-quartz: vault missing at $vault" >&2
  exit 1
fi

# --- stage content ---
rm -rf "$content"
mkdir -p "$content"
rsync -a --delete "$vault/" "$content/"

# --- synthetic landing ---
cat > "$content/_index.md" <<'EOF'
---
title: Knowledge Base
---
# mork knowledge base

Browse topics in the left sidebar (desktop) or via the hamburger (mobile).
Use search (top-left) to jump straight to a note.

- **Wikilinks** follow the Obsidian vault structure
- **Backlinks** and the **graph** live on the right side of each page
- Site is rebuilt every 5 minutes from the live Obsidian-Synced vault

## Recent activity

Jump into any topic folder on the left. The operational / day-to-day stuff
usually lives under `personal-notes`, `personal-laptop`, `engineering-process`
and the `autopatrol` / `vms-connector` technical topics.
EOF

# --- preflight: quarantine files with broken YAML frontmatter ---
# Quartz spawns multiple parse workers and aborts the entire build on the
# first frontmatter parse error it hits. A single malformed file (missing
# parent key, unquoted colon in title, stray injected line) takes down the
# whole site. We scan the staged copy, move broken files into a quarantine
# dir, and let Quartz build the rest. Vault is untouched.
python3 - "$content" "$quarantine" <<'PYEOF'
import re, sys, pathlib, shutil
import yaml

content = pathlib.Path(sys.argv[1])
quarantine = pathlib.Path(sys.argv[2])
FM_RE = re.compile(r"^---\n(.*?\n)---\n", re.DOTALL)

if quarantine.exists():
    shutil.rmtree(quarantine)
quarantine.mkdir(parents=True, exist_ok=True)

bad = []
for md in content.rglob("*.md"):
    raw = md.read_text(encoding="utf-8", errors="replace")
    m = FM_RE.match(raw)
    if not m:
        continue
    try:
        yaml.safe_load(m.group(1))
    except yaml.YAMLError as e:
        rel = md.relative_to(content)
        dest = quarantine / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(md), str(dest))
        bad.append(f"{rel}\t{str(e).splitlines()[0]}")

if bad:
    (quarantine / "_quarantine-log.txt").write_text("\n".join(bad) + "\n")
print(f"rebuild-quartz: quarantined {len(bad)} files with broken frontmatter")
PYEOF

# --- preprocessing: add aliases to date-prefixed files ---
# Obsidian wikilinks often reference date-prefixed notes by their trailing
# slug (e.g. [[connector-library-deployment-lifecycle]] targets the file
# 2026-04-14_connector-library-deployment-lifecycle.md). Quartz's shortest-
# resolution emits the wikilink text verbatim as the URL, so the redirect
# needs to come from alias metadata — AliasRedirects plugin creates a
# /slug/index.html that redirects to the real page.
#
# This pass walks content/*.md, and for each file whose basename matches
# "YYYY-MM-DD_<slug>" or "YYYY-MM-DD-<slug>", injects <slug> into the
# frontmatter's aliases list (additive, preserves existing aliases).
python3 - "$content" <<'PYEOF'
import os, re, sys, pathlib
import yaml

content = pathlib.Path(sys.argv[1])
DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})[-_](.+)$")
FM_RE = re.compile(r"^---\n(.*?\n)---\n(.*)$", re.DOTALL)

touched = 0
for md in content.rglob("*.md"):
    stem = md.stem
    m = DATE_RE.match(stem)
    if not m:
        continue
    alias = m.group(2)
    raw = md.read_text(encoding="utf-8", errors="replace")
    fm_match = FM_RE.match(raw)
    if fm_match:
        fm_text, body = fm_match.group(1), fm_match.group(2)
        try:
            fm = yaml.safe_load(fm_text) or {}
        except yaml.YAMLError:
            continue
    else:
        fm, body = {}, raw

    aliases = fm.get("aliases") or []
    if isinstance(aliases, str):
        aliases = [aliases]
    if alias in aliases:
        continue
    aliases.append(alias)
    fm["aliases"] = aliases

    new_fm = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True).strip()
    md.write_text(f"---\n{new_fm}\n---\n{body}", encoding="utf-8")
    touched += 1

print(f"rebuild-quartz: aliased {touched} date-prefixed files")
PYEOF

# --- build ---
cd "$HOME/quartz"
rm -rf "$out_staging"
npx quartz build -o "$out_staging"

# --- atomic rotate ---
if [[ -d "$out_live" ]]; then
  rm -rf "${out_live}.prev"
  mv "$out_live" "${out_live}.prev"
fi
mv "$out_staging" "$out_live"

echo "rebuild-quartz: done, $(find "$out_live" -type f | wc -l) files"
