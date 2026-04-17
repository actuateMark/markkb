# Reading List: VMS Connector

## Confluence Pages

### EDOCS Space (Engineering Docs)
- [ ] [vms-connector](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496238597/vms-connector) -- Top-level connector documentation hub
- [ ] [vms-connector: Connector Operations](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497319944/vms-connector+Connector+Operations) -- Runtime lifecycle and operational behavior
- [ ] [vms-connector: Performance Optimization](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496238617/vms-connector+Performance+Optimization) -- Tuning and bottleneck resolution
- [ ] [vms-connector: Pipeline Architecture](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496074759/vms-connector+Pipeline+Architecture) -- Frame processing pipeline design
- [ ] [vms-connector: Integrations](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497877012/vms-connector+Integrations) -- VMS integration overview
- [ ] [vms-connector: Supported Integrations](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496828419/vms-connector+Supported+Integrations) -- List of supported VMS platforms
- [ ] [vms-connector: RTSP Integration](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496074778/vms-connector+RTSP+Integration) -- RTSP camera connectivity
- [ ] [vms-connector: RTSP Camera Simulator](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497614850/vms-connector+RTSP+Camera+Simulator) -- Testing tool for RTSP streams
- [ ] [vms-connector: Exacq Integration](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496402453/vms-connector+Exacq+Integration) -- Exacq-specific connector behavior
- [ ] [vms-connector: AutoPatrol Integration](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496238638/vms-connector+AutoPatrol+Integration) -- AutoPatrol mode in the connector
- [ ] [vms-connector: Detection Window Internals](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497876993/vms-connector+Detection+Window+Internals) -- Detection window algorithm details
- [ ] [vms-connector: Products & Detection](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496697349/vms-connector+Products+Detection) -- Product types and detection modes
- [ ] [vms-connector: Platform Ecosystem](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497319963/vms-connector+Platform+Ecosystem) -- How connector fits in the broader platform
- [ ] [vms-connector: Backend](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497745924/vms-connector+Backend) -- Backend service interactions
- [ ] [vms-connector: Dependencies](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496140355/vms-connector+Dependencies) -- Library and service dependencies
- [ ] [vms-connector: Dependency Tree](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496369678/vms-connector+Dependency+Tree) -- Visual dependency graph
- [ ] [vms-connector: Deployment & Operations](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/495910920/vms-connector+Deployment+Operations) -- Deploy process and operational runbooks
- [ ] [vms-connector: Log Cleanup](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496140336/vms-connector+Log+Cleanup) -- Log rotation and cleanup procedures
- [ ] [vms-connector: New Relic Reporting](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/495779865/vms-connector+New+Relic+Reporting) -- Observability and metrics reporting

### kb Space (Legacy Knowledgebase)
- [ ] [connector-tools](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160071832/connector-tools) -- Utilities for connector management
- [ ] [Connector Warnings](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160203115/Connector+Warnings) -- Known warning conditions and troubleshooting
- [ ] [Container Per Camera, Pod Per Site](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160072881/Container+Per+Camera+Pod+Per+Site) -- Architecture decision on resource allocation
- [ ] [Lecture Notes - lifecycle of a frame in the connector](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/250544138/Lecture+Notes+-+lifecycle+of+a+frame+in+the+connector) -- Detailed frame lifecycle walkthrough
- [ ] [Motion Filters](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160268644/Motion+Filters) -- Motion filtering logic
- [ ] [Motion Sleep](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160400386/Motion+Sleep) -- Motion sleep optimization
- [ ] [Dynamic Slicing](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160268866/Dynamic+Slicing) -- Dynamic image slicing for inference
- [ ] [Confidence](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160072925/Confidence) -- Confidence threshold configuration
- [ ] [Ignore Zones by Label](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160071864/Ignore+Zones+by+Label) -- Label-based ignore zone setup
- [ ] [Blur](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160728029/Blur) -- Blur detection and handling
- [ ] [Crop](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/161251589/Crop) -- Image crop configuration
- [ ] [Blacklist](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160727751/Blacklist) -- Camera blacklist functionality
- [ ] [Image Refresh](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160269121/Image+Refresh) -- Image refresh behavior
- [ ] [Alarm Filtering](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/161120396/Alarm+Filtering) -- Alarm filtering rules
- [ ] [Motion-plus deployment](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/161251446/Motion-plus+deployment) -- Motion+ model deployment
- [ ] [CPU and Memory Review](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160268695/CPU+and+Memory+Review) -- Resource usage analysis
- [ ] [Custom Metrics](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160203325/Custom+Metrics) -- Custom metric definitions
- [ ] [Flex Schedules](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160891186/Flex+Schedules) -- Schedule-based connector behavior

