---
title: "Alert Viewer"
type: entity
topic: actuate-platform
tags: [react, vite, alert-video, standalone-app, monitoring-api, cognito]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Alert Viewer

Alert Viewer (`alertviewer`) is a lightweight standalone React application for viewing random alert video clips from the Actuate monitoring system. Unlike the full [[camera-ui]], it is a single-purpose tool designed for quickly browsing and reviewing alert footage without the overhead of the complete camera management interface.

## Purpose

The app serves a focused use case: fetching random recent alert clips that have video, playing them on loop, and optionally auto-advancing through alerts. It supports both random alert selection and manual URL input for direct video playback. This makes it useful for quality assurance, demo purposes, and quick surveillance review.

## Tech Stack

- **Framework**: React 19 (JSX, no TypeScript)
- **Bundler**: Vite 8 with `@vitejs/plugin-react` v6
- **Styling**: Plain CSS (no component library, no Tailwind)
- **State**: React hooks (`useState`, `useRef`, `useCallback`) -- no external state library
- **API**: Native `fetch` with manual Bearer token headers
- **Auth**: AWS Cognito SSO flow + manual token paste fallback
- **Dev server port**: 8501

The app is intentionally minimal: no routing library, no UI framework, and no build-time type checking. The entire UI lives in a single `App.jsx` with inline SVG icon components.

## Authentication

The `TokenGate` component manages the auth flow:

1. **Cognito SSO**: Redirects to `actuate-settings.auth.us-west-2.amazoncognito.com` with the app's client ID. On return, exchanges the authorization `code` for backend tokens via `/actuate-auth/token/`.
2. **Manual token**: Users can paste a Bearer token directly (e.g., copied from the `token` cookie in [[camera-ui]]).
3. **Storage**: Tokens are stored in both cookies and localStorage (belt-and-suspenders pattern). Sign-out clears both.

The Vite dev server proxies `/actuate-auth` to `https://admin.actuateui.net/api/auth/` and `/api` to `https://admin.actuateui.net/monitoring-api/` to avoid CORS issues during development.

## Features

- **Random alert loading**: Fetches recent alerts with video from the [[monitoring-api]] (`GET /alert/?window_filter=recent&has_video=true`), picks one at random, and fetches its MP4 clip via the async clip generation endpoint with polling fallback.
- **Group filtering**: Users can select a parent account group to scope alerts. Groups are fetched from `GET /group/?parent_account=true`. The selected group ID is persisted in the URL query string.
- **Loop control**: Configurable loop count (1-99) determines how many times a clip replays before advancing.
- **Autoplay mode**: When enabled, the app automatically loads the next random alert after all loops complete.
- **Prefetch pipeline**: The `useAlert` hook prefetches the next alert and clip URL in the background while the current clip plays, enabling instant transitions when autoplay advances.
- **Manual URL input**: Users can paste any direct video URL (MP4, WebM) for playback.
- **Video controls**: Fullscreen, Picture-in-Picture, and open-in-new-window options.
- **Alert metadata display**: Shows alert label, site name, camera name, and timestamp for random alerts.

## Architecture

The codebase is compact:

- `src/api/alerts.js` -- API functions: `fetchGroups`, `fetchRecentAlerts`, `fetchClipUrl` (with async generation + polling)
- `src/api/auth.js` -- Cognito SSO flow, token exchange, storage helpers
- `src/hooks/useAlert.js` -- State machine (`idle` / `loading` / `ready` / `error`) with prefetch support
- `src/components/TokenGate.jsx` -- Auth gate component with SSO and manual token entry
- `src/App.jsx` -- Main UI with all viewer logic and inline SVG icons

## Related

- [[camera-ui]] -- the full camera management SPA that this app is derived from
- [[monitoring-api]] -- the backend API both apps consume for alert data and video clips
