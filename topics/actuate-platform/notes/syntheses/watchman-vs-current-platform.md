---
title: "Watchman vs Current Platform"
type: synthesis
topic: actuate-platform
tags: [synthesis, cross-topic, watchman, b2b, b2b2b, immix, architecture, comparison]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
---

# Watchman vs Current Platform

[[watchman/_summary|Actuate Watchman]] represents Actuate's biggest strategic pivot: from a B2B2B detection engine sold through monitoring center partners to a B2B direct AI-powered virtual security operator for commercial businesses. This synthesis compares what [[watchman-repo|Watchman]] reuses from the current [[actuate-platform/_summary|Actuate Platform Overview]], what it builds new, and the infrastructure implications of running both models simultaneously.

## Business Model Shift

### Current Platform: B2B2B

The current Actuate platform operates as a **detection layer** sold to monitoring center partners. The commercial chain is:

**Actuate -> Monitoring Center (Immix, [[sentinel-components|Sentinel]], SureView, etc.) -> End Customer (business, campus, municipality)**

Actuate never touches the end customer. [[integrations/immix/_summary|Immix]] is the primary partner, and [[autopatrol/_summary|AutoPatrol (H1.2)]]'s VCH product generates ~$800K/12mo through Immix's platform. Alert delivery terminates at the partner's console -- what happens next (dispatch, escalation, verification) is the partner's responsibility. This model means Actuate controls the AI but not the customer experience.

### Watchman: B2B Direct

[[watchman-repo|Watchman]] flips this to:

**Actuate -> Commercial Business (4-30 cameras, direct)**

[[watchman-repo|Watchman]] owns the entire vertical: camera connectivity, AI detection, threat assessment, escalation, notification, and even operator gamification. The monitoring center is removed. Target customers are businesses with 4-30 cameras who cannot afford live remote video monitoring ($50-150+/camera/month) and currently have unmonitored surveillance -- a segment Actuate estimates at the vast majority of the $56-74B global video surveillance market.

### Coexistence Implications

Both models will run simultaneously. The B2B2B platform continues serving existing monitoring center partners, while [[watchman-repo|Watchman]] targets a new market segment. This means Actuate must maintain two go-to-market motions, two UI paradigms (partner console integration vs direct terminal-style UI), and two escalation models (partner-handled vs Watchman-automated).

## What Watchman Reuses

[[watchman-repo|Watchman]] is not a ground-up rebuild. The [[watchman/_summary|Actuate Watchman]] summary explicitly lists reused components:

| Component | Current Platform | [[watchman-repo|Watchman]] Adaptation |
|---|---|---|
| **Camera connectivity** | [[actuate-wireguard]] tunnels via Teltonika RUT241 | Reused as "Actuate Secure" connectivity layer. Adding Actuate Secure App as alternative to hardware router. |
| **Connector pipeline** | [[vms-connector]] full pipeline (pullers, FDMD, inference, filters, observers) | Reused as the AI Detection Layer. Same [[actuate-libraries]] stack. |
| **AI models** | [[ai-models/_summary|AI Models & Evaluation]] -- intruder (v5/v8), weapon, fire, loitering, line crossing, crowd, fall | Reused directly. The Actuate Threat Agent wraps existing model inference. |
| **AutoPatrol scheduling** | [[autopatrol/_summary|AutoPatrol (H1.2)]] patrol microservice | Adapted for [[watchman-repo|Watchman]]'s Patrol Agent. Continuous adaptive scheduling (5-15 min cycles) instead of Immix-triggered. |
| **VLM FP filter** | [[actuate-vlm]] (Qwen3-VL-8B) | Reused for false positive reduction in the Assessment Agent. |
| **CHM patterns** | [[camera-health-monitoring/_summary|Camera Health Monitoring (H1.1)]] (scene change, connectivity, recording status) | Reused for camera health in the Connectivity Agent. |
| **Settings automation** | [[settings-automation/_summary|Settings Automation (H1.4)]] (PPF, auto-ignore zones) | Context synthesis feeds into the Site Context Agent's learned patterns. |

The entire [[actuate-libraries]] dependency tree -- 41 packages -- underpins [[watchman-repo|Watchman]] just as it does the current platform. The [[ds-server-container]] Rust inference servers, the `ds-model-prod` K8s namespace, the DynamoDB tables, the S3 storage -- all shared infrastructure.

## What Watchman Builds New

