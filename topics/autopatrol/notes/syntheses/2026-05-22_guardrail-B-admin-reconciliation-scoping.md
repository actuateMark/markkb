---
title: "Guardrail B — admin reconciliation cron for stranded AutoPatrol schedules (design scoping)"
type: synthesis
topic: autopatrol
tags: [autopatrol, admin, reliability, design, scoping]
created: 2026-05-22
updated: 2026-05-22
author: mark
---

# Guardrail B — admin reconciliation cron (scoping pass)

Companion to [[2026-05-22_autopatrol-onboarding-silent-deploy-failure]]. Guardrail A (onboarder-side post-deploy verification) is the band-aid shipping today; Guardrail B is the durable structural fix.

This note is **scoping only** — design intent + concrete delta against the current code, no implementation. Use as the basis for the implementation PR + review conversation.

## Problem statement

When the onboarder POSTs a new `AutoPatrolSchedule` to admin, admin's `AutoPatrolScheduleSync.process_item` creates the DB row inside the request thread, then kicks off a `Thread(target=_delayed_deploy_settings_{id})` to upload settings to S3 and call connector_deployer. The thread is:

- **Fire-and-forget** — exceptions inside it are caught and logged but never trigger a retry
- **Untracked** — there is no DB record of "this schedule needs a deploy attempt" that survives a crashed thread
- **Unobservable** — admin pod logs are absent from New Relic (separate gap; not AUTO-566, see below), so when the thread dies, no human knows

Result: a schedule lands in admin DB with no S3 settings and no K8s cronjob, indefinitely. The onboarder re-syncs every 5 min but `process_item` only re-fires the deploy thread if `created=True OR has_changes OR devices_updated OR products_added OR reactivated`. Steady-state, the thread is never re-fired.

## Design intent

Replace the fire-and-forget Thread pattern with **state-tracking + periodic reconciliation**. The Thread becomes one worker among many; a separate cronjob retries any schedule the worker failed to complete.

The critical shift: failure becomes a *state in the database*, not an exception in a process. Anything in `state in {pending, failed}` for longer than the SLA is a reconciliation candidate. A pod restart, network blip, or settings_generator exception no longer leaves work stuck — the next reconcile tick finds it.

## Delta against current code

### Schema additions on `AutoPatrolSchedule`

`/home/mork/work/actuate_admin/inframap/sites/autopatrol/autopatrol_schedule_model.py`

```python
class AutoPatrolDeployState(models.TextChoices):
    PENDING = "pending", "Pending — deploy not yet attempted"
    IN_PROGRESS = "in_progress", "Deploy thread running"
    SETTINGS_UPLOADED = "settings_uploaded", "S3 upload done, deployer not yet called"
    CRONJOB_CREATED = "cronjob_created", "Deployer ack'd cronjob creation (terminal-success)"
    FAILED = "failed", "Last attempt failed — reconciler will retry"

deploy_state = models.CharField(
    max_length=24,
    choices=AutoPatrolDeployState.choices,
    default=AutoPatrolDeployState.PENDING,
    db_index=True,  # reconciler queries by state
)
deploy_attempts = models.PositiveIntegerField(default=0)
deploy_last_attempted_at = models.DateTimeField(null=True, blank=True)
deploy_last_error = models.TextField(null=True, blank=True)
```

**Note**: do NOT remove `Customer.settings_deployed` — it's load-bearing for site-level state (set in `Customer.set_deployed()` at `customer_model.py:2140`, referenced in serializers + view filters). The new fields are *additional*, per-schedule.

### Lifecycle hooks

In `_delayed_deploy_settings` and `_deploy_settings`:

