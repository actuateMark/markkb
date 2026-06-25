---
title: "dev.powerplus.com WebSocket SSL certificate verification failure"
type: concept
topic: vms-connector
tags: [bug, autopatrol, vch, immix, websocket, ssl, certificate, powerplus, alert-dispatch]
jira: ""
status: open
severity: high
discovered: 2026-04-20
created: 2026-04-20
updated: 2026-04-20
author: kb-bot
incoming:
  - home/offboarding/2026-06-23_autopatrol-handoff.md
  - topics/camera-health-monitoring/notes/syntheses/chm-enhanced-diagnostics-proposal.md
  - topics/camera-health-monitoring/notes/syntheses/chm-phase1-network-probe.md
  - topics/engineering-process/notes/syntheses/2026-05-20_ait-phase-7-alert-capture-replay.md
  - topics/personal-notes/notes/daily/2026-04-20.md
  - topics/personal-notes/notes/daily/2026-04-27.md
  - topics/personal-notes/notes/daily/_archive-snapshots/2026-04-27_mark-todos-pre-cleanup.md
  - topics/personal-notes/notes/entities/mark-todos.md
  - topics/vms-connector/notes/concepts/2026-04-20_streamid-null-patrol-alert-bug.md
incoming_updated: 2026-06-25
---

# dev.powerplus.com WebSocket SSL certificate verification failure

Every AutoPatrol / VCH WebSocket stream connection in the fleet currently routes to `wss://dev.powerplus.com/devices/camera?...` and fails at the TLS handshake with `[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: unable to get local issuer certificate`. This prevents the connector from ever receiving video frames for patrols routed through PowerPlus — cameras appear "broken" in healthcheck output (`resolution: 0`, `fps: 10000`, `is_blank_frame: true` sentinel values), but the actual failure is connector-side certificate trust, not camera unreachability. Distinct from [[2026-04-20_streamid-null-patrol-alert-bug]] — that's about alert dispatch failing; this is about frame retrieval failing.

## Discovery

Found while investigating patrol `65026ba0-e2a6-4eeb-1abb-08de98a22646` (VCH run for site `GWSI|GoldenWestSecurity|308479|SeaColonyApts`, container `connector-44346`). User reported "the client says we never tried to connect." [[new-relic|New Relic]] investigation showed:
- 71 WebSocket connection attempts in one ~40-minute patrol run (24 cameras × ~3 retries each)
- 71 matching `SSL: CERTIFICATE_VERIFY_FAILED` errors
- 0 successful frame deliveries
- All URLs pointed at `wss://dev.powerplus.com/devices/camera?token=<JWT>&quality=Medium&usePassthrough=False`

## The Bug Flow

1. Immix returns 200 OK from `get_patrol_stream` with `{"deviceStreamUrl": "wss://dev.powerplus.com/devices/camera?token=...", "deviceStreamId": "<GUID>"}`
2. Puller stores `self.stream_id` and `self.url` correctly
3. `consume_stream` attempts `websockets.connect(self.url, open_timeout=10, close_timeout=10)` at `actuate_pullers/socket/autopatrol_websocket_stream_puller.py:128`
4. Python's default SSL context cannot validate `dev.powerplus.com`'s cert chain
5. `websockets` raises `ssl.SSLCertVerificationError` wrapped in the puller's WebSocket exception handler (line 289)
6. `connectivity.broken_stream = True`, retry loop kicks in (up to `retry_count = 3` times with `retry_sleep_time = 30-90s`)
7. All retries fail at the same TLS step
8. Healthcheck payload emits sentinel values (resolution=0, fps=10000, is_blank_frame=true) because no frames ever arrived
9. VCH path updates the healthcheck API via `successfully updated hc` (HTTPS REST, different path — works fine)
10. No CNCTNFAIL alert is raised because the incident was opened in March and `current_run_status: unchanged`

## Observed Scale (Fleet-Wide, 7-Day Window)

- **3,870 total WebSocket connection attempts — 100% to `dev.powerplus.com`**
- **0 attempts to any other host** (not prod.powerplus, not immixconnect, not any other hostname)
- Cert-verify failures: flat ~560-588/day
- Affected containers: 2 on days 1-3, **3 from 2026-04-17 onward** (one new site joined on 2026-04-17; worth tracking whether blast radius keeps growing)
- 17,175 log lines mentioning `dev.powerplus.com` in 7 days

