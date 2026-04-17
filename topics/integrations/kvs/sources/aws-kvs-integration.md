---
title: "Source: AWS Kinesis Video Streams (KVS) Integration"
type: source
topic: integrations/kvs
tags: [source, integration, kvs, documentation]
ingested: 2026-04-15
author: kb-bot
---

## KVS Integration Overview

AWS Kinesis Video Streams (KVS) is a cloud-based video streaming service. Actuate integrates with KVS to pull video frames from KVS streams for AI inference. This integration is used when customer cameras push video to AWS KVS rather than making streams available via RTSP or other direct protocols.

## Confluence Knowledge

Confluence search for "kinesis video" returned references from EDOCS engineering docs:

- **"actuate-pullers: Puller Integrations"** (page 497844226, EDOCS) -- documents the KVS puller class that retrieves frames from Kinesis Video Streams.
- **"vms-connector: Supported Integrations"** (page 496828419, EDOCS) -- lists KVS integration with AWS IAM authentication.
- **"actuate-config"** (page 497057794, EDOCS) -- documents the KVS connector configuration class.

## VMS-Connector Documentation

From `docs/backend/integrations.md`:
- **KVS** is listed as a supported integration type with **AWS IAM** authentication
- Described as: "AWS Kinesis Video Streams -- pulls frames from KVS"
- Along with **SQS Video** (also AWS IAM), these are the AWS-native video ingestion integrations

## Actuate Implementation

**Connector Factory**: `connector_factories/kvs/` -- KVS-specific factory that creates cameras and site manager for KVS stream pulling.

**Puller**: The KVS puller in `actuate-pullers` retrieves video frames from AWS Kinesis Video Streams using the AWS SDK (boto3). Unlike RTSP pullers that use cv2.VideoCapture, KVS pullers interact with the AWS API.

**Config**: `actuate_config/connector/kvs/` -- KVS-specific connector configuration including AWS region, stream ARN/name, and IAM credentials.

## Auth Method

**AWS IAM**: Authentication uses AWS IAM credentials (access key + secret key, or IAM roles when running in EKS). The connector assumes an IAM role or uses configured AWS credentials to access KVS streams. This is the same auth pattern used by SQS Video.

## Key Technical Details

- KVS streams are cloud-native -- no network configuration needed for camera access
- Frames are pulled from KVS's GetMedia or GetMediaForFragmentList APIs
- AWS credentials must have `kinesisvideo:GetMedia` and related permissions
- Can be used when customers already push their camera feeds to AWS KVS

## Key Considerations

- Cloud-native integration -- requires AWS infrastructure on the customer side
- IAM-based auth integrates naturally with Actuate's existing AWS infrastructure
- Distinct from RTSP: no direct camera access, frames come through AWS's managed service
- SQS Video is a related AWS integration that receives frame references via SQS messages

## Key Confluence Pages

| Page | ID | Space |
|---|---|---|
| actuate-pullers: Puller Integrations | 497844226 | EDOCS |
| vms-connector: Supported Integrations | 496828419 | EDOCS |
| actuate-config | 497057794 | EDOCS |
