# Reading List: Camera Health Monitoring

## Confluence Pages

### CHM Space
- [ ] [CHM Launch Plan](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/52133889/CHM+Launch+Plan) -- CHM launch strategy and timeline
- [ ] [Immix VCH Requirements](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/52166700/Immix+VCH+Requirements) -- VCH product requirements for Immix
- [ ] [VCH vs CHM feature comparison](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/79986691/VCH+vs+CHM+feature+comparison) -- Feature comparison between CHM and VCH
- [ ] [VCH User Profiles](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/61145090/VCH+User+Profiles) -- Target user profiles for VCH
- [ ] [API Details](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/58687612/API+Details) -- CHM/VCH API specification
- [ ] [Scene Change Initial Evaluation](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/34504725/Scene+Change+Initial+Evaluation) -- Scene change v3 evaluation
- [ ] [Scene Change Logic](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/35061768/Scene+Change+Logic) -- Scene change detection algorithm
- [ ] [SAC parameter testing](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/159285254/SAC+parameter+testing) -- Scene change parameter tuning
- [ ] [CHM mini-sprint 3.1](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/154533895/CHM+mini-sprint+3.1) -- Sprint 3.1 focus on alert volumes
- [ ] [Release Notes - H1.1 - CHM - CHM Sprint 3 v1](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/121110577/Release+Notes+-+H1.1+-+CHM+-+CHM+Sprint+3+v1+-+Aug+05+13+02) -- Sprint 3 release notes
- [ ] [Retrospective: VCH](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/154566703/Retrospective+VCH) -- VCH retrospective
- [ ] [Autopatrol UAT Checklist](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/68354126/Autopatrol+UAT+Checklist) -- UAT checklist for AutoPatrol/CHM
- [ ] [Sample Reports](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/58753110/Sample+Reports) -- Sample VCH report examples
- [ ] [VCH Feedback Sessions](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/329056257/VCH+Feedback+Sessions) -- Customer feedback on VCH
- [ ] [VCH UAT Notes](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/62881908/VCH+UAT+Notes) -- UAT testing notes
- [ ] [VCH Daily sync notes 6/17-](https://actuate-team.atlassian.net/wiki/spaces/CHM/pages/84410405/VCH+Daily+sync+notes+6+17-) -- Daily sync meeting notes

### kb Space
- [ ] [Camera Health Monitoring](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160268517/Camera+Health+Monitoring) -- CHM overview in legacy KB
- [ ] [CHM Logs](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/168329221/CHM+Logs) -- CHM log analysis guide

### DS Space -- Scene Change
- [ ] [Motion Detection & Stationary Filter: Scoping Document](https://actuate-team.atlassian.net/wiki/spaces/DS/pages/482541575/Motion+Detection+Stationary+Filter+Scoping+Document) -- Motion detection scoping relevant to CHM

### PM Space
- [ ] [Release Notes - H1.1 - CHM - test version](https://actuate-team.atlassian.net/wiki/spaces/PM/pages/48398346/Release+Notes+-+H1.1+-+CHM+-+test+version+-+Apr+22+14+44) -- CHM test release notes

### EDOCS Space
- [ ] [actuate-healthmonitoring](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497877031/actuate-healthmonitoring) -- Health monitoring library docs
- [ ] [actuate-healthcheck-objects](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497418266/actuate-healthcheck-objects) -- Health check data objects
- [ ] [actuate-suddenscenechange](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496533547/actuate-suddenscenechange) -- Scene change detection library

## GitHub Repos
- [ ] actuate-healthmonitoring -- Health monitoring library (ingested as entity)
- [ ] actuate-suddenscenechange -- Scene change library (ingested as entity)
- [ ] actuate-healthcheck-objects -- Health check objects (ingested as entity)

## Locally 
- [x] There should be a plan for significant enhancements to CHM diagnostics -> No grand plan doc found, but architecture is solid with clear gaps. Created [[chm-diagnostics-architecture]], [[chm-rd-opportunities]], and [[chm-enhanced-diagnostics-proposal]].
- [x] Cross-reference to all integrations documentation -> Created [[chm-diagnostics-gap-analysis]] mapping all 29 integrations against 7 diagnostic types with feasibility assessment.

## R&D Follow-Up (from diagnostic research)
- [ ] **Phase 1: NetworkProbe** -- Build shared utility for DNS/TCP/ping/WG diagnostics (3-5 days). Replaces HTTP GET in RTSP diagnostics with real protocol-level checks.
- [ ] **Phase 2: StreamProbe** -- Surface puller metadata (codec, FPS, bandwidth, keyframe interval) to diagnostics (2-3 days). Data already collected but never exposed.
- [ ] **Phase 3: Cross-camera correlation** -- NVR/WireGuard/subnet failure grouping in send_healthcheck_results (2-3 days). Reduces alert noise, identifies root cause.
- [ ] **Phase 4: GenericDiagnostics** -- Replace DummyDiagnostics for 24 integrations with at least TCP probe + frame recency (1-2 days).
- [ ] **Phase 5: FrameProbe** -- Black frame, frozen frame, IR mode, color drift, edge density analysis (1 week).
- [ ] **Phase 6: SMTP/AILink diagnostics** -- Frame recency + SQS latency checks (2-3 days).
- [ ] **Phase 7: Historical trending** -- Degradation detection over time, not just point-in-time (1-2 weeks).
- [ ] Investigate HikCentral Artemis API for deep NVR diagnostics (richest untapped API)
- [ ] Investigate Eagle Eye cloud API for health status endpoints
- [ ] Investigate Milestone management server API for recording server diagnostics
- [ ] Evaluate VLM-based visual quality assessment (blur/obstruction beyond FFT)
- [ ] Design Watchman Site Context Agent integration for proactive health awareness