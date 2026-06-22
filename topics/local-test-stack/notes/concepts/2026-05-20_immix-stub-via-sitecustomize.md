---
title: Immix stub via sitecustomize meta_path finder
type: concept
topic: local-test-stack
tags: [python, sitecustomize, monkey-patch, importlib, meta-path-finder, autopatrol-api, immix, integration-testing]
created: 2026-05-20
updated: 2026-05-20
author: kb-bot
incoming:
  - topics/local-test-stack/_summary.md
  - topics/local-test-stack/notes/syntheses/2026-05-20_local-ap-e2e-stack-installed.md
  - topics/personal-notes/notes/daily/2026-05-21.md
incoming_updated: 2026-05-27
---

# Immix stub via sitecustomize meta_path finder

Pattern for monkey-patching a third-party SDK class at Python startup without touching the SDK source or requiring service-side wrapper code. Used to stub `actuate_integration_calls.autopatrol.autopatrol_api.AutoPatrolAPI` in the [[2026-05-20_local-ap-e2e-stack-installed|local-test-stack]] so AP runs don't hit real Immix.

## Why not just monkey-patch in a wrapper script?

The vms-connector and autopatrol-server both instantiate `AutoPatrolAPI` directly. A wrapper script (`import autopatrol_api; autopatrol_api.AutoPatrolAPI.start_patrol = lambda *a, **kw: ...`) would work, but it requires every entry point to opt in. We want a zero-touch stub that fires regardless of how Python is invoked.

## Mechanism

Python's `site.py` automatically imports `sitecustomize` (and `usercustomize`) at startup if such a module is on `sys.path`. By putting `pythonpath/sitecustomize.py` into a directory and prepending that directory to `PYTHONPATH`, we get an automatic startup hook.

Inside that startup hook, we install a `MetaPathFinder` into `sys.meta_path`. The finder intercepts the import of the target SDK module, lets the real loader run, then patches the resulting class before returning the spec.

```python
class _ImmixPatcherFinder(MetaPathFinder):
    def find_spec(self, fullname, path, target=None):
        if fullname != "actuate_integration_calls.autopatrol.autopatrol_api":
            return None
        # Find the real spec via OTHER finders (skip self to avoid recursion).
        real = None
        for finder in sys.meta_path:
            if finder is self:
                continue
            real = finder.find_spec(fullname, path, target)
            if real:
                break
        # Wrap its loader so we can patch after exec_module.
        ...
```

The patch is simple — for each named method on the class, replace it with a no-op that logs + records the call to a JSONL file:

```python
def _make_stub(method_name):
    def _stub(self, *args, **kwargs):
        _record(method_name, (self,) + args, kwargs)
        return None
    return _stub

for name in ("start_patrol", "end_patrol", "get_patrol_stream", "raise_patrol_alert", "update_patrol"):
    setattr(cls, name, _make_stub(name))
```

Output records to `/tmp/local-test-stack/immix-calls.jsonl` for post-run inspection.

## Recursion trap {#recursion-trap}

**Trap encountered 2026-05-20 first run:** initial draft called `importlib.util.find_spec(fullname)` inside `_ImmixPatcherFinder.find_spec` to locate the real spec. That helper iterates `sys.meta_path` — which includes our finder. Result: `RecursionError: maximum recursion depth exceeded`.

**Fix:** iterate `sys.meta_path` directly, skipping `self`. Don't use any of the convenience helpers in `importlib.util` from within a meta-path finder.

This trap is generic to any meta-path finder pattern that wants to consult "what would the real loader say?" — always go direct to other finders, never to the helper APIs.

## Disable path

Just unset `PYTHONPATH` or remove `/home/mork/work/local-test-stack/pythonpath` from it. The SDK falls back to its real network-calling methods.

## When this pattern would NOT be right

- If you need different stub behavior per-test (sitecustomize fires once per Python process; class-level patches stick). Use pytest fixtures + `unittest.mock.patch` instead.
- If the SDK is loaded via dynamic `importlib.import_module` from a path you can't predict. Meta-path finders only see imports through the normal mechanism.
- If you need to stub methods that are bound at instance creation time (rare). Class-attribute replacement works for normal methods only.

## Cross-refs

- [[2026-05-20_local-ap-e2e-stack-installed]] — where this is used.
- Python docs: [site.py](https://docs.python.org/3/library/site.html), [importlib.abc](https://docs.python.org/3/library/importlib.html#importlib.abc.MetaPathFinder).
