---
title: "AIT ↔ actuate-validator integration plan — fault lines, alignment, bucket safety"
type: synthesis
topic: engineering-process
tags: [actuate-validator, actuate-integration-tools, ait, integration-plan, fault-lines, refactor, terraform, s3-buckets, golden-set]
created: 2026-05-21
updated: 2026-05-21
author: mark
incoming:
  - topics/engineering-process/notes/syntheses/2026-05-21_ait-validator-dovetail.md
  - topics/engineering-process/notes/syntheses/2026-05-22_actuate-testing-toolkit-overview.md
  - topics/engineering-process/notes/syntheses/2026-05-22_ait-phase-12-sweep.md
  - topics/engineering-process/notes/syntheses/2026-05-27_zack-coordination-brain-in-jar.md
  - topics/engineering-process/notes/syntheses/2026-05-29_ait-watch-manager-integration.md
  - topics/hypothesis/notes/syntheses/2026-05-21_hypothesis-in-actuate.md
  - topics/personal-notes/notes/daily/2026-05-21.md
  - topics/personal-notes/notes/daily/2026-05-27.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-05-30
---

# AIT ↔ actuate-validator integration plan

Gating doc — captures the integration agreement before any further AIT dev. Three deliverables: (1) fault-line analysis showing what currently lives where vs where it *should* live, (2) alignment decisions for each divergence, (3) bucket-safety constraints so test data and crash dumps never co-mingle.

Decided 2026-05-21 with Mark. Validator and AIT converged independently on adjacent problems; integrating them is cheaper than diverging.

## Part 1 — Fault-line analysis

Walking through what each library owns today and asking "is this in its natural home?":

### Cross-library moves (these belong elsewhere)

| Currently in | Should be in | What | Why |
|---|---|---|---|
| `actuate-validator/mocks.py` | `actuate-daos/testing/mocks.py` | `MockDaoManager` (17 DAO properties + alert-capture interception) | It mocks `actuate_daos.DaoManager`. Natural home is next to the package being mocked, mirroring `actuate-pipeline-objects/testing/`. AIT Phase 8 will also need it. |
| `actuate-validator/mocks.py` | `actuate-image-cache/testing/mocks.py` | `MockImageCache` (in-memory frame store) | Mocks `actuate_image_cache.ImageCache`. Same colocation logic. |
| `actuate-validator/pipeline_harness.py` (inline `_MockImageDataPacket`, `_MockProductDataPacket`, `_MockFeatureDeployment`) | **delete + use `actuate-pipeline-objects/testing/factories.py`** | mock packets | Phase 11 factories already produce these faithfully via `make_idp` / `make_pdp`. Eliminates a second source of truth for packet shape. |
| `actuate-validator/pipeline_harness.py` (`_StationaryFilterAdapter`) | possibly `actuate-pipeline/testing/adapters.py` | step adapter wrapping `StationaryFilterStep` without full link infra | When AIT Phase 6 lands `MockStepRunner` integration, an adapter consolidation makes sense. Defer to Phase 6. |

### Stays where it is

