---
title: "Integrations — VMS platforms, monitoring centers & partners"
type: summary
topic: integrations
tags: [integrations, vms, monitoring-centers, partners, moc]
updated: 2026-06-24
author: kb-bot
---

# Integrations

The largest topic (~88 notes). Each integration is a **sub-topic with its own `_summary`** under `topics/integrations/<name>/`. Three classes:

## VMS platforms (frame sources — where video comes IN)
[[milestone/_summary|Milestone]] · [[avigilon/_summary|Avigilon]] · [[exacq/_summary|Exacq]] · [[eagle-eye/_summary|Eagle Eye]] · [[digital-watchdog/_summary|Digital Watchdog]] · [[hikcentral/_summary|HikCentral]] · [[genetec/_summary|Genetec]] · [[luxriot/_summary|Luxriot]] · [[openeye/_summary|OpenEye]] · [[orchid/_summary|Orchid]] · [[salient/_summary|Salient]] · [[video-insight/_summary|Video Insight]] · [[rtsp/_summary|Generic RTSP]] · [[kvs/_summary|AWS KVS]] · [[adpro/_summary|Adpro XO]] · [[ajax/_summary|Ajax]] · [[vch/_summary|VCH]]

## Monitoring centers (alert destinations — where alerts go OUT)
[[immix/_summary|Immix]] *(primary partner)* · [[sentinel/_summary|Sentinel]] · [[bold/_summary|Bold]] · [[patriot/_summary|Patriot]] · [[sureview/_summary|SureView]] · [[softguard/_summary|Softguard]] · [[lisa/_summary|LISA]]

## Partner / platform integrations
[[ebus/_summary|EBUS (Accellence)]] *(first v5 API consumer)* · [[morphean/_summary|Morphean / VIDEOR]] · [[evalink/_summary|Evalink]] · [[webhook/_summary|Webhook]] · [[autopatrol-integration/_summary|AutoPatrol]]

## How this fits
Frame sources feed the [[vms-connector/_summary|VMS connector]] pipeline (puller layer); detections are dispatched to monitoring centers via the alarm-senders. For the connector-side decode/puller mechanics see [[video-processing/_summary]]; for the alert plumbing see [[alerts-improvements/_summary]] and [[autopatrol/_summary]].
