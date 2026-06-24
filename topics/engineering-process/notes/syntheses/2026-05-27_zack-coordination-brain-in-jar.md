---
title: "Zack-bound coordination — brain-in-jar arc + actuate-validator integration"
type: synthesis
topic: engineering-process
tags: [actuate-validator, actuate-integration-tools, ait, brain-in-jar, coordination, zack, factories, hypothesis]
created: 2026-05-27
updated: 2026-05-27
author: mark
incoming:
  - topics/engineering-process/notes/entities/actuate-integration-tools.md
  - topics/personal-notes/notes/daily/2026-05-27.md
  - topics/personal-notes/notes/syntheses/2026-05-27_brain-in-jar-handoff.md
incoming_updated: 2026-06-19
---

# Brain-in-jar arc — coordination doc for Zack

**Audience**: [[zack-schmidt|Zack Schmidt]] (actuate-validator primary author). **Format**: shareable as-is — copy the body below into Slack DM, email, or the PR body when the libs branch goes up. **Purpose**: unblock cross-library coordination on the brain-in-jar testing arc, so validator can adopt our new factories and we can lift validator's mocks to upstream libs.

---

Hey Zack —

Over the last week-and-a-half I've been building a brain-in-jar capture/replay arc as a new toolkit alongside your `actuate-validator`. The work touched a bunch of upstream libraries (`actuate-pipeline-objects`, `actuate-instrumentation`, `actuate-pipeline`, `actuate-pullers`, `actuate-alarm-senders`) so there's a coordination story to walk through before it lands. **None of it customer-facing yet** — internal Actuate test deployments only.

This doc is the synthesis of where we landed + what I'd love from you. Big asks are bold; everything else is FYI.

## What we built (at a glance)

A capture/replay/simulate arc with these surfaces:

- **Phase 4** — `ImageDataPacket.to_dict / from_dict` round-trip + `actuate_instrumentation.data_dump` extended with sidecars. Fixes the broken `DataDumpLink` that was calling a method that didn't exist.
- **Phase 5** — `DumpReplayPuller` in `actuate-pullers/dump_replay/`. Feeds frames from a dump directory into a frame_queue; standalone (not a `BasePuller` subclass — too heavy for replay scenarios).
- **Phase 7** — `AlertData.to_dict / from_dict` round-trip + `CapturingAlertSender` (env-var-gated capture; perf-disciplined zero-overhead-when-off) + `ReplaySender` (drives a target sender against a captured payload).
- **Phase 11** — `actuate-pipeline-objects/testing/` subpackage with `make_idp` / `make_pdp` / `make_wdp` / `make_alerting_window` factories + Hypothesis [[strategies]] built on top.
- A standalone CLI tool `ait` (`actuate-integration-tools`, local-only repo for now) that wraps inspection/validation/simulate/replay over this.

These are **complementary** to your validator, not redundant. I wrote a master synthesis last week that lays out the full landscape:

- KB: [[2026-05-22_actuate-testing-toolkit-overview]] (`topics/engineering-process/notes/syntheses/2026-05-22_actuate-testing-toolkit-overview.md`)

