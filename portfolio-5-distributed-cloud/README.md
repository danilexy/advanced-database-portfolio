# Portfolio 5: Distributed and Cloud Database Exercise

**What was actually set up:** two PostgreSQL 16 servers on one host. The **primary** is on port 5432. The **streaming replica** is on port 5433, built with `pg_basebackup` and a physical replication slot. I then tested replication, read scaling, a read-only standby and **failover**. Sharding is shown with hash partitioning on the shard key. [`docker-compose.yml`](docker-compose.yml) packages the same topology for deployment on a cloud VM (a configuration file; it wasn't run in my environment).

| File | Shows |
|---|---|
| [`01_replication_demo.sh`](01_replication_demo.sh) → [`output_01_replication.txt`](output_01_replication.txt) | Replication status, lag, read-only replica, read scaling, failover |
| [`02_sharding_partitioning.sql`](02_sharding_partitioning.sql) → [`output_02_sharding.txt`](output_02_sharding.txt) | Shard-key choice, data distribution, shard pruning vs scatter-gather |
| [`docker-compose.yml`](docker-compose.yml), [`init/`](init/) | Containerised primary + replica deployment |

## 1. Replication setup

```bash
# on the primary: wal_level=replica, max_wal_senders=5
pg_basebackup -h <primary> -D replica -R -X stream -C -S replica1_slot --checkpoint=fast
pg_ctl -D replica -o "-p 5433" start          # -R wrote primary_conninfo + standby.signal
```

**Results** (from `output_01_replication.txt`):
- `pg_stat_replication` showed the standby in state **streaming**, sync_state **async**, **0 bytes** of lag, and replay_lag ≈ 28 ms. The slot `replica1_slot` is active, so the primary keeps the WAL until the replica has received it.
- A transfer committed on the primary was **visible on the replica at the first check, 85 ms later**.
- A write on the replica was rejected with `ERROR: cannot execute UPDATE in a read-only transaction`.
- **Read scaling:** a full-table report over 290k rows ran on the replica, which takes load off the primary that handles payments.
- **Failover:** I killed the primary (`pg_ctl -m immediate stop`) and ran `pg_promote()` on the replica. It left recovery, accepted a new transfer, and still had the transfer committed before the crash.

## 2. Sharding

**Shard key = `customer_id`** (hash, 4 shards). The result was an even spread: 24.2–25.6% of 436k ledger entries per shard.
- **Single-shard query.** A customer's statement (`WHERE customer_id = 100`) was **pruned to `txn_shard_1` only**. Most app traffic is per-customer, so most queries touch one node.
- **Scatter-gather query.** A query without the shard key (`amount > 49000`) had to **scan all 4 shards** and merge the results. Analytics like this belong on a replica or a warehouse.
- **Why not shard by date or by account?** Sharding by date makes all of today's writes land on one "hot" shard. Sharding by account would split a customer's accounts across nodes, so even a statement would need several nodes.
- **Cross-shard transfers.** A transfer between customers on different shards needs a **distributed transaction** (two-phase commit, `PREPARE TRANSACTION`/`COMMIT PREPARED`) or a saga with compensating reversals. This is why the ledger records debit and credit entries separately: each one lives on its owner's shard.

## 3. Consistency, availability and the CAP trade-off for SwiftPay

| Choice | Effect | SwiftPay decision |
|---|---|---|
| **Async replication** (what I tested) | Fast commits. If the primary dies before WAL is shipped, the last few transactions can be lost (RPO > 0). Replica reads can be slightly stale. | OK for read replicas that serve reports and statements |
| **Sync replication** (`synchronous_standby_names`, `synchronous_commit=on`) | A commit waits for the standby, so RPO = 0. Writes are slower, and if the standby is down, writes block. | **Required for the payments primary:** a lost confirmed transfer is unacceptable |
| **CAP** | During a network partition, the system must choose between Consistency and Availability | Ledger = **CP**: refuse a transfer rather than risk a double spend. Redis cache, leaderboard and profile documents = **AP** / eventually consistent. |
| **Read-your-writes** | A user who just paid may read the replica before it has caught up | Route that user's reads to the primary for a few seconds after a write, or compare `pg_last_wal_replay_lsn()` |

## 4. Cloud deployment

For production I would use a managed service, for example **Amazon RDS / Aurora PostgreSQL, Azure Database for PostgreSQL, or Google Cloud SQL**, with:
- **Multi-AZ** synchronous standby for automatic failover (RTO ≈ 1–2 min), plus cross-region read replicas for disaster recovery
- Automated backups with point-in-time recovery, encryption at rest (KMS) and TLS in transit. For Nigerian customer data, hosting in-country or in a compliant region (NDPA 2023) should be checked.
- A connection pooler (PgBouncer / RDS Proxy) and a read/write split in the application
- Citus (Azure Cosmos DB for PostgreSQL) if a single primary's write capacity is ever exceeded, using the same `customer_id` shard key

**Limitation of my setup:** both nodes ran on one machine, so this demonstrates the *mechanism* of replication and failover, not real network latency or a real network partition. I promoted the replica by hand. In production, a tool such as Patroni or the cloud provider does this automatically.
