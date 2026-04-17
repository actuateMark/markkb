---
title: "Source: Bold Microservice Design"
type: source
topic: integrations
tags: [worklog, bold, manitou, microservice, alert-delivery, socket, queue]
ingested: 2026-04-14
author: kb-bot
---

# Bold Microservice Design

Worklog notes describing the architecture of the Bold Manitou integration microservice -- a dedicated alert delivery system for customers using Bold as their monitoring platform.

## Architecture

### Bold Site Manager

A dedicated pod deployed into the K8s cluster as though it were a site. It manages all sites associated with a given Bold server for a given customer. Each Bold instance has a unique identification mapped to something within Admin. The site manager handles start, stop, and restart lifecycle operations for all sites under its purview.

### Alert Queue

One SQS queue per Bold instance, mapped to the customer ID. All associated sites push alert packets onto this shared queue. Each packet includes all data needed to format the alert for the specific site and detection. The Bold site manager reads from the queue, formats the packet for the Manitou protocol, and pushes it to the connected Bold Manitou server.

### Socket Connection

The site manager maintains a persistent socket connection with its Bold Manitou server and sends heartbeats at a regular interval. It also receives signals from the BM server -- these are lifecycle commands (startup/shutdown) for sites under its management. When received, it calls the relevant Admin UI API to execute the lifecycle action.

## Deployment Model

- Admin UI deploys the site manager automatically on startup.
- Individual site startup/shutdown/reboot calls from the UI still work for granular control.
- The Bold alert sender within the VMS connector is **removed** and replaced by a queue-pushing sender. All other alert senders remain unchanged.
- This is the **only** deployment model for Bold customers -- there is no alternative path.

## Scalability

The system should scale to handle 1000+ sites without issue, as long as it does not need to perform heavy image processing. Alert forwarding is lightweight.

## See Also

- [[data-flow-architecture]] -- where alert delivery fits in the overall pipeline
