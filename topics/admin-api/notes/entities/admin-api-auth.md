---
title: "Prod admin API — programmatic auth"
type: entity
topic: admin-api
tags: [admin-api, auth, drf-token, ecs, deploy-branch, ops, actuate_admin]
created: 2026-05-27
updated: 2026-05-27
author: kb-bot
incoming:
  - topics/actuate-platform/notes/entities/branch-conventions.md
  - topics/personal-notes/notes/concepts/2026-05-28_session-handoff.md
  - topics/personal-notes/notes/daily/2026-05-27.md
incoming_updated: 2026-05-29
---

# Prod admin API — programmatic auth

How to call the prod admin API (`https://admin.actuateui.net/api/...`) from a script/CLI, e.g. to drive the §29 custom-branch `deploy_branch` lifecycle. Discovered 2026-05-27 while running the first prod custom-branch deploy (cust 705 PyAV-17 dry-run).

## The problem is auth, not reachability

The admin API is publicly reachable (an unauthenticated GET returns HTTP 302 → login redirect). The blocker is **proving you're an authenticated superuser**. Normal human login is **Google OAuth (social login)** — there's no standing credential on disk to pick up, so a script must be handed one.

## What auth the endpoints accept

`StandardViewSet` (base for `CustomerViewSet`, `CustomBranchViewSet`, most CRUD viewsets) sets:

```python
# api/serializers/adminutils/shared/standard_viewset.py
authentication_classes = [
    SocialTokenAuthentication,            # Google OAuth social token (human login)
    authentication.SessionAuthentication, # logged-in browser session cookie
    TokenAuthenticationStrict,            # DRF token: Authorization: Token <key>
]
permission_classes = [permissions.IsAuthenticated]   # + SuperuserMixin gates on is_superuser
```

- **No global `DEFAULT_AUTHENTICATION_CLASSES`** in `settings.REST_FRAMEWORK` — so endpoints that *don't* override (non-StandardViewSet) fall back to DRF defaults (`SessionAuthentication` + `BasicAuthentication`). StandardViewSet ones do **not** accept Basic auth.
- `TokenAuthenticationStrict` (`api/serializers/adminutils/auth/token_authentication_strict.py`) = stock DRF `TokenAuthentication` that rejects anonymous and raises `PermissionDenied` on failure. **No IP allowlist, no expiry** — a freshly-minted token works immediately.

## Recommended path for CLI/script: DRF token

1. **Mint/reuse a token via Django admin** (the `authtoken.TokenProxy` model is registered in the admin):
   - List page: `https://admin.actuateui.net/authtoken/tokenproxy/` — DRF tokens are **one-per-user**; if your user already has one, copy its 40-char key from the **Key** column (the `/add/` page errors on a duplicate user).
   - To force a fresh key: delete the existing row, then `/add/` (key shows once on creation).
   - **Note the admin URL is NOT under `/admin/`** — it's `https://admin.actuateui.net/authtoken/tokenproxy/` (this admin mounts at root).
2. **Use it:** `Authorization: Token <40-char-key>`. No CSRF needed (CSRF only applies to session auth).
3. **Attribution:** the token authenticates *as its owning user*, so audit rows (e.g. `BranchDeploymentEvent.user`) correctly attribute to that human. Don't make a separate "bot" token — it'd need its own superuser account and muddy attribution.

### Local token storage (laptop)

Saved at **`~/.config/actuate/admin_token`** (`chmod 600`). It's a superuser credential — keep perms tight. Read it inline so the value never prints/logs:

```bash
TOKEN=$(cat ~/.config/actuate/admin_token)
curl -fsS -H "Authorization: Token $TOKEN" https://admin.actuateui.net/api/customer/705/branch_status/
```

## Dead ends (don't waste time here)

