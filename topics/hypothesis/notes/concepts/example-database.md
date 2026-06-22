---
title: "Hypothesis example database (failing-case replay)"
type: concept
topic: hypothesis
tags: [hypothesis, database, example-database, replay, persistence, testing]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/hypothesis/_summary.md
  - topics/hypothesis/notes/concepts/given-and-settings.md
  - topics/hypothesis/notes/concepts/shrinking.md
  - topics/hypothesis/reading-list.md
  - topics/hypothesis/sources/hypothesis-api-reference.md
incoming_updated: 2026-05-27
---

# Hypothesis example database

Hypothesis persists every failing example to disk so subsequent runs can replay it. This is the mechanism behind "fix the bug, the test still fails — the database remembers the bad case." Once the test passes again, the database trims the entry.

## Default behaviour

`DirectoryBasedExampleDatabase` writes to `.hypothesis/examples/` in the project root. Keys are bytes (test identifier); values are bytes (example payload). The directory should be committed to git **only if you want the rest of the team to inherit the saved failures** — typically yes for repos with property tests.

```
.hypothesis/
├── examples/
│   └── <hash>/             ← one dir per test
│       └── <hash>          ← one file per saved example
└── unicode_data/
```

You don't write to this directly; Hypothesis manages it.

## How replay works

When you `@given(...)` a test, Hypothesis runs phases in order: `explicit` → `reuse` → `generate` → `target` → `shrink`. The `reuse` phase reads the example database and re-runs every saved example first. **If any saved example still fails, the test fails before any new generation happens.**

This means:
- A bug fix has to pass *all previously failing examples*, not just survive a fresh random pass.
- Two engineers fixing different bugs against the same property both inherit each other's saved failures.
- Tests get faster over time at finding regressions (the saved cases are the ones most likely to break again).

## Disabling replay

```python
@settings(phases=[Phase.explicit, Phase.generate, Phase.shrink])
```

Skips `Phase.reuse`. Useful when:
- You want to confirm a fresh test pass without help from the database.
- You're debugging the database itself.
- A saved example is hanging or producing weird state.

## Custom databases

Subclass `ExampleDatabase`:

```python
from hypothesis.database import ExampleDatabase

class MyDB(ExampleDatabase):
    def save(self, key: bytes, value: bytes) -> None: ...
    def fetch(self, key: bytes) -> Iterable[bytes]: ...
    def delete(self, key: bytes, value: bytes) -> None: ...
    # Optional:
    def move(self, src_key: bytes, dest_key: bytes, value: bytes) -> None: ...
```

Use cases:
- **`InMemoryExampleDatabase`** (ships with Hypothesis) — for ephemeral test runs that shouldn't affect disk. Often used in CI.
- **Shared / S3-backed DB** — for cross-machine sharing across a CI fleet so saved failures propagate. Concrete impls aren't shipped; build your own.
- **Multiprocess-safe DB** — when pytest-xdist or similar spreads tests across workers. Hypothesis's default DirectoryBased DB is multiprocess-safe via filesystem locking.

Wire via `settings(database=MyDB())`.

## When to nuke the database

```bash
rm -rf .hypothesis/examples
```

Two legit reasons:
1. **Strategy schema change** — you renamed fields, changed bounds, or removed a strategy. Old saved blobs decode to nonsense; clear and start fresh.
2. **Hypothesis version bump with breaking blob format** — rare but happens. The version is part of the blob; mismatches are silently skipped, but it's worth a clean re-run.

Don't nuke it routinely; the database is supposed to accumulate signal over time.

## `print_blob` for one-shot reproduction

Independent of the on-disk database, Hypothesis can print a `@reproduce_failure(...)` decorator that encodes the exact failing case. Paste it into the test source and re-run — the case re-runs even if the database is cleared:

```python
@reproduce_failure("6.152.9", b"AXicY2BgZGJgZGJgZGJgZGJgZG...")
@settings(...)
@given(...)
def test_x(...):
    ...
```

Enabled via `@settings(print_blob=True)` (auto-True in CI). Discard after the bug fixes; blobs aren't stable across Hypothesis major versions.

## Cross-references

- [[given-and-settings]] — the `Phase.reuse` phase + `print_blob` option
- [[shrinking]] — shrunk examples are what gets saved to the DB
- [[../sources/hypothesis-database]] — upstream how-to
