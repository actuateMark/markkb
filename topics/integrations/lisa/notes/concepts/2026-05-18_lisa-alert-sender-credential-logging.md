---
title: "Lisa alert sender logs the auth token on every send"
type: concept
topic: integrations/lisa
tags: [lisa, alert-sender, security, credential-leak, logging, actuate-alarm-senders, bug]
created: 2026-05-18
updated: 2026-05-18
author: mark
[]
incoming:
  - topics/integrations/vch/notes/syntheses/2026-05-18_libav-decoder-warmup-frame-fix.md
  - topics/personal-notes/notes/daily/2026-05-18.md
incoming_updated: 2026-05-19
---

# Lisa alert sender logs the auth token on every send

## What

`actuate-alarm-senders/src/actuate_alarm_senders/lisa/lisa_alert_sender.py:102` builds a `data` dict that includes `"token": lisa_config.lisa_token` and then runs:

```python
logger.info(f"Sending clip {clip_data.file_id} to Lisa: {data}")
```

The full dict — including the bearer token — lands in centralized logs ([[new-relic|New Relic]], CloudWatch, etc.) on every Lisa alert send. Any operator with log-read access can see the Lisa auth token in cleartext for any tenant.

Two lines below, also worth flagging:

```python
log(
    f"Event handler response for Lisa clip {clip_data.file_id} "
    f"(server={lisa_config.lisa_server}): status={status} body={body!r}"
)
```

The Cursor security agent (PR review on `vms-connector#1699`, MEDIUM severity) flagged the `body={body!r}` line — unbounded response body in logs can carry stack traces / tokens / PII echoed back from the Lisa endpoint. Real but secondary to the line-102 credential leak above.

## Surfaced via

Discovered 2026-05-18 during the security review of `actuate-alarm-senders` 1.9.17 → 1.9.20 bump pulled in by `vms-connector#1699`. The lisa logging change is commit `bfe888e9` ([[paolo-zilioti|Paolo Zilioti]], 2026-04-21) "better logs when event handler fails" — improved the failure-path observability but left the existing `data` dict logging as-is (which already contained the token). The Cursor agent caught the new `body` log; the underlying `data` token log is older and pre-existing.

## Fix scope

Belongs in `actuate-libraries` as a `[patch:actuate-alarm-senders]` bump, not blocking the VCH connector PR that surfaced it. Two changes in the same file:

1. Sanitize `data` before logging — remove the `token` key, or log only field names + non-sensitive identifiers (`clip_data.file_id`, `event`, `area`, `zone`, `connection`).
2. Bound the response body in logs — `body[:200]` instead of `{body!r}`, or only log body on non-2xx (already gated by `log = logger.info if status and 200 <= status < 300 else logger.warning`, so the body only logs on warning — but the bound is still worth it).

## Impact assessment

- Severity: HIGH for the `data` token leak (cleartext credential in logs); MEDIUM for the response-body log (Cursor's original finding).
- Reach: any Lisa-integrated customer using [[actuate-alarm-senders]] ≥ 1.9.18 (when the relevant changes shipped). The token leak existed before 1.9.18 too — the `data` dict logging is older — but the recent "better logs" commit drew Cursor's attention to the file.
- Detection: anyone with NR / CloudWatch / centralized log access at Actuate or a downstream operator who consumes these logs.
- Remediation: rotate Lisa auth tokens for all tenants after the fix lands, since old tokens are presumed compromised in log retention.

## Cross-references

- [[lisa]] — Lisa integration topic (parent)
- [[2026-05-18_libav-decoder-warmup-frame-fix]] — adjacent finding surfaced during the same validation cycle
- vms-connector PR [#1699](https://github.com/aegissystems/vms-connector/pull/1699) — where the Cursor finding surfaced
- actuate-libraries `actuate-alarm-senders/lisa/lisa_alert_sender.py`
