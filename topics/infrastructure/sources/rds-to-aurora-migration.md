---
title: "Source: RDS to Aurora PostgreSQL Migration Runbook"
type: source
topic: infrastructure
tags: [worklog, rds, aurora, postgresql, migration, aws, runbook]
ingested: 2026-04-14
author: kb-bot
---

# RDS to Aurora PostgreSQL Migration Runbook

Source: AWS Support guidance on migrating RDS PostgreSQL to Aurora PostgreSQL, preserved as a runbook reference.

## Constraint

Blue/green deployment is **not supported** for RDS-to-Aurora migrations. It only works for RDS-to-RDS or Aurora-to-Aurora.

## Method 1: Aurora Read Replica (Preferred -- Near-Zero Downtime)

1. **Create Aurora replica cluster** from the source RDS instance:
   ```
   aws rds create-db-cluster --db-cluster-identifier <name> \
     --engine aurora-postgresql --replication-source-identifier <source-ARN> \
     --storage-encrypted --kms-key-id <KMS-ARN> ...
   ```
2. **Add instances** to the new cluster:
   ```
   aws rds create-db-instance --db-cluster-identifier <cluster> \
     --db-instance-identifier <instance> --engine aurora-postgresql ...
   ```
3. **Wait for replication lag to reach 0.** Monitor via CloudWatch metrics or:
   ```sql
   SELECT extract(epoch from now() - pg_last_xact_replay_timestamp()) AS slave_lag;
   ```
4. **Promote** the replica cluster to standalone:
   ```
   aws rds promote-read-replica-db-cluster --db-cluster-identifier <cluster>
   ```

This is the preferred method because it avoids extended downtime -- the cutover happens only when the replica is fully caught up.

## Method 2: Snapshot Restore (Simpler, Requires Downtime)

1. **Restore** an RDS snapshot to a new Aurora cluster:
   ```
   aws rds restore-db-cluster-from-snapshot --db-cluster-identifier <name> \
     --snapshot-identifier <snapshot-ARN> --engine aurora-postgresql ...
   ```
2. **Add instances** to the restored cluster (same as Method 1, step 2).

This method is simpler but requires downtime proportional to database size, since data is only current as of the snapshot.

## Key References

- [AWS: Migrating data to Aurora PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.Migrating.html)
- [Instance class compatibility](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Concepts.DBInstanceClass.html)