### kb Space -- VMS-Specific Integrations
- [ ] [Milestone](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160071883/Milestone) -- Milestone VMS integration
- [ ] [Hikvision - Alibi - LTS](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160203037/Hikvision+-+Alibi+-+LTS) -- Hikvision family integration
- [ ] [Avigilon](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160268714/Avigilon) -- Avigilon VMS
- [ ] [Exacq](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160071956/Exacq) -- Exacq VMS
- [ ] [Genesis](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160071975/Genesis) -- Genesis integration
- [ ] [Digital Watchdog](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160268625/Digital+Watchdog) -- DW Spectrum / Hanwha Wave
- [ ] [Digital Watchdog / Hanwha Wave](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160071905/Digital+Watchdog+Hanwha+Wave) -- Combined DW/Hanwha docs
- [ ] [Bosch](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160399621/Bosch) -- Bosch VMS
- [ ] [Axis](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160399608/Axis) -- Axis camera integration
- [ ] [Angelcam](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160268568/Angelcam) -- Angelcam cloud integration
- [ ] [Ajax](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/294813697/Ajax) -- Ajax integration
- [ ] [Ajax Cloud](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/293502977/Ajax+Cloud) -- Ajax Cloud integration
- [ ] [Bold](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160204384/Bold) -- Bold VMS
- [ ] [Bold Site Manager](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/161120487/Bold+Site+Manager) -- Bold Site Manager integration
- [ ] [Digifort](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160269868/Digifort) -- Digifort VMS
- [ ] [Indigo Vision](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160268752/Indigo+Vision) -- IndigoVision integration
- [ ] [Lorex](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160399647/Lorex) -- Lorex integration
- [ ] [March Networks](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160072220/March+Networks) -- March Networks integration
- [ ] [March Network](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160399862/March+Network) -- March Networks (duplicate?)
- [ ] [Mobotix](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160399634/Mobotix) -- Mobotix integration
- [ ] [Mobotix Cameras](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160072017/Mobotix+Cameras) -- Mobotix camera specifics
- [ ] [Openeye](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160399557/Openeye) -- OpenEye integration
- [ ] [Insta360](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160694501/Insta360) -- Insta360 camera support
- [ ] [Dice Video Verification](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160759957/Dice+Video+Verification) -- Dice VV integration
- [ ] [Frontel/Videofied](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/213417985/Frontel+Videofied) -- Frontel/Videofied integration
- [ ] [Evalink](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/258211842/Evalink) -- Evalink alarm management platform
- [ ] [LISA](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/247627790/LISA) -- LISA integration
- [ ] [NX Proxy](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160399506/NX+Proxy) -- Network Optix proxy integration
- [ ] [azena](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160399787/azena) -- Azena platform

### QPS Space
- [ ] [Custom VMS Connector](https://actuate-team.atlassian.net/wiki/spaces/QPS/pages/140279924/Custom+VMS+Connector) -- QA process for custom VMS connectors

### Rearchitecture Space
- [ ] [Rollout process](https://actuate-team.atlassian.net/wiki/spaces/Rearchitec/pages/26705936/Rollout+process) -- Connector rollout procedures

## GitHub Repos
- [ ] vms-connector -- Core connector codebase (already partially ingested)
- [ ] actuate-libraries -- Shared libraries used by the connector
- [ ] ds-terraform-eks-v2 -- Kubernetes infrastructure for connector deployment
