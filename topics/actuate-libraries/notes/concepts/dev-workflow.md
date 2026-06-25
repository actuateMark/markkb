---
type: concept
topic: actuate-libraries
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
incoming:
  - home/offboarding/2026-06-23_local-repo-audit.md
  - topics/actuate-libraries/_summary.md
  - topics/actuate-libraries/notes/concepts/dependency-graph.md
  - topics/actuate-libraries/notes/syntheses/2026-04-14_ci-pipeline-mechanics.md
  - topics/actuate-platform/notes/entities/camera-ui.md
  - topics/autopatrol/notes/entities/autopatrol-server-deployment.md
  - topics/engineering-process/notes/syntheses/2026-04-14_connector-library-deployment-lifecycle.md
  - topics/profiling-and-performance/notes/concepts/2026-05-19_handoff-cv2-dst-stage-deploy.md
  - topics/vms-connector/notes/syntheses/library-connector-dependency-map.md
incoming_updated: 2026-06-25
---

# Library Development Workflow

The 41 packages in the actuate-libraries UV workspace monorepo follow a structured promotion workflow that moves code from feature branch through dev testing to stable release. The workflow is designed to let consumer repos (primarily `vms-connector`) validate library changes before they reach production, while keeping the `main` branch as the single source of truth for stable versions.

## The Promotion Pipeline

### 1. Feature Branch

All work starts on a feature branch in the `actuate-libraries` repository. The UV workspace means any library in the monorepo can be modified, tested, and versioned independently. Local development uses the workspace's editable installs -- changing [[actuate-filters]] code is immediately visible to [[actuate-connector-observers]] in the same workspace without re-publishing.

### 2. Dev Version on CodeArtifact

When a feature branch is pushed, CI automatically publishes a dev version to the shared AWS CodeArtifact registry at `actuate-388576304176.d.codeartifact.us-west-2.amazonaws.com/pypi/actuate/simple/`. Dev versions use a pre-release suffix (e.g., `2.0.5.dev3`) so they sort below stable versions in PEP 440 ordering. This means `pip install actuate-filters` still resolves to the latest stable, while `pip install actuate-filters==2.0.5.dev3` explicitly pulls the dev build.

### 3. Consumer Pins Dev Version

The consumer repo (`vms-connector` or another connector service) updates its `pyproject.toml` or requirements to pin the exact dev version. This lets the team test the library change end-to-end in the connector's integration tests and staging deployments. Because libraries like [[actuate-pipeline]] depend on up to 13 other actuate packages, a single change can cascade -- the dev pin ensures the entire dependency chain is tested together.

### 4. Merge to Main -- Stable Publish

Once the feature branch is validated, it merges to `main`. CI auto-publishes a stable version to CodeArtifact. This is a critical gate: pushing to `main` triggers an immediate publish, so an accidental merge can release broken code. The team enforces branch protection and PR reviews to guard this step.

### 5. Consumer Pins Stable Version

After the stable version is published, the consumer repo updates its pin from the dev version to the stable version. This is typically a one-line change in the dependency file.

### 6. Merge to Rearchitecture

The consumer's stable-pin change merges into the `rearchitecture` branch (or the current long-lived integration branch), which represents the next release train for the connector. This final step closes the loop: the library improvement is now part of the connector's production path.

## Why This Workflow Exists

The monorepo contains libraries at very different levels of the stack. Leaf libraries like [[actuate-filterpy]], [[actuate-log]], and [[actuate-secrets]] have no internal dependencies and can be changed with low risk. Core libraries like [[actuate-config]], [[actuate-daos]], and [[actuate-pipeline-objects]] are depended on by nearly everything -- a breaking change in [[actuate-config]] ripples through [[actuate-alarm-senders]], [[actuate-connector-observers]], [[actuate-pullers]], [[actuate-monitoring]], and more.

The dev-version step gives the team a safe staging ground. Rather than hoping a library change works in the connector, they can prove it does before committing to a stable release. The explicit pin-then-merge pattern also creates a clear audit trail: every connector deployment can trace exactly which library versions it includes.

## Versioning Conventions

Libraries use semantic versioning. The CodeArtifact registry holds both stable (`1.2.3`) and dev (`1.2.3.dev4`) versions. The UV workspace's `pyproject.toml` files declare dependency ranges using compatible-release operators (e.g., `actuate-inference-objects ~=1.1`), but consumer repos pin exact versions for reproducibility.

## Risks and Mitigations

The biggest risk is an accidental merge to `main` publishing a broken stable version. Since CodeArtifact does not support yanking packages the way PyPI does, a bad publish requires either a hotfix version or manual intervention. The team mitigates this with required PR reviews and CI checks that must pass before merge. The dev-version testing step also catches most issues before they reach the stable-publish gate.
