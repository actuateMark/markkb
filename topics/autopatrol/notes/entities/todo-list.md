---
author: kb-bot
---

This is a stub that should be expanded and formatted properly to track todos for this topic

currently many AP schedules are dead, yet run anyway. The goal is that when we get a "no patrols to run, exiting" error we should key off a job to an sqs queue that feeds a lambda that then checks against the immix server in question to see if the schedule is still active. If it is not, then we should disable it on our admin side.

This new lambda code should just be in the same repo as the onboarder, but should be deployed to a new but similar lambda that just checks one site at a time. The repo is:  https://github.com/aegissystems/autopatrol_onboarder

