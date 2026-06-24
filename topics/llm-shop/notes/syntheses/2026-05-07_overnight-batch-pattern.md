---
title: "Overnight batch pattern for the LLM shop"
type: synthesis
topic: llm-shop
tags: [llm-shop, batch, kb-intake, overnight, systemd, harness-pattern, kb-readinglist-drive]
created: 2026-05-07
updated: 2026-05-11
author: kb-bot
status: design-locked
outgoing:
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/syntheses/2026-05-07_kb-deep-intake-architecture.md
  - topics/llm-shop/notes/syntheses/2026-05-07_long-running-multi-agent-pattern.md
incoming:
  - topics/actuate-platform/notes/concepts/2026-06-22_npu-server-llm-shop-runbook.md
  - topics/llm-shop/_summary.md
  - topics/llm-shop/notes/syntheses/2026-05-07_kb-deep-intake-architecture.md
  - topics/llm-shop/notes/syntheses/2026-05-07_long-running-multi-agent-pattern.md
  - topics/personal-notes/notes/daily/2026-05-08.md
  - topics/personal-notes/notes/daily/2026-05-11.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-06-24
---

# Overnight batch pattern for the LLM shop

> **Refinement (2026-05-07, same day):** the worker behind this batch is now [[2026-05-07_kb-deep-intake-architecture|kb-deep-intake]] — a 5-phase planner→workers→composer→linker pipeline — not the original single-pass `POST /kb-intake` harness. The transport (run-id, scp, manifest, pull, merge) is unchanged; only the worker module that the batch runner imports is richer. Both syntheses are load-bearing: this one for plumbing, the deep-intake one for what runs inside.

## What this is

A pattern for running long [[2026-05-05_phase-2-next-steps|kb-intake]]-style workloads (URL → drafted KB source note) on the [[host-npu-server|`npu-server`]] LLM shop that survives the laptop sleeping or shutting down. The laptop dispatches a batch, the box runs to completion, the laptop pulls and merges results in the morning.

This is the third orchestration layer on top of the existing [[harness-pattern|harness pattern]]:

| Layer | Surface | Lifetime | Use |
|---|---|---|---|
| Harness | `POST /kb-intake` | per-request | One URL → one draft response |
| Sync driver | `~/bin/kb-readinglist-drive <topic>` | seconds-minutes | Walk a reading-list, ingest a few URLs synchronously |
| **Batch (this doc)** | `kb-batch-submit` / `kb-batch-pull` | hours, survives laptop shutdown | Walk a reading-list (or any URL list), ingest dozens, pull in the morning |

## Why we need it

`kb-readinglist-drive` runs the orchestration on the laptop. If the laptop sleeps, the in-flight HTTP request times out, the loop dies, only drafts already written survive. With ~7-10 min per draft on the [[2026-05-05_ollama-vulkan-broken-on-meteor-lake|SYCL Qwen-14B backend]], a 30-URL batch is ~4 hours wallclock — comfortably overnight, but only if the orchestration runs on the box.

The batch pattern also generalizes beyond reading-lists. Any "ingest N URLs and put the drafts somewhere" workload (the [[_dive-queue|dive queue]], an arXiv reading list, an OPML import) can reuse the same dispatch + pull plumbing.

## Flow

```
LAPTOP (evening)               BOX (npu-server)              LAPTOP (morning)
──────────────────             ──────────────                ──────────────
kb-batch-submit \              ⤷ writes:                     kb-batch-pull <run-id>
  --topic video-processing       ~/llm-shop/                   ↓ scp -r run dir
  --limit 30                     research-output/              ↓ for each manifest item:
  ↓ build input.json             <run-id>/                      • write draft to
  ↓ scp input.json to box          input.json                     topics/<topic>/
  ↓ ssh systemctl --user           drafts/                        _research-inbox/
       start llm-shop-kb-           <slug>.md                    • flip reading-list
       batch@<run-id>               …                              line → [x] [[slug]]
  ↓ print run-id                   manifest.json                ↓ archive manifest locally
  ↓ exit (laptop free)             log.jsonl                    ↓ leave box dir for now
                                   DONE  ← sentinel               (cleanup is age-based)
```

## Layout on the box

```
~/llm-shop/research-output/<run-id>/
├── input.json        # what the laptop sent
├── drafts/<slug>.md  # one file per successfully drafted URL
├── manifest.json     # per-item status + draft_path + topic_claimed + elapsed_ms
├── log.jsonl         # one event per line (start, fetch_ok, gen_ok, write, error)
└── DONE              # touched at clean exit; absence = in-progress or crashed
```

`<run-id>` format: **`YYYY-MM-DDTHHMMZ-<topic-or-tag>-<seq>`** (UTC, no separator-conflicts). Example: `2026-05-07T2235Z-video-processing-001`. UTC chosen over local time to avoid DST/travel ambiguity.

## Schemas

**`input.json`** (laptop → box):

