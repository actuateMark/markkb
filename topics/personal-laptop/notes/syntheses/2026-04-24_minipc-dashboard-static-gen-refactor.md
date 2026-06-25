---
title: "Minipc dashboard — static-gen refactor (Quartz + 11ty + trimmed FastAPI)"
type: synthesis
topic: personal-laptop
tags: [minipc, dashboard, quartz, eleventy, static-gen, refactor]
jira: ""
created: 2026-04-24
updated: 2026-04-24
author: kb-bot
incoming:
  - home/operations/2026-06-22_actuate-footprint-handoff.md
  - topics/engineering-process/notes/syntheses/2026-04-30_three-tier-routine-check-pattern.md
  - topics/personal-laptop/notes/concepts/2026-04-27_handoff-repos-architectural-dashboard.md
  - topics/personal-laptop/notes/concepts/2026-04-29_minipc-api-surface.md
  - topics/personal-laptop/notes/syntheses/2026-04-24_skills-audit-script-candidates.md
  - topics/personal-laptop/notes/syntheses/2026-04-27_minipc-tooling-improvements.md
  - topics/personal-notes/notes/daily/2026-04-24.md
  - topics/personal-notes/notes/daily/2026-04-29.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-25
---

# Minipc dashboard — static-gen refactor

## Context

The Phase 1–3 dashboard app ([[2026-04-23_firebat-minipc-as-claude-dev-box]] §12a–e) shipped all seven surfaces functional but "hideous" (user, 2026-04-24). The root cause is that FastAPI+Jinja+HTMX with a minimal hand-rolled palette can't compete with a purpose-built static-site generator's typography, nav, and note-rendering polish. Also: **the KB browser (the load-bearing surface) is trying to reimplement wikilinks, trees, frontmatter, etc. — all things Obsidian-native static-site tools already do well.**

Decision: **split the three classes of content across three purpose-fit tools**, glue with Caddy, rebuild periodically.

## Target architecture

```
Browser
  │
  ▼
Caddy :80  (mork-firebat)
  │
  ├── /                    static status page   (bash-regen every 30s — unchanged)
  ├── /dashboard/          /dashboard-check artifact (unchanged)
  ├── /obsidian/           container            (admin only — unchanged)
  ├── /logs/               job-log file-browser (unchanged)
  │
  ├── /app/                → 11ty (eleventy-base-blog, customised)
  │     /                    dashboard landing — tiles for today/jira/repos/metrics/kb
  │     /today/              daily /kb-recap artifact, rendered from markdown
  │     /jira/               parsed from mark-todos auto-sync blocks
  │     /repos/              collect-repos JSON → list
  │     /metrics/            last observation table + 24h sparklines
  │     /admin/              maintenance tiles
  │
  ├── /app/kb/             → Quartz (Obsidian-native garden)
  │     /                    vault landing
  │     /<path-in-vault>/    rendered note with wikilinks, backlinks, graph, search
  │     /tags/<tag>/         tag index pages
  │
  └── /app/api/            → FastAPI (trimmed down — ONLY the dynamic bits)
        /kb/query            POST → `claude -p /kb-ask`   (form target + JSON)
        /metrics.json        live JSONL read
        /metrics.txt         curl-friendly one-liner
        /healthz             heartbeat
```

Rationale:
- **Quartz** is purpose-built for Obsidian vaults (wikilinks, backlinks, graph, search, transclusions, popover previews). Far less custom work than reimplementing these in 11ty.
- **11ty base-blog** gives the dashboard pages a cohesive, clean look with minimal custom code — Nunjucks + markdown, navigation plugin, typography via the starter's CSS.
- **FastAPI** keeps only the two things that *must* be dynamic: the KB-ask POST endpoint (spawns a Claude subprocess) and live metrics.

## Repo layout (on laptop, versioned under `local_network_scripts/`)

