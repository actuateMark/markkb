---
title: "Security Hardening Checklist"
type: concept
topic: engineering-process
tags: [security, hardening, validation, checklist]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
outgoing:
  - topics/engineering-process/_summary.md
  - topics/engineering-process/notes/concepts/2026-04-27_headless-mcp-bypass.md
  - topics/engineering-process/notes/concepts/2026-04-28_minting-github-pats-for-automation.md
  - topics/engineering-process/notes/entities/agent-actuate-pr-reviewer.md
  - topics/engineering-process/notes/entities/agent-issue-auditor.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/engineering-process/notes/entities/skill-api-endpoint-development.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming:
  - topics/engineering-process/_summary.md
  - topics/engineering-process/notes/concepts/2026-04-27_headless-mcp-bypass.md
  - topics/engineering-process/notes/concepts/2026-04-28_minting-github-pats-for-automation.md
  - topics/engineering-process/notes/entities/agent-actuate-pr-reviewer.md
  - topics/engineering-process/notes/entities/agent-issue-auditor.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/engineering-process/notes/entities/skill-api-endpoint-development.md
  - topics/personal-notes/notes/concepts/2026-05-19_handoff-anomaly-branches-triage.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
incoming_updated: 2026-05-27
---

# Security Hardening Checklist

Standards for input validation, error handling, and RBAC integration on Actuate API endpoints. Derived from the v5 inference API security audit.

## Processing Order

The order of operations matters for security:

1. **Authentication** — API Gateway validates API key (happens before Lambda)
2. **Model/resource lookup** — 404 if not found (cheap, no information leak)
3. **RBAC check** — 403 if denied. **Must happen before validation** to prevent unauthenticated users from probing which inputs are valid.
4. **Input validation** — 422 if schema invalid. Only runs for authorized users.
5. **Business logic** — frame decoding, inference, filtering

Rule: *Never validate input for unauthorized users. Check roles first.*

**Information leakage in error responses:** Error messages that list available options (e.g., "Available: [...]") must also be role-filtered. A 404 on an unknown resource should only list resources the caller has access to — not the full set.

**List/discovery endpoints must be role-filtered:** Discovery endpoints should filter results by the caller's roles so users only see resources they can access. Show all when no auth context is present (local dev).

## Input Validation Standards

### String Fields

| Concern | Mitigation |
|---------|-----------|
| Unbounded length | Set `max_length` on all string fields (Pydantic `Field(max_length=N)`) |
| Injection | Use regex patterns for enum-like fields (`pattern="^(true\|tag\|false)$"`) |
| Type confusion | JSON sends everything as string/number/bool. Validate explicitly. |

### Numeric Fields

| Concern | Mitigation |
|---------|-----------|
| Out of range | Use `ge`, `le`, `gt`, `lt` constraints |
| int vs float | `isinstance(x, (int, float)) and not isinstance(x, bool)` |
| Negative values | Enforce `ge=0` or `ge=1` as appropriate |

### List Fields

| Concern | Mitigation |
|---------|-----------|
| Unbounded length | Set `max_length` on all list fields |
| Empty when required | Set `min_length=1` |
| Item validation | Pydantic validates item types automatically |

### Image/File Fields

| Concern | Mitigation |
|---------|-----------|
| Not a real image | Validate with PIL `Image.open()` — catches corrupt/fake data |
| Oversized | Check `len(data)` before PIL (50MB max) |
| Huge dimensions | Check `img.size` after PIL open (8192x8192 max) |
| Wrong format | Normalize to RGB JPEG (convert non-RGB, re-encode non-JPEG) |
| Invalid base64 | Use `base64.b64decode(data, validate=True)` — catches padding errors |
| Event loop blocking | Run PIL validation in `asyncio.to_thread()` |
| SSRF via URL | The URL downloader validates content-type is `image/*` and verifies with PIL |

### Request Body

| Concern | Mitigation |
|---------|-----------|
| Oversized payload | Lambda API Gateway enforces 6MB limit. Document for base64 users. |
| Extra fields | Pydantic ignores unknown fields by default (safe) |
| Type coercion | Pydantic `strict=False` coerces silently — validate critical fields explicitly |
| Echo/pass-through fields | Optional strings echoed in response (e.g., `camera_id`, `site_id`) still need `max_length` — unbounded echo is a log injection / memory vector |

## Error Response Standards

### Do

- Return generic messages: `"Invalid image data"`, `"Failed to decode frames"`
- Include the field name or index: `"Frame at index 2 is not valid base64"`
- Return expected schema on validation errors (the schema is public via GET /models)
- Use appropriate HTTP status codes (400, 403, 404, 422, 503)

### Don't

- Don't include `str(e)` from internal exceptions
- Don't include file system paths (especially in 404 fallbacks)
- Don't include stack traces
- Don't include database connection info or internal URLs
- Don't differentiate between "API key not found" and "API key revoked" (both → 403)
- Don't list resources the caller doesn't have access to in error hints (filter 404 suggestions by role)

## RBAC Integration

### For endpoints with static roles (v1-v4 pattern)

```python
@router.post("/endpoint")
async def endpoint(
    _security: None = Depends(check_api_key),
    _roles: None = Depends(check_required_roles),
):
```

### For endpoints with dynamic roles

```python
@router.post("/endpoint")
async def endpoint(request: Request, body: RequestModel, _api_key: None = Depends(check_api_key)):
    entry = get_resource(body.resource_id)
    if entry is None:
        # Filter 404 hints by caller's roles
        user_roles = get_user_roles(request)
        available = [r.id for r in list_resources()
                     if not user_roles or has_role_access(user_roles, r.accepted_roles)]
        raise HTTPException(status_code=404, detail=f"Unknown. Available: {available}")
    CheckRoles(accepted_roles=entry.accepted_roles)(request)  # before validation
    validated_data = entry.data_schema.model_validate(body.data)  # after RBAC
```

### For discovery/list endpoints

```python
@router.get("/resources")
async def list_resources(request: Request, _api_key: None = Depends(check_api_key)):
    user_roles = get_user_roles(request)
    return [r for r in all_resources
            if not user_roles or has_role_access(user_roles, r.accepted_roles)]
```

The `not user_roles` fallback ensures local dev (no auth context) sees everything.

### Docs integration

Add endpoints to the role mapping so they appear in role-filtered Swagger docs.

### Testing RBAC enforcement

Use `patch.object(CheckRoles, "_extract_roles", return_value="role_string")` to inject roles into the real RBAC path — don't mock `CheckRoles.__call__` to a no-op for role enforcement tests.

```python
@patch.object(CheckRoles, "_extract_roles", return_value="role_a")
async def test_role_a_cannot_access_role_b_resource(self, _mock):
    response = self.client.post("/endpoint", json={"resource_id": "b_resource", ...})
    assert response.status_code == 403
```

## Testing Security

Maintain a separate `TestInputValidation` class with tests for each boundary:

```python
class TestInputValidation(unittest.IsolatedAsyncioTestCase):
    async def test_reject_invalid_base64(self): ...
    async def test_reject_non_image_base64(self): ...
    async def test_reject_too_many_frames(self): ...
    async def test_reject_oversized_model_id(self): ...
    async def test_reject_too_many_ignore_labels(self): ...
    async def test_stationary_filter_rejects_invalid_value(self): ...
```
