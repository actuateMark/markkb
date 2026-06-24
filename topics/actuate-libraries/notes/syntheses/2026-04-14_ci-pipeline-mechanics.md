---
title: "CI Pipeline Mechanics and Workarounds"
type: synthesis
topic: actuate-libraries
tags: [ci, github-actions, codeartifact, publish, versioning, workarounds]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
incoming:
  - topics/engineering-process/notes/concepts/2026-06-16_squash-merge-ci-skip-suppression-recurrence.md
  - topics/offboarding/notes/concepts/2026-06-23_local-repo-audit.md
incoming_updated: 2026-06-24
---

# CI Pipeline Mechanics and Workarounds

## Stable Publish Pipeline (push to main)

A push to `main` triggers `publish.yaml`, which sequences two reusable workflows: `bump-stable.yaml` followed by `publish-base.yaml`.

**bump-stable.yaml** runs a single `discover-new-versions` job:

1. Scans all commit messages in the push range (`BEFORE_SHA..AFTER_SHA`) for version tags. Per-library tags (`[patch:actuate-pullers]`, `[minor:actuate-config]`) take priority; a global tag (`[patch]`, `[minor]`, `[major]`) applies to all libraries that had changed files. If a library is tagged multiple times across commits, the highest level wins.
2. Discovers which libraries actually changed via `ci/discover-changed-libraries.sh`.
3. Runs `ci/bump-version-stable.sh` with the extracted SEM_VER JSON and the changed-library list. For each library: strips any local `+branch` segment, promotes any `dev` pre-release suffix to stable, then applies the sem_ver bump if a tag was found and no dev promotion occurred.
4. Runs `just lock` and `uv sync` to refresh the workspace lock file.
5. Commits changed `pyproject.toml` files and `uv.lock` with a `[no ci]` prefix commit message and pushes back to main.

**publish-base.yaml** then:

1. Pulls the latest commit (picking up the version-bump commit just pushed).
2. Discovers libraries whose published version in CodeArtifact differs from the local `pyproject.toml` version via `ci/discover-new-library-versions.sh`.
3. Runs a matrix job across each changed library x two architectures (arm64, x86): syncs deps, runs tests (exit code 5 = no tests, treated as pass), builds and publishes wheels with `just publish-package`, and creates a GitHub release tagged `<library>-v<version>`.

## Dev Publish Pipeline (push to feature branch)

A push to any non-main branch triggers `bump-dev.yaml` (not shown but analogous), which appends a `.devN+branch.name` local segment to the version. `publish-dev.yaml` then discovers and publishes these pre-release wheels to CodeArtifact. The `+branch.name` local segment is mandatory in consumer pins to avoid ambiguity between dev builds from different branches.

## Version Bump Mechanics

Tags in commit messages drive the bump logic:

| Tag | Effect |
|-----|--------|
| `[patch]` | Patch bump for all changed libraries |
| `[minor]` | Minor bump for all changed libraries |
| `[major]` | Major bump for all changed libraries |
| `[patch:actuate-pullers]` | Patch bump for that library only |
| `[minor:actuate-config]` | Minor bump for that library only |

Per-library tags always override global ones. The highest level wins when a library appears in multiple commits. Tags are scanned across the entire push range, not just the HEAD commit.

## Known Issues and Workarounds

### Issue 1: `gh pr merge` does not trigger workflows

When a PR is merged via `gh pr merge` (GitHub CLI or API), the resulting push event uses `GITHUB_TOKEN` from the Actions app. GitHub intentionally does not trigger further workflow runs from pushes made by `GITHUB_TOKEN` to prevent recursive loops. As a result, the `Publish Stable` workflow never fires after an API-based merge.

**Workaround:** After merging, push an empty commit to main to generate a human-actor push event:

```bash
git commit --allow-empty -m "chore: trigger CI for stable version publish"
git push origin main
```

### Issue 2: `jq`/`xargs` quoting bug in `bump-version-stable.sh`

The script passes the SEM_VER JSON and changed-library JSON through `xargs -P` using shell quoting (`'$SEM_VER_JSON'`). When the JSON contains square brackets or colons (e.g. `{"_global":"patch"}`), `xargs` can mangle or drop the JSON structure depending on the shell quoting context, causing `jq` to receive an empty or malformed string and silently skip the bump.

**Workaround:** Manually bump each affected library on main, commit with a `[no ci]` prefix to skip the bump step, then push a separate empty commit to trigger the publish step cleanly:

```bash
uv version --package actuate-pullers --frozen 1.7.1
git add actuate-pullers/pyproject.toml
git commit -m "[no ci] Manually bump actuate-pullers to 1.7.1"
git push origin main
# Then push empty commit to trigger publish:
git commit --allow-empty -m "chore: trigger stable publish"
git push origin main
```

### Issue 3: Squash merge brings dev versions to main

When a feature branch is squash-merged to main, any `dev` version strings in `pyproject.toml` files travel with it. `bump-version-stable.sh` is supposed to strip them (it detects `dev` in the version string and calls `uv version --bump stable`). However, if the bump job fails — due to the `xargs` quoting bug, a CodeArtifact auth issue, or a `uv` error — the `[no ci]` commit is never pushed and main is left with dev version strings. These persist until manually fixed, because the `[no ci]` guard prevents further CI runs from addressing them automatically.

**Recovery:** Same as Issue 2 — manually promote each dev version to stable on main with `uv version`, commit with `[no ci]`, then trigger publish with an empty commit.

## Related Notes

- [[dev-workflow]]
- [[2026-04-14_connector-library-deployment-lifecycle]]