## Affected Containers Identified So Far

- `connector-44346-vch-1049-chm-cronjob` — site 10095 "GWSI|GoldenWestSecurity|308479|SeaColonyApts" — ~540 cert-verify failures/24h
- `connector-44781-vch-1053-chm-cronjob` — ~24/24h
- `connector-23202-chm-cronjob` — ~24/24h (joined 2026-04-17)

## Two Separable Root Causes to Investigate

**1. Why `dev.powerplus.com`?**

This is a dev subdomain of a third-party video streaming provider that Immix uses for patrol streams. Either this customer is legitimately on PowerPlus dev (unlikely for prod), or Immix's prod autopatrol service is leaking dev URLs into prod customers' patrol responses. Needs Immix team input — possibly related to how `get_patrol_stream` constructs `deviceStreamUrl`.

**2. Why can't we verify the cert?**

Possible causes: (a) self-signed or private-CA cert on `dev.powerplus.com`; (b) cert signed by a CA missing from our container's CA bundle; (c) cert chain missing intermediate; (d) our CA bundle is stale. Verifiable from a pod with `openssl s_client -connect dev.powerplus.com:443 -showcerts`.

## Why It Looks Like "Cameras Are Down"

The healthcheck record for every affected camera shows:
- `connectivity.broken_stream: true`
- `connectivity.frame_returned: false`
- `stream_quality.resolution: 0` (sentinel "no frames received")
- `stream_quality.fps: 10000` (sentinel impossible value)
- `scene_change.is_blank_frame: true`
- `status: "ongoing"`, `current_run_status: "unchanged"`

Without looking at the raw WebSocket connection log and the SSL error, this presents identically to a camera that is physically offline. Easy misdiagnosis.

## Why the Client Reports "We Never Tried"

From the PowerPlus server-side view, our connection attempts terminate at the TLS handshake before the application-level WebSocket is established. If PowerPlus's logs only record application-level (post-handshake) connections, we will be invisible in their logs. Our connector is making 550+ TCP+TLS attempts per day against their endpoint — they would only see them if they log TCP accept / TLS handshake failures.

## Distinction from streamId-Null Bug (GH#1656 / [[2026-04-20_streamid-null-patrol-alert-bug]])

| Aspect | streamId-null | dev.powerplus SSL (this note) |
|---|---|---|
| Failure location | Alert dispatch (`raise_patrol_alert`) | Frame retrieval (WebSocket connect) |
| Trigger | `get_patrol_stream` already failed → `stream_id` is None | `get_patrol_stream` succeeded → URL is a dev host we can't verify |
| Visible symptom | `raise_patrol_alert failed: 400 $.streamId Guid` | `WebSocket connection error: SSL CERTIFICATE_VERIFY_FAILED` |
| Data path affected | CNCTNFAIL alert to Immix never reaches them | Frames never reach the connector for processing |
| Which side owns fix | Primarily Immix (schema change or lookup endpoint) | Connector-side (CA bundle) OR Immix-side (URL routing) |

Both observed on production `:latest` post-PR-1654 merge, but they are different code paths and need different fixes.

## Root Cause (Confirmed via `openssl s_client` Probe)

Ran against `dev.powerplus.com:443` 2026-04-20:
```
$ echo | openssl s_client -connect dev.powerplus.com:443 -servername dev.powerplus.com -showcerts
Certificate chain
 0 s:CN = *.powerplus.com
   i:C = GB, O = Sectigo Limited, CN = Sectigo Public Server Authentication CA DV R36
   a:PKEY: rsaEncryption, 2048 (bit); sigalg: RSA-SHA384
   v:NotBefore: Jun 11 00:00:00 2025 GMT; NotAfter: Jun 11 23:59:59 2026 GMT
Verification error: unable to verify the first certificate
Verify return code: 21 (unable to verify the first certificate)
```

**Chain length returned: 1 (leaf only). Intermediate is missing.** The leaf is signed by Sectigo Public Server Authentication CA DV R36 — a well-known commercial intermediate whose parent root is in standard OS trust stores. Python's `ssl` module does not chase AIA (Authority Information Access) to auto-fetch missing intermediates, so verification fails. Browsers (Chrome, Safari, Firefox) do chase AIA, which is why the URL "works in a browser" but fails in our connector.

