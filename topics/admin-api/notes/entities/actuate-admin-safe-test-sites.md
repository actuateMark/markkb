---
title: "Safe test sites for local admin development"
type: entity
topic: admin-api
tags: [safety, local-dev, test-sites, deploy-branch, actuate-group, runbook]
created: 2026-05-21
updated: 2026-05-21
author: kb-bot
outgoing:
  - topics/admin-api/notes/concepts/2026-05-20_actuate-admin-local-bringup.md
  - topics/admin-api/notes/concepts/2026-05-21_deploy-branch-e2e-cycle-verified.md
  - topics/admin-api/notes/syntheses/2026-05-20_deploy-branch-full-scope.md
incoming:
  - topics/admin-api/notes/concepts/2026-05-20_actuate-admin-local-bringup.md
  - topics/admin-api/notes/concepts/2026-05-21_deploy-branch-e2e-cycle-verified.md
  - topics/admin-api/notes/entities/admin-api-auth.md
  - topics/admin-api/notes/syntheses/2026-05-20_deploy-branch-full-scope.md
  - topics/personal-notes/notes/daily/2026-05-21.md
  - topics/personal-notes/notes/entities/mark-todos.md
incoming_updated: 2026-05-27
---

# Safe test sites for local admin development

The local restore of `actuateadmin` carries the **full production fleet** (~22k customers). Any DB-mutating dev work — deploy-branch flips, fleet-wide ALTERs, bulk imports — must restrict its blast radius to customers Actuate owns. This note codifies the safety convention.

## The hard rule

**A customer is safe to test against if and only if BOTH hold:**

1. `Customer.deployment_phase == "STAGE"` — never test against PROD/REARCH/DEV/CUSTOM-already sites
2. The customer's group ancestry includes the **Actuate root group at `id=641`**

`Group(pk=641)` is the canonical Actuate-owned root — name="Actuate", `parent=None`. Its tree (171 groups) contains all the Actuate-owned demo/test/eval/dev customers. Customers under this root are owned by us and safe to flip.

## Why both clauses

| Clause alone | Risk it leaves open |
|---|---|
| Phase-only (`STAGE`) | STAGE includes external-partner trial sites (Alibi, Securitas, Openeye…) we don't own. Flipping their deployment_phase mid-test could trigger their connectors to roll. |
| Group-ancestry-only (under Actuate) | A PROD Actuate customer (e.g. "Actuate Office Wave v6 direct") is still production — flipping deployment_phase would actually break our own office cameras. |

Intersection is the narrow safe zone.

## Local-restore baseline (2026-05-21)

```
STAGE customers total locally:         99
STAGE under Actuate root (id=641):     25   ← the safe candidate pool
```

Sample of the safe pool (first 5 by id):

| Customer ID | Name | Group ID | connector_version_id |
|---|---|---:|---|
| 705 | Alibi Vigilant | 10641 | 111 |
| 5353 | Star4Live Test | 6408 | None |
| 5599 | DEMO 2 (Hikvision) | 6702 | 111 |
| 5647 | Alibi P2P | 6774 | 104 |
| 7291 | Openeye Test 1 | 9041 | 99 |

**id=5353 'Star4Live Test'** is the recommended default candidate — it has `connector_version=None` so it won't collide with an existing image-tag override. Used in the [[2026-05-21_deploy-branch-e2e-cycle-verified|e2e cycle verification]].

## Enforcement — encode the gate in every test driver

Any script that walks customers (e2e driver, mgmt command, ad-hoc shell) must filter on the safety gate at the start. Pattern:

```python
from inframap.group.group_model import Group
from inframap.sites.customer.customer_model import Customer

ACTUATE_ROOT_GROUP_ID = 641
actuate_descendant_ids = list(
    Group.objects.get(pk=ACTUATE_ROOT_GROUP_ID)
    .get_descendants(include_self=True)
    .values_list("id", flat=True)
)
safe_qs = Customer.objects.filter(
    deployment_phase="STAGE",
    group_id__in=actuate_descendant_ids,
)
# pick the candidate; refuse to operate if safe_qs is empty
```

The e2e driver at `/tmp/e2e_deploy_branch_demo.py` implements this gate and **refuses to proceed** if no safe candidate exists.

## Anti-patterns

- **`Customer.objects.first()` — never.** This grabs whatever has the lowest pk, which is usually a long-tenured production customer.
- **Filtering only by `deployment_phase="STAGE"` — not enough.** See "Why both clauses" above.
- **Hardcoding a specific customer ID in a checked-in test** — IDs are stable across local restores (since the restore is a snapshot), but the *meaning* of an ID isn't documented. Use the dynamic safe_qs filter so the test continues to work if 5353 ever stops being safe.
- **Touching the audit/event log without a clear cleanup story.** Local audit rows accumulate across runs — fine for now, but if a script writes hundreds, periodically truncate `inframap_branchdeploymentevent` for the throwaway test branches.

## Defense in depth — what protects you even if the gate slips

Documented in [[2026-05-21_deploy-branch-e2e-cycle-verified]] § "Safety mechanism":

1. `reboot_connector` short-circuits when `settings.STAGE != "prod"` — local mode never hits the real deployer.
2. The Customer save-hook's K8s namespace switch is a no-op without a K8s API.
3. The audit row is still written — so even an accidental flip produces a record.

**These are second-line. The safety gate is first-line. Don't rely on the short-circuit as your only protection.**

## Discovery commands

```bash
# Count safe candidates
PYTHONPATH=. uv run python -c "
import django, os; os.environ.setdefault('DJANGO_SETTINGS_MODULE','actuate_admin.settings'); django.setup()
from inframap.group.group_model import Group
from inframap.sites.customer.customer_model import Customer
ids = list(Group.objects.get(pk=641).get_descendants(include_self=True).values_list('id', flat=True))
print(Customer.objects.filter(deployment_phase='STAGE', group_id__in=ids).count())
"

# List them
PYTHONPATH=. uv run python -c "
import django, os; os.environ.setdefault('DJANGO_SETTINGS_MODULE','actuate_admin.settings'); django.setup()
from inframap.group.group_model import Group
from inframap.sites.customer.customer_model import Customer
ids = list(Group.objects.get(pk=641).get_descendants(include_self=True).values_list('id', flat=True))
for c in Customer.objects.filter(deployment_phase='STAGE', group_id__in=ids).order_by('id')[:25]:
    print(c.pk, getattr(c, 'name', '?'), c.group_id, c.connector_version_id)
"
```

Both expect `STAGE=local` sourced from `.env` first.

## When this list goes stale

The candidate pool drifts whenever an Actuate-owned STAGE site is promoted to PROD (or new ones are scaffolded). Re-run the discovery command at the start of any session that needs more than one candidate. The conventions (root id=641, the two-clause gate) are stable — only the per-ID inventory changes.

## Cross-references

- [[2026-05-20_actuate-admin-local-bringup]] — bring-up runbook (prereq)
- [[2026-05-21_deploy-branch-e2e-cycle-verified]] — first concrete use of this gate
- [[2026-05-20_deploy-branch-full-scope]] — the §29 design that motivates the gate
- [[actuate-admin-rds]] — RDS restore tooling (the source of the local data)
