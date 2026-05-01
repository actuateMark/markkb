# Knowledge Base Index

> Actuate AI Video Surveillance Platform -- Personal KB
> Last synced: 2026-04-15 | 340+ files across 18 topics + 29 integrations + 13 models

## Bases (Dataview Dashboards)
- [[bases/All Notes|All Notes]] -- every note, filterable by type/topic/tags
- [[bases/Syntheses|Syntheses]] -- cross-topic analysis (highest-value docs)
- [[bases/Topic Summaries|Topic Summaries]] -- quick-access to every summary
- [[bases/Concepts|Concepts]] -- architecture patterns and technical deep-dives
- [[bases/Entities|Entities]] -- services, repos, tools, and people
- [[bases/Sources|Sources]] -- ingested source material with provenance
- [[bases/Recent Changes|Recent Changes]] -- last 50 updated notes
- [[bases/Stale Notes|Stale Notes]] -- notes needing refresh (>14 days old)

## Platform & Architecture
- [[actuate-platform/_summary|Actuate Platform Overview]] -- end-to-end architecture, products, strategic direction
- [[vms-connector/_summary|VMS Connector]] -- core frame processing pipeline (19+ VMS, K8s, chain-of-responsibility)
- [[actuate-libraries/_summary|Actuate Libraries]] -- 41 shared Python packages (UV monorepo, CodeArtifact)
- [[infrastructure/_summary|Infrastructure & Security]] -- AWS, EKS, WireGuard, security gaps, IaC

## APIs & External Services
- [[inference-api/_summary|Inference API]] -- FastAPI detection API (Lambda, v1-v5, EBUS first consumer)
- [[knowledgebase/topics/admin-api/_summary|Admin API]] -- Django REST API (ECS, 50+ resources, config backbone)
- [[external-api/_summary|External API Initiative]] -- umbrella for partner-facing APIs (ENG-122)

## Products & Initiatives
- [[watchman/_summary|Watchman]] -- AI-powered virtual security operator (ASAP priority, multi-agent)
- [[knowledgebase/topics/autopatrol/_summary|AutoPatrol (H1.2)]] -- automated patrol + VLM analysis (50+ open issues)
- [[camera-health-monitoring/_summary|Camera Health Monitoring (H1.1)]] -- connectivity/scene change monitoring
- [[alerts-improvements/_summary|Alerts Improvements (H1.3)]] -- alert muting, Immix dispatch (stalled)
- [[settings-automation/_summary|Settings Automation (H1.4)]] -- VLM FP reduction, PPF, recommender

## Integrations (topics/integrations/)
### VMS Platforms (Frame Sources)
- [[integrations/milestone/_summary|Milestone]] | [[integrations/avigilon/_summary|Avigilon]] | [[integrations/exacq/_summary|Exacq]]
- [[integrations/eagle-eye/_summary|Eagle Eye]] | [[integrations/digital-watchdog/_summary|Digital Watchdog]] | [[integrations/hikcentral/_summary|HikCentral]]
- [[integrations/genetec/_summary|Genetec]] | [[integrations/luxriot/_summary|Luxriot]] | [[integrations/openeye/_summary|OpenEye]]
- [[integrations/orchid/_summary|Orchid]] | [[integrations/salient/_summary|Salient]] | [[integrations/video-insight/_summary|Video Insight]]
- [[integrations/rtsp/_summary|Generic RTSP]] | [[integrations/kvs/_summary|AWS KVS]] | [[integrations/adpro/_summary|Adpro XO]]
- [[integrations/ajax/_summary|Ajax]] | [[integrations/vch/_summary|VCH]]

### Monitoring Centers (Alert Destinations)
- [[integrations/immix/_summary|Immix]] (primary partner, ~$800K/12mo) | [[integrations/sentinel/_summary|Sentinel]]
- [[integrations/bold/_summary|Bold]] | [[integrations/patriot/_summary|Patriot]] | [[integrations/sureview/_summary|SureView]]
- [[integrations/softguard/_summary|Softguard]] | [[integrations/lisa/_summary|LISA]]

### Partner Integrations
- [[integrations/ebus/_summary|EBUS (Accellence)]] -- first v5 API consumer
- [[integrations/morphean/_summary|Morphean / VIDEOR]] -- cloud + edge, 30 countries
- [[integrations/evalink/_summary|Evalink]] -- alarm management (Protectas)

### Generic
- [[integrations/webhook/_summary|Webhook]] | [[integrations/autopatrol-integration/_summary|AutoPatrol]]

## AI Models (topics/models/)
### Production
- [[models/intruder-v5/_summary|Intruder v5]] (YOLOv5, current PROD) | [[models/intruder-v8/_summary|Intruder v8]] (YOLOv8, rolling out)
- [[models/weapon-v8/_summary|Weapon v8]] (YOLOv8 XL, deploying) | [[models/fire-detection/_summary|Fire Detection]]

