---
title: "Source: SES Configuration References"
type: source
topic: infrastructure
tags: [worklog, ses, aws, email, sns, configuration]
ingested: 2026-04-14
author: kb-bot
---

# SES Configuration References

Source: bookmark reference for AWS SES configuration resources.

## Resources

- **SES Configuration Set**: [actuate-configuration-set](https://us-west-2.console.aws.amazon.com/ses/home?region=us-west-2#/configuration-sets/actuate-configuration-set) in us-west-2.
- **Rendering Failure SNS Topic**: [ActuateSESRenderingFailure](https://us-west-2.console.aws.amazon.com/sns/v3/home?region=us-west-2#/topic/arn:aws:sns:us-west-2:388576304176:ActuateSESRenderingFailure) -- SNS topic that receives notifications when SES template rendering fails.

## Notes

The SES configuration set is in the primary AWS account (388576304176), us-west-2 region. The rendering failure topic provides observability into email template issues -- relevant to the [[ses-email-tooling-pitch|SES email tooling pitch]] which identified lack of error visibility as a key gap.
