---
title: "Improvement Opportunities: Low-Hanging Fruit for Tech Docs & Proposals"
type: synthesis
topic: product-roadmap
tags: [synthesis, improvements, proposals, adr, tech-debt, opportunities]
created: 2026-04-15
updated: 2026-04-15
author: kb-bot
---

# Improvement Opportunities

30 actionable ideas sorted by impact/effort ratio, derived from KB synthesis notes, [[active-risks|active risks]], worklog sources, and cross-topic analysis.

## Tier 1: Quick Wins (Days, High Impact)

### 1. Fix CI JSON Quoting Bug in bump-version-stable.sh
`xargs -P` mangles JSON args to `jq` when commit messages contain `[patch]`/`[minor]` tags. Forces 3-step manual workaround on every stable publish. Root cause is identified.
- **Impact:** Medium (DX) | **Effort:** Small | **Jira:** None yet
- **KB:** [[ci-pipeline-mechanics]], [[connector-library-deployment-lifecycle]]

### 2. Fix gh pr merge CI Trigger Gap
GitHub CLI merge uses a token that doesn't trigger the Publish Stable workflow. Requires manual empty commit after every library merge. Fix: use PAT or GitHub App token, or trigger on `pull_request` closed+merged.
- **Impact:** Medium (DX) | **Effort:** Small | **Jira:** None yet

### 3. Aurora Recursive CTE Performance Fix
`get_descendants()` recursive CTE causes 98.7% Aurora CPU spikes. Fix: add index on `inframap_group.parent_id` + cache group tree.
- **Impact:** High (reliability) | **Effort:** Small-Medium | **Jira:** BT-926, BACK-623
- **KB:** [[active-risks]], [[database-performance]]

### 4. Schedule Race Condition Fix
Midnight overrides miss arming due to croniter race condition. Band-aid deployed (scaler replicas 10->20) but underlying bug unfixed.
- **Impact:** High (reliability) | **Effort:** Small-Medium | **Jira:** ENG-96 (Highest, unassigned)

## Tier 2: High-Impact ADRs & Proposals (1-2 Weeks)

### 5. ADR: External Secrets Operator Migration
Secrets in Git (cluster-values.yaml). Deploy ESO to sync from AWS Secrets Manager. Critical security gap.
- **Impact:** High (security) | **Effort:** Medium | **Jira:** None yet
- **KB:** [[secrets-management]]

### 6. ADR: Per-Application Cognito Client Provisioning
19+ apps share one Cognito client with destructive update API. One misconfigured update breaks all auth.
- **Impact:** High (security) | **Effort:** Small | **Jira:** None yet
- **KB:** [[rbac-model]]

### 7. VPA Right-Sizing + EKS 1.35 Upgrade Plan
3-5x CPU over-provisioning across hundreds of pods. EKS 1.35 enables in-place pod resize.
- **Impact:** High (cost + reliability) | **Effort:** Medium | **Jira:** ENG-78, ENG-79 (both Highest, unassigned)
- **KB:** [[vpa-behavior]], [[cost-architecture]]

### 8. Event-Listener Thundering Herd Mitigation
Silent event drops during traffic spikes. Jittered backoff + circuit breaker + queue rate limiting.
- **Impact:** High (reliability) | **Effort:** Medium | **Jira:** ENG-66 (Highest, unassigned)

### 9. Intruder v8 Fleet Rollout Completion
v8 passed all evaluation gates. Needs: v8-calibrated settings generation, pilot sites, fleet migration tooling.
- **Impact:** High (product) | **Effort:** Medium | **Jira:** AI-180
- **KB:** [[model-lifecycle-end-to-end]], [[confidence-threshold-calibration]]

### 10. Connector healthz Endpoint for Spot Scheduling
Complete healthz endpoint -> Karpenter spot instances -> 30-70% compute savings.
- **Impact:** High (cost) | **Effort:** Medium | **Jira:** None yet
- **KB:** [[performance-optimization-landscape]]

## Tier 3: Strategic Architecture Proposals

### 11. ADR: Dynamic Per-Site Shard Sizing
Fixed 24-camera shard size wastes resources. Log per-site perf data, auto-set shard size via connector-deployer.
- **Impact:** High (cost) | **Effort:** Large (ADR itself is days)
- **KB:** [[sharding]], [[cost-architecture]]

### 12. Adaptive Temperature for Context-Aware FPS
Per-camera temperature that boosts FPS on detection, decays to baseline. Captures full events while conserving resources.
- **Impact:** Medium (detection quality + cost) | **Effort:** Medium
- **KB:** [[adaptive-temperature]]

### 13. Server-Side Filter Consolidation
Move confidence/label filters to inference server to reduce network transfer and connector CPU.
- **Impact:** Medium (performance) | **Effort:** Medium
- **KB:** [[filter-pipeline-ordering]], [[performance-optimization-landscape]]