### Detection Products
- [[models/loitering/_summary|Loitering]] (BoTSORT tracking) | [[models/line-crossing/_summary|Line Crossing]] (86-98% alert reduction)
- [[models/motion-plus/_summary|Motion+]] | [[models/crowd-detection/_summary|Crowd]] | [[models/fall-detection/_summary|Fall Detection]]

### Specialized
- [[models/blacklist-reid/_summary|Blacklist/Re-ID]] | [[models/pet-detection/_summary|Pet]] | [[models/hardhat-detection/_summary|Hard Hat]]
- [[models/thermal-intruder/_summary|Thermal Intruder]]

## AI & Data Science
- [[ai-models/_summary|AI Models & Evaluation]] -- model catalog, shadow testing, evaluation framework
- [[data-science/_summary|Data Science Methodology]] -- pipeline, training, evaluation, tracking

## Observability
- [[new-relic/_summary|New Relic]] -- NRQL patterns, data model, query cookbook, deep links
  - [[new-relic/notes/concepts/nrql-efficient-query-patterns|Efficient Query Patterns]] -- context-saving NRQL rules
  - [[new-relic/notes/concepts/nr-connector-query-cookbook|Connector Query Cookbook]] -- ready-to-paste templates
  - [[new-relic/notes/concepts/nr-programmatic-deep-links|Programmatic Deep Links]] -- URL generation for admin integration

## Knowledge Base Tooling
- [[obsidian/_summary|Obsidian]] -- the app + companion CLI that back this KB; install paths on laptop and firebat, capability matrix, KB-skill integration
  - [[obsidian-cli|Obsidian CLI]] -- entity note: capability matrix, firebat container wrapper, common patterns
  - [[2026-04-30_kb-skill-cli-retrofit|KB Skill / Agent CLI Retrofit]] -- 2026-04-30 sweep replacing recursive Grep with `obsidian` CLI calls in kb-* skills

## Video Processing
- [[video-processing/_summary|Video Processing]] -- codecs, containers, transport, FFmpeg, GStreamer, OpenCV, AWS video services, mapped onto Actuate use cases
  - [[actuate-video-pipeline-walkthrough|Actuate Video Pipeline Walkthrough]] -- end-to-end map of one frame's life
  - [[actuate-frame-ingest-decode-paths|Frame Ingest & Decode Paths]] -- per-integration decoder strategy table
  - [[actuate-clip-generation-flow|Clip Generation Flow]] -- where MP4s come from (and don't)
  - [[actuate-build-vs-buy-tradeoffs|Build vs Buy Tradeoffs]] -- AWS managed-service replacement candidates
  - [[aws-video-services-decision-matrix|AWS Video Services Decision Matrix]] -- 13 use cases × 9 services
  - [[protocol-latency-comparison|Protocol Latency Comparison]] -- RTSP/RTMP/HLS/WebRTC/SRT/KVS latency floors
  - [[gstreamer-vs-ffmpeg|GStreamer vs FFmpeg]] -- opinionated selection policy

## Software Architecture & Governance
- [[knowledgebase/topics/software-architecture/_summary|Software Architecture Health & Governance]] -- code health, architecture enforcement, tech debt automation
  - [[2026-04-16_code-health-dashboard|Code Health Dashboard]] -- extensible dashboard consolidating all quality metrics
  - [[2026-04-16_tooling-landscape|Tooling Landscape & Reading List]] -- catalog of analysis, enforcement, and monitoring tools
  - [[2026-04-16_metrics-to-track|Metrics to Track]] -- complexity, coverage, coupling, debt, architecture conformance
  - [[2026-04-16_architecture-enforcement|Architecture Enforcement]] -- fitness functions, import linting, CI gates
  - [[2026-04-16_tech-debt-agent|Automated Tech Debt Agent]] -- headless AI agent for codebase patrol
- [[fleet-architecture/_summary|Fleet Architecture Redesign]] -- 5 candidate architectures (A-E) to replace the site-per-pod monolith, with PoC specs and evaluation rubric

## Organization
- [[team-structure/_summary|Team Structure & Assignments]] -- who is doing what (April 2026)
- [[product-roadmap/_summary|Product Roadmap]] -- initiatives, revenue, risks
- [[jira-organization/_summary|Jira Organization]] -- 21 projects, reorg proposal (39 -> 6)

---

## Meta
- [[_schema|Schema]] -- KB structure specification
- [[_rules|Rules]] -- behavioral rules for agents and humans
- [[_checkpoint|Checkpoint]] -- last sync state
- [[_dive-queue|Dive Queue]] -- queued sources for future ingestion
- [[_todo|TODO]] -- KB maintenance tasks
- [[readinglist/Links|Reading List]] -- external links and bookmarks
