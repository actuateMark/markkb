---
title: "IAM Roles Anywhere for the minipc — unattended AWS auth without static keys"
type: synthesis
topic: personal-laptop
tags: [aws, iam, rolesanywhere, minipc, security, automation, dashboard-check]
created: 2026-04-27
updated: 2026-04-27
author: kb-bot
---

# IAM Roles Anywhere for the minipc — unattended AWS auth without static keys

Setting up the Firebat minipc to call AWS APIs from a cron, without long-lived access keys and without browser-interactive SSO refreshes. The first concrete consumer is `/dashboard-check` (CloudWatch Logs / Metrics / Cost Explorer reads); same pattern reusable for any future workload on the box that needs read access to AWS.

## Decision: Roles Anywhere over Identity Center over static keys

Three options were on the table. Verdict for unattended-cron use case:

| Approach | Fit | Why |
|---|---|---|
| Static IAM access keys | Acceptable | Long-lived secret to protect; broad blast radius if leaked |
| **IAM Identity Center (SSO)** | **Bad** | SSO tokens expire after a few hours; refresh requires `aws sso login` in a browser. Cron silently fails after first expiry. Right answer for humans at terminals, wrong answer for headless workloads |
| **IAM Roles Anywhere** | **Best** | Purpose-built for "long-running workloads outside AWS." X.509 cert + private key on disk; helper daemon trades cert for short-lived role credentials and refreshes transparently. No expiring tokens, no static IAM access key, secret is filesystem-protected |

AWS surfaces this as the recommendation when you go to "Create access key" on a programmatic IAM user. Worth following — Roles Anywhere is the right architecture even though setup is a little more involved.

## Architecture

```
Laptop (CA owner)              Minipc (workload)              AWS
─────────────────              ────────────────              ──────────────────
~/secure/aws-rolesanywhere/    ~/.config/aws-rolesanywhere/   IAM Roles Anywhere
  ca.crt    ←(uploaded)──────►   trust anchor: mork-personal-ca
  ca.key    (NEVER LEAVES)         (binds to CA cert; the
  ca.srl                            "are you legit?" gate)
  mork-firebat.crt   ───copy──►  mork-firebat.crt
  mork-firebat.key   ───copy──►  mork-firebat.key (mode 0600)
                                                              IAM Profile
                                                                ↳ allowed roles
                                /usr/local/bin/                 ↳ session settings
                                  aws_signing_helper           
                                ~/.aws/config                   IAM Role
                                  credential_process = …         ↳ trust policy:
                                                                    rolesanywhere svc
                                                                    + Condition: cert CN
                                                                 ↳ permissions policy
```

**Runtime flow** (every ~1h, transparent to caller):

1. App calls AWS API with `AWS_PROFILE=dashboard-check`
2. AWS CLI / boto3 reads profile, sees `credential_process = aws_signing_helper …`
3. Helper signs a `CreateSession` request using the cert+key, posts to `rolesanywhere.us-west-2.amazonaws.com`
4. Roles Anywhere validates the cert against the trust anchor + the role's trust-policy condition (cert CN matches), returns short-lived credentials
5. Helper hands credentials back to the AWS SDK; SDK makes the actual API call
6. Credentials cached for their TTL (~1h); next call within window uses the cache

The **only long-lived secret** is the leaf private key on the minipc filesystem, mode 0600. If it leaks, revoke by deleting the trust anchor (kills all certs under that CA) or by rotating the leaf cert (issue a new one with a new key, distribute, delete the old).

## Step-by-step procedure (reproducible)

These are the steps that worked end-to-end on 2026-04-27. Where there was a gotcha I noted it inline.

### 1. Generate the CA + leaf cert (on the laptop)

```bash
mkdir -p ~/secure/aws-rolesanywhere && chmod 700 ~/secure/aws-rolesanywhere
cd ~/secure/aws-rolesanywhere

openssl genrsa -out ca.key 4096
```

CA cert — note the explicit `-addext` calls. Without these, the resulting cert lacks `Basic Constraints: critical, CA:TRUE` and Roles Anywhere rejects it with `incorrect basic constraints for ca cert`:

```bash
openssl req -x509 -new -nodes -key ca.key -sha256 -days 7300 -out ca.crt -subj "/CN=mork-personal-rolesanywhere-ca" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -addext "subjectKeyIdentifier=hash"
```

Leaf cert (5-year — calendar a renewal):

```bash
openssl genrsa -out mork-firebat.key 2048
openssl req -new -key mork-firebat.key -out mork-firebat.csr -subj "/CN=mork-firebat"
```

