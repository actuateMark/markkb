---
title: "Squash Merge CI-Skip Suppression: Recurrence #1731 (2026-06-16)"
type: concept
topic: engineering-process
tags: [ci, incident, vms-connector, release, squash-merge, recurrence, github-actions]
jira: "BT-7788"
created: 2026-06-16
updated: 2026-06-16
author: kb-bot
---

# Squash Merge CI-Skip Suppression: Recurrence #1731

**What:** vms-connector PR #1731 (stage→rearchitecture promotion) was squash-merged to production (rearchitecture branch) as commit d0066b43 on 2026-06-16. The default squash body concatenated all branch commit messages; line ~375 contained a literal CI-skip directive token (specifically `[no ci]`) buried inside backtick-quoted instructional prose describing the scrub convention. GitHub Actions parses CI-skip tokens **anywhere** in the commit message — backticks, code fences, and markdown do NOT escape them. Result: all push-triggered workflows on rearchitecture silently suppressed (`rearch.yml` build + deploy, `sonar.yml`, `reset-stage-after-merge.yml`). The merge landed as a commit but **no container image was built, and no deploy happened** — confirmed by rarch.yml last run timestamp (2026-06-09 commit 1a7040d6, not d0066b43).

**Detection:** Jacob Aegis noticed rarchitecture's image tag had not advanced from the prior merge (2026-06-09). Verified in GitHub Actions UI: rarch.yml had no run for d0066b43. Re-checked the squash body for CI-skip directives; found the token inline in instructional prose.

**Recovery:** Pushed an empty commit 11ff4d6c ("ci: trigger rearchitecture build + deploy for #1731") and manually triggered `gh workflow run rarch.yml --ref rearchitecture`. The dispatch succeeded (workflow_dispatch ignores commit-message suppression): ARM64 build, x86 build, ECR push all green, deployment confirmed. No force-push, no history rewrite.

## Second Occurrence of Same Failure

This is the **second recurrence** of the same failure mode:

- **PR #1688 (2026-05-11):** CI-skip token appeared in instructional prose explaining what NOT to use. All rarch workflows suppressed; required manual `workflow_dispatch` to recover.
- **PR #1731 (2026-06-16):** CI-skip token appeared in instructional prose describing scrub/cleanup conventions. All rarch workflows suppressed again; same recovery pattern.

The token can appear in:
- Dev-bump bot's auto-generated bookkeeping commits (e.g. `[no ci] Bump versions for: actuate-*`)
- Instructional prose explaining the convention ("don't use `[no ci]`", "remove `[skip ci]` lines")
- Inadvertent inclusion anywhere in branch history

## Root Cause

`gh pr merge --squash` with no explicit `--subject` / `--body` uses default behavior: concatenates commit subject and body of every commit in the range into a single message. Prose and bookkeeping tokens leak into the body uncleaned. The org rule "never write CI-skip tokens even explanatorily; paraphrase only" (in global CLAUDE.md) existed but was not enforced by automation at the actual merge moment.

## Prevention: Automated Checks at Merge

Added BLOCKING pre-merge scans to two vms-connector locations (both ship in the standard merge workflow):

### vms-connector `.claude/agents/pr-prep.md` (Step 4.5)

Builds the expected squash body via `git log --format='%B' rearchitecture..HEAD`, greps for all CI-skip token forms:
- `[no ci]`, `[no-ci]`
- `[ci skip]`, `[ci-skip]`, `[skip ci]`, `[skip-ci]`
- `[skip actions]`, `[skip-actions]`, `[actions skip]`, `[actions-skip]`

If any match, blocks the merge and requires the user to emit a cleaned explicit `--subject` / `--body` for `gh pr merge --squash`. The [patch:|minor:|major:<pkg>] bump tag MUST be preserved in the cleaned subject.

### vms-connector `.claude/skills/pre-merge-workflow.md` (Step 4)

Same scan as a merge-time gate. Also documents recovery command: `gh workflow run rarch.yml --ref rearchitecture`.

## Key Lessons

1. **Scan the assembled body, not individual commits.** The token can come from concatenated prose across the branch — a grep of current HEAD alone misses it.
2. **Verify at merge time, not only at prep time.** The stage branch keeps receiving commits after prep; the squash body can drift.
3. **Recovery is always workflow_dispatch, never force-push.** `gh workflow run rarch.yml --ref rearchitecture` bypasses commit-message suppression and is safe.
4. **A CI guard can't catch this.** The guard workflow itself gets suppressed — prevention must be a pre-merge local/skill check, not a push-time gate.
5. **Paraphrase-only discipline is necessary but not sufficient.** Instructional prose ("do NOT use X") carries risk. The scan must be mechanical.

## Related Notes

- [[feedback_library_no_dev_versions]] — Global rule on squash-merge hygiene (§ Squash-merge gotcha)
- [[2026-04-14_ci-pipeline-mechanics]] — CI pipeline and known issues
- [[2026-06-15_pr1731-ap-to-prod-promotion-review]] — PR #1731 promotion synthesis
