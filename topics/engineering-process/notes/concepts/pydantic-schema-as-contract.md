---
title: "Pydantic Schema-as-Contract Pattern"
type: concept
topic: engineering-process
tags: [pydantic, api-design, validation, schema, json-schema]
created: 2026-04-14
updated: 2026-04-14
author: kb-bot
incoming:
  - topics/engineering-process/_summary.md
  - topics/engineering-process/notes/entities/agent-actuate-pr-reviewer.md
  - topics/engineering-process/notes/entities/agents-catalog.md
  - topics/engineering-process/notes/entities/skill-api-endpoint-development.md
incoming_updated: 2026-05-01
---

# Pydantic Schema-as-Contract Pattern

A design pattern where Pydantic models serve triple duty: input validation, API documentation, and client-side schema generation. Used in the v5 inference API model registry.

## The Pattern

Define per-variant Pydantic schemas that describe what each variant of your API accepts:

```python
class StandardModelData(BaseModel):
    sensitivity: Union[str, float] = Field(default="medium", description="...")
    ignore_labels: List[str] = Field(default_factory=list, max_length=50)
    stationary_filter: str = Field(default="false", pattern="^(true|tag|false)$")
```

Register each variant with its schema:

```python
MODEL_REGISTRY = {
    "resource-a": RegistryEntry(data_schema=StandardData, ...),
    "resource-b": RegistryEntry(data_schema=ExtendedData, ...),
}
```

The endpoint validates dynamically:

```python
validated_data = entry.data_schema.model_validate(body.data)  # validates
schema = entry.data_schema.model_json_schema()  # documents
```

## Three Benefits

1. **Validation** — `model_validate(body.data)` rejects invalid input with structured errors. Constraints like `max_length`, `ge`, `le`, `pattern` are enforced automatically.

2. **Documentation** — `model_json_schema()` produces a JSON Schema that clients can use to build forms, validate client-side, or generate code. A discovery endpoint returns this per resource.

3. **UI generation** — A test page can read the schema and generate appropriate form controls dynamically: dropdowns for enum-like fields, number inputs for integers, tag inputs for arrays.

## When to Use

- You have a single endpoint that handles multiple resource variants
- Each variant accepts slightly different parameters
- You want clients to discover the accepted parameters programmatically
- You want validation and documentation to stay in sync automatically

## When Not to Use

- Simple endpoints with fixed parameters (v1-v4 — just use FastAPI's built-in Form validation)
- Parameters that can't be expressed as JSON Schema (complex cross-field validation)

## Inheritance for Shared Fields

Use Pydantic class inheritance to share common fields:

```
BaseModelData (sensitivity, ignore_labels)
    └── StandardModelData (+stationary_filter)
         └── SlicedModelData (+max_slices, +stationary_filter_excluded_labels)
    └── MotionPlusData (no additional fields)
```

The `isinstance()` check in the endpoint determines which fields to extract:

```python
if isinstance(validated_data, StandardModelData):
    stationary_filter = validated_data.stationary_filter
```

## Reference Implementation

See [[v5-implementation-patterns]] in the inference-api topic for concrete file paths and registry structure.