| Component | What's New | Why It Can't Be Reused |
|---|---|---|
| **Multi-agent orchestration** | Site Supervisor Agent coordinates 8 specialized agents | Current platform has no orchestration layer -- it's a [[detection-pipeline|detection pipeline]], not a decision system. |
| **Two-track routing** | Precursor classification (YOLO as a filter gate) vs active threat detection | Current platform treats every detection equally. [[watchman-repo|Watchman]] needs a "is this worth investigating?" pre-filter. |
| **Compound severity scoring** | Cross-camera severity scoring by Assessment Agent | Current platform scores per-camera independently. [[watchman-repo|Watchman]] correlates across cameras for site-level threat assessment. |
| **Multi-tier escalation** | CRITICAL (push+SMS+call, auto-escalate 60s), HIGH (push+SMS), MEDIUM (push) | Current platform hands off to the monitoring center for escalation. [[watchman-repo|Watchman]] owns it. |
| **[[triage-gamification|Triage gamification]]** | XP/streak system for operator engagement | No equivalent in B2B2B model where operators are professional monitoring center staff. |
| **Terminal-style UI** | Chat-style agentic interface with ghost tile dashboard | Current platform integrates into partner UIs ([[alert-ui]], [[camera-ui]]). [[watchman-repo|Watchman]] has its own design language. |
| **BYOD self-service onboarding** | 9-step wizard (WireGuard setup, camera discovery, site classification) | Current onboarding is partner-mediated and manual. |
| **Learning Agent** | Triage feedback loop with accuracy tracking | Current platform has no closed-loop learning from operator feedback. |

## Agent Architecture Detail

[[watchman-repo|Watchman]] introduces 9 agents, mapped to the reuse spectrum:

| Agent | JIRA | Status | Reuse Level |
|---|---|---|---|
| Connectivity Agent | PROD-120 | EXISTS | High -- adapts [[actuate-wireguard]] + Actuate Secure |
| Patrol Agent | PROD-152 | EXISTS | High -- adapts [[autopatrol/_summary|AutoPatrol (H1.2)]] scheduling |
| Actuate Threat Agent | PROD-132 | EXISTS | High -- wraps existing [[vms-connector]] pipeline |
| Assessment Agent | PROD-157 | PARTIAL | Medium -- extends AUTO-110 VLM assessment |
| Site Context Agent | PROD-167 | PARTIAL | Medium -- adapts settings automation context |
| Recommendation Agent | PROD-162 | EXISTS | Medium -- adapts AUTO-124 recommendation system |
| Site Supervisor Agent | PROD-147 | NEW | None -- new orchestration layer |
| Escalation Agent | PROD-172 | NEW | None -- new multi-tier notification chain |
| Learning Agent | PROD-209 | NEW | None -- new feedback loop system |

Three agents are genuinely new (Supervisor, Escalation, Learning). Three are heavy adaptations. Three are relatively straightforward wrappers around existing capabilities.

## Infrastructure Implications

### Shared Infrastructure

Both platforms share the same AWS account (388576304176), EKS clusters, [[ds-server-container]] model servers, DynamoDB tables, and S3 buckets. [[watchman-repo|Watchman]] does not require a separate inference stack -- it uses the same `ds-model-prod` namespace.

### New Infrastructure

| Need | Why |
|---|---|
| **Agent runtime** | The multi-agent orchestration layer needs a hosting environment. Likely K8s in a new namespace. |
| **Notification infrastructure** | Push notifications, SMS, and automated phone calls (CRITICAL tier) require new integrations beyond existing SES/SNS. |
| **Self-service onboarding backend** | Camera discovery (ONVIF/[[rtsp-deep-dive|RTSP]]), automated WireGuard provisioning, site type classification -- all require new API endpoints. |
| **Triage/feedback data stores** | XP tracking, triage history, learning agent state -- new DynamoDB tables or PostgreSQL schemas. |
| **On-prem evaluation** | [[actuate-watchman-internal]] already established performance baselines for on-prem models (OpenVINO INT8). Edge deployment may require ARM builds. |

### Scaling Differences

The current platform scales per-site via [[connector-deployer]] (one K8s Deployment per site, memory at `cameras * 32MB + 500MB base`). [[watchman-repo|Watchman]] targets businesses with 4-30 cameras -- smaller sites but potentially far more of them. The agent orchestration layer adds per-site overhead beyond the bare connector pipeline. The EKS upgrade (ENG-79, 1.32 -> 1.35 for in-place pod resize) and VPA fixes (ENG-78) become more urgent as [[watchman-repo|Watchman]] multiplies the number of active deployments.

## Risk Assessment

The biggest risk is not technical -- it is organizational. Running a B2B2B detection engine and a B2B direct security operator platform simultaneously means serving two distinct customer types (monitoring centers vs businesses) with different support models, different SLAs, and different feature priorities. The [[autopatrol/_summary|AutoPatrol (H1.2)]] team's work on [[flex-ignore-zones|flex ignore zones]], [[vlm-integration|VLM integration]], and Immix bounding boxes serves the B2B2B model. The [[watchman-repo|Watchman]] team's work on agents, escalation, and onboarding serves B2B direct. Shared infrastructure changes (EKS upgrades, library updates, model deployments) affect both.

The MVP target of 10-20 beta sites with live camera feeds is deliberately small, allowing the team to validate the agent architecture without disrupting the revenue-generating B2B2B platform.
