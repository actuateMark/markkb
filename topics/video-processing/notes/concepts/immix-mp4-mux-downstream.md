---
title: "Downstream Immix MP4 Muxer (event_queue_immix_alarm.fifo consumer)"
type: concept
topic: video-processing
tags: [immix, mp4, clip-generation, sqs, lambda, follow-up]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# Downstream Immix MP4 Muxer

## Question

[[actuate-clip-generation-flow]] flagged a seam: `actuate-libraries/actuate-alarm-senders/src/actuate_alarm_senders/immix/immix_alert_sender.py:88-100` pushes an `event_type` + `s3_folder` + `attachment_frames` payload onto `event_queue_immix_alarm.fifo` when an Immix recipient has `use_mp4=True`, but no MP4 muxer exists in the connector / pullers / alarm-senders codebases. **Who consumes the FIFO and assembles the MP4?**

## What we found

The consumer is **`queue_consumer`** at `/home/mork/work/queue_consumer/`, specifically `consumers/immix/immix_consumer.py` — `ImmixConsumer.queue_name = "event_queue_immix_alarm.fifo"` (line 33). It is **not a Lambda**; it is a long-running queue listener packaged two ways:

- **ECS Fargate** task definition `consumers/immix/immix-task-definition.json` → image `388576304176.dkr.ecr.us-west-2.amazonaws.com/queue_immix_consumer:latest`, family `queue_immix_consumer`, 2 vCPU / 4 GB RAM. ECS autoscaling target defined at `/home/mork/work/ds-terraform-eks-v2/stages/prod/us-west-2/ecs-autoscaling/terragrunt.hcl:11-22`: cluster `prod-queue-consumers-sqs`, service `prod-queue-immix-consumer`, min 7 / max 300 tasks, scale-out at 500 visible SQS messages, scale-in disabled.
- **EKS Helm chart** `/home/mork/work/kubernetes-deployments/deployments/applications/queue-consumer-prd/templates/deployment_immix.yaml` → deployment `queue-immix-consumer` with HPA at `templates/hpa_immix.yaml`. Same image artifact, deployed via the EKS path. Both paths exist; the active runtime is whichever has tasks/pods scheduled today (likely ECS by the autoscaling block being live).

The SQS queue itself is provisioned in `/home/mork/work/ds-terraform-eks-v2/stages/prod/us-west-2/sqs_queue/` and `stages/prod/eu-west-1/sqs_queue/terragrunt.hcl:43-46` (`event_queue_immix_alarm = { name = "event_queue_immix_alarm.fifo", enable_sse = false }`). Both regions have it.

The consumer entrypoint: `app.py` reads `CONSUMER=immix` from env → `consumer_factory.make_consumer("immix")` → `ImmixConsumer()` → `super().__init__(self.queue_name)` in `consumers/base_queue_consumer.py:17-29` polls SQS via `boto3.resource("sqs").get_queue_by_name(QueueName="event_queue_immix_alarm.fifo")` and dispatches messages to `ImmixConsumer.action()` which spawns a thread per message.

## What we ruled out

- **No Lambda function** named `immix-clip-muxer-*` or `*-mp4-builder-*` exists. No Lambda IaC matched. The autoscaling target is an ECS service, not a Lambda event-source-mapping.
- **No [[aws-mediaconvert-entity|MediaConvert]] job** is dispatched. No `mediaconvert.create_job` calls anywhere in `queue_consumer/`. See [[aws-mediaconvert-entity]] — it would not have been a fit anyway given the per-clip latency budget (alert clips need to be on a dispatcher screen in seconds, not 30s-2min).
- **Not in the connector / libraries**. Confirmed by the original scout pass — no `av.open(..., mode="w")`, no `cv2.VideoWriter`, no `imageio.get_writer`, no muxing `subprocess.run` in `actuate-pullers`, `actuate-pipeline`, or `actuate-alarm-senders`.
- **Not in `actuate_admin`**. Not a consumer of this queue.

## How the mux actually works

End-to-end in the consumer:

1. **`ImmixConsumer.thread_action`** (`immix_consumer.py:50-56`) deserializes the SQS message body → `ImmixAlertData`. The alert data parses the recipients JSON; if **any** recipient has `use_mp4=True`, the whole alert is treated as MP4 (`immix_alert_data.py:31-32`).
2. **`get_images(alert_data, enriched_frames_dao, s3_dao, logger)`** (`consumers/shared/utils.py`) reads the JPEG sequence from `s3_folder` using the `EnrichedFrameDAO` (DDB table `EnrichedFrameV2`) to find each frame's `s3_bucket` + `s3_key`, then pulls the bytes via `S3DAO`. It also computes `fps` from the timestamp delta of the first vs last frame, with `fps` clamped to `[1, 4]` and defaulting to 1 if degenerate (`shared/utils.py:130-141`).
3. **`make_video_from_images(images, video_name, use_opencv=False, fps, logger)`** (`shared/utils.py:144-153`) — `ImmixConsumer` always passes `use_opencv=False` (`immix_consumer.py:107`), so it routes to `make_video_ffmpeg`.
4. **`make_video_ffmpeg`** (`shared/utils.py:174-204`) — writes each frame to `/tmp/<video_name>/frameNNN.png` via `cv2.imencode(".png", image)`, then **`subprocess.run(["ffmpeg", "-framerate", str(fps), "-i", frame_path, "-vcodec", "libxvid", filename])`** with `check=True`. **The output is `.avi` with libxvid** (MPEG-4 ASP / Xvid), despite `make_video_from_images` constructing a `.mp4` filename — line 186-187 strips the `.mp4` extension and replaces it with `.avi` before invoking [[ffmpeg-entity|ffmpeg]]. So the file is named `.avi` and is Xvid in an AVI container, not [[h264-deep-dive|H.264]] in MP4.
5. **The "MP4" is delivered as an SMTP email attachment** (`immix_consumer.py:185-193`) — the mux output is read back, wrapped in `MIMEApplication`, given the `Content-Disposition: attachment; filename="video.mp4"` header (note: the **filename header lies — the bytes are AVI/Xvid**), attached to a MIME multipart, and `smtplib.SMTP(recipient["server"], recipient["port"]).sendmail(...)` ships it to the Immix server's SMTP listener with the alert XML body. Up to `MAX_IMMIX_RETRIES=2` SMTP attempts. The temp file is removed on the way out (line 222-225).

So: **muxer is `subprocess.run(["ffmpeg", ...])` with `-vcodec libxvid` writing to AVI**; container/codec is decoupled from the `use_mp4` boolean (which is really "send a video instead of stills"); delivery is **SMTP, not S3 or HTTP POST**.

This matches Option C from [[actuate-clip-generation-flow]] (`subprocess.run(["ffmpeg", ...])`) — the unbounded-subprocess concern raised in that synthesis applies here too. There is **no timeout** on the [[ffmpeg-entity|ffmpeg]] subprocess (`shared/utils.py:198`), which is a hang risk under the same family as the `fish2pano` finding.

The `make_video_opencv` path (`shared/utils.py:206-224`) is the [[opencv-entity]]-based fallback (mp4v fourcc, real `.mp4`) but it is **not reachable from the Immix path** as currently wired.

## Open follow-ups / next steps

1. **The `.mp4` filename / AVI bytes mismatch** — Immix VCH may be parsing this leniently but the filename should match the bytes. Either the codec should switch to [[h264-deep-dive|H.264]]-in-MP4 (libx264 + container `.mp4`) or the attachment filename should change to `video.avi`. Worth raising as a tracked issue.
2. **No subprocess timeout** — `make_video_ffmpeg` has no `timeout=` and `check=True`; a malformed PNG sequence could hang an ECS task indefinitely. Same family of risk as flagged in [[actuate-clip-generation-flow]] under Option C cons. Add `timeout=30`.
3. **The `use_mp4` semantics drift** — the field name implies MP4, the consumer produces AVI/Xvid. Renaming to `use_video` (with explicit `video_format` if needed) would prevent future confusion.
4. **The temp directory is not cleaned up** — `make_video_ffmpeg:202` removes the `frameNNN.png` files but not the parent directory `/tmp/<video_name>/`. Slow tmpfs leak per task lifetime.
5. **Confirm the EU consumer** — `event_queue_immix_alarm.fifo` exists in `eu-west-1` per the Terragrunt block, but the `ecs-autoscaling` block is only set under `us-west-2`. Verify whether the EU queue is consumed at all (separate ECS service in eu-west-1, or same-region consumption with cross-region delivery, or unused). Check `/home/mork/work/ds-terraform-eks-v2/stages/prod/eu-west-1/` for an analogous autoscaling or service definition.

## Cross-references

- [[actuate-clip-generation-flow]] — parent synthesis; this note resolves the "downstream FIFO consumer" seam called out at line 24.
- [[ffmpeg-entity]], [[ffmpeg-python-bindings]] — the muxer is a raw `subprocess.run` to `ffmpeg`, not the python-[[ffmpeg-entity|ffmpeg]] binding.
- [[aws-mediaconvert-entity]] — ruled out; latency budget incompatible with alert dispatch.
- [[pyav-entity]], [[opencv-entity]] — the candidate libraries [[actuate-clip-generation-flow]] discusses for an in-process replacement; not currently on this path.
- [[integrations/immix/_summary]] — Immix integration overview.
- [[vms-connector/_summary]] — upstream producer of the SQS message.