```json
{
  "run_id": "2026-05-07T2235Z-video-processing-001",
  "submitted_at": "2026-05-07T22:35:00Z",
  "context": { "type": "reading-list", "topic": "video-processing" },
  "items": [
    {
      "ref_id": "0023",
      "url": "https://github.com/abhiTronix/vidgear",
      "hint_topic": "video-processing",
      "anchors": ["pyav-entity", "ffmpeg-entity"],
      "max_summary_words": 300
    }
  ]
}
```

`ref_id` is the reading-list line index at submit time. The pull step uses URL match as primary, ref_id as tiebreaker — handles the case where the reading-list is edited between submit and pull.

**`manifest.json`** (box → laptop):

```json
{
  "run_id": "...",
  "started_at": "2026-05-07T22:35:04Z",
  "finished_at": "2026-05-08T03:12:11Z",
  "exit": "success|partial|error",
  "items": [
    {
      "ref_id": "0023",
      "url": "...",
      "status": "ok|failed|timeout",
      "draft_path": "drafts/2026-05-07-vidgear.md",
      "topic_claimed": "video-processing",
      "elapsed_ms": 87234,
      "error": null
    }
  ]
}
```

## Components (new files to build)

| Where | File | Purpose |
|---|---|---|
| Laptop | `~/bin/kb-batch-submit` | Build `input.json` from a reading-list (or URL file), scp to box, kick off systemd unit, print run-id and exit |
| Laptop | `~/bin/kb-batch-pull` | scp run dir off box, walk manifest, write drafts into KB, flip reading-list lines, archive manifest |
| Laptop | `~/bin/kb-batch-status <run-id>` | Sanity check — ssh + DONE check + last log lines, for "did it finish?" |
| Box | `~/llm-shop/bin/kb-batch-runner.py` | Worker — reads input.json, loops items, calls `kb_deep_intake.run(item)` per [[2026-05-07_kb-deep-intake-architecture]], writes drafts + manifest + log |
| Box | `~/llm-shop/systemd/llm-shop-kb-batch@.service` | Templated user unit; `%i` is the run-id, runner reads `~/llm-shop/research-output/%i/input.json` |

All source-controlled in `local_network_scripts/files/llm-shop/` (box-side files) and `local_network_scripts/files/` (laptop-side scripts).

## Concurrency

Single SYCL backend → only one inference at a time. Runner takes `flock(~/llm-shop/research-output/.lock)` non-blocking; if a second batch is dispatched while one is running, the second runner exits with `exit: error` and a clear message in `log.jsonl`. No queueing in v1 — caller resubmits manually.

## Cleanup

**Locked decision:** keep the **last 7 days** of run dirs on the box. Pull step does not delete (so a re-pull is always possible). Runner-side cleanup pass at start of each run: `find ~/llm-shop/research-output -maxdepth 1 -mtime +7 -type d -name '20*Z-*' -exec rm -rf {} +`. Cheap and self-healing — even if no batches run for a while, the next one cleans up.

