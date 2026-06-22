---
title: "Verdict-as-exit-code footgun + container_hash audit pattern"
type: synthesis
topic: engineering-process
tags: [systemd, monitoring, post-merge-verification, nrql, lessons-learned, soak-script, footgun]
created: 2026-05-12
updated: 2026-05-12
author: kb-bot
outgoing:
  - topics/personal-notes/notes/daily/2026-05-12.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/personal-notes/notes/daily/2026-05-12.md
incoming_updated: 2026-05-13
---

# Verdict-as-exit-code footgun + container_hash audit pattern

Two generalizable lessons that surfaced during the PR #1688 ([vms-connector](https://github.com/aegissystems/vms-connector/pull/1688)) post-merge verification on 2026-05-12. Both cost real session time before being recognized, and both have clear default patterns going forward.

## Lesson 1 — Verdict-as-exit-code on a oneshot systemd unit is a footgun

### What broke

`~/bin/pr-1688-soak-check` (an autonomous Tier-1 verification script — see [[three-tier-routine-check-pattern]] for the broader pattern) was designed to surface its overall verdict via the process exit code:

```python
sys.exit({"GREEN": 0, "YELLOW": 1, "RED": 2}[overall])
```

The intent was reasonable: an external monitor could `systemctl is-failed pr-1688-soak-tonight.service` and react when the verdict went RED.

The reality bit hard. Both `pr-1688-soak-t1h.service` and `pr-1688-soak-tonight.service` ran successfully overnight, produced complete reports, and persisted JSON state. They exited 2 because the verdict was genuinely RED (pre-restart fleet was still on the old image; expected). systemd's LSB exit-code reporting surfaced this as:

```
Main process exited, code=exited, status=2/INVALIDARGUMENT
Failed with result 'exit-code'.
```

The morning post-mortem latched onto `INVALIDARGUMENT` (an LSB convention for "bad CLI args") and concluded `argparse` had rejected a flag — even though `argparse` had never run. The "fix" task then was scoped as patching a missing-flag bug that didn't exist. Real cost: roughly half a session spent in the wrong direction.

### Why systemd-LSB exit codes are misleading

The Linux Standard Base init-script convention maps integer exit codes to named statuses for human readability:

| Exit code | LSB name             |
|-----------|----------------------|
| 0         | success              |
| 1         | generic error        |
| 2         | INVALIDARGUMENT      |
| 3         | NOTIMPLEMENTED       |
| 4         | INSUFFICIENT_PRIVILEGES |
| ...       | ...                  |

systemd surfaces these in `systemctl status` regardless of what the process actually did. Any script that exits 2 — for any reason — gets the `INVALIDARGUMENT` label glued onto its failure record. Once that label is in the daily-note paste, it actively misleads the next reader.

### The default pattern going forward

For any Tier-1 verification script wired to a `Type=oneshot` systemd unit:

1. **Process exit code = "did the script complete?"** Use `sys.exit(0)` on successful run, non-zero only when the script actually crashed (uncaught exception, missing creds, NR auth failure, etc.).
2. **Verdict = artifact on disk.** Write JSON state to a predictable path (`~/.local/state/minipc-tasks/<job>/<label>-<ts>.json`) and append markdown to the daily note (already a working pattern in [[skill-daily-scope]]).
3. **Verdict-driven alerting goes in a separate monitor.** If you want a paging signal on RED, layer a follow-up timer that reads the JSON state file or greps the daily-note section. Don't conflate "the script crashed" with "the verdict was bad" — they're qualitatively different incidents and conflating them poisons the diagnosis path.
4. **Add a `SuccessExitStatus=` to the unit if you genuinely want exit-code-as-signal.** This tells systemd that a non-zero exit is still a successful run (e.g., `SuccessExitStatus=0 1 2`). But this still corrupts `systemctl is-failed` semantics, so prefer pattern #3.

### What was actually fixed

`local_network_scripts/files/pr-1688-soak-check.sh` line 280 was changed from `sys.exit({"GREEN":0,"YELLOW":1,"RED":2}[overall])` to `sys.exit(0)` with an inline comment explaining the rationale. Synced to Firebat, failed units reset, re-fired cleanly with `status=0/SUCCESS`.