```python
def _delayed_deploy_settings(self, logger, delay_seconds=10, call_deployer=False, user=None):
    self.deploy_state = AutoPatrolDeployState.IN_PROGRESS
    self.deploy_last_attempted_at = timezone.now()
    self.deploy_attempts = F("deploy_attempts") + 1
    self.save(update_fields=["deploy_state", "deploy_last_attempted_at", "deploy_attempts"])

    try:
        self.ensure_default_configurations(logger=logger)
        if delay_seconds:
            time.sleep(delay_seconds)
        self._deploy_settings(user=user)
        self.deploy_state = AutoPatrolDeployState.SETTINGS_UPLOADED
        self.save(update_fields=["deploy_state"])

        if call_deployer:
            self.deploy()
            self.deploy_state = AutoPatrolDeployState.CRONJOB_CREATED
            self.deploy_last_error = None
            self.save(update_fields=["deploy_state", "deploy_last_error"])
    except Exception as e:
        self.deploy_state = AutoPatrolDeployState.FAILED
        self.deploy_last_error = repr(e)[:1000]
        self.save(update_fields=["deploy_state", "deploy_last_error"])
        logger.exception(f"_delayed_deploy_settings failed for {self!r}")
        # don't re-raise — caller does nothing useful with it
```

Two non-obvious points:
- `deploy_attempts` is incremented atomically via `F()` to handle concurrent threads
- `update_fields=` everywhere so the schedule row's `updated_at` doesn't trigger spurious change-detection in the onboarder's `has_changes` check

### Reconciler — Django management command

New file: `actuate_admin/api/management/commands/reconcile_autopatrol_deployments.py`

```python
class Command(BaseCommand):
    help = "Re-attempt deploys for AutoPatrolSchedule rows stuck in pending/failed/in_progress states."

    def add_arguments(self, parser):
        parser.add_argument("--max-attempts", type=int, default=10)
        parser.add_argument("--stale-minutes-pending", type=int, default=15)
        parser.add_argument("--stale-minutes-in-progress", type=int, default=10)
        parser.add_argument("--stale-minutes-failed", type=int, default=30)
        parser.add_argument("--dry-run", action="store_true")
        parser.add_argument("--batch-limit", type=int, default=50)

    def handle(self, *args, **options):
        now = timezone.now()
        candidates = (
            AutoPatrolSchedule.objects.filter(is_deleted=False)
            .filter(deploy_attempts__lt=options["max_attempts"])
            .filter(
                Q(deploy_state=AutoPatrolDeployState.PENDING,
                  deploy_last_attempted_at__isnull=True)
                | Q(deploy_state=AutoPatrolDeployState.PENDING,
                    deploy_last_attempted_at__lt=now - timedelta(minutes=options["stale_minutes_pending"]))
                | Q(deploy_state=AutoPatrolDeployState.IN_PROGRESS,
                    deploy_last_attempted_at__lt=now - timedelta(minutes=options["stale_minutes_in_progress"]))
                | Q(deploy_state=AutoPatrolDeployState.FAILED,
                    deploy_last_attempted_at__lt=now - timedelta(minutes=options["stale_minutes_failed"]))
            )
            .order_by("deploy_attempts", "deploy_last_attempted_at")
            [: options["batch_limit"]]
        )
        for schedule in candidates:
            if options["dry_run"]:
                self.stdout.write(f"[DRY] would retry {schedule!r} state={schedule.deploy_state} attempts={schedule.deploy_attempts}")
                continue
            schedule.deploy_schedule_settings(call_deployer=True, logger=logger)
```

The reconciler **reuses** `deploy_schedule_settings` (current entry point) — no new code paths. State transitions happen inside the Thread; the reconciler just kicks the Thread.

### Deployment: cronjob

`kubernetes-deployments` chart for camera-admin gets a new `CronJob`:

```yaml
schedule: "*/10 * * * *"  # every 10 min — well below pending/failed staleness windows
```

The cronjob runs `python manage.py reconcile_autopatrol_deployments` inside the admin container. Stagger from other admin cronjobs to avoid DB contention.

### Onboarder integration

