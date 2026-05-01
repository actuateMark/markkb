---
title: "Connector Factory Pattern"
type: concept
topic: vms-connector
tags: [connector, factory-pattern, integration, vms]
created: 2026-04-13
updated: 2026-04-14
author: kb-bot
incoming:
  - topics/actuate-libraries/notes/concepts/image-cache-strategies.md
  - topics/actuate-platform/notes/syntheses/camera-onboarding-end-to-end.md
  - topics/actuate-platform/notes/syntheses/how-a-frame-becomes-an-alert.md
  - topics/actuate-platform/notes/syntheses/integration-landscape.md
  - topics/autopatrol/notes/concepts/generic-patrol-mode.md
  - topics/fleet-architecture/notes/concepts/library-decomposition-required.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-a-minimal-split.md
  - topics/fleet-architecture/notes/syntheses/2026-04-16_proposal-c-camera-worker.md
  - topics/integrations/genetec/notes/entities/genetec-components.md
  - topics/integrations/luxriot/notes/entities/luxriot-components.md
incoming_updated: 2026-05-01
---

# Connector Factory Pattern

The vms-connector uses a factory pattern to create VMS-specific camera objects and site managers from a single entry point. The dispatch hub is `connector_factories/shared/factory.py::generate_site()`, called by `connector.py` after loading the settings JSON.

## Factory Dispatch

`generate_site()` reads `settings["customer"]["integration_type"]` and imports the matching factory class. There are 19+ integration types, each with a dedicated factory module under `connector_factories/<integration>/`:

| integration_type | Factory Class | Module Path |
|---|---|---|
| `rtsp`, `milestone_rtsp`, `adpro` | `RTSPConnectorFactory` | `connector_factories/rtsp/rtsp_factory.py` |
| `milestone` | `MilestoneConnectorFactory` | `connector_factories/milestone/` |
| `avigilon` | `AvigilonConnectorFactory` | `connector_factories/avigilon/` |
| `exacq` | `ExacqConnectorFactory` | `connector_factories/exacq/` |
| `autopatrol` | `AutoPatrolConnectorFactory` | `connector_factories/autopatrol/` |
| `vch` | `VCHConnectorFactory` | `connector_factories/autopatrol/` |
| `patrol` | `PatrolConnectorFactory` | `connector_factories/patrol/` |
| ... | ... | ... |

All factory imports are lazy (inside if/elif branches), so only the selected integration's dependencies are loaded.

## BaseConnectorFactory

Every integration factory extends `BaseConnectorFactory` (`connector_factories/shared/base_connector_factory.py`), which provides:

- **Config binding**: Sets AWS resource references (S3 buckets, SQS URLs, SNS topics, API URLs) from `app_config` onto the parsed config object.
- **DAO creation**: Calls `make_dao_manager()` to build the shared DAO layer (DynamoDB, Admin API, error alarm, metrics).
- **Observer construction**: `build_observers()` iterates `camera_streams` and creates per-camera observer lists (loitering, line crossing, blacklist) based on feature deployment metrics.
- **Motion listener setup**: `motion()` starts the appropriate SQS motion listener thread based on integration type and config flags.
- **`core()`**: Convenience method that initializes boto3 clients (SNS, SES, Lambda), builds observers, and starts motion listeners. Most subclass `default()` methods call `self.core(dao_manager)` as their first line.

The base class defines four abstract methods that subclasses must implement: `default()`, `healthcheck()`, `mock()`, and `local()`. There is also a concrete `patrol()` method on the base that wraps any integration's cameras in `PatrolCamera` instances.

## Subclass Pattern (RTSPConnectorFactory Example)

A typical factory subclass is minimal. `RTSPConnectorFactory` overrides `__init__` to parse settings into an `RTSPConnectorConfig`, then implements `default()`:

```python
class RTSPConnectorFactory(BaseConnectorFactory):
    def __init__(self, settings=None, *args, **kwargs):
        self.config = RTSPConnectorConfig(settings)
        super().__init__(config=self.config)

    def default(self, dao_manager=None, job_queue=None, res_queue=None):
        ui_url, sns_client, ses_client, lambda_client, observers, motion_queues = self.core(dao_manager)
        cameras = []
        for cs in self.config.camera_streams:
            camera = RTSPCamera(
                ui_url=ui_url, config=self.config, camera_config=cs,
                dao_manager=dao_manager, observers=observers[cs.camera.admin_camera_id],
                motion_queue=motion_queues.get(cs.camera.name), ...
            )
            cameras.append(camera)
        return cameras
```

The factory returns a list of camera objects. Each camera is fully constructed with its pipeline, puller, observers, and alert senders -- all before the site manager starts running.

## Site Manager Selection

After the factory produces cameras, `generate_site()` selects the appropriate site manager:

- **Healthcheck mode** (`-hc`): Uses `ChmSiteManager` (or `VCHSiteManager` for VCH).
- **Patrol mode** (`-p`): Uses `PatrolSiteManager`. This flag is set when `integration_type` is `patrol`; `PatrolSiteManager` receives `camera_runners` (plural) from `factory.patrol()` rather than a flat cameras list.
- **Standard mode**: Uses `get_site_type()` to pick an integration-specific `AnalyticsSiteManager` subclass (e.g., `MilestoneAnalyticsSiteManager`, `ExacqAnalyticsSiteManager`), or the base `AnalyticsSiteManager` for generic integrations.
- **[[sharding|Sharding]]**: If `camera_count > shard_size`, wraps everything in `ChunkedSiteManager` which spawns child processes. See [[sharding]].

## `patrol` vs `autopatrol` in the Factory

Both modes run patrol workflows, but they differ in how they obtain a patrol ID and what config they use:

| | `autopatrol` | `patrol` |
|---|---|---|
| Factory | `AutoPatrolConnectorFactory` | `PatrolConnectorFactory` |
| Config class | `AutoPatrolConnectorConfig` | `PatrolConnectorConfig` |
| `patrol_id` source | Fetched from Immix API during `default()` | Generated locally with `uuid.uuid4().hex` — no external call |
| Immix dependency | Yes (calls Immix to register the patrol run) | None |
| Module path | `connector_factories/autopatrol/` | `connector_factories/patrol/` |

`PatrolConnectorFactory.default()` writes the generated UUID directly onto `config.patrol.patrol_id` before constructing `PatrolCamera` instances. Because there is no Immix call, `patrol` can run against any VMS integration as a [[generic-patrol-mode|generic patrol mode]] — the inner integration type is controlled by `settings["patrol"]["inner_integration_type"]` (defaulting to `rtsp`).

Both integration types bypass [[sharding]]: `get_sharding_strategy()` returns a shard size of 2000 for `autopatrol`, `vch`, and `patrol`.

## SIGTERM Handling

The factory registers a SIGTERM handler in `__init__` that calls `endrun()` -- this fires `site_product_ended` events for every camera/product combination via the event library, then calls `sys.exit()`. The site manager overrides this handler with its own once `run()` starts. This layered approach ensures clean shutdown even if the connector receives SIGTERM during the factory build phase.
