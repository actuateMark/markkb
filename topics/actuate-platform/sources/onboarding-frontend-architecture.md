---
title: "Source: Dynamic Onboarding Form Architecture"
type: source
topic: actuate-platform
tags: [worklog, onboarding, frontend, react, dynamic-forms, wizard]
ingested: 2026-04-14
author: kb-bot
---

# Dynamic Onboarding Form Architecture

Source: internal design discussion on building a dynamic, integration-agnostic onboarding form system in React.

## Core Design Principle

The frontend should **never contain business-specific logic**. It does not know what an OpenEye, Dahua, or DW integration is -- they are all the same to the frontend. If a new integration needs a special field type, that is a backend planning failure, not a frontend concern.

## Dynamic Form System

The backend returns a serialized form definition per integration type, containing:

- A list of form steps (site, camera, schedule, and future entities like ignore zones).
- For each step, a list of fields with their types.

The frontend has a **component library of field types**:
- Basic: `IntegerField`, `StringField`, `ChoiceField`
- Specialized: `CalendarField`, `GroupField`, `ProductField`

These are small, reusable components that compose into full dynamic forms.

## Wizard Flow

1. User selects an integration type.
2. Frontend requests the form definition from the API -- receives the steps and their fields.
3. The wizard renders each step by instantiating the appropriate field components.
4. Camera forms can be **dynamically added** ("keep adding cameras until done") rather than pre-planned.
5. Each step can optionally be validated server-side before proceeding.
6. Final submission sends the complete form data to the save endpoint.

## API Contract

The submission payload is integration-agnostic:

```json
{
  "integrationtype": "<selected integration>",
  "data": "<opaque form values -- frontend never inspects this>",
  "user": "<session/auth context>"
}
```

The backend handles deserialization based on the integration type. The frontend treats `data` as a black box.

## Advantage Over Previous System

This approach leverages React's strengths (dynamic rendering, component composition) better than the previous system, which required pre-planning all cameras and schedules upfront.
