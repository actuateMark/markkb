---
title: "Camera UI"
type: entity
topic: actuate-platform
tags: [react, spa, camera-management, frontend, typescript, zustand, parcel, aws-s3]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Camera UI

Camera UI (`actuate-camera-ui`) is the primary React single-page application for Actuate AI's security camera management platform. It provides operators with tools to manage sites, view and triage alerts, configure camera settings, define ignore zones, manage patrols, and view analytics dashboards. The current version is 4.23.3.

## Tech Stack

- **Framework**: React 17 with TypeScript, using react-router-dom v6 for routing
- **Bundler**: Parcel (with HMR error overlay disabled via alias)
- **Styling**: Tailwind CSS + MUI v5 (Material UI) + Emotion. Tailwind is preferred for new code, though inline styles and MUI styled components are also present (mixed legacy)
- **State Management**: Zustand stores following a per-page pattern, plus heavy use of `localStorage` for cross-component data passing (legacy pattern)
- **API Layer**: Axios via a centralized `createApi` utility (`src/Components/utils/createApi.tsx`) that constructs authenticated clients with cookie-based Bearer tokens
- **Auth**: Cookie-based authentication with refresh tokens. Cognito SSO handles login; the app reads a `token` cookie for API authorization
- **Feature Flags**: [[launchdarkly]] via `launchdarkly-react-client-sdk`
- **Charts**: Chart.js / react-chartjs-2 and Recharts for analytics
- **Forms**: Formik + Yup for validation
- **Testing**: Jest + React Testing Library. Coverage thresholds enforced at 60% (branches, functions, lines, statements). Reports uploaded to Codecov on PRs to `develop` and `main`
- **Container**: Node 18.10.0 Docker image, with a Podman-based local dev workflow

## Pages and Features

The `src/Components/pages/` directory contains the major feature areas:

- **Alerts** -- alert viewing and triage with video playback. Uses the [[monitoring-api]] alert endpoints
- **Sites** -- site management with an about page and site-level Zustand store
- **EditIgnoreZones** -- polygon editor for camera ignore zones using normalized coordinates (0-1 range) with a 30px canvas padding offset
- **EditCamera** -- camera settings editor
- **EditLineCrossings** -- line crossing configuration
- **Patrols** -- patrol scheduling and management
- **Clips** -- video clip browser
- **Analytics / Dashboard** -- operational dashboards with Chart.js and Recharts
- **HealthMonitoring** -- camera health monitoring views (related to [[health-report]])
- **Calendars / AddSchedule** -- scheduling interfaces
- **CameraAutoAdd / AddCamera / AddSite** -- onboarding workflows
- **Onboarding / MFASetup** -- user setup flows
- **ActionLogs / GroupUsers** -- admin features

Each page directory typically contains: a main component, sub-components, a `*Store/` directory with a Zustand store, and a `*Utils/` directory.

## Deployment

Camera UI is deployed to AWS S3 behind CloudFront. The `develop` branch deploys to `dev.actuatesecurity.com` (staging API at `staging.actuateui.net`), while `main` deploys to production via the `prod-camera-ui` S3 bucket (production API at `admin.actuateui.net`). Rollbacks are performed with `aws s3 sync` from versioned release buckets. CI auto-bumps the version on pushes using semantic commit message keywords (`BREAKING CHANGE`/`major`, `feat`/`minor`, or patch by default).

## Key Patterns and Gotchas

- **localStorage coupling**: Preview URLs, camera info, and ignore zone data are passed between components via localStorage. This is a legacy pattern that complicates debugging.
- **Coordinate handling**: Ignore zones use a 30px padding offset on the canvas. Points are incremented by 30 on load and decremented on save. Camera images are resized to 720px width with preserved aspect ratio via `adjustDimensions`.
- **Brand colors**: `actuate-blue` (#001943), `actuate-orange` (#FF8400), `actuate-grey` (#E5E5E5). Fonts are Mulish (primary) and Roboto (secondary).

## Related

- [[alertviewer]] -- lightweight standalone alert video viewer that shares the same [[monitoring-api]]
- [[actuate-libraries]] -- shared backend libraries used across the platform
