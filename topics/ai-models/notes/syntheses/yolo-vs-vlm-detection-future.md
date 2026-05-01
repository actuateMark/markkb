---
title: "YOLO vs VLM Detection Future"
type: synthesis
topic: ai-models
tags: [synthesis, cross-topic, yolo, vlm, inference, cost, latency, evaluation, watchman, autopatrol]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# YOLO vs VLM Detection Future

Actuate's detection architecture is evolving from a single-model pipeline (YOLO on every frame) to a layered system where YOLO serves as a fast, cheap filter gate and Vision Language Models provide expensive, accurate secondary verification. This synthesis examines the cost, latency, evaluation, and architectural implications of this shift, and asks the critical economic question: when is VLM worth the cost?

## The Two Tiers

### YOLO: Fast, Cheap, High False Positive Rate

The production fleet runs YOLOv5 (`intruder-384h-512w-svc`, 7 classes) with v8 (`int07-actuate003-v8`) approved for rollout. YOLO inference is synchronous within the [[pipeline-architecture]] -- each frame passes through the [[inference-pool|AsyncInferencePool]] (AIMD congestion control, 200ms latency target) to Rust [[ds-server-container]] model servers in `ds-model-prod`. The inference is deterministic, fixed-compute, and runs on Inferentia2 accelerators for YOLO workloads, making it significantly cheaper per frame than GPU inference.

YOLO's weakness is false positives. Common culprits include reflections triggering person detection, animals classified as intruders, swaying vegetation, and lighting changes interpreted as threats. The entire post-processing chain in the connector -- stationary filter, IoU deduplication, [[ignore-zones|ignore zones]], confidence thresholding, sliding window confirmation -- exists to suppress YOLO's false positive tendency. Despite this, FP rates remain high enough to drive operator alert fatigue, which is the foundational problem that both the [[vlm-fp-reduction]] filter and [[watchman/_summary|Actuate Watchman]]'s [[triage-gamification|triage gamification]] system aim to address.

### VLM: Expensive, Accurate, Asynchronous

[[vlm-inference|VLM inference]] (Qwen3-VL-8B-Instruct, Qwen2.5-VL-32B-Instruct-AWQ, Gemma-3-12B-IT-FP8) runs on a completely separate infrastructure path. The [[actuate-vlm]] client library submits requests to SQS FIFO queues; [[vlm-inference]] GPU workers (running vLLM on g5.2xlarge instances, ~$1.21/hr, 24 GB VRAM) pick them up and write results to DynamoDB. KEDA scales replicas from zero based on queue depth.

VLMs can do what YOLO cannot: describe context ("a person climbing over a fence at 3 AM carrying a large bag"), assess anomaly ("this is unusual for a loading dock at this hour"), and provide structured reasoning about whether a detection constitutes a genuine threat. This contextual assessment is the qualitative leap that [[autopatrol/_summary|AutoPatrol (H1.2)]]'s [[vlm-integration|VLM integration]] and [[watchman/_summary|Actuate Watchman]]'s Assessment Agent depend on.

## The Layered Architecture

The emerging pattern -- formalized in [[watchman/_summary|Actuate Watchman]]'s two-track routing -- layers these tiers:

```
Frame -> YOLO (every frame, ~ms latency, Inferentia2)
    |
    +--> No detection -> discard (vast majority of frames)
    |
    +--> Detection -> Post-processing filters -> Confirmed event
              |
              +--> VLM review (select events, ~seconds latency, g5.2xlarge GPU)
                       |
                       +--> Confirm -> alert
                       +--> Reject -> suppress
                       +--> Uncertain -> lower-priority queue
```

YOLO processes every frame (high throughput, low cost per inference). VLM reviews only confirmed detection events (low throughput, high cost per inference). The economic viability of this architecture depends entirely on the ratio: if YOLO produces 100 events and VLM reviews all 100, the cost is dominated by VLM. If YOLO's post-processing filters reduce events to 5 before VLM review, the VLM cost is manageable.

## Cost Tradeoff

| Dimension | YOLO | VLM |
|---|---|---|
| **Hardware** | Inferentia2 (inf2 instances) | g5.2xlarge GPU (~$1.21/hr) |
| **Scaling** | Always-on (YOLO servers handle all frames) | Scale-to-zero via KEDA (SQS queue depth) |
| **Per-inference cost** | Very low (custom silicon, batch-optimized) | High (general GPU, attention-heavy architecture) |
| **Latency** | ~ms (sync, within pipeline) | Seconds (async, SQS + DynamoDB polling) |
| **Throughput** | Every frame (1-3 analytics FPS per camera) | Select events only |

For an 8B parameter model on 24 GB VRAM, recommended GPU settings are `GPU_MEMORY_UTIL=0.95`, `ENFORCE_EAGER=true`, `MAX_MODEL_LEN=8192`. OOM mitigation requires lowering `MAX_NUM_SEQS` or `MAX_MODEL_LEN` -- meaning a single GPU instance has a hard ceiling on concurrent requests. The 32B quantized model (Qwen2.5-VL-32B-Instruct-AWQ) uses AWQ quantization to fit in the same VRAM budget but may still require a dedicated instance.

Multi-head inference (AI-204, not yet started) could reduce YOLO's per-frame cost by running multiple detection models in a single forward pass, widening the cost gap between YOLO and VLM tiers.

