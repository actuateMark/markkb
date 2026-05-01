---
title: "vlm-eval-visualizer"
type: entity
topic: ai-models
tags: [repo, vlm, streamlit, evaluation, labeling, dynamodb, alert-verification]
created: 2026-04-13
updated: 2026-04-13
author: kb-bot
incoming:
  - topics/ai-models/notes/concepts/vlm-pipeline-architecture.md
  - topics/ai-models/notes/entities/ds-smart-alert-supervisor.md
  - topics/ai-models/notes/syntheses/yolo-vs-vlm-detection-future.md
  - topics/data-science/notes/syntheses/model-lifecycle-end-to-end.md
incoming_updated: 2026-05-01
---

# vlm-eval-visualizer

Streamlit application for reviewing security alerts alongside VLM (Vision Language Model) verdicts. Supports manual True Positive / False Positive labeling with keyboard shortcuts and provides VLM performance statistics.

**Repo:** `aegissystems/vlm_eval_visualizer` (private, updated 2026-03-23)

## Purpose

After [[vlm-inference|VLM inference]] runs on security camera alerts, someone needs to verify whether the model's verdicts are correct. This tool presents each alert in an embedded Actuate UI iframe, fetches the corresponding `vlm_detail` and `vlm_verdict` from the `WindowIdsV2` DynamoDB table, and lets the reviewer label each alert as TP or FP with a single keypress.

## Features

- **Alert viewer**: Embedded iframe showing the alert in the Actuate UI, with a Tampermonkey userscript available to auto-fill the password prompt.
- **DynamoDB integration**: Pulls `vlm_detail` and parses `vlm_verdict` for each alert directly from the `WindowIdsV2` table in `us-west-2`.
- **Manual labeling**: Press `T` (True Positive) or `F` (False Positive) to label and auto-advance. Labels persist to a `-verified.csv` output file.
- **Performance stats**: Computes TP / FP / FN / TN counts with accuracy metrics based on manual labels vs. VLM verdicts.
- **Timeline visualization**: Stacked bar chart of passed / suppressed / not-evaluated alerts over time, with configurable bin sizes (15 min, 1 hr, 4 hr, 1 day).
- **Filtering**: Filter by VLM verdict and free-text search.

## Data Flow

1. Start with a raw alerts CSV (e.g., from the `fp-report` repo) containing `Site`, `Camera`, `Alert Type`, `Alert URL`.
2. Run `window_id_parser.py` to extract `window_id` from alert URLs and produce the input CSV.
3. Point `app_vlm_results.py` at the parsed CSV and launch with `streamlit run`.
4. The app fetches VLM results from DynamoDB and presents them for review.
5. Output is a verified CSV with columns: `window_id`, `site`, `camera`, `alert_type`, `alert_url`, `vlm_detail`, `vlm_verdict`, `manual_label`.

## Requirements

Python 3.10+, `streamlit`, `pandas`, `boto3`. AWS credentials with read access to the `WindowIdsV2` DynamoDB table.

## Related

- [[vlm-inference]] -- the GPU worker that produces the VLM verdicts this tool reviews
- [[actuate-vlm]] -- client library for submitting VLM requests
- [[ds-smart-alert-supervisor]] -- frame-level alert verification that also uses VLM verdicts