TL;DR: five tools (your validator + AIT's `validate` / `diff` / `simulate` / `replay`) answer four different questions — replay is bounded by what production captured, simulate is unbounded synthetic, validator is curated + scored, diff is structural. All share the Phase 4 IDP serializer + Phase 11 factories as substrate.

## Integration plan (six "plays")

Earlier KB pass identified six places where our libraries should coordinate. Full doc at [[2026-05-21_ait-validator-dovetail]] + the operationalized version at [[2026-05-21_ait-validator-integration-plan]] (the second is the gating doc — Mark and I locked the alignment decisions there).

| Play | What | Effort (your side) | Status |
|---|---|---|---|
| **A** | Validator's `pipeline_harness.py` adopts our `make_idp` / `make_pdp` factories — drops the inline `_MockImageDataPacket` / `_MockProductDataPacket` stubs | **~30 min** | **Ask** |
| **B** | Lift `MockDaoManager` from `actuate-validator/mocks.py` → `actuate-daos/src/actuate_daos/testing/mocks.py` | **~1 h** (coord) | **Ask** |
| **C** | Lift `MockImageCache` similarly to `actuate-image-cache/testing/mocks.py` | **~30 min** (coord) | **Ask** |
| D | Shared Terraform `test-data-bucket` module skeleton (encryption + logging + versioning + tagging) — lifecycle declared per-bucket | ~2 h (when we get to Phase 10) | post-Phase-9 |
| E | Brain-in-jar dumps become a new validator test_type (`dump_replay` harness) — every interesting prod crash becomes a permanent regression test | ~2-4 h (joint) | post-Phase-10 |
| F | Validator gets a Hypothesis-driven fuzz mode (`just test-package actuate-validator --fuzz`) — perturbs golden-set test cases within bounded ranges | ~2 h (your side, once Phase 11 publishes) | optional |

## The immediate asks

### Play A — adopt our factories

Once the libraries PR I'm about to open lands, `actuate-pipeline-objects` will publish a new minor version with `actuate_pipeline_objects.testing.factories`. The validator's `pipeline_harness.py` has these inline today:

```python
class _MockProductDataPacket:
    def __init__(self, raw_model_response: list):
        self.raw_model_response = raw_model_response

class _MockImageDataPacket:
    def __init__(self, motion_boxes: MultiPolygon, products: dict):
        self.motion_boxes = motion_boxes
        self.skip_stationary_filter = False
        self.is_high_motion_sensitivity = False
        self.products = products
```

Replace with:

```python
from actuate_pipeline_objects.testing import make_idp, make_pdp

idp = make_idp(
    motion_boxes=multipoly,
    products={"intruder": make_pdp(raw_model_response=detections)},
)
```

The factory output is a real `ImageDataPacket` (no field-stub gap), accepts every constructor kwarg, and round-trips through Phase 4's serializer. **Single source of truth for packet shape** — when packet fields change, validator's tests no longer need a parallel update.

Happy to write the PR myself if it'd save you time. Just say the word.

### Plays B + C — lift mocks upstream

`MockDaoManager` and `MockImageCache` are in `actuate-validator/mocks.py` today. They'd naturally live in `actuate-daos/testing/mocks.py` and `actuate-image-cache/testing/mocks.py` respectively — same colocation pattern Phase 11 set for `actuate-pipeline-objects/testing/`.

Two reasons to lift:

1. **AIT Phase 8 (camera from_dump) needs both mocks** — and would prefer to import from `actuate-daos` rather than depending on validator just for mocks.
2. **The colocation pattern is more discoverable** — engineers looking for mock-DAO-stuff naturally check `actuate-daos/testing/` before `actuate-validator/mocks.py`.

The move:

1. Move the class verbatim into the upstream lib's new `testing/` subpackage.
2. Bump the upstream lib's minor version (`[minor:actuate-daos]` and `[minor:actuate-image-cache]`).
3. In `actuate-validator/mocks.py`, replace the class def with a re-export: `from actuate_daos.testing.mocks import MockDaoManager`. Keeps validator's import surface stable for back-compat; lets new code import from the new home.

Happy to do the upstream moves myself if you'd rather just review. The validator-side import swap is trivial.

### Play D — shared Terraform bucket module (later)

Not blocking anything today; flagging because Phase 10 (S3 sink for brain-in-jar dumps) will want a new bucket alongside your `actuate-test-sets`. The plan is to factor a `ds-terraform-eks-v2/modules/test-data-bucket/` module that covers shared infra (encryption, logging, versioning, tagging) but **leaves lifecycle, replication, and bucket policy per-bucket** — your golden-set bucket has indefinite retention, mine has 3-day TTL for raw dumps.

The bucket-safety constraints from our integration plan are in [[2026-05-21_ait-validator-integration-plan]] § "Bucket safety constraints" — would value your eyes on those before we lock in the module spec.

## Open questions for you

### 1. Library home for `actuate-validator`

Right now `actuate-validator` lives in `actuate-libraries` but has 13 production deps and a CLI surface (`python -m actuate_validator walkthrough`). That's a strange footprint for a library — it reads more like a top-level tool. `actuate-integration-tools` recently went through similar growth and we promoted it to its own repo (still local-only at the moment).

Would you want to pull `actuate-validator` out to `aegissystems/actuate-validator` at some point? No urgency, but if the answer is "yes eventually," there's value in doing it before the validator surface grows further.

### 2. Score-based regression model

I love your `baselines.json` + per-suite score tracking with XFAIL on individual failures. If we ever ship `ait sweep` (the QA-driven Phase 12 parameter search), it'd want a similar regression-detection model. Any opinion on whether that should live in validator (where it already exists) or get factored out into a shared library?

### 3. Naming convention — `testing/` subpackage

Phase 11 established `<lib>/testing/` as the colocation pattern for factories + mocks (alongside the package being tested). Validator's `mocks.py` predates this convention — should we keep it as-is for back-compat or move to `actuate-validator/testing/mocks.py` for consistency? My instinct is move + re-export from `mocks.py` for one minor version, then deprecate.

## What's where (links into the KB)

I've been writing this up extensively. Pointers if you want to dig in:

- **Master synthesis**: [[2026-05-22_actuate-testing-toolkit-overview]] — landscape map + per-persona workflows + deliberately-NOT-building section
- **Validator entity note**: [[actuate-validator]] (you might want to skim this for accuracy — written from a code-survey of `feat/motion-validator` 2026-05-21)
- **Integration plan**: [[2026-05-21_ait-validator-integration-plan]] — fault-line analysis, alignment decisions, bucket-safety constraints
- **Dovetail synthesis**: [[2026-05-21_ait-validator-dovetail]] — six plays (A-F) with effort estimates
- **AIT entity note**: [[actuate-integration-tools]] — what AIT does + roadmap
- **Phase 11 + Hypothesis context**: [[2026-05-21_ait-phase-11-simulate]] + [[knowledgebase/topics/models/hypothesis/_summary|Hypothesis (property-based testing)]]
- **Phase 4 keystone**: [[2026-05-20_ait-phase-4-idp-serializer]]

## Ticket

ENG-246 is the umbrella ticket. I posted a scope-update comment on 2026-05-20 noting that the work grew past the original "performance instrumentation" scope into the full brain-in-jar / state-capture story. Worth a re-scope or successor ticket once we agree on the integration plan.

## Logistics

The libs PR is queued + ready to push from `feat/idp-serializer-brain-in-jar-phase-4` against `main`. Five commits, semver-tagged. Squash subject will reproduce the `[minor:...]` tags so CI bumps each library on merge.

Let me know if you want me to drive the validator-side adoption work (Plays A-C) myself or if you'd rather take it. Either way works.

---

**Mark**

(2026-05-27)

## Internal-only notes (not for the message body)

These are for me, not Zack:

- The doc is structured to be copy-pasteable to Slack / email / PR body. Drop the "Internal-only notes" section before sending.
- If sending to Slack: pre-render the markdown (Slack handles MD in DMs reasonably well now). If sending to email: render as HTML.
- Cross-link this doc from [[2026-05-27_brain-in-jar-handoff]] (the personal handoff doc) and from the dovetail synthesis when sent.
- Once Zack responds, fold their feedback into the integration plan + update Plays A-F status.

## Cross-references

- [[2026-05-27_brain-in-jar-handoff]] — handoff doc (personal-notes)
- [[2026-05-22_actuate-testing-toolkit-overview]] — master synthesis (shared)
- [[2026-05-21_ait-validator-integration-plan]] — gating doc (decisions locked here)
- [[2026-05-21_ait-validator-dovetail]] — six plays
- [[actuate-validator]] — entity (Zack's library)
- [[actuate-integration-tools]] — entity (our toolkit)
