---
title: AWS Rekognition Video
type: entity
topic: video-processing
tags: [aws, rekognition, ml, video-analytics, kvs, content-moderation, custom-labels]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
incoming:
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/video-processing/_summary.md
  - topics/video-processing/notes/syntheses/actuate-build-vs-buy-tradeoffs.md
  - topics/video-processing/notes/syntheses/aws-video-services-decision-matrix.md
incoming_updated: 2026-05-01
---

# AWS Rekognition Video

## What it is

Managed video analytics. Rekognition Video runs pre-trained ML models against either:

- **Stored video** in S3 (asynchronous job model — you submit, it returns labels later); or
- **Streaming video** in [[aws-kvs-entity]] ([[aws-kvs-entity|Kinesis Video Streams]]) — a continuous Stream Processor consumes a [[kvs-components|KVS]] stream and emits results into a Kinesis Data Stream.

Built-in detection categories:

- **Label detection** — generic object/scene labels (Car, Person, Building, Sky, ...).
- **Faces** — detection + matching against face collections (`IndexFaces` / `SearchFacesByImage`); face attributes (age range, emotions, glasses, beard) — accuracy varies and is usage-policy-restricted.
- **Celebrity recognition** — pretrained celebrity database (limited usefulness outside media monitoring).
- **Person paths / tracking** — bounding-box trajectories per detected person across the clip.
- **Content moderation** — explicit / suggestive / violence / weapons / drugs taxonomy with confidence scores.
- **Technical cue detection** — black frames, color bars, end credits, shot boundaries (broadcast-QC use case).
- **Text detection (OCR)** — detect & read text in the video.

Rekognition Image is the per-image variant (stateless, single image input, single response); Rekognition Video stitches these into temporal pipelines plus offers tracking/path/moderation that need temporal context.

## API surface

`boto3.client("rekognition")` is unified across Rekognition Image and Video:

- **Stored video (async)** — `start_label_detection(Video={'S3Object': {...}}, NotificationChannel={'RoleArn', 'SNSTopicArn'})` → polled with `get_label_detection(JobId)` or pushed via SNS on completion. Same pattern for `start_face_detection`, `start_face_search`, `start_content_moderation`, `start_person_tracking`, `start_text_detection`, `start_segment_detection`.
- **Streaming video ([[kvs-components|KVS]])** — `create_stream_processor(Input={'KinesisVideoStream': {'Arn'}}, Output={'KinesisDataStream': {'Arn'}}, Settings={'FaceSearch'|'ConnectedHome'})`. Two flavors: face search against a collection (security) and "ConnectedHome" home-camera detections (people / pets / packages).

**Custom Labels** is a distinct sub-product — `start_project_version` / `detect_custom_labels` — for training and serving small custom classifiers on your own image data. Status as of late 2025: AWS announced **Rekognition Custom Labels is being deprecated / no longer accepting new customers**, replaced by SageMaker / Bedrock workflows. Confirm current state before designing anything new on top of it.

## Quotas and pricing

- **Stored video**: per-minute-of-video pricing per analysis type; minutes round up; minimum charge per job. Rough numbers (us-east-1, late 2025): ~$0.10/min for label detection, similar for face detection, more for content moderation.
- **Streaming video**: per-minute-of-stream-processed; persistent stream processors bill while running.
- Per-account TPS / concurrent-job limits, raisable via support.

For a fleet running thousands of cameras at multiple frames-per-second, Rekognition's per-minute pricing ends in eye-watering territory very quickly — the math doesn't favor it for high-volume streaming workloads.

## When to reach for it

- ✅ Low-volume, occasional ingestion-time labeling (tag a single user-uploaded clip).
- ✅ Content moderation for user-generated video (textbook fit).
- ✅ Face search against a small collection on a small number of streams.
- ✅ Broadcast-QC technical-cue detection.
- ✅ "We need *some* video AI on this video service we just shipped, and we don't want to operate models" — Rekognition is the easiest box-checking option.

## When not to reach for it

- ❌ High-throughput per-frame inference at fleet scale (the Actuate use case).
- ❌ You need domain-specific behavior (loitering on a car lot, perimeter intrusion, tailgating) — generic labels miss it.
- ❌ Fine-grained per-class alert-rate tuning.
- ❌ On-prem / air-gapped deployment.

## Actuate touchpoints

**Not used.** No `rekognition` boto3 client invocations anywhere in scouted libraries.

Actuate runs **its own model stack** ([[ai-models/_summary]]) — YOLO variants, custom-trained motion-plus / fire / weapon / person-on-property detectors, plus VLM-based analysis ([[watchman/_summary]]) for clip review. The decision to roll our own is intentional and well-grounded:

1. **Domain fit.** Surveillance-specific behaviors (perimeter cross, loitering, scene-class-specific person detection) need surveillance training data. Rekognition's generic labels would produce constant false-positives on, e.g., a "Person" label when the customer only cares about a person on a roof.
2. **Per-frame cost.** At ~thousands of cameras × many fps × 24/7, the per-minute Rekognition pricing is several orders of magnitude more expensive than running our own GPU pool on EC2 G5/G6 instances.
3. **Custom alert-rate tuning.** We need per-customer false-positive ceilings, post-detection VLM verification ([[watchman/_summary]]), and contextual logic. Rekognition is opaque and untunable.
4. **Custom models** for things Rekognition doesn't ship — fire / smoke detection, weapon detection, license-plate context, motion-plus.
5. **On-prem viability.** Some customer scenarios require encoder-or-inference-on-prem; AWS Rekognition is cloud-only. Our model stack runs on customer hardware too.

**Custom Labels** specifically is doubly problematic — it's deprecated, and even at its best it didn't meaningfully outperform a properly trained YOLO on our data.

The plausible narrow use cases for Rekognition Video at Actuate, all niche:

- **Content-moderation pre-filter** on user-submitted clips for any future operator-onboarding flow (UGC).
- **One-off technical-cue detection** to find a black-frame in a partner-supplied clip during incident analysis.
- **Customer-supplied legacy face-collection-style search** (specific contractual ask) — one-off integration, not a default.

None of these are on the roadmap. Default verdict: **skip**, our home-rolled stack is the right call. Worth re-evaluating only if the per-stream economics of the AWS managed services improve dramatically, or if a contract specifically requires AWS-branded inference.

Cross-references: [[ai-models/_summary]], [[watchman/_summary]], [[aws-video-services-decision-matrix]] for the side-by-side, [[reading-list]] for AWS GroundTruth Video labeling (the relevant tool if our training-data scope grows).