- All **harness implementations** (validator-specific test orchestration; coupled to manifest schema).
- **Manifests** (validator-specific declarative test format).
- **Golden sets** (validator-specific curated test data; lives at repo root or S3).
- **`config_factory.py`** (validator-specific param→production-config translation).
- **`walkthrough.py`** (validator-specific interactive UX).
- **`trajectory_metrics.py`** (validator-specific evaluation primitives).
- **`runner.py` / `test_golden_set.py` / `conftest.py`** (validator's pytest plumbing + manifest discovery).
- **`base.py` (BaseHarness, RunContext, RunResult, HARNESS_REGISTRY)** — the framework. Stays in validator unless a third consumer materializes.

### Already aligned (no action)

- **Registry pattern** — `HARNESS_REGISTRY` (validator) ≈ `VALIDATORS` (AIT Phase 2) ≈ `SCENARIOS` (AIT Phase 11). Dict keyed on name.
- **Subpackage-by-type colocation** — `actuate-validator/manifests/` ≈ AIT `simulate/scenarios/`. One module per test case.
- **Semver discipline** — both use `[major|minor|patch:<lib>]` tags in commit messages for CI version bumps.
- **CodeArtifact-hosted deps** — both pull internal deps from the same registry.

### AIT-side fault lines (less urgent)

| Currently in | Possible move | Note |
|---|---|---|
| `actuate-instrumentation/data_dump.py` | could grow into a richer state-capture primitive (Phase 9 + 10) | Already on roadmap. |
| AIT `simulate/scenarios/` | could be referenced from validator as scenario-derived golden sets | Future cross-pollination (Play E in the dovetail synthesis). |

## Part 2 — Alignment decisions

Per user direction: when conventions diverge, **whichever is further along AND more robust wins**, and we align ours to theirs where possible. With the proviso that "more robust" sometimes pulls us the other way.

### Convention table

| Topic | Validator's choice | AIT's choice | Winner | Why |
|---|---|---|---|---|
| Mock layout | `mocks.py` flat | `testing/` subpackage | **AIT** | More scalable when surface grows (factories + [[strategies]] + mocks); validator's `mocks.py` is fine today because it's a single file. Going forward, both libraries use the `testing/` subpackage pattern when there's >1 testing-related file in scope. |
| Registry dispatch | `HARNESS_REGISTRY[test_type]` | `VALIDATORS[name]` / `SCENARIOS[name]` | **Tie — already aligned** | Same pattern. No move needed. |
| Test-case definition | JSON manifest | Python `Scenario` dataclass + factory functions | **Both, no merge** | Validator: schema-evolvable, no Python edits needed to add tests. AIT: typed, IDE-discoverable, factory-driven. Different tools, different audiences (operators vs engineers); both forms keep their place. |
| Score-based regression | `baselines.json` + per-suite score tracking; failures get XFAIL'd | strict pass/fail | **VALIDATOR** | Score-based is more sophisticated and tolerates flake without losing the regression signal. AIT's fleet-validate work (when it materializes) should adopt this model. |
| Mocks colocation | inline in validator | lifted into upstream `testing/` | **AIT** | The colocation pattern from `actuate-pipeline-objects/testing/` (Phase 11) is the better template. Validator's mocks should follow. |
| CLI entrypoint | `python -m actuate_validator walkthrough` | `ait <subcommand>` | **Neither — orthogonal** | Different tools, different commands. No conflict. |
| Top-level data | `actuate-validator/golden-sets/` (repo) + S3 | (AIT doesn't store data) | **VALIDATOR** | Validator's mixed local-repo + S3 model is correct for its workload — small immutable detection files in repo, big videos in S3. AIT doesn't need this today. |
| Library home | inside `actuate-libraries` | own repo (`actuate-integration-tools`) | **Open question** | Validator's "testing library with 13 production deps" is a strange library footprint. Possibly belongs in its own repo like AIT. Discuss with Zack; not blocking. |

### Net direction

Validator wins on **test-orchestration sophistication**: manifest schema, harness registry, walkthrough UX, score-based regression detection. AIT picks these up for future fleet-validate / brain-in-jar work.

AIT wins on **mock/factory organization**: lift validator's mocks into upstream `testing/` subpackages, drop inline `_Mock*Packet` shims in favor of our factories, follow the colocation pattern.

Both wins are real and additive. No backtracking required.

## Part 3 — Bucket safety constraints

Both libraries will own S3 buckets in production (`actuate-test-sets` for validator golden sets, `actuate-crash-dumps` for AIT Phase 10). Shared Terraform module + lifecycle policies are tempting, but the workloads are **fundamentally different** and conflating them risks data loss.

### Risk catalogue

| Risk | What goes wrong | Mitigation |
|---|---|---|
| Crash-dump lifecycle policy applied to test-sets bucket | Curated golden-set videos vanish after 3 days, breaking test suites and losing data we may not be able to reconstruct | Lifecycle policy lives at the **bucket** level, not the module level. The Terraform module factors common infra (encryption, logging, RBAC primitives) but each bucket's lifecycle is declared in its own resource block. |
| Crash-dump compaction Lambda gains read access to test-sets bucket via shared IAM role | Lambda might write a "summary" of test data, deleting frames as part of compaction; or test data could leak into crash-dump pipeline | Lambda IAM role scoped explicitly to `arn:aws:s3:::actuate-crash-dumps/raw/*` + `arn:aws:s3:::actuate-crash-dumps/summaries/*`. **NO wildcards across buckets.** No cross-bucket bucket policies. |
| Bucket-policy template applied via shared Terraform module mistakenly opens write access to engineering on golden-set bucket | Engineers can accidentally modify "immutable" test data | Test-sets bucket: engineering = read-only by default; writes via a dedicated CI role only. Crash-dumps bucket: engineering = read on summaries, no access to raw (raw is connector-pod-write + lifecycle-expiry). Different RBAC, declared explicitly per bucket. |
| Backups / cross-region replication enabled on both | Crash dumps replicate unnecessarily; or golden sets fail to replicate when assumed shared | Replication is bucket-level config, not module-level. Test-sets bucket: replicated to backup region for durability (long-lived data). Crash-dumps bucket: NO replication (ephemeral). |
| Future "actuate-* bucket cleanup" automation iterates all buckets matching a prefix and applies a default policy | Sweeps test data | Bucket names use distinct prefixes (`actuate-test-sets-*` vs `actuate-crash-dumps-*`). Tagging discipline: every bucket carries a `data-class` tag (`test-fixtures`, `crash-dumps`, `customer-data`, `infra-config`). Any cleanup script must filter on `data-class`. |

### Terraform module strategy

Factor a **`ds-terraform-eks-v2/modules/test-data-bucket/`** module that provides:

- Server-side encryption (KMS, AWS-managed key)
- Bucket logging to the audit-log bucket
- Versioning enabled
- Tagging primitives (with `data-class` as a required input)

Do **NOT** factor into the module:

- Lifecycle policies (caller declares per bucket)
- Replication (caller declares per bucket)
- Bucket policy beyond access-deny defaults (caller declares per-IAM-role grants)
- Notification configuration (caller wires Lambda triggers per bucket)

Each bucket resource block:

- Imports the module for the encryption / logging / versioning baseline
- Declares its own lifecycle, replication, bucket policy, notification config
- Reads as a self-contained spec for that bucket

### Concrete declarations

**`actuate-test-sets`** (validator golden sets):
- Tags: `data-class = "test-fixtures"`, `owner = "validator"`, `retention = "indefinite"`
- Lifecycle: none (preserve indefinitely)
- Replication: backup region
- RBAC: engineering = read-only via SSO role; `validator-ci-role` = write-on-explicit-prefix
- Notifications: none

**`actuate-crash-dumps`** (AIT Phase 10):
- Tags: `data-class = "crash-dumps"`, `owner = "ait"`, `retention = "3-days"`
- Lifecycle: `raw/*` → 3-day expiry; `summaries/*` → 90-day expiry
- Replication: none
- RBAC: engineering = read-only on `summaries/`; connector-pod IAM = write-only on `raw/`; engineering = read on `raw/` for active investigation
- Notifications: PUT on `raw/*` triggers `compact-crash-dumps` Lambda

The bucket policies are **disjoint** — there's no IAM role with cross-bucket access, no shared CloudFront distribution, no shared replication. Operationally separate even if they share a Terraform module skeleton.

## Sequencing — what needs to land in order

| Step | When | Effort | Blocks |
|---|---|---|---|
| 1. Phase 11 commits land on libraries `main` (factories + [[strategies]] publish) | Pending review + Zack's alignment | external — coordinate via PR | Step 2 |
| 2. Validator adopts factories (Play A, dovetail synthesis) | After step 1 | ~30min (Zack-side, or our PR) | nothing — net code reduction |
| 3. Lift `MockDaoManager` → `actuate-daos/testing/mocks.py` | After Phase 11 publishes; coordinate with Zack | ~1h | AIT Phase 8 mock work |
| 4. Lift `MockImageCache` → `actuate-image-cache/testing/mocks.py` | Same as step 3 | ~30min | AIT Phase 8 |
| 5. Factor `ds-terraform-eks-v2/modules/test-data-bucket/` | Before AIT Phase 10 lands a real bucket | ~2h | Phase 10 |
| 6. Declare `actuate-test-sets` and `actuate-crash-dumps` in Terraform | After step 5; staged per bucket | ~1h | Phase 10 |
| 7. AIT Phase 8 imports lifted mocks; doesn't reinvent | When Phase 8 ships | included in Phase 8 estimate | nothing |
| 8. AIT future fleet-validate adopts validator's score-based regression | If/when fleet-validate ships | ~2h | nothing — net feature |

Steps 1–4 require coordination with Zack on the validator side. Steps 5–6 are AIT-owned. Step 7 is AIT-owned. Step 8 is speculative.

## What's still owed

This plan does NOT cover:

- The exact wire format for the validator-side adoption of factories (Play A) — that's a small PR to be written when the time comes.
- The lift PRs for `MockDaoManager` / `MockImageCache` — coordinate with Zack on naming + timing.
- Whether `actuate-validator` should leave `actuate-libraries` for its own repo (like AIT did). Logged in dovetail synthesis as open question; ping Zack when convenient.
- Detailed Terraform module spec — that's a Phase 10 deliverable.

## Cross-references

- [[2026-05-21_ait-validator-dovetail]] — six plays + sequencing (this plan operationalizes the alignment plays)
- [[actuate-validator]] — entity overview
- [[actuate-integration-tools]] — sibling toolkit
- [[2026-05-20_ait-brain-in-jar-spec]] — AIT replay arc parent
- [[2026-05-21_ait-phase-11-simulate]] — AIT simulate arc; factories that Play A adopts
- [[2026-05-20_ait-phase-8-camera-from-dump]] — needs lifted mocks (steps 3 + 4 unblock)
- [[2026-05-20_ait-phase-10-s3-sink-review-ux]] — needs the Terraform module decisions
