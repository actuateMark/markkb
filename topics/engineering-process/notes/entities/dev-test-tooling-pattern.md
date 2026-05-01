---
title: "Dev Test Tooling Pattern"
type: entity
topic: engineering-process
tags: [testing, dev-tools, local-development, test-page]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
---

# Dev Test Tooling Pattern

A reusable pattern for building local test infrastructure alongside new API features. Established during the v5 inference API project.

## Components

### 1. Interactive Test Page (`tools/{feature}/index.html`)

A single-file HTML page served by the API at `GET /{version}/test` during local development. Not deployed to production (returns 404 if the file isn't found on disk).

**What it should include:**
- Dynamic form controls generated from the API's schema (e.g., a discovery endpoint populates dropdowns)
- File upload with drag-and-drop
- Visual results overlay (bounding boxes on images, response data tables)
- Display settings that adjust the visualization without re-submitting (line width, font, label position)
- Raw JSON response collapsible for debugging
- Link to Swagger docs

**Key design principle:** The test page reads its configuration from the API itself. When you add a new model to the registry, the test page automatically shows it — no HTML changes needed.

### 2. One-Command Startup Script (`tools/{feature}/run.sh`)

A bash script that brings up all dependencies and the dev server with a single command. For the inference API, this means:

1. AWS SSO login (if session expired)
2. kubectl access verification
3. kubefwd for k8s service DNS (with sudo, passing user's kubeconfig and AWS config)
4. FastAPI dev server with security disabled

**Key patterns:**
- `sudo -v` upfront to cache credentials before backgrounding processes
- `KUBECONFIG="$KUBECONFIG"` passed explicitly to sudo (root doesn't inherit user's kubeconfig)
- `HOME="$HOME"` and `AWS_CONFIG_FILE` passed for AWS credential chain
- Trap handler cleans up all background processes on Ctrl+C
- sudo keepalive loop refreshes every 50 seconds

### 3. Endpoint-Served Test Page

The API itself serves the test page via a GET endpoint (e.g., `GET /{version}/test`). This has advantages over a separate static server:
- Same origin as the API (no CORS issues)
- Hot-reload picks up HTML changes automatically
- No second server process to manage

**Production safety:** The endpoint reads from a file path relative to the repo root. In the deployed environment, dev tools aren't included in the build artifact. The endpoint returns a generic 404 "not available in production" without leaking the file path.

### 4. Live Regression Suite (`tools/{feature}/regression.html`)

A browser-based test runner that hits every API version's endpoints with real images.

**What it should include:**
- Every endpoint across all versions (v1 through current), not just the new one
- Multipart form upload for legacy endpoints, JSON body for new ones
- Pass/fail/skip status with elapsed time per endpoint
- Detection count per endpoint for quick sanity checking
- Auto-skip for endpoints requiring more frames than provided
- **Copy Results JSON button** — copies structured results to clipboard for pasting into Claude Code or tickets

**Key implementation lessons:**
- `File` objects from `<input type=file>` must be re-read via `arrayBuffer()` for each request — wrapping as `new Blob([buf])` with explicit content type ensures the multipart form sends correctly
- Handle non-JSON responses gracefully — some endpoints return 204 No Content (empty body) or HTML error pages. Parse text first, then try `JSON.parse` in a try/catch.
- Legacy `/vs/` endpoints use `files` field (with filenames) instead of `frames`, and require an `id` parameter — detect these with a `legacy: true` flag in the endpoint config
- Inference timeouts should be configurable via env var (`INFERENCE_TIMEOUT_SECONDS`) — local dev over remote connections needs more than the 3s production default
- Pre-read base64 frames once before the loop for JSON-body endpoints, don't re-read per iteration
- Metadata-only endpoints (like `GET /models`) pass even without kubefwd — detection endpoints require it. This is useful for distinguishing infrastructure failures from code failures.

### 5. Startup Script Resilience

The run script must handle stale processes from crashed sessions:

```bash
# Kill stale server on port 8000
STALE_PIDS=$(lsof -ti:8000 2>/dev/null || true)
[ -n "$STALE_PIDS" ] && kill $STALE_PIDS 2>/dev/null

# Kill stale kubefwd for the namespace
STALE_KUBEFWD=$(pgrep -f "kubefwd svc -n $NAMESPACE" || true)
[ -n "$STALE_KUBEFWD" ] && sudo kill $STALE_KUBEFWD 2>/dev/null
```

This prevents "address already in use" errors that block the [[dev-environment|dev environment]] from starting.

## Reference Implementation

See [[v5-implementation-patterns]] in the inference-api topic for concrete file paths.