Laptop side: pulled manifests archived to `~/Documents/worklog/knowledgebase/_pulls/<run-id>/manifest.json` so a future audit can answer "what got ingested when". Drafts themselves live in their topic's `_research-inbox/` and don't need archiving (they're either promoted to a real note or deleted by the human reviewer).

## Failure handling

- **Per-URL failure** (502 from harness, fetch error, timeout): manifest item gets `status: failed`. Pull step skips merge for that line; reading-list entry stays `[ ]`. User can resubmit just the failed URLs by passing `--retry-from <run-id>` (followup, not v1).
- **Whole-run crash** (box reboot, OOM kill, manual systemctl stop): no `DONE` sentinel. **Locked decision: pull step merges what landed and warns**, leaving unprocessed lines `[ ]` for resubmit. Output: `"<run-id>: partial — 17/30 merged, 13 unprocessed (resubmit those URLs)"`.
- **Network failure** box→external: same as per-URL failure — recorded in manifest, skipped on pull.
- **Concurrent dispatch**: second runner exits immediately due to flock; submit step warns and shows the in-flight run-id.

## Why not extend the harness instead

The harness (`POST /kb-intake`) is intentionally stateless and per-URL. Pushing batch state into the harness would couple the model-call surface to the orchestration model. Two reasons to keep them separate:

1. The harness can be reused for non-batch consumers (Obsidian plugin, Claude Code skill, Pi agent) without dragging batch state along.
2. Future batch consumers — dive queue, OPML import — don't need a reading-list parser, just URL + topic-hint pairs. Orchestrator is the right layer to expose the generic interface.

## Driver split — locked

`kb-readinglist-drive` and `kb-batch-submit` stay as separate commands. Mental model:
- **`kb-readinglist-drive <topic>`** — fast feedback, hand-on-keyboard, 1-5 URLs, runs locally
- **`kb-batch-submit --topic <topic> --limit N`** — fire-and-forget, dozens of URLs, runs on the box

Considered collapsing into `kb-batch-submit --sync` — rejected because the synchronous path doesn't need scp/ssh/systemd/manifest plumbing, and the simpler driver is easier to debug when the harness misbehaves.

## Followups (out of v1 scope)

- `kb-batch-submit --retry-from <run-id>` — resubmit only failed items
- Web view of run history at `:8080/runs/<run-id>` — surfaces `manifest.json` + `log.jsonl` timeline
- Batch from arbitrary URL file: `kb-batch-submit --urls urls.txt --hint <topic>`
- Multi-topic batch (one batch covers items from several reading-lists)
- Auto-pull cron on the laptop — every morning at 0700 local, pull any new `DONE` runs
- Slack/email ping on `DONE`

## Build sequencing

1. Hone the [[kb-intake-harness|kb-intake]] output quality via the synchronous pilot driver (in flight 2026-05-07)
2. Once drafts are quality-on-par, build this overnight pattern against the validated harness
3. Run a 30-URL batch overnight as the first real exercise
4. Add followup niceties from the list above as needed

## Build log (2026-05-11)

Plumbing landed in two commits: `0eec65c` (batch pieces + linker fix) and `e62252f` (the rest of the box-mirror that had drifted untracked since 2026-05-06). Sequencing was reordered against the original plan above: built the dispatch path before re-tuning prompts, on the reasoning that real-corpus drafts beat synthetic prompt-iteration.

**Shipped files:**

| Where | Path | Role |
|---|---|---|
| Laptop | `~/bin/kb-batch-submit` | reading-list → input.json → scp → systemctl start |
| Laptop | `~/bin/kb-batch-pull` | scp run dir → re-link with live KB → drop into `_research-inbox/` → flip reading-list |
| Laptop | `~/bin/kb-batch-status` | quick "did it finish?" — DONE check + manifest counts + last 10 log events |
| Box | `~/llm-shop/bin/kb-batch-runner.py` | imports `kb_deep_intake.run`, loops items, persists manifest after every item, flock to prevent concurrent runs |
| Box | `~/llm-shop/systemd/llm-shop-kb-batch@.service` | templated oneshot, `%i` is the run-id |

Smoke test (`2026-05-11T1331Z-video-processing-001`, ollama backend via per-instance drop-in override): 2 URLs (decord + vidgear), ~23 min wallclock, both merged cleanly to `topics/video-processing/_research-inbox/`, reading-list lines flipped, manifest archived to `_pulls/`.

**Bug fix bundled with the plumbing — linker substituted zero anchors before this:** the original linker matched anchor slugs literally (e.g. `ffmpeg-entity` looked for "[[ffmpeg-entity|ffmpeg]] entity" in body text — a phrase that never occurs in real prose). New behavior:

1. Reads each anchor file's frontmatter `title:` field, falls back to slug-with-dashes-as-spaces.
2. Splits the title at " — ", " - ", or trailing parenthetical so `FFmpeg Python bindings — decision matrix` matches as `FFmpeg Python bindings`.
3. Hyphen-aware boundaries `(?<![A-Za-z0-9_\-])...(?![A-Za-z0-9_\-])` instead of `\b`, so `ffmpeg` inside `ffmpeg-python` is NOT broken.
4. Splits the chunk on existing wikilinks, code spans, and fenced code blocks before substitution — prevents `[[ffmpeg-entity|...]]` getting re-wrapped, and stops `import ffmpeg` from getting linked.
5. Tokens within a form accept `[\s\-]+` as the inter-token separator, so an anchor whose title is "[[ffmpeg-python-bindings|FFmpeg Python bindings]]" still matches body text "ffmpeg-python bindings".

**Architecture decision worth noting:** the linker runs *twice* — once on the box (kb_root="" → frontmatter-repair + sanity-caps only, no substitution since the box has no KB) and once on the laptop during pull (kb_root=KB_ROOT → full anchor substitution). It's idempotent thanks to the existing `if f"[[{anchor}" in chunk: continue` skip-if-linked check. This decouples the box from the KB filesystem and keeps the anchor walk local to where the truth lives.

**Quality observations for prompt-tuning followup (open work in §24):**
- Planner is too inclusive: vidgear draft kept "Donations and Sponsorships" + "Contributor Information" sections that should have been in `skip_source_idxs` per the schema. The planner system prompt needs sharper guidance on what counts as KB-relevant.
- Open-questions section still drifts toward generic ("How does X compare?", "What are the system requirements?") rather than the planner's `open_question_seeds`. Probably a composer prompt issue — the seeds aren't being respected.
- Linker missed `LibAV` (decord) — `ffmpeg-libav-libraries.md` has title "FFmpeg libav* libraries" which doesn't reduce to a "libav" alias. Followup: optional `aliases:` frontmatter list.

## Related

- [[2026-05-05_using-the-llm-shop|Using the LLM Shop — Day-to-Day Reference]]
- [[2026-05-05_phase-2-next-steps|Phase 2 next-steps menu]]
- [[2026-05-05_ollama-vulkan-broken-on-meteor-lake|Why kb-intake routes to SYCL not Ollama-CPU]]
- [[host-npu-server]] — the box this all runs on
- [[harness-pattern]] — why the harness stays stateless
