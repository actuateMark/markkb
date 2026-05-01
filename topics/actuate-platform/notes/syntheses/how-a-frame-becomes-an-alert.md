---
title: "How a Frame Becomes an Alert"
type: synthesis
topic: actuate-platform
tags: [synthesis, cross-topic, pipeline, detection, alert, end-to-end, frame-processing, vms-connector]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/fleet-architecture/notes/concepts/downstream-consumer-impact.md
incoming_updated: 2026-05-01
---

# How a Frame Becomes an Alert

An end-to-end trace of a single camera frame from [[rtsp-deep-dive|RTSP]] ingestion through AI inference, filtering, observer logic, and alert delivery to a customer's monitoring console. Every hop involves a distinct library or service from the [[actuate-libraries]] monorepo, orchestrated by the [[vms-connector]].

## 1. Frame Acquisition (actuate-pullers)

The journey begins at the camera. The [[connector-deployer]] has provisioned a Kubernetes Deployment in the `rearchitecture` namespace for this site. Inside the pod, the [[connector-factory]] reads the site's `settings.json` (fetched from S3 via [[actuate-config]]) and dispatches to the correct factory class based on `integration_type` -- [[rtsp-deep-dive|RTSP]], Milestone, Avigilon, Eagle Eye, or any of the 19+ supported VMS types.

The factory instantiates an [[actuate-pullers]] subclass -- typically `UrlFramePuller` for [[rtsp-deep-dive|RTSP]] streams, or a VMS-specific puller like `MilestoneJpgFramePuller`. The puller runs in its own thread, decoding the inbound stream at 15-30 FPS via [[opencv-entity|OpenCV]] `VideoCapture`. Each decoded frame is stamped with `approx_capture_timestamp` and stored in the [[actuate-image-cache]] (thread-safe LRU/TTL cache). The frame is wrapped in an `ImageDataPacket` from [[actuate-pipeline-objects]] and pushed onto the camera's frame queue.

## 2. Motion Detection Gate (actuate-movement)

Before the frame reaches inference, [[actuate-movement]]'s `MotionDetector` runs frame-difference motion detection (FDMD). The `FrameDiffMotionDetector` computes contours from the delta between the current and previous frames, converts them to Shapely polygons, and returns a motion boolean plus a `MultiPolygon` of motion regions. If the scene is static, the puller sets `abort=True` on the packet, skipping inference entirely and saving GPU cost. Adaptive sensitivity adjusts thresholds for slicing, fire, smoke, or infrequent-frame modes. Timestamp zones are masked via OCR to prevent clock digits from triggering false motion.

## 3. YOLO Inference (actuate-inference-client -> ds-server-container)

The frame enters the [[pipeline-architecture]]'s three-phase chain-of-responsibility, built by `PipelineFactory` from [[actuate-pipeline]]. In the processing phase, the `YoloProcessingStep` submits the frame to the [[inference-pool]] -- the `AsyncInferencePool` with AIMD congestion control (initial window 48, floor 8, target 200ms latency). The pool consolidates all camera threads' HTTP calls onto a single asyncio event loop, eliminating GIL convoy effects.

The HTTP request hits [[ds-server-container]], a Rust-based inference server running on AWS Inferentia2 in the `ds-model-prod` Kubernetes namespace. For the intruder product, the model is `intruder-384h-512w-svc` (YOLOv5, being replaced by `int07-actuate003-v8`). The server runs NMS and returns a list of `Detection` objects -- each carrying a bounding box, class label (person, car, bicycle, motorcycle, bus, truck, machinery), and confidence score. These are deserialized into [[actuate-inference-objects]]'s canonical `Detection` / `BoundingBox` types.

For high-resolution streams, the [[actuate-inference-slicing]] library (SAHI-style) or the Rust `slicing_server` on Graviton4 tiles the image into overlapping chips, dispatches each to the inference server, and merges results.

## 4. Post-Processing Filter Chain (actuate-filters)

The raw detections now pass through the [[filter-architecture]] -- a sequence of `BaseFilter` subclasses applied in order:

1. **LabelFilter** -- keeps only classes enabled for this camera's product (e.g., person-only for basic Intruder)
2. **ConfidenceFilter** / **LabelwiseConfidenceFilter** -- discards detections below the per-class sensitivity threshold (HIGH/MED/LOW maps to specific confidence values)
3. **PolyZoneFilter** -- removes detections inside polygonal [[ignore-zones|ignore zones]] defined in [[actuate-config]]'s `CameraConfig`, computed via Shapely geometry
4. **IoUFilter** -- deduplicates overlapping boxes using IoU from [[actuate-math]], a second NMS pass complementing the server-side one
5. **StationaryFilter** -- compares current detections against a history of prior positions; objects that have not moved are tagged `STATIONARY_VEHICLE` via [[actuate-inference-objects]]'s `DetectionTag` system
6. **BlacklistFilter** -- checks detections against license plate/face blacklists from [[actuate-daos]]'s `BlacklistDAO`