- **ECS Exec is DISABLED** on the `prod-camera-admin` ECS service (`enableExecuteCommand: false`, ~15 running tasks). Can't `aws ecs execute-command` to shell in + mint a token server-side without `update-service --enable-execute-command` + a force-redeploy that rolls all tasks. Not worth it for a token.
- **No standing admin API token in Secrets Manager** — only `prod/admin/rdsproxy` (DB proxy creds, VPC-internal, not reachable from a laptop). No `prod/admin/api-token` or similar.
- **Basic auth does not work** on StandardViewSet endpoints (auth_classes overridden; no BasicAuthentication).

## Token-free alternatives (when you'd rather drive in-browser)

Your browser is already authenticated (Google OAuth → session cookie). Either:
- **DRF browsable API:** navigate to the endpoint (e.g. `/api/customer/705/deploy_branch/`); DRF renders an HTML POST form. Session + CSRF handled automatically.
- **Browser console `fetch()`:** on an admin page, `fetch('/api/...', {method:'POST', headers:{'Content-Type':'application/json','X-CSRFToken':<csrftoken cookie>}, body:...})`. Uses the session cookie; grab `X-CSRFToken` from the `csrftoken` cookie.

## Route gotchas

- Customer route is **singular**: `/api/customer/{id}/` (not `customers`). Actions: `/api/customer/{id}/deploy_branch/`, `/revert_branch/`, `/branch_status/`.
- Custom-branch route: `/api/custom_branches/` (register/list), `/api/custom_branches/{tag}/` (detail), `/{tag}/delete/`, `/{tag}/extend/`.
- The limited customer **detail** serializer (17 keys) does NOT populate `deployment_phase`/`connector_version`/cameras — use `branch_status/` for the real deployment state; `ecs_task_id` + `container_name` on the detail indicate a live connector.

## Verify a customer's RUNNING connector image (definitive)

After a `deploy_branch`, `branch_status` only tells you what admin *intends* — it does NOT prove the pod pulled the image. NR doesn't expose the container image either. The **definitive** check is kubectl against the connector fleet, which **is reachable from the standard laptop kubeconfig** (context `inference-eks-us` = cluster `inference-eks-Ny9n`, account 388576304176; the connector fleet lives in its **`rearchitecture` namespace** — ~5.7k pods — and is what NR labels `cluster_name = Connector-EKS`). The pod is labeled `app=<hostname_id>` where `hostname_id` = the customer's `container_name`.

```bash
kubectl get pods -n rearchitecture -l app=<container_name> \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.metadata.labels.deployment_phase,START:.status.startTime,STATUS:.status.phase
```

The `IMAGE` column is the answer (e.g. `…/arm_connector_rearch:featurepyav-17-bump-clean`); `START` should match the `deploy_branch` event timestamp; the `deployment_phase` label is set to the **image tag** (not literally `custom`). Verified 2026-05-27 on cust 705 (`actuate-nyc-alibi-vigilant`) — pod started 17:47:32Z on the expected custom image.

**Lesson:** the connector fleet is NOT in a separate inaccessible account — just run kubectl directly rather than inferring reachability from context names.

## Deployment-topology context

- Prod admin web tier = ECS service `prod-camera-admin` (cluster `prod-camera-admin`, ~15 tasks) + EU prod on k8s (`cameraAdmin`). Deploys via `main.yml` on push to `main` (ECS deploy waits for service stability). v2.10.4 (with §29) live as of 2026-05-26.
- `reboot_connector` gates the real connector roll on **`settings.STAGE == "prod"`** (the admin *server's* env), not the customer's deployment_phase — so prod admin issues real reboots even for STAGE-phase customers. See [[branch-conventions]] + [[feedback-rearch-is-a-prod-fleet]].

## Cross-refs

- [[2026-05-20_deploy-branch-full-scope]] — §29 custom-branch lifecycle (the main consumer of this auth)
- [[branch-conventions]] — branch → ECR → fleet map; reboot_connector behavior
- [[actuate-admin-safe-test-sites]] — STAGE + Actuate-root-group safe-test pool (note: phase data there is from a 2026-05-21 local DB restore; verify against prod via `branch_status/`)
- [[feedback-admin-repo-rules]] — never push admin without asking / never edit migrations