## Lesson 2 — `container_hash` is the only reliable restart-audit signal for Connector-EKS pods

### What kept getting wrong

The PR #1688 verification needed to confirm which connector pods had rotated onto the new image (ECR push of `sha256:a1a9a6d3...` at 2026-05-11T19:04:27Z). The session tried three different proxies before landing on the right one:

1. **`message LIKE '%Starting connector%'`** — a "pod just booted" log marker. The pattern doesn't actually exist in this codebase. Query silently returned zero rows, which was interpreted as "0% of pods restarted." Caveat added to the daily note.
2. **`earliest(timestamp) FROM Log ... FACET container_name SINCE 4 hours ago`** — first_seen timestamp within a query window. The bug is subtle: `earliest()` within `SINCE 4 hours ago` returns the *window edge*, not the actual pod birth time, if the pod has been alive longer than the window. So a pod that booted at T-12h shows `first_seen = T-4h` in a 4-hour window, indistinguishable from a pod that genuinely booted 4 hours ago. This reproduced the "stale pods" false-positive *after* the caveat was already in place.
3. **`uniques(container_hash) FACET container_name SINCE 30 hours ago`** + `latest(container_hash) ... SINCE 30 minutes ago` — this is the right pattern.

### Why `container_hash` works

NR `Log` events in the Connector-EKS environment carry a `container_hash` attribute: the **first 4 characters of the image digest**. When the pod restarts onto a new image, every subsequent log line carries the new digest's prefix. So:

- `uniques(container_hash)` over a long window shows every digest the container has run on
- `latest(container_hash)` over a short window shows what it's running on right now
- `earliest(timestamp) FACET container_name WHERE container_hash = '<new>'` over the long window shows when the new digest first appeared in the logs — this **is** the restart-or-newer event

The ECR push timestamp (from the workflow run or the registry) tells you the new digest's prefix; you check `latest(container_hash) = <new prefix>` to confirm current state, and the `earliest(timestamp) WHERE container_hash = <new prefix>` to know when each pod actually rotated.

### Example query

```sql
SELECT latest(container_hash) as current,
       earliest(timestamp) as first_seen_current
FROM Log
WHERE cluster_name = 'Connector-EKS'
  AND container_name IN ('connector-11196', 'connector-30978', ...)
FACET container_name
SINCE 30 hours ago
LIMIT 10
```

(Use a window long enough to span the deploy event you're auditing. 30 hours is comfortable for "rolled within the last day"; expand if auditing an older deploy.)

### Anti-pattern callouts

- **Don't trust log-message proxies for pod-age** (`Starting connector`, `Boot complete`, etc.). They drift with the codebase, may not exist, and silent zeros are indistinguishable from "no restart." If you must, validate by running the exact LIKE pattern against a known recent restart first.
- **Don't use `earliest(timestamp)` over a fixed window without thinking about the window edge.** `SINCE 4 hours ago` is asking "what's the oldest log in the last 4 hours?" — not "when did this pod boot?" If the pod is older than the window, you'll get the window edge. To detect "restarted since X," either widen the window to span X+ or filter by image attribute (`container_hash`, `container_image`).
- **`pod_name` is a 5-char hash that changes on every restart.** It's not a stable identity. `container_name` is. (When pods get recreated they keep their container_name and get a new pod_name suffix.)

## Cross-references

- Today's daily note has the full investigation arc and the soak-script post-mortem: [[2026-05-12]]
- The post-merge verification scaffold is the Tier-1 layer of the broader [[three-tier-routine-check-pattern]] — same lesson applies to any future Tier-1 verification timer.
- Mark-todos workstream context: §N for PR #1688 verification is closed today; the methodology lessons here outlive the workstream.

## Carry-forward

- When the next post-merge verification script gets scaffolded, copy this pattern: exit 0 on successful run, JSON state file, daily-note append, optional separate monitor for RED-paging.
- Consider adding a `container_hash` audit helper to `local_network_scripts/` so the next "did pods rotate?" investigation has a one-liner answer.
- The soak-script's `connector_pod_errors_1h` threshold was also recalibrated today (from 200/500 to 15000/25000) because the fleet's baseline ERROR rate has drifted upward; this is a separate (and recurring) form of "stale threshold" footgun worth noting alongside.
