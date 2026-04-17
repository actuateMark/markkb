---
title: "Source: SES Email Tooling Pitch"
type: source
topic: actuate-platform
tags: [worklog, ses, email, templates, tooling, aws]
ingested: 2026-04-14
author: kb-bot
---

# SES Email Tooling Pitch

Source: internal pitch document for building custom SES email template tooling.

## Problem

AWS SES includes a full email templating engine, but provides essentially **zero tooling** for working with it. Specifically, AWS lacks:

- Error reporting for template syntax issues
- Any UI to view, create, or update templates
- Visibility into whether an email was sent successfully (and why it failed)
- A WYSIWYG editor for modifying existing templates

All of the above is technically possible, but only through esoteric IAM role configuration, alert/event setup within AWS, or direct API calls. There is no integrated management experience.

## Proposed Tool

A lightweight internal tool that provides:

1. **Template browser** -- list and inspect all SES templates.
2. **WYSIWYG editor** -- load an existing template, modify visually, and push updates.
3. **Error reporting** -- surface template rendering failures with context.
4. **Send status** -- track whether emails were delivered and expose failure reasons.

The initial version (browse + WYSIWYG edit) would be simple to build and deliver significant productivity gains. Further extensions (delivery dashboards, test-send, template versioning) would be straightforward additions.

## Assessment

This represents a "major hole" in AWS's own tooling and a high-value internal tool opportunity with a small implementation cost. The pitch positioned it as a quick win with a clear expansion path.
