---
title: "Research Inbox"
type: convention
created: 2026-04-21
updated: 2026-04-21
author: kb-bot
---

# Research Inbox

Staging area for **downloaded source material** that `WebFetch` can't process directly — PDFs, gated content that requires manual download, redirect-trap URLs. Populated by either:

1. **Agents** — the `research-prospector` downloads PDFs it encountered during a web-research pass into this directory using `curl`, so the source-reader (or a human) can process them later via `Read(file, pages=)`.
2. **Humans** — the user manually drops a PDF / HTML / MD file here (e.g. after filling out a vendor gated-content form, after fetching a paywalled paper via a library proxy).

## Why this directory exists

Discovered 2026-04-21 during the frame-storage prospector pilot ([[2026-04-21_rd-agent-pilot-learnings]]): `WebFetch` returns unparseable binary content when pointed at a PDF URL. The workaround is a `curl` download + `Read(file, pages="1-N")` — proven end-to-end on Milestone's XProtect Storage Architecture PDF (1.5MB, 48 pages, opened cleanly via `Read`).

Having one well-known inbox prevents ad-hoc per-topic staging folders scattered across the KB.

## Filename convention

```
{vendor-or-source-slug}-{short-title-slug}-{YYYY-MM-DD}.{ext}
```

Examples:
- `milestone-xprotect-storage-architecture-2023-09.pdf`
- `axis-av1-codec-blog-2024.html`
- `nature-keyframe-extraction-2024.pdf`

The date is the **source's publish/version date when known**, else the ingest date. The source-reader will parse the slug when writing the downstream source note.

## Flow

```
reading-list entry (needs a PDF)
          │
          ├── agent: curl -L -o _research-inbox/{slug}.pdf {url}
          │   (research-prospector can do this during its pass)
          │
          ├── user drops file here manually (gated content, paywalled paper)
          │
          ▼
  [ _research-inbox/{slug}.pdf  or  .html  or  .md ]
          │
          ▼
  source-reader agent: Read(file, pages="1-N") → source note in topic KB
          │
          ▼
  After source note written, the inbox file can be:
    (a) kept in place (source-of-truth archive), OR
    (b) moved to /archive/ subfolder once note is written + reviewed
```

## What goes here vs. elsewhere

- **Goes here:** canonical PDFs / HTML / docs from reading-lists that need agent processing
- **Does NOT go here:** random personal PDFs unrelated to research, downloaded pages already turned into source notes, temp files

## Pending / to-revisit

Reading-list entries that need this workflow (maintained by agents; check + clear periodically):

- [ ] Milestone XProtect Storage Architecture 2023-09 — downloaded 2026-04-21, pending source-reader processing
- [ ] Nature: keyframe extraction for surveillance videos (2024) — 303 redirect on DOI; try `curl -L` with explicit user-agent
- [ ] Milestone XProtect VMS 2025 R1 System Architecture — PDF, not yet downloaded
- [ ] Verkada H.265 whitepaper — form-gated; **user manual download** required
- [ ] (add more as `research-prospector` flags them)

## Related

- [[2026-04-21_rd-agent-pilot-learnings]] — where this convention came from
- `~/.claude/agents/research-prospector.md` — agent that downloads here
- `~/.claude/agents/source-reader.md` — agent that reads from here
