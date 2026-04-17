---
title: "actuate-automation-test"
type: entity
topic: actuate-platform
tags: [testing, e2e, playwright, typescript, automation, ci]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# actuate-automation-test

The end-to-end test suite for the Actuate platform, built with Playwright and TypeScript. It provides automated smoke and regression tests that run against staging and production environments, targeting the Actuate configuration UI (`config.actuateui.net`).

**Repo:** `aegissystems/actuate-automation-test` (GitHub, private)
**Language:** TypeScript
**Runtime:** Node.js 22.15.1, Yarn 1.22.22
**License:** Apache-2.0
**Last updated:** 2026-04-07

## Test Execution

Tests are configured per environment via `.env.stage` and `.env.prod` files containing the target URL and credentials. Key commands:

- `yarn test-stage` / `yarn test-prod` -- headless test runs
- `yarn test-stage-ui` / `yarn test-prod-ui` -- headed (browser visible)
- `yarn test-stage-debug` / `yarn test-prod-debug` -- debug mode with inspector
- `yarn report` -- open the HTML test report
- `yarn show-trace <path>` -- view Playwright trace files for debugging failures

Individual test files can be run directly: `yarn playwright test src/tests/<file>.test.ts`.

## CI/CD Integration

GitHub Actions workflows in `.github/workflows/` run smoke tests against both staging and production. The smoke workflow status is tracked via a badge on the repo README.

## Code Quality

The project enforces strict code standards through:

- **ESLint** for static analysis
- **Prettier** for formatting
- **EditorConfig** for consistent editor behavior
- **Husky + lint-staged** for pre-commit hooks that run lint and format checks on staged files

Run `yarn lint` to check manually. VS Code settings are included for automatic format-on-save with Prettier.

## Project Structure

Tests live in `src/tests/` as `.test.ts` files. Test results are stored in the `test-results/` directory. The project uses the standard Playwright configuration pattern with environment-specific settings.

## Relationship to Other Services

- **[[camera-ui|Camera UI / config.actuateui.net]]** -- the primary application under test
- **[[alertviewer|Alert Viewer]]** -- likely tested as part of the platform UI flows
- **GitHub Actions** -- CI runner for automated smoke tests on every push
