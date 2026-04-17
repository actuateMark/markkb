---
title: "Source: CodeArtifact Setup Guide"
type: source
topic: actuate-libraries
tags: [worklog, codeartifact, aws, poetry, pip, twine, github-actions]
ingested: 2026-04-14
author: kb-bot
---

# CodeArtifact Setup Guide

Worklog notes with links and commands for setting up AWS CodeArtifact as the private Python package repository.

## Publishing Stack

- **Poetry** (`https://python-poetry.org/`) for package management and building
- **Twine** for uploading packages to CodeArtifact
- Integration guide: `https://chariotsolutions.com/blog/post/using-codeartifact-with-poetry/`

## Local Authentication

Add to `.bashrc` for automatic token refresh:

```bash
aws codeartifact login --tool pip --domain my_domain --domain-owner 111122223333 --repository my_repo --duration 43200
aws codeartifact login --tool twine --domain my_domain --domain-owner 111122223333 --repository my_repo
```

The pip login uses a 12-hour token (`--duration 43200`). Both pip (for installing) and twine (for publishing) need separate authentication.

## GitHub Actions

For CI/CD, CodeArtifact tokens are set via environment variables as described in the AWS docs on token authentication.

## Key AWS Documentation

- Token authentication, pip configuration, twine configuration, and upstream external connections (for proxying PyPI packages through CodeArtifact) are all referenced.

## See Also

- [[worklog-bump-process]] -- how version bumps trigger publishing
- [[worklog-microservice-library-plan]] -- why CodeArtifact exists in this architecture