Build a small extensions file for the leaf (avoids `\` line continuations on the openssl x509 call):

```bash
echo 'basicConstraints=critical,CA:FALSE' > leaf.ext
echo 'keyUsage=critical,digitalSignature' >> leaf.ext
echo 'extendedKeyUsage=clientAuth' >> leaf.ext
echo 'subjectKeyIdentifier=hash' >> leaf.ext
echo 'authorityKeyIdentifier=keyid,issuer' >> leaf.ext
```

Sign — using `set --` to keep each command line short (terminal wrapping issue, see Gotchas):

```bash
set -- -req -in mork-firebat.csr
set -- "$@" -CA ca.crt -CAkey ca.key
set -- "$@" -CAcreateserial
set -- "$@" -out mork-firebat.crt
set -- "$@" -days 1825 -sha256 -extfile leaf.ext
openssl x509 "$@"
```

Verify:

```bash
openssl verify -CAfile ca.crt mork-firebat.crt
openssl x509 -in ca.crt -noout -text | grep -A 1 'Basic Constraints'
openssl x509 -in ca.crt -noout -text | grep -A 1 'Key Usage'
```

Both grep outputs must show `critical` for AWS to accept the trust anchor.

### 2. IAM permission policy + role

Create the IAM permission policy first so it can be attached at role-creation time. For dashboard-check:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadCWLogsForDashboardSignals",
      "Effect": "Allow",
      "Action": [
        "logs:FilterLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:us-west-2:388576304176:log-group:/aws/lambda/immix-autopatrol-onboarding:*"
    },
    {
      "Sid": "ReadCWMetricsForDashboardSignals",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:GetMetricData",
        "cloudwatch:ListMetrics"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ReadCostExplorer",
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage",
        "ce:GetCostForecast",
        "ce:GetDimensionValues"
      ],
      "Resource": "*"
    },
    {
      "Sid": "BasicSelfIdentify",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

**`logs:FilterLogEvents` is resource-scoped** to the one log group dashboard-check actually reads. CW Metrics + CE need `*` because they're account-wide query APIs (data is still implicitly scoped by your filter). Don't add `logs:DescribeLogGroups` — that's a list-action that needs `*`, and we don't actually use it.

Then **IAM → Roles → Create role → Custom trust policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "rolesanywhere.amazonaws.com" },
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession",
        "sts:SetSourceIdentity"
      ],
      "Condition": {
        "StringEquals": {
          "aws:PrincipalTag/x509Subject/CN": "mork-firebat"
        }
      }
    }
  ]
}
```

The `Condition` is the **load-bearing security control** — it locks the role to certs whose subject CN is `mork-firebat`. Without it, any cert under our CA could assume the role. With it, even if we issue more leaf certs under the same CA in future, only those with `CN=mork-firebat` can use this role.

Attach the permission policy. Note the role ARN.

### 3. Trust Anchor + Profile (in IAM → Roles Anywhere, region us-west-2)

- **Trust anchor** `mork-personal-ca`: paste contents of `ca.crt` as external certificate bundle.
- **Profile** `dashboard-check-profile`: select the role created above; default 1h session duration.

Capture all three ARNs:
```
arn:aws:iam::388576304176:role/dashboard-check-rolesanywhere
arn:aws:rolesanywhere:us-west-2:388576304176:trust-anchor/<uuid>
arn:aws:rolesanywhere:us-west-2:388576304176:profile/<uuid>
```

### 4. Install on the minipc

AWS CLI v2 — note Ubuntu 24.04 dropped the `awscli` apt package; must use the official installer:

```bash
ssh mork@mork-firebat 'sudo apt-get install -y -qq unzip'
ssh mork@mork-firebat 'cd /tmp && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip && unzip -q awscliv2.zip && sudo ./aws/install --update'
```

Signing helper (current at v1.6.0; check AWS docs for newer):

```bash
ssh mork@mork-firebat 'curl -fsSL "https://rolesanywhere.amazonaws.com/releases/1.6.0/X86_64/Linux/aws_signing_helper" -o /tmp/aws_signing_helper && chmod +x /tmp/aws_signing_helper && sudo mv /tmp/aws_signing_helper /usr/local/bin/aws_signing_helper'
```

### 5. Push cert + key + write `~/.aws/config`

From laptop:

```bash
ssh mork@mork-firebat 'mkdir -p ~/.config/aws-rolesanywhere && chmod 700 ~/.config/aws-rolesanywhere'
scp ~/secure/aws-rolesanywhere/mork-firebat.crt mork@mork-firebat:~/.config/aws-rolesanywhere/
scp ~/secure/aws-rolesanywhere/mork-firebat.key mork@mork-firebat:~/.config/aws-rolesanywhere/
ssh mork@mork-firebat 'chmod 600 ~/.config/aws-rolesanywhere/mork-firebat.key'
```

Build `~/.aws/config` via shell variable concatenation (avoids the long-line paste mangling that bites copy-paste — see Gotchas):

```bash
TA=arn:aws:rolesanywhere:us-west-2:388576304176:trust-anchor/<uuid>
PR=arn:aws:rolesanywhere:us-west-2:388576304176:profile/<uuid>
RL=arn:aws:iam::388576304176:role/dashboard-check-rolesanywhere
CRT=/home/mork/.config/aws-rolesanywhere/mork-firebat.crt
KEY=/home/mork/.config/aws-rolesanywhere/mork-firebat.key
HELPER=/usr/local/bin/aws_signing_helper
CP="$HELPER credential-process --certificate $CRT --private-key $KEY --trust-anchor-arn $TA --profile-arn $PR --role-arn $RL"
ssh mork@mork-firebat "mkdir -p ~/.aws && chmod 700 ~/.aws && printf '%s\n' '[profile dashboard-check]' 'region = us-west-2' 'credential_process = $CP' > ~/.aws/config && chmod 600 ~/.aws/config"
```

### 6. Smoke test

```bash
ssh mork@mork-firebat 'AWS_PROFILE=dashboard-check aws sts get-caller-identity'
```

Expected: assumed-role ARN with the cert's source-identity hash trailing. Then exercise the actual permissions you provisioned (CW Logs FilterLogEvents, CW Metrics, CE) against real resources to confirm.

### 7. Cleanup

If you'd previously created a static-keys IAM user (e.g. as a backup plan), delete it. Keep the permission policy — it's now attached to the Roles Anywhere role, not the user.

## Gotchas (in order of pain inflicted)

1. **`openssl req -x509` without `-addext` produces a CA cert AWS rejects.** Default config in many distros doesn't set `basicConstraints=critical,CA:TRUE`. Fix: explicit `-addext` flags as shown. Symptom: Trust Anchor creation fails with `incorrect basic constraints for ca cert`.
2. **Trust-policy `Condition` is the security boundary, not the cert itself.** Without `aws:PrincipalTag/x509Subject/CN` matching, any cert your CA ever signs could assume the role. Always include the condition; rotate it if you ever change the leaf CN.
3. **Ubuntu 24.04 dropped `apt install awscli`.** Have to use the official installer. Documented in [[firebat-minipc-as-claude-dev-box]] phase-06 too.
4. **`logs:DescribeLogGroups` needs `Resource: "*"`.** It's a discovery list-action. If you only need `FilterLogEvents` on one group, scope it tight and skip Describe — what we did. The ad-hoc smoke test using `describe-log-groups` will fail AccessDenied; that's expected and isn't a workload regression.
5. **Long shell commands break on terminal-width paste.** Real lesson learned during this setup. Caused two separate paste failures (heredoc mangling on indent + 190-char `printf` getting wrapped into 4 separate commands). Codified in `~/.claude/projects/-home-mork-work-local-network-scripts/memory/shell-snippet-format.md`. Architectural pattern: when a command needs many flags, build them up via `set --` accumulation across short lines. When writing a config file with a long credential-process value, use shell-variable concatenation then `printf '%s\n' "$VAR" > file`.
6. **`aws_signing_helper` is a separate binary you must install.** Not bundled with AWS CLI v2 (AWS docs imply it might be — it's not, you download it separately).

## Renewal cadence

| Artifact | Lifetime set | Next action |
|---|---|---|
| CA cert (`ca.crt`) | 20 years (2046-04-22) | Renew CA cert (re-run openssl req with same key); re-upload trust anchor |
| Leaf cert (`mork-firebat.crt`) | 5 years (2031-04-26) | Issue a new leaf with same key OR new key; copy to minipc |
| Helper binary | rolling | `apt-style` update during phase re-provision; check AWS doc page for latest version |
| Role permissions policy | as needed | Edit if the cron's data needs change |

Calendar reminder for ~2030 to renew the leaf. CA renewal is multi-year horizon.

## Reusing this pattern for a new workload

If we ever want a second workload on the minipc with different AWS permissions:

1. Mint a new IAM **role** (e.g. `kb-sync-rolesanywhere`) with its own permission policy — but **same trust policy** (point at the existing trust anchor; same cert authenticates).
2. Add the role to the **same profile** OR create a new profile. (One profile can list many roles; the helper picks via `--role-arn`.)
3. Drop a second `[profile kb-sync]` block in `~/.aws/config` with the new role ARN. Same cert, same key, same trust anchor — only `--role-arn` differs.

The CA + cert is reusable infrastructure. New workloads = new role + permission policy, nothing else.

## Files inventory

**Laptop:**
- `~/secure/aws-rolesanywhere/{ca.crt,ca.key,ca.srl,mork-firebat.{crt,key,csr},leaf.ext}` — chmod 700 dir, 600 keys

**Minipc:**
- `~/.config/aws-rolesanywhere/mork-firebat.{crt,key}` — chmod 700 dir, 600 key, 644 cert
- `~/.aws/config` — chmod 700 dir, 600 file
- `/usr/local/bin/aws_signing_helper` + `/usr/local/bin/aws` (CLI v2)

**AWS:**
- IAM Policy `dashboard-check-readonly`
- IAM Role `dashboard-check-rolesanywhere`
- Roles Anywhere Trust Anchor `mork-personal-ca`
- Roles Anywhere Profile `dashboard-check-profile`

## Related

- [[firebat-minipc-as-claude-dev-box]] — the always-on box this auth feeds
- [[2026-04-24_skills-audit-script-candidates]] — why dashboard-check is being de-LLM'd, which motivated this auth setup
- [[skill-dashboard-check]] — first consumer of these credentials
- [[automation-overnight-check]] — adjacent workload that could reuse the same trust anchor + a second profile
- AWS docs: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_non-aws.html
- Helper repo: https://github.com/aws/rolesanywhere-credential-helper
