---
title: "Source: Onboarding API Contract Design"
type: source
topic: actuate-platform
tags: [worklog, onboarding, api, frontend, form-flow, integration]
ingested: 2026-04-14
author: kb-bot
---

# Onboarding API Contract Design

Source: internal specification of the API contract between the onboarding frontend and Django backend.

## Endpoints

### 1. `GET /integrations`
Returns the list of available integration types. This populates the initial selection screen.

### 2. `POST /getform`
Accepts the selected integration type. Returns a JSON structure describing:
- Each step of the onboarding wizard.
- The fields to render per step, including field type and configuration.
- Additional metadata (styling hints, validation rules) can be added incrementally.

### 3. `POST /validate` (future)
Accepts a single step's data for server-side validation. Prevents bad UX where the entire form errors out at the end. Not required for the initial implementation.

### 4. `POST /formsubmit`
Accepts the completed form submission:

```json
{
  "integrationtype": "<integration>",
  "data": "<form values -- opaque to frontend>",
  "user": "<user/session data>"
}
```

Key contract rule: **the frontend never inspects the `data` object**, and never needs to know about specific fields. The backend uses the integration type to determine deserialization. This clean separation means new integration types require zero frontend code changes -- only new field types (if needed) would require frontend work, and those should always be generic (e.g., "address field") rather than business-specific.

## Design Philosophy

The form definition is fully server-driven. The frontend is a generic form renderer. Business logic lives exclusively on the backend. This makes the system resilient to new integrations, changing field requirements, and evolving validation rules without frontend deployments.