## Latency: Sync vs Async

YOLO inference is synchronous within the pipeline. The [[inference-pool|AsyncInferencePool]]'s AIMD window targets 200ms response time, with three-component timing (queue_ms, network_ms, gil_reacquire_ms) for diagnosis. The pipeline blocks on inference -- a frame cannot proceed to post-processing until YOLO returns results.

[[vlm-inference|VLM inference]] is fully asynchronous. The [[actuate-vlm]] client submits to SQS and polls DynamoDB. This decoupling means VLM results arrive seconds after the initial detection, which is acceptable for alert verification (the alert can be held pending VLM verdict) but incompatible with real-time frame-by-frame processing. The webhook callback option (`callback_url` on submit) enables event-driven architectures where the pipeline does not poll.

[[watchman/_summary|Actuate Watchman]]'s two-track routing makes this latency difference architectural. The "precursor" track (YOLO) operates at frame rate for real-time awareness. The "threat assessment" track (VLM) operates at event rate for verification. The Site Supervisor Agent switches between Patrol Mode (mostly precursor) and Active Monitoring Mode (both tracks simultaneously) based on activity levels. This dual-tempo design accepts VLM latency as a feature, not a bug -- it provides time for cross-camera correlation in the Assessment Agent before surfacing alerts to the operator.

## Evaluation: Two Paradigms

The evaluation methodologies for YOLO and VLM are fundamentally different:

**YOLO evaluation** uses quantitative CV metrics: mAP@0.5 on labeled datasets (28,828+ images via `actuate-eval`), McNemar's paired statistical test at the alert level (`shadow-test-eval`), confidence threshold sweeps (0.10-0.80), FP stress testing on Genesis image sets, shadow testing on live traffic, and point-based annotation (Mladen Lukic's centroid matching). These are well-established computer vision benchmarks with clear numeric thresholds.

**VLM evaluation** requires a different paradigm. The VLM returns natural language verdicts (confirm/reject/uncertain), not bounding boxes. Evaluation tools include the [[vlm-eval-visualizer]] (Streamlit app for manual TP/FP labeling against VLM verdicts, with accuracy metrics), LLM-as-Judge baselines (GPT-4o-mini and Claude Haiku comparing model verdicts against ground truth), and the VLM/LLM Scorecard tracked by the DS team. [[carlos-torres|Carlos Torres]] runs assessment sub-tasks (PROD-276 through PROD-282) comparing models on accuracy, latency, and false positive rate.

The gap is that YOLO evaluation produces mAP numbers that can be compared across model versions. VLM evaluation produces verdict accuracy rates that depend heavily on prompt engineering ([[alena-prashkovich|Alena Prashkovich]]'s Phase III work), the specific event types tested, and the subjective definition of "false positive" for complex scenes. The [[vlm-eval-visualizer]]'s manual labeling workflow (press T for True Positive, F for False Positive) highlights this: a human reviewer must decide whether the VLM's contextual assessment is correct, introducing human judgment into the evaluation loop.

## When Is VLM Worth the Cost?

The economic question reduces to: **what is the dollar value of a suppressed false positive?**

For [[autopatrol/_summary|AutoPatrol (H1.2)]]'s Immix integration, each false alert that reaches a monitoring center operator wastes professional monitoring time. If monitoring center labor costs $20-30/hour and each false alert consumes 30-60 seconds of operator time, the cost of a false positive is $0.17-0.50. A g5.2xlarge hour at $1.21 can process hundreds of VLM requests. If VLM suppresses even a modest percentage of false alerts for a high-volume site, the ROI is positive.

For [[watchman/_summary|Actuate Watchman]]'s direct-to-business model, the calculus changes. A false alert pushed to a business owner erodes trust and contributes to the alert fatigue that eventually leads to the system being ignored. The cost is not labor time but product abandonment risk. This makes VLM verification more valuable per event in the [[watchman-repo|Watchman]] context, even if the per-site event volume is lower.

The break-even depends on three variables: (1) the false positive rate of the YOLO + post-processing chain before VLM review, (2) the VLM's true negative rate (how many FPs it actually catches), and (3) the cost of serving [[vlm-inference|VLM inference]] at the required volume. With KEDA scaling to zero, idle VLM cost is near-zero. The marginal cost is the GPU-seconds consumed per event. For [[watchman-repo|Watchman]]'s target of 4-30 cameras per site, the event volume is low enough that VLM cost per site should be modest -- but across hundreds of [[watchman-repo|Watchman]] sites, the aggregate GPU demand requires careful capacity planning.

## The Coexistence Trajectory

The near-term architecture is clear: YOLO remains the primary detector, VLM is layered on as an optional post-filter. The medium-term question is whether VLM moves earlier in the pipeline. The [[adaptive-temperature]] concept (proposed, not implemented) hints at a future where detection confidence influences processing intensity. A frame that YOLO marks as uncertain could be routed directly to VLM without waiting for the full post-processing chain -- trading latency for accuracy on ambiguous detections.

The long-term trajectory may involve VLM models efficient enough for real-time inference, collapsing the two tiers back into one. But as of April 2026, the cost and latency gap between Inferentia2-hosted YOLO and g5.2xlarge-hosted VLM is wide enough that the layered architecture is the only economically viable design for production-scale video analytics.
