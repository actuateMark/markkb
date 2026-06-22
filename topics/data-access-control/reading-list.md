# Reading List: Data Access Control

## Confluence Pages (to ingest)

### EDOCS / kb
- [ ] [Authentication](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496173057/Authentication) — current admin auth system
- [ ] [API Gateway utilization for data access](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160269465/API+Gateway+utilization+for+data+access) — historical proposal; check whether still relevant
- [ ] [Camera Admin Database](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160399900/Camera+Admin+Database) — schema + access model
- [ ] [Camera Admin Database Cleanup](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/160400348/Camera+Admin+Database+Cleanup) — exemplar of admin-side DB-mutating script
- [ ] [Camera Admin Postmortem — March 27, 2026](https://actuate-team.atlassian.net/wiki/spaces/kb/pages/472252417/Camera+Admin+Postmortem+-+March+27+2026) — what direct-DB access made possible/worse
- [ ] [actuate-daos](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/497418247/actuate-daos) — current DAO layer
- [ ] [actuate-daos: DAO Reference](https://actuate-team.atlassian.net/wiki/spaces/EDOCS/pages/496697368/actuate-daos+DAO+Reference) — full DAO surface

## Code to Audit

- `actuate_admin/admin/settings_secrets.py` — current multi-user wiring (default + sqlexplorer + django_q + jobscheduler + closeinfo)
- `actuate_admin/external_api/external_api_set_up.py` — token minting + group-bound service accounts
- `actuate_admin/api/serializers/adminutils/auth/token_authentication_strict.py` — strict-mode token auth
- `actuate-libraries/actuate-daos/src/actuate_daos/admin_dao.py` — direct psycopg2 pool used by 4+ services
- `actuate-libraries/actuate-wireguard/src/actuate_wireguard/db.py` — second direct-DB library
- `actuate-libraries/actuate-admin-api/src/actuate_admin_api/admin_api.py` — the API-routed alternative
- `actuate_bi/noteboooks/src/admin_queries.py` + `actuate_bi/.../sql/*.sql` — raw SQL on disk
- `actuate-wireguard/scripts/integration_check.py` — firefighter-style CLI

## External Reading (optional, principle docs)

- [ ] Postgres `GRANT`, `REVOKE`, role inheritance docs — for per-role least privilege
- [ ] AWS IAM database authentication for RDS — alternative to passwords for app users
- [ ] AWS SSO + Postgres — for human CLI access without static creds
- [ ] OAuth2 scopes vs. coarse roles — model for per-token API scopes
