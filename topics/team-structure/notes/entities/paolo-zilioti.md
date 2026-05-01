---
type: entity
author: kb-bot
created: 2026-04-15
updated: 2026-04-15
tags: [person, engineering, admin-api, integrations, vms, smtp]
incoming:
  - topics/actuate-platform/notes/concepts/multi-region-deployment.md
incoming_updated: 2026-05-01
---

# Paolo Zilioti

Paolo Zilioti is a prolific backend engineer at Actuate with **458 commits to the [[actuate-admin-api]]**, making him the most active contributor to the Admin API codebase. His work spans VMS integrations, SMTP clip handling, and third-party alarm panel support.

## Admin API Contributions

Paolo's 458 commits to the Admin API reflect deep ownership of core platform functionality. The [[actuate-admin-api]] is the Django 6.0 + DRF backend that serves as the central data store and management layer for Actuate's platform -- handling camera configuration, site management, user accounts, schedules, and integration settings. Paolo's volume of contributions indicates he is a go-to resource for Admin API architectural decisions and institutional knowledge about its data model.

## YoursIx VMS Integration (ENG-118)

Paolo leads the YoursIx VMS integration under ticket ENG-118. YoursIx is a Video Management System that Actuate connects to for camera frame ingestion. This integration follows the same connector pattern used by other VMS integrations in the [[vms-connector]] ecosystem, where a puller component extracts frames from the VMS and feeds them into Actuate's inference pipeline.

## SMTP Clips (ENG-29)

Paolo works on SMTP-based clip ingestion under ticket ENG-29. The SMTP pathway allows cameras to send alert clips via email, which Actuate's [[frame-receiver-smtp-v2]] service receives and processes. This is an alternative ingestion path to the [[vms-connector|VMS connector]] pipeline, commonly used by standalone cameras without a VMS.

## Ajax and StarFM Integration (ED-2)

Under the EU Deployment project, Paolo handles [[ajax-components|Ajax]] alarm panel and StarFM integration (ED-2). [[ajax-components|Ajax]] is a European wireless alarm system manufacturer, and StarFM is a monitoring platform. These integrations extend Actuate's reach into the European security market.

## See Also

- [[actuate-admin-api]] -- the codebase he dominates
- [[vms-connector]] -- the connector ecosystem for VMS integrations
- [[frame-receiver-smtp-v2]] -- SMTP clip ingestion service
- [[multi-region-deployment]] -- EU deployment context for [[ajax-components|Ajax]]/StarFM