```
local_network_scripts/
├── minipc-blog/             # NEW — 11ty dashboard (from eleventy-base-blog starter)
│   ├── eleventy.config.js
│   ├── package.json / package-lock.json
│   ├── content/
│   │   ├── index.njk        # dashboard landing
│   │   ├── today.md         # GENERATED at build time from artifact
│   │   ├── jira.md          # GENERATED from mark-todos auto-sync
│   │   ├── repos.md         # GENERATED from collect-repos JSON
│   │   ├── metrics.md       # GENERATED from metrics JSONL (latest + sparks)
│   │   └── admin.md         # hand-written (static content)
│   ├── _includes/layouts/   # customised from base-blog
│   │   └── base.njk         # shared shell + palette (matches static status page)
│   ├── _data/
│   │   └── nav.json         # top-nav entries
│   ├── public/
│   │   └── css/app.css      # Quartz + blog + status page all share these tokens
│   └── scripts/
│       └── prebuild.js      # run BEFORE `eleventy build`: writes the GENERATED content/*.md
│
├── minipc-quartz/           # NEW — Quartz configuration pointing at the vault
│   ├── quartz.config.ts
│   ├── quartz.layout.ts
│   ├── content → /home/mork/Documents/worklog/knowledgebase  (symlink on minipc)
│   └── ...                  # standard Quartz skeleton
│
├── minipc-app/              # TRIMMED — FastAPI now only serves dynamic routes
│   └── (kb, jira, repos, today, admin, metrics routes removed;
│        main.py + routes/kb_query.py + routes/metrics_api.py + healthz remain)
│
└── phase-14-static-sites.sh # NEW — deploys both static sites + rebuild timers
```

On the **minipc**, the deployed layout is:
```
~/minipc-blog/            ← rsynced from laptop
~/minipc-quartz/          ← rsynced, with content/ → ~/Documents/worklog/knowledgebase
~/minipc-app/             ← rsynced, trimmed
~/.local/state/minipc-dashboard/
    ├── blog-output/      ← `eleventy build` writes here
    └── quartz-output/    ← `npx quartz build` writes here
/etc/caddy/Caddyfile      ← routes /app/kb → quartz-output, /app/api → 127.0.0.1:8081,
                            /app/ → blog-output
```

## Rebuild cadence

