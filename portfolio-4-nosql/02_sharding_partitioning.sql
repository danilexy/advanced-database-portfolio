-- =====================================================================
-- Portfolio 5B - Horizontal partitioning by shard key (customer_id)
-- In a single node this is HASH PARTITIONING; in a distributed deployment
-- each partition would live on a different node (e.g. Citus, or
-- postgres_fdw foreign partitions). The routing logic is identical.
-- Shard key = customer_id: a customer's ledger always lives on ONE shard,
-- so statements and the common transfer path stay single-shard.
-- =====================================================================
SET search_path TO swiftpay;
DROP TABLE IF EXISTS txn_sharded;
CREATE TABLE txn_sharded (
    txn_id       BIGINT,
    customer_id  INT NOT NULL,
    account_id   INT NOT NULL,
    direction    CHAR(2) NOT NULL CHECK (direction IN ('DR','CR')),
    amount       NUMERIC(14,2) NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (customer_id, txn_id, direction)      -- PK must include the shard key
) PARTITION BY HASH (customer_id);

CREATE TABLE txn_shard_0 PARTITION OF txn_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE txn_shard_1 PARTITION OF txn_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE txn_shard_2 PARTITION OF txn_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE txn_shard_3 PARTITION OF txn_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- each transfer becomes a debit entry on the sender's shard and a credit entry on the receiver's shard
INSERT INTO txn_sharded
SELECT t.txn_id, a.customer_id, a.account_id, 'DR', t.amount, t.created_at
FROM txn t JOIN account a ON a.account_id = t.from_account_id WHERE t.status = 'SUCCESS'
UNION ALL
SELECT t.txn_id, a.customer_id, a.account_id, 'CR', t.amount, t.created_at
FROM txn t JOIN account a ON a.account_id = t.to_account_id WHERE t.status = 'SUCCESS';
ANALYZE txn_sharded;

\echo '=== Data distribution across the 4 shards (hash spreads load evenly) ==='
SELECT tableoid::regclass AS shard, count(*) AS rows,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM txn_sharded GROUP BY 1 ORDER BY 1;

\echo '=== Single-shard query: statement for customer 100 -> planner PRUNES to 1 shard ==='
EXPLAIN (COSTS OFF)
SELECT * FROM txn_sharded WHERE customer_id = 100 ORDER BY created_at DESC LIMIT 20;

\echo '=== Scatter-gather query: no shard key -> must visit ALL shards ==='
EXPLAIN (COSTS OFF)
SELECT count(*) FROM txn_sharded WHERE amount > 49000;