After this chain, only actionable, high-confidence, non-duplicate, non-ignored detections survive.

## 5. Observer Logic (actuate-connector-observers)

The filtered detections reach the [[observer-pattern]] layer. The `ObservableManager` pre-captures the frame from [[actuate-image-cache]] (preventing TTL eviction races), then dispatches to each attached observer via a single-worker `ActuateThreadPoolExecutor` from [[actuate-threadpool]].

For the **Intruder** product, `IntruderObserver` checks whether `frame_thresh` consecutive frames contain a detection. For **Loitering**, `PersonLoitererObserver` or `VehicleLoitererObserver` feeds detections into [[actuate-botsort]]'s BoT-SORT multi-object tracker (Kalman filter from [[actuate-filterpy]] + appearance features). When a tracked object's dwell time exceeds the configured threshold, the observer fires. For **Line Crossing**, `LineCrossingObserver` uses a `TrajectoryManager` to detect sign-change crossings of a configured boundary line. For **Blacklist**, `BlacklistObserver` fires on re-identification matches.

## 6. Sliding Window Confirmation

The observer opens a detection window -- a `WindowDataPacket` from [[actuate-pipeline-objects]] with an ID of `{custcam_id}{label}{timestamp}`. Each subsequent frame's capture timestamp is appended. Frame images are persisted to S3 via [[actuate-frames]]'s `save_frame`. After `window_length` seconds, the window closes and its metadata is written to DynamoDB's `WindowIdsV2` table via [[actuate-daos]]'s `WindowIdsDAO`. This grouping mechanism batches related detections into a single alertable event, reducing alert fatigue.

## 7. Alert Generation and Dispatch (actuate-alarm-senders)

When the observer decides to fire, it calls `trigger_alert()` on the camera's `MultiAlertSender` from [[actuate-alarm-senders]]. The `MultiAlertSender` builds an `AlertData` object (window ID, labels, confidence, frame dimensions, alert URL, customer/camera metadata), writes the detection window to DynamoDB, and fans out to every configured sender for that camera via a single-worker thread pool.

Senders that need frame images extend `AttachmentAlertSender`, which retrieves annotated frames from S3 and DynamoDB's `EnrichedFrameV2`. Senders that target SQS-based integrations extend `EventListenerAlertSender`, which dispatches via [[actuate-event-listener]] to per-integration SQS FIFO queues.

## 8. SQS Delivery to Customer Systems (queue_consumer)

The [[queue-consumer]] service -- deployed as per-integration Docker containers on the `prod-queue-consumers-sqs` ECS cluster -- long-polls its dedicated SQS FIFO queue. The `ImmixConsumer` reads from `event_queue_immix_alarm.fifo`, formats an XML alarm payload with JPEG/video attachments, and sends it via SMTP to the customer's Immix monitoring station. The `EvalinkConsumer` posts JSON to the [[evalink-components|Evalink]] REST API. The `WebhookConsumer` fires an HTTP POST to a configured URL. Each of the 16 consumer types handles protocol-specific formatting and retry logic.

## 9. Customer Monitoring Console

The alert arrives at the monitoring center's platform -- Immix, [[sentinel-components|Sentinel]], Patriot, SureView, or another of the 27 supported destinations. The operator sees an alarm with annotated frame images (bounding boxes rendered by [[actuate-viz]]), detection metadata, and a link back to the [[alert-ui]] web dashboard. The detection that started as a single [[rtsp-deep-dive|RTSP]] frame has traversed roughly a dozen libraries, two Kubernetes namespaces, three AWS storage services, and an SQS FIFO queue -- in under 10 seconds (p95 target).

## Cross-Topic Dependencies

This flow touches every major topic in the KB: [[vms-connector]] (orchestration), [[actuate-libraries]] (41 packages), [[ai-models/_summary|AI Models & Evaluation]] (YOLO inference), [[data-science/_summary|Data Science Methodology]] (model training and evaluation that produced the model), [[infrastructure/_summary|Infrastructure & Security]] (EKS, DynamoDB, S3, SQS), and every [[integration-immix|integration topic]] (alert delivery). A failure at any stage -- puller timeout, inference server overload, filter misconfiguration, SQS throttling -- can break the chain.