**This is a server misconfiguration on `dev.powerplus.com`, not an issue with our CA bundle.**

## Fix Recipe

### Primary: server-side chain completion (one-line change on PowerPlus side)

**nginx:**
```nginx
ssl_certificate /etc/ssl/certs/fullchain.pem;  # leaf + Sectigo intermediate concatenated
```

**Apache 2.4+:**
```apache
SSLCertificateFile /etc/ssl/certs/fullchain.pem  # modern bundled form
```

**IIS:** import Sectigo DV R36 intermediate into local `Intermediate Certification Authorities` store (`certutil -addstore CA sectigo_intermediate.cer` + `iisreset`).

**AWS ALB/ACM:** re-upload with `--certificate-chain file://sectigo_intermediate.pem`.

The Sectigo intermediate PEM is available from Sectigo's cert-issuance package, or at `https://crt.sh/?Identity=Sectigo+Public+Server+Authentication+CA+DV+R36`.

### Workaround (connector-side only): explicit SSL context with pinned intermediate

Only if the server-side fix is blocked by external timelines. Replace `websockets.connect(self.url, ...)` with a version passing an `ssl=` kwarg whose context has the Sectigo intermediate loaded via `ssl_context.load_verify_locations(cadata=...)`. Fragile — binds us to Sectigo's current intermediate, breaks on rotation. Documented in GH#1658 issue comments as Option 3.

## Diagnostic Procedure (Reusable)

When you see `[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: unable to get local issuer certificate` on WebSocket / HTTPS calls in any connector log, and healthcheck payloads show sentinel values (`resolution: 0`, `fps: 10000`, `is_blank_frame: true`), run:

```bash
echo | openssl s_client -connect <host>:<port> -servername <host> -showcerts 2>&1 | head -80
```

Decision tree:
- **Chain length 1 (leaf only) + `Verify return code: 21`** → server missing intermediate; server-side fix via chain completion (see recipe above).
- **Chain length > 1 but `Verify return code: 19 (self-signed in chain)`** → self-signed or private-CA cert; needs our CA bundle updated OR they move to a public CA.
- **Chain length > 1 + `Verify return code: 0 (ok)`** → cert is fine; the error comes from somewhere else (client-side CA bundle stale? system clock skew? SNI mismatch?). Check `date` on the pod; check `/etc/ssl/certs/ca-certificates.crt` age.
- **Connection refused / timeout** → not a cert issue; network or firewall problem.

Expected post-fix output against `dev.powerplus.com`:
```
Certificate chain
 0 s:CN = *.powerplus.com
   i:C = GB, O = Sectigo Limited, CN = Sectigo Public Server Authentication CA DV R36
 1 s:C = GB, O = Sectigo Limited, CN = Sectigo Public Server Authentication CA DV R36
   i:C = US, ST = New Jersey, L = Jersey City, O = The USERTRUST Network, CN = USERTrust RSA Certification Authority
Verify return code: 0 (ok)
```

## Remaining Open Items

1. Raise chain-completion fix with PowerPlus (via Immix) — **comms task, user action**
2. Raise URL routing with Immix — why `dev.powerplus.com` for prod customers — **comms task, user action**
3. ~~Identify `connector-23202-chm-cronjob` customer + what changed 2026-04-17~~ — **partial answer 2026-04-27, see "In-house update" below**
4. Consider option-3 mitigation if external timelines slip — **design decision pending external timeline visibility**
5. Verify `actuate-pullers`' `websockets.connect()` default SSL context path (confirmed: uses system CA bundle, no custom context — option 3 would introduce a custom context)

## In-house update (2026-04-27)

Investigated item 3 via NR log queries against `connector-23202-chm-cronjob`:

