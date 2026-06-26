---
title: "Colleague prep — before the firebat handoff session"
type: concept
tags: [offboarding, handoff, prep, home]
updated: 2026-06-25
author: kb-bot
incoming:
  - No backlinks found.
incoming_updated: 2026-06-26
---

# Firebat handoff — please prep before our session (~15 min)

Quick context: **firebat** is the always-on mini-PC that runs our morning-routine automation, the ops dashboard, and the KB site. It currently authenticates as my personal accounts; in our session we'll re-home it onto **your** logins so it keeps running after I leave. To make that fast, please mint a few credentials in advance.

**Mint everything under your own existing logins. Keep them in a password manager / secure note — please don't send the secret values back to me in plaintext (chat/email); you'll read them to me to type on the box.**

## 1. GitHub fine-grained PAT
- github.com → your avatar → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**
- Name: `firebat-automation` · **Resource owner: `aegissystems`** · Repository access: **All repositories**
- Permissions → **Contents: Read and write**, **Metadata: Read**, **Pull requests: Read**, **Issues: Read**
- Generate → copy and save it.
- *(If the org requires approval for fine-grained PATs, an org owner must approve it before it works — worth checking now.)*

## 2. New Relic User key
- one.newrelic.com → bottom-left user menu → **API keys → Create a key**
- Type: **User** · Name: `firebat-automation` → copy the `NRAK-…` and save it.

## 3. Atlassian API token
- id.atlassian.com → **Security → API tokens → Create API token**
- Label: `firebat-jira-sync` → copy and save it. (Also note your Atlassian account email.)

## 4. Tailscale — needs a tailnet admin of `aegissystems.ai`
The owner/admin is most likely **[[jacob-weiss|Jacob Weiss]]** (or possibly **[[tatiana-hanazaki|Tatiana Hanazaki]]**) — Mike, Aziz, and I aren't admins. **Could you confirm with Jacob and have him either do this or be reachable during our session?**
- (Admin) login.tailscale.com → **Access controls**: ensure `tag:server` exists under `tagOwners`, and ACLs let team devices reach `tag:server` over SSH/HTTP.
- (Admin) **Settings → Keys → Generate auth key** with tag **`tag:server`** → copy the `tskey-…`.
- *Not a hard blocker:* if no admin is available in time, the box still runs and stays reachable on the office LAN (`actuate-dev.local`); only off-LAN access via `mork-firebat` lapses when my account is deactivated, and an admin can re-tag it later from the box console. But sorting it with Jacob beforehand is cleanest.

## 5. Your SSH public key
- Run `cat ~/.ssh/id_ed25519.pub` (or `id_rsa.pub`) → copy it. (For maintenance access to the npu-server box.)

## 6. Quick access check
- Confirm you can read the `aegissystems` repos and approve PRs, have [[new-relic|New Relic]] + Jira access, and have **Tailscale installed on your laptop** (we'll use it to verify the box is reachable at the end).

---

**Bring to the room (in a secure note):** GitHub PAT · New Relic `NRAK-…` · Atlassian token + your email · Tailscale `tskey-…` (if admin) · your SSH public key.

That's it — the session itself is ~30 min: I drive the box over SSH while you read me the tokens to type, we re-tag it in Tailscale at the console, you approve a couple of docs PRs, and we verify it's all green from your machine.
