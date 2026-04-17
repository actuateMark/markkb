---
type: concept
author: kb-bot
created: 2026-04-13
updated: 2026-04-13
tags: [settings-automation, vlm, false-positive, fp-reduction, mvp, filter]
---

# VLM False Positive Reduction

The VLM FP Reduction filter is a major initiative within [[settings-automation]] that uses Vision Language Models to post-process detection alerts and filter out false positives before they reach operators. Tracked as SA-221 and PROD-2, with an MVP definition actively driven by Laura Reno as of April 2026.

## The False Positive Problem

Traditional object detection models (YOLO variants, Actuate's proprietary threat models) produce false positives at rates that can overwhelm operators. Common culprits include: reflections triggering person detection, animals flagged as intruders, swaying vegetation classified as motion threats, and lighting changes interpreted as fire. Each false positive erodes operator trust and contributes to alert fatigue -- the same problem [[watchman]]'s [[triage-gamification]] system is designed to combat from the engagement side.

The VLM FP filter attacks the problem from the technical side: catch false positives before they become alerts.

## How the Filter Works

The VLM FP filter operates as a second-pass verification layer in the detection pipeline:

1. **Initial detection** -- The primary model (YOLO precursor or Actuate threat model) flags an event with a detection class, bounding box, and confidence score
2. **VLM review** -- The flagged frame (or short clip) is sent to a VLM with a prompt engineered to evaluate whether the detection is genuine. The prompt includes the detection class and asks the model to confirm or deny
3. **Verdict** -- The VLM returns a structured verdict: confirm (genuine threat), reject (false positive), or uncertain
4. **Routing** -- Confirmed detections proceed through the alert pipeline normally. Rejected detections are suppressed. Uncertain verdicts may be routed differently (e.g., lower-priority queue or logged for review)

This architecture adds latency (VLM inference takes time) but dramatically reduces the volume of false alerts reaching operators.

## MVP Scope (SA-221)

Laura Reno is defining the MVP, which includes:

- **Quantified FP reduction performance** -- Hard metrics showing the before/after false positive rate. This is the headline number that justifies the feature
- **Frontend components** -- UI for viewing alerts filtered by VLM verdict, so operators can see why an alert was passed or suppressed
- **New Relic logging** -- Adequate observability to monitor VLM filter performance in production (latency, verdict distribution, error rates)
- **Documentation** -- Internal and external support docs, marketing materials, demo video and demo site

The emphasis on documentation and marketing alongside the technical deliverables suggests this is being positioned as a flagship capability for sales conversations.

## Models Under Evaluation

The VLM FP filter draws from the same model evaluation pipeline as [[vlm-integration]] in AutoPatrol:

- **Qwen3-VL-8B-Instruct** -- fast inference, lower accuracy ceiling
- **Qwen2.5-VL-32B-Instruct-AWQ** -- quantised for efficiency, higher accuracy
- **Gemma-3-12B-IT-FP8** -- mid-range alternative

Carlos Torres leads model routing and the VLM FP filter implementation (SA-171 epic). The VLM/LLM Version 2.0 epic (PROD-272) tracks next-generation model integration including supervisor models (PROD-273) and an upgraded Temporal Linker (PROD-274).

## Key People

| Person | Role |
|--------|------|
| Laura Reno | MVP definition, requirements |
| Carlos Torres | Model routing, filter implementation |
| Zack Schmidt | Testing, productionisation |
| Otzar Jaffe | Related work on ignore zones and Classifyr |

## Relationship to Other Initiatives

VLM FP reduction is listed as reused technology that feeds into [[watchman]]. In Watchman's [[multi-agent-architecture]], the filter would sit within the Actuate Threat Agent's dual-track routing -- VLM verification happens after the YOLO precursor gate and before events are forwarded to the Assessment Agent. Reducing false positives at this stage means the Assessment Agent processes fewer garbage events, the Recommendation Agent generates fewer spurious instructions, and operators see cleaner triage queues in the [[triage-gamification]] system.