| Source change                                   | Rebuild trigger                              | Cadence / mechanism                        |
|---                                              |---                                           |---                                         |
| Obsidian Sync writes to vault                   | Quartz rebuild                               | systemd path unit OR 5-min timer           |
| `collect-repos` JSON artifact refreshed (30min) | 11ty prebuild.js re-reads → rebuild          | 30-min timer                               |
| `run-kb-recap` artifact refreshed (daily 07:00) | 11ty rebuild                                 | hooks onto the existing timer's `OnSuccess`|
| `gen-status-page` writes JSONL (every 30s)      | 11ty metrics.md rebuild                      | 5-min timer (don't need 30s for a chart)   |
| `mark-todos.md` changes (Obsidian Sync)         | 11ty jira.md rebuild                         | same 5-min timer as metrics                |

All timers are user-level systemd (linger on from §11 phase-02). Build failures log to journal; the existing output stays live.

## Phase sequence

### Phase 14a. Scaffold 11ty dashboard

- Clone `eleventy-base-blog` into `minipc-blog/`
- Replace `content/` with our six pages (index.njk + 4 generated .md + admin.md)
- Adapt `_includes/layouts/base.njk` to match the status-page palette (shared CSS tokens)
- Write `scripts/prebuild.js` that reads artifacts → writes content/*.md
- Configure `pathPrefix: "/app/"` so generated links work under Caddy
- Verify `eleventy build` locally produces `_site/` that renders correctly

### Phase 14b. Scaffold Quartz KB site

- `npx quartz create` into `minipc-quartz/`
- Configure `content/` as a symlink to `~/Documents/worklog/knowledgebase` on the minipc
- `quartz.config.ts`: set `baseUrl`, turn on wikilinks, backlinks, graph, search
- Ignore patterns: `.obsidian/`, `.git/`, `_dive-queue.md`
- Configure pathPrefix so it serves under `/app/kb/`
- Verify `npx quartz build` completes and produces sane output

### Phase 14c. Trim FastAPI to the dynamic bits

- Delete routes: `kb.py` (browse+view; query stays), `today.py`, `jira.py`, `repos.py`, `admin.py`, `metrics.py` HTML page (keep `.json`/`.txt`)
- Keep: `kb_query` (POST), `metrics_api` (JSON/text), `healthz`
- Move dynamic endpoints to `/app/api/*` so the static sites own `/app/` and `/app/kb/`
- Update `minipc-app.service` — unchanged, same port
- Update `phase-12-app.sh` to reflect the slimmer app

### Phase 14d. Caddy routing + rebuild timers

- `Caddyfile` route order (Caddy matches most-specific first):
  ```
  handle_path /app/api/*  { reverse_proxy 127.0.0.1:8081 }
  handle_path /app/kb/*   { root * ~/.local/state/minipc-dashboard/quartz-output; file_server }
  handle_path /app/*      { root * ~/.local/state/minipc-dashboard/blog-output; file_server }
  handle /app             { redir /app/ permanent }
  ```
- systemd timer `rebuild-minipc-blog.timer` every 5 min + `OnChange=` hook from artifact-producing timers
- systemd timer `rebuild-minipc-quartz.timer` every 5 min (or systemd path-unit watching the vault)
- Deploy via `phase-14-static-sites.sh`

### Phase 14e. Migration + cleanup

- Verify parity: every URL that worked in the old FastAPI still works post-switch
- Kill the old Jinja templates once verified
- Update the KB note and README with the new architecture
- Log follow-ups to §12 for anything not covered (e.g., Quartz graph customisation, base-blog CSS drift)

## Critical files

### New

- `local_network_scripts/minipc-blog/`  (entire tree, from eleventy-base-blog)
- `local_network_scripts/minipc-blog/scripts/prebuild.js`  (NEW glue code)
- `local_network_scripts/minipc-quartz/`  (entire tree, from `npx quartz create`)
- `local_network_scripts/phase-14-static-sites.sh`  (deploy + timers)
- `local_network_scripts/files/rebuild-minipc-blog.service` + `.timer`
- `local_network_scripts/files/rebuild-minipc-quartz.service` + `.timer`

### Modified

- `local_network_scripts/minipc-app/main.py`                — drop routers
- `local_network_scripts/minipc-app/routes/`                — delete kb.py (browse+view), today.py, jira.py, repos.py, admin.py; rename metrics.py → metrics_api.py (JSON/text only); leave kb_query.py
- `local_network_scripts/files/Caddyfile`                   — new route table
- `local_network_scripts/files/gen-status-page.sh`          — nav links may need prefix updates

### Deleted

- `local_network_scripts/minipc-app/templates/`             — all .html files (11ty + Quartz own rendering now)
- `local_network_scripts/minipc-app/static/app.css`         — replaced by the shared CSS token file in `minipc-blog/public/css/app.css` (11ty copies it; Quartz can import the same tokens)

## Reusable patterns being pulled in

- **eleventy-base-blog** (official starter) — starting point for the dashboard site
- **Quartz** (jzhao.xyz, separate tool) — starting point for the KB site
- **phase-12-app.sh + phase-13-tasks.sh** — deployment-script pattern extends naturally to phase-14
- **`gen-status-page.sh` → JSONL sink** — unchanged, consumed by 11ty's prebuild step
- **Obsidian Sync** — vault stays live on the minipc, Quartz reads from it directly

## Verification (end-to-end)

After Phase 14 lands:

- [ ] `curl -s http://mork-firebat/app/ | grep -oE "<title>[^<]*"` returns blog title
- [ ] `curl -s http://mork-firebat/app/kb/ | grep -iq graph` or similar signal confirms Quartz served
- [ ] `curl -X POST -d "question=hi" http://mork-firebat/app/api/kb/query` returns an answer
- [ ] `curl http://mork-firebat/app/api/metrics.txt` returns the live one-liner
- [ ] Phone (cellular + Tailscale) loads the homepage cleanly, renders a KB note with wikilinks working
- [ ] Edit a note in the laptop Obsidian → within ~5 min it shows in `/app/kb/<note-path>/`
- [ ] Run `ssh mork@mork-firebat systemctl --user start rebuild-minipc-blog` — blog rebuilds without error
- [ ] Reboot the minipc — all three (blog, quartz, FastAPI) come back; dashboard reachable

## Risks and rollback

- **Two new build systems** (11ty + Quartz) = more moving parts. Mitigation: both are widely-used, fast to build, failures are transparent via journal.
- **Quartz ingests 1,300+ notes** — build time unknown. Mitigation: incremental builds; profile before committing to 5-min cadence. Could slip to 15-min or path-triggered if needed.
- **pathPrefix gotchas** — both tools handle subpath deployments but behave slightly differently (absolute vs relative URL rewriting). Test early.
- **If the refactor goes sideways**, rollback is: revert the Caddyfile to `handle_path /app/* → 127.0.0.1:8081`, revert FastAPI to include the router set that's still in git history. No destructive moves.

## What this plan does NOT do (deliberate deferrals)

- **SSE streaming for KB-ask** — separate Phase 5 item; independent of the static-gen refactor.
- **POST-to-run-now endpoints** (Phase 4) — blocked behind this; we'll add once the static sites are stable.
- **Graph customisation / note-filtering in Quartz** — take the defaults for MVP.
- **Any theme work** beyond matching the shared palette — iterate after MVP is live.

## Execution notes (2026-04-24 Phase 14b SHIPPED)

Phase 14b (Quartz for `/app/kb/*`) landed end-to-end. Concrete learnings that should inform 14a (11ty) and future static-gen work:

### Quartz specifics

- **Quartz generates RELATIVE paths everywhere** (`href="../../../.."`, `href="./index.css"`, `href="#anchor"`). The plan's sed post-processing to inject `/app/kb/` into absolute paths was a false assumption — unnecessary and removed. The rebuild service now has no sed step.
- **Path-prefix deploy recipe that works:** `handle_path /app/kb/*` in Caddy strips the prefix; combined with `try_files {path}.html {path}/index.html {path}` it correctly serves Quartz's pretty URLs (note `.html` files emitted flat, not inside directories).
- **Build perf:** `npx quartz build` against 558 markdown files → 1942 output files in ~15s wall, 40s CPU. The 5-min rebuild-quartz.timer cadence is fine; could easily go to 2-min if sync-freshness matters.
- **`enableSPA: false`** — critical for subpath deploy. With SPA on, Quartz's client-side router fetches `/foo` absolute-path JSON for route changes, which breaks under `handle_path` prefix-stripping.
- **Upstream tag/branch:** we track `main` HEAD (current tip is `d25a6ea` as of 2026-04-24). Pin-on-upgrade is a follow-up if we hit breaking changes.

### Vault cleanup findings (unexpected scope)

Phase-08 rsync seed from 2026-04-23 left the minipc vault in a 3-way mess. Diagnosed + cleaned this session:

- **Live synced vault on the minipc is at `~/Documents/worklog/work/`** (NOT at `~/Documents/worklog/knowledgebase/` as assumed). The container's Obsidian Sync joined via `/vaults/work/` which maps to `~/Documents/worklog/work/` on host.
- The phase-08 seeded content at `~/Documents/worklog/{knowledgebase,Untitled*.md,...}` was stale. **Deleted (24 MB backup at `/tmp/worklog-stale-seed-*.tar.gz`).**
- A nested frozen snapshot at `~/Documents/worklog/work/worklog/` (256 md files, all Jan-2026 mtimes — origin unclear, probably an early Obsidian Sync reconciliation artefact). **Deleted (103 KB backup at `/tmp/work-worklog-nested-*.tar.gz`).**
- Cleanup meant Quartz points at `~/Documents/worklog/work/knowledgebase/` — the live-sync subfolder, 560 files. Sync lag may still leave 50-100 stale files at times, acceptable.

### Obsidian short-wikilinks need alias redirects

A whole class of 404s showed up post-deploy: Obsidian wikilinks like `[[2026-04-14_connector-library-deployment-lifecycle]]` that reference a **date-prefixed file** (`2026-04-14_connector-library-deployment-lifecycle.md`) or a file at a deep path via just its basename. Obsidian's own fuzzy resolver handles this; Quartz's `markdownLinkResolution: "shortest"` emits the wikilink text verbatim as the URL, so the href points to a slug that doesn't exist on disk.

Fix: **pre-build pass that adds the date-stripped (or basename) slug as an `aliases:` entry in each file's frontmatter**, combined with Quartz's `AliasRedirects()` plugin (already in our config). This creates a `/short-slug/index.html` that redirects to the real URL. Resolves transparently to the browser.

Implementation: `rebuild-quartz.sh` gained a Python pass using pyyaml that walks `~/quartz/content/*.md`, matches filenames of the form `YYYY-MM-DD[_-]<slug>`, and injects `<slug>` into `aliases:`. The rsync from the vault overwrites content each build so the aliases are re-added idempotently (they never leak back to the vault).

Impact on build: +71 HTML files emitted for alias redirects (1920 → 1991 total), negligible on build time. pyyaml added as a minipc dep.

### Caddy routing order matters

- Added `handle /app/kb/query*` BEFORE `handle_path /app/kb/*` to preserve FastAPI's POST query endpoint. Forgot this on first deploy — Quartz shadowed the query route until the specific-match handle was prepended.
- Full /app routing order (Caddyfile now):
  ```
  handle /app/kb/query*   → FastAPI         (keeps KB-ask working)
  handle_path /app/kb/*   → Quartz output   (everything else under /app/kb/)
  handle_path /app/*      → FastAPI         (the rest of the dashboard)
  ```
  Phase 14a will add `handle /app/api/*` for the trimmed-down FastAPI once 11ty takes over the dashboard landing / today / jira / repos pages.

### Files touched

- `minipc-quartz/quartz.config.ts` — our overlay (title, baseUrl, ignorePatterns, disabled analytics + CustomOgImages, enableSPA: false, palette matches static-status-page)
- `phase-14b-quartz.sh` — deploy script (clone, overlay, symlink content, npm i, build, rotate, caddy patch)
- `files/rebuild-quartz.service` + `rebuild-quartz.timer` — 5-min rebuild cadence
- Caddyfile — two new handle blocks + existing `handle_path /app/*` preserved

### 14a shipped 2026-04-24 — 11ty dashboard live at `/app/`

Landed cleanly. Structure in `local_network_scripts/minipc-blog/`:

- `eleventy.config.js` with `pathPrefix: "/app/"` + `EleventyHtmlBasePlugin` so absolute URLs get the prefix and Caddy's `handle_path` strips it
- `content.json` (directory data file) → every markdown in `content/` picks up `layout: layouts/dashboard.njk` + `tags: [dashboard]` automatically
- `_data/site.json` — single source for brand text, host, cross-site URLs; the `base.njk` layout reads it
- `_includes/layouts/{base,dashboard}.njk` — shell chrome + article wrapper
- `scripts/prebuild.js` — Node ESM, reads task artifacts, writes `content/{today,jira,repos,metrics}.md`. **One generator function per page** — adding a new page is: write `gen<Name>()` → push it into `main()`'s generator array. Frontmatter helper emits YAML flow-style (JSON subset) for nested objects to satisfy gray-matter's js-yaml parser.
- Shared palette CSS — same `:root` custom-property tokens as `gen-status-page.sh` and `quartz.config.ts` colours, so the three surfaces look like one site.
- Atomic rotate via `~/bin/rebuild-blog.sh` (mirrors `rebuild-quartz.sh`), keeps `.prev` for rollback.

Caddy routing after 14a:
```
handle /app/kb/query*   → FastAPI          (KB-ask endpoint, specific-first)
handle_path /app/kb/*   → Quartz output    (KB static)
handle_path /app/api/*  → FastAPI          (dynamic — metrics.json/txt, healthz)
handle_path /app/*      → 11ty output      (dashboard static — NEW)
handle /app             → redir /app/
```

Gotchas captured:

- **11ty v3 is ESM-only** — must set `"type": "module"` in `package.json`, use `import/export` throughout. The default base-blog starter is already ESM.
- **gray-matter parses nested-object frontmatter strictly** — block-style (`key:\n<json>`) fails because YAML treats the json-object-on-next-line as a string. Use YAML flow (`key: {"a":1}` all on one line) — it's a subset of JSON and parses cleanly.
- **11ty `url` filter vs raw href** — the `EleventyHtmlBasePlugin` handles `<a href="/today/">` rewrites for you; stick to absolute paths in templates and let the plugin prepend `/app/`.
- **Caddy `handle_path` regex-swap gotcha** — the phase-14a script replaces the original FastAPI `handle_path /app/*` block via regex. If the old block wasn't tab-indented consistently, the regex misses it and leaves a dead duplicate at column 0 (harmless — later handles don't fire — but ugly in the file). Cleanup step in the script now removes any non-indented stray.
- **11ty's `EleventyHtmlBasePlugin` double-prefixes URLs** — it parses output HTML and prepends `pathPrefix` to any absolute URL, but doesn't detect URLs that ALREADY have the prefix. So `/app/kb/` (cross-site URL in `site.json`) + plugin becomes `/app/app/kb/`, and `{{ '/css/app.css' | url }}` (produces `/app/css/app.css`) + plugin becomes `/app/app/css/app.css`. Both 404. **Fix: don't load `EleventyHtmlBasePlugin`.** The `| url` filter alone does the right thing for internal paths, and bare absolute URLs (to /dashboard/, /obsidian/, cross-site in site.json) stay bare — which is what we want. Also: collection item URLs (`item.url` from `collections.nav`) are internal (pre-pathPrefix), so they MUST be piped through `| url` in templates.
- **Rebuilt-outside-vault artefacts got nuked** — `~/Documents/worklog/dashboard/` is a SIBLING of the vault's `work/`, not inside it. The earlier vault-cleanup deleted it too. Restored via rsync from laptop; long-term fix is §13a's laptop→minipc sync will mirror it regularly. Phase 14a's deploy script does NOT seed it (kept scope tight).

### Adding a new dashboard page (comprehensive)

There are three flavours, picked by **what the page needs to render**:

| Flavour | Example | Where it lives | Build mechanism |
|---|---|---|---|
| **Static markdown** | `/app/admin` — hand-written prose with SSH one-liners | `minipc-blog/content/<slug>.md` | 11ty renders once per rebuild |
| **Generated markdown** | `/app/today`, `/app/jira`, `/app/repos`, `/app/metrics` — reads a file/artifact/API, emits markdown | `minipc-blog/scripts/prebuild.js` → writes `content/<slug>.md` | 11ty renders the emitted file |
| **Dynamic API** | `/app/api/kb/query` (POST), `/app/api/metrics.{json,txt}` (live reads) | `minipc-app/routes/<mod>.py` (FastAPI) | Caddy reverse-proxies `/app/api/*` → `127.0.0.1:8081` |

Pick dynamic API only if the route needs POST, a subprocess call, live-fresh-every-request data, or SSE streaming. Everything else should be generated markdown (rebuilt every 5 min).

#### Flavour 1 — static markdown

1. Drop a file at `local_network_scripts/minipc-blog/content/<slug>.md`:
   ```yaml
   ---
   title: my page
   tileDescription: what shows on the landing tile
   eleventyNavigation:
     key: my-page   # nav-bar label
     order: 50      # sort order; 1=home, 10=today, 20=jira, 30=repos, 40=metrics, 99=admin — add between
   ---
   Any markdown body here.
   ```
2. `content/content.json` auto-applies `layout: layouts/dashboard.njk` + `tags: [dashboard]` — tile + nav entry appear automatically. If you want a different wrapper, add `layout: layouts/<other>.njk` in the frontmatter.
3. Deploy: `TARGET=mork@actuate-dev.local ./phase-14a-blog.sh` (or just wait up to 5 min for the timer to pick up rsync'd changes — except rsync doesn't happen on the timer, so you DO need to deploy).

#### Flavour 2 — generated markdown (reads an artifact / API / file)

1. Write a `gen<Name>()` function in `minipc-blog/scripts/prebuild.js`:
   ```js
   function genMyPage() {
     const data = readMaybe("/home/mork/.local/state/somewhere/latest.json");
     const mtime = statMtime("/home/mork/.local/state/somewhere/latest.json");

     const fm = frontmatter({
       title: "my page",
       tileDescription: "what the tile says",
       eleventyNavigation: { key: "my-page", order: 50 },
       generatedAt: mtime,
     });
     const body = /* render `data` into markdown */;
     return { path: join(CONTENT_DIR, "my-page.md"), content: fm + body };
   }
   ```
2. Push the function into `main()`'s generator array:
   ```js
   const generators = [genToday, genJira, genRepos, genMetrics, genMyPage];
   ```
3. The helper `frontmatter()` emits YAML-flow-style for nested objects (JSON subset) so gray-matter's YAML parser accepts it. **Do not** put nested objects on a separate line — it breaks the parse.
4. The emitted file is written into `content/` at build time and rendered by 11ty in the same rebuild. The `.gitignore` / rsync excludes don't need updating — `content/*.md` is always re-materialised.
5. Deploy: same as flavour 1 — `phase-14a-blog.sh` pushes the new prebuild.js + runs one rebuild. Subsequent rebuilds pick it up automatically.

For rendering raw HTML inside markdown (e.g. inline SVG sparklines), just include the HTML — 11ty's markdown-it has `html: true`. For rich HTML templates (e.g. a widget layout), write a custom Nunjucks layout at `_includes/layouts/<name>.njk` and reference it in the generated frontmatter's `layout:`.

#### Flavour 3 — dynamic FastAPI route

1. Add a router in `minipc-app/routes/<mod>.py`:
   ```python
   from fastapi import APIRouter
   router = APIRouter()

   @router.get("/foo")
   async def foo():
       return {"live": True}
   ```
2. Include it in `main.py`:
   ```python
   from routes import mymod
   app.include_router(mymod.router, prefix="/mymod", tags=["mymod"])
   ```
3. Route is reachable at `/app/api/mymod/foo` because Caddy's `handle_path /app/api/*` strips the prefix and proxies to FastAPI.
4. Deploy via `TARGET=mork@actuate-dev.local ./phase-12-app.sh` — it rsyncs + restarts the service.
5. If the route needs to be linked from an 11ty page, hardcode the full URL (e.g. `/app/api/mymod/foo`) — 11ty doesn't resolve API paths.

Do NOT add dynamic-flavour pages at `/app/<name>` top-level — those collide with 11ty's output directory. Keep dynamic under `/app/api/*` always.

#### CSS / styling conventions

- **Tokens live in `minipc-blog/public/css/app.css`** — `:root` custom-properties, `@media (prefers-color-scheme: dark)` for dark-mode. Palette is shared with `gen-status-page.sh` and `quartz.config.ts` so all three surfaces match.
- **Adding a new component**: append a new rule block to `app.css`, reference tokens (`var(--accent)` etc.) not hardcoded colours.
- **Adding a new page layout**: create `_includes/layouts/<name>.njk` that extends `layouts/base.njk`.

#### Cross-site URLs

`_data/site.json` holds every inter-surface URL (KB, ops dashboard, status page). Reference in templates via `{{ site.kbUrl }}` — don't hardcode. If the minipc ever gets a different hostname or the Caddy routing changes, update only `site.json`.

#### Local dev loop

From `minipc-blog/` on the laptop:
```bash
npm install                # one-time
npm run serve              # 11ty dev server with prebuild + hot-reload
# browse http://localhost:8080/
```

Prebuild generates content from the laptop's LOCAL artifact paths (may not have data — generated pages will show their empty-state placeholders). Full data needs the minipc's artifacts, which means testing after deploy.

#### Debugging

- **Build fails in `prebuild.js`**: `node scripts/prebuild.js` locally shows the error. The wrapper (`~/bin/rebuild-blog.sh`) pipes stderr to journald on the minipc.
- **Build fails in 11ty**: `journalctl --user -u rebuild-blog -n 50` on the minipc. Common cause: YAML frontmatter parse error (nested objects on their own line — use flow style).
- **404 on a page**: `ssh mork@mork-firebat ls ~/.local/state/minipc-dashboard/blog-output/<slug>/` — file emitted? If not, 11ty skipped the source file (check frontmatter).
- **Broken palette**: check `curl -s http://mork-firebat/app/css/app.css | head` — if the CSS doesn't have our `:root` block, the rsync didn't land it.
- **Tile doesn't appear on landing**: missing `eleventyNavigation.key` in frontmatter. The `collections.nav` loop in `index.njk` filters for the `dashboard` tag (auto-applied by `content.json`) and sorts by `order`.

#### Typical latency from edit → live

- Local edit + `phase-14a-blog.sh`: ~10-15 seconds end-to-end (rsync + npm, initial build, Caddy reload — skipped if already set up)
- Artifact change (task runs that writes a new file): **up to 5 min** until the next `rebuild-blog.timer` tick. Force an immediate rebuild: `ssh mork@mork-firebat systemctl --user start rebuild-blog.service`

### Deferred (status-refreshed post 14a)

- **14c (trim FastAPI)** — ready to execute. Remove `minipc-app/routes/{kb,today,jira,repos,admin,metrics}.py`, keep `kb_query` + a new `metrics_api` (JSON/text only) + `healthz`. Also update `minipc-app.service` root_path if appropriate (currently `/app` — move to `/app/api` to match the new routing).
- **14d (formal Caddy routing overhaul)** — mostly done during 14a; just needs a cleanup pass to ensure the file is tidy and documented.
- **14e (parity verification + old Jinja cleanup)** — trivially contingent on 14c.

## Related

- [[2026-04-23_firebat-minipc-as-claude-dev-box]] — overall architecture
- [[2026-04-23_firebat-minipc-network-setup]] — provisioning prequel
- §12 in [[mark-todos]] — workstream tracker; this plan is §12g
- §13 in [[mark-todos]] — failsafe toolkit (the new minipc-quartz dir gets rsynced under §13a)