### 14. AdminDAO Decoupling -- Monitoring Read-Model Table
Monitoring directly queries Admin Postgres. Decouple via DynamoDB table for monitoring-relevant fields.
- **Impact:** Medium (architecture + reliability) | **Effort:** Medium
- **KB:** [[admindao-deprecation]]

### 15. ADR: Unified RBAC Strategy
Three independent auth systems with no unified access view. Document current state and decide on long-term approach.
- **Impact:** Medium (security) | **Effort:** Small (ADR) | **Jira:** ENG-123/124/125
- **KB:** [[rbac-model]], [[api-key-lifecycle]]

## Tier 4: Product & Process Improvements

### 16. Watchman Cost Model for Small Sites
Model per-site economics for 4-30 camera sites. Validate/invalidate the [[watchman-repo|Watchman]] market thesis.
- **Impact:** High (product) | **Effort:** Medium
- **KB:** [[cost-architecture]], [[revenue-drivers]]

### 17. AIM Initiative Triage and Staffing Plan
25/29 issues unassigned. Triage the 5-7 highest-ROI items, propose staffing.
- **Impact:** Medium (product) | **Effort:** Small
- **KB:** [[b2b2b-vs-b2b-go-to-market]]

### 18. VLM Cost Monitoring Dashboard
Track VLM GPU spend before it surprises. SQS queue depth + KEDA + cost projection.
- **Impact:** Medium (cost/ops) | **Effort:** Small
- **KB:** [[yolo-vs-vlm-detection-future]]

### 19. Settings Automation for Watchman Zero-Touch Onboarding
Derive defaults from site type classification. Which of 150+ fields can be auto-derived?
- **Impact:** High (product) | **Effort:** Large (proposal is a week)
- **KB:** [[camera-onboarding-end-to-end]]

### 20. VLM Evaluation Framework Formalization
YOLO has 6-tier evaluation. VLM has manual labeling. Formalize benchmarks and regression tests.
- **Impact:** Medium (product) | **Effort:** Medium
- **KB:** [[evaluation-tiers]], [[yolo-vs-vlm-detection-future]]

## Tier 5: Longer-Term Architecture

### 21. Multi-Head YOLO Inference
Run intruder + weapon + fire in single forward pass. Multiplicative cost savings.
- **Impact:** High (cost) | **Effort:** Large | **Jira:** AI-204

### 22. Classic-to-Modern Inference Client Migration
Deprecate [[actuate-classic-inference-client]]. Audit 30+ consumers, prove equivalence, phased migration.
- **Impact:** Medium (DX) | **Effort:** Medium
- **KB:** [[inference-client-evolution]]

### 23. Connector Fleet Rollout Automation
Semi-automated rollout with NR regression detection and one-command rollback.
- **Impact:** Medium (DX/ops) | **Effort:** Medium
- **KB:** [[rollout-process]]

### 24. K8s Deployments Repo Split
Separate Helm charts from [[argocd|ArgoCD]] manifests. Reduce blast radius, improve reusability.
- **Impact:** Medium (DX) | **Effort:** Medium
- **KB:** [[argocd-gitops-workflow]]

### 25. SNS/SQS Fan-out for Alert Delivery
Evaluate SNS topic fan-out vs current per-integration SQS FIFO queues. Simplify adding new integrations.
- **Impact:** Medium (architecture) | **Effort:** Medium
- **KB:** [[sns-sqs-fanout-pattern]]

### 26. Job Executor System Design
Centralize 30+ scattered admin jobs with Django-Q based executor. Creation endpoints, workflow chains, tracking.
- **Impact:** Medium (DX/ops) | **Effort:** Large
- **KB:** [[job-executor-architecture]]

### 27. Jira Reorganization Implementation
39 -> 6 projects. Makes bandwidth allocation between B2B2B and B2B explicit.
- **Impact:** Medium (process) | **Effort:** Medium
- **KB:** [[jira-reorg-proposal]]

### 28. GStreamer/FFmpeg Puller Variants
Isolate suspected [[opencv-entity|OpenCV]] memory leak. Potential decode speedup.
- **Impact:** Medium (reliability) | **Effort:** Medium
- **KB:** [[memory-management]]

### 29. SES Email Template Management Tool
Lightweight tool for browsing/editing SES templates. Quick win for ops.
- **Impact:** Low-Medium (DX) | **Effort:** Small
- **KB:** [[ses-email-tooling-pitch]]

### 30. Watchman Self-Service WireGuard Provisioning
Self-service tunnel setup for <10 min onboarding. Hard prerequisite for [[watchman-repo|Watchman]] beta.
- **Impact:** Medium (product) | **Effort:** Medium | **Jira:** ENG-117, PROD-265/266