- **Customer ID:** `23202` (per `customer_id` in healthcheck `event_info` payloads)
- **Integration type:** `RTSPCustomerConfig` — this is fundamentally an [[rtsp-deep-dive|RTSP]] customer with VCH-routed patrols mixed in (which is why the `-chm-cronjob` container hits PowerPlus dev). Naming convention differs from the `-vch-NNNN-chm-cronjob` pattern of pure-VCH customers (44346, 44781) — suggests this customer was added VCH coverage on top of an existing [[rtsp-deep-dive|RTSP]] integration rather than provisioned VCH-first.
- **Sites observed in healthcheck logs** (last 24h):
  - `act_e: "Brightside Fire Pit (copy)"` — `act_11: 310775`
  - `act_e: "Club verano Fire Pit (copy)"` — `act_11: 310410`
  - `act_e: "Fire Pit Cabana (copy)"` — `act_11: 310422`
  - Additional site IDs surfacing: `310788` (act_e `"test"`)
- **Strong "what changed 2026-04-17" signal:** every site name carries the `(copy)` suffix. This is the [[actuate_admin]] convention for sites cloned from templates, almost always indicating recent provisioning. The 2026-04-17 onset of SSL failures matches the most likely scenario: **a customer-23202 site cluster was cloned-and-deployed on or near 2026-04-17, all carrying the same VCH/PowerPlus-dev URL pattern that the existing fleet has been failing on since March**.
- **Customer name not yet resolved.** Sites have a "Fire Pit" theme (Brightside, Club verano, Fire Pit Cabana — sounds like a multi-property hospitality / vacation-rental customer) but the customer-side name doesn't appear in NR logs (only customer_id=23202). Confirming requires `actuate_admin` DB lookup: `SELECT name FROM core_customer WHERE pk = 23202;` or the admin UI at `/admin/core/customer/23202/`.

### What's still blocked (and why)

| Open item | Blocker | Unblock action |
|---|---|---|
| Raise chain-completion with PowerPlus | Requires Immix relay (we don't talk to PowerPlus directly) | Slack to Immix integration contact with the openssl probe + nginx/Apache fix recipe from this note |
| Raise URL routing with Immix | Same channel as above | Combine with chain-completion message; one Slack thread |
| Resolve customer-23202 customer name | `actuate_admin` DB lookup | 30-second admin UI check |
| Decide on option-3 mitigation | External timeline visibility | After Immix responds; or hard-cap at e.g. 7d if no response |

### Suggested Slack message for Immix (draft — review before sending)

> Hey [Immix contact] — we're seeing fleet-wide SSL cert verification failures on the WebSocket stream URLs returned by `get_patrol_stream`. Probe details:
>
> - 100% of `wss://` URLs we receive route to `dev.powerplus.com` (~3,870 attempts / 7d, 0 successes). We're not seeing any `prod.powerplus`, `immixconnect`, or other hosts.
> - The cert chain on `dev.powerplus.com:443` returns leaf-only — the Sectigo Public Server Authentication CA DV R36 intermediate is missing. Python's `ssl` module does not chase AIA, so verification fails for our pods.
> - This presents to our customers as "cameras offline" in healthcheck (`resolution: 0`, `is_blank_frame: true`) — we already misdiagnose it that way without the underlying SSL probe.
>
> Two asks:
> 1. **Server-side fix on PowerPlus:** chain completion (1-line nginx/Apache change). Recipe: `ssl_certificate /etc/ssl/certs/fullchain.pem` (leaf + Sectigo intermediate concatenated). The Sectigo intermediate PEM is at `crt.sh/?Identity=Sectigo+Public+Server+Authentication+CA+DV+R36`.
> 2. **Why is `dev.powerplus.com` the URL for prod customers?** (Customer 23202 onboarded ~2026-04-17 hit it immediately — same fail pattern as the ~Mar customers.) If `prod.powerplus` exists, can `get_patrol_stream` be switched to it for non-dev tenants?
>
> Full investigation note + openssl probe output in our KB if useful: [[2026-04-20_dev-powerplus-ssl-cert-verify-failure]]. Happy to relay any extra detail.

## Cross-References

- GH#1656 — streamId-null bug; closely related but distinct failure mode, same investigation session
- [[2026-04-20_streamid-null-patrol-alert-bug]] — KB counterpart to GH#1656
- [[2026-04-20_vms-connector-pr-1654|PR #1654 release note]] — both bugs surfaced during post-deploy investigation
- `actuate-pullers` library: `socket/autopatrol_websocket_stream_puller.py:125-306` (consume_stream, the WebSocket retry loop)
- `actuate-integration-calls` library: `autopatrol/autopatrol_api.py:342-358` (get_patrol_stream, where Immix returns the dev URL)