Once Guardrail B lands, Guardrail A's verification logic can be tightened: instead of waiting for an actual patrol to fire, the onboarder can query admin's `/auto_patrol_schedule/?deploy_state=cronjob_created` and immediately confirm.

Or simpler: A and B coexist — A is a safety net for cases B doesn't cover (e.g. cronjob created but pod never started for some reason).

## What this does NOT solve

Things explicitly out of scope:

- **Admin pod absent from NR** — Guardrail C. Without C, the reconciler will log retries to stdout that no NR alert can fire on. The DB state is queryable, but a dashboard query is not a paging signal.
- **Detection of cronjob deletion without admin notification** — if connector_deployer deletes a cronjob out-of-band, admin's `deploy_state=cronjob_created` is stale. Needs a separate "deployer → admin" reverse channel.
- **Settings generator bugs that crash for a specific schedule config** — the reconciler will increment attempts and eventually give up at `max_attempts=10`. Without observability, those terminal-failed rows would just sit there. Mitigation: dashboard query for "schedules with deploy_state=failed AND attempts >= 10".

## Migration / rollout sequence

1. Schema migration (additive, all-default — safe to deploy without code change)
2. Backfill existing `AutoPatrolSchedule` rows: set `deploy_state=cronjob_created` if `customer.settings_deployed=True AND customer.deployed_date IS NOT NULL`, else `pending`. One-shot migration script.
3. Wire state transitions in `_delayed_deploy_settings` — gated by feature flag `AUTOPATROL_DEPLOY_STATE_TRACKING_ENABLED` so the migration can roll back behavior cleanly
4. Deploy reconciler as a Django management command (no cronjob yet — manual `python manage.py` runs only)
5. Manual reconcile test on a known-stranded schedule (rare these days post-A)
6. Enable cronjob in k8s deployments
7. Flip the feature flag to true

## Effort estimate

- Schema migration + state hook plumbing: 1 day
- Reconciler command + tests: 1 day
- Backfill script + rollout coordination: 0.5 day
- Cronjob YAML + ArgoCD wiring: 0.5 day
- Buffer (review, edge cases, migration verification on a clone): 1-2 days

**Total: 3-5 day implementation.** Lighter if we skip the feature flag (riskier) or skip the backfill script and let the reconciler naturally pick up old rows over time (cheaper, lazier).

## Open design decisions for the PR author

1. **`deploy_state` on AutoPatrolSchedule vs new `AutoPatrolDeployAttempt` model.** The state field is denormalized (history is in `deploy_attempts` count + last error). A separate `AutoPatrolDeployAttempt` model would be richer (full retry history queryable, latency analysis possible) but adds a join + write per attempt. **Recommended**: start with denormalized fields; add the model later if we need retry analytics.

2. **Reconciler picks vs leases.** With multiple replicas of the cronjob, two reconciler runs could pick the same schedule. Either (a) use `select_for_update(skip_locked=True)` to lease rows, or (b) accept that `IN_PROGRESS` self-check at deploy_schedule_settings entry de-dupes (the existing `redis_cli.set_action_running` lock with 60s TTL covers most of this). **Recommended**: rely on the existing redis lock; revisit if reconciler scales out.

3. **Error category granularity.** `deploy_last_error` stores the repr of the last exception. Worth adding `deploy_last_error_category` enum (`s3_upload_failed`, `deployer_5xx`, `settings_generation_error`, etc.) for dashboardable failure types. **Recommended**: defer to v2 — `repr(e)` is enough to grep in v1.

## Cross-references

- [[2026-05-22_autopatrol-onboarding-silent-deploy-failure]] — the incident that motivates B
- `customer_model.py:2140` (`set_deployed`) — existing site-level deploy flag, do not remove
- `autopatrol_schedule_model.py:993` (`Thread(target=_delayed_deploy_settings_*)`) — the call site this design retains and instruments
- vms-connector `autopatrol-onboarder` repo `deploy_verification.py` — Guardrail A (the v1 band-aid shipping today)
