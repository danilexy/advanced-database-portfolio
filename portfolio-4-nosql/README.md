# Portfolio 4: NoSQL and Advanced Data Models

The same SwiftPay case study is modelled in three non-relational styles. Each one is matched to a workload where it beats the normalised schema from Portfolio 1. **The relational database stays the system of record for money**, and the NoSQL models serve the read-heavy, fast-changing or connected-data workloads around it (*polyglot persistence*).

| Model | Technology used (actually run) | SwiftPay workload | Evidence |
|---|---|---|---|
| **Document** | PostgreSQL 16 `JSONB` + GIN index | "Customer 360" profile for the app home screen | [`01_document_model_jsonb.sql`](01_document_model_jsonb.sql) → [`output_01_document.txt`](output_01_document.txt) |
| **Key-value** (+ sorted set, stream) | Redis 7 | Sessions, balance cache, KYC daily limits, leaderboard, event stream | [`02_key_value_redis.sh`](02_key_value_redis.sh) → [`output_02_redis.txt`](output_02_redis.txt) |
| **Graph** | Recursive CTE (equivalent Cypher shown) | Money-mule / circular-transfer fraud detection | [`03_graph_fraud_ring.sql`](03_graph_fraud_ring.sql) → [`output_03_graph.txt`](output_03_graph.txt) |

> Note: MongoDB and Neo4j weren't available in my environment. The document model therefore uses PostgreSQL's native JSONB document store, which offers the same document concepts (schemaless documents, embedding, containment queries, GIN indexing). The graph model runs the traversal as a recursive CTE, and the equivalent Cypher query is given in the file header.

## A. Document model: Customer 360

**Design: embed, don't join.** One document per customer embeds name, contact, KYC tier, branch, *all accounts*, the *5 most recent transactions*, beneficiaries and preferences (see the sample in the output file). The app home screen then needs **one primary-key lookup instead of a 5-table join**.

**What the output shows**
- **Schema flexibility:** 100 business customers have an extra `business{name, cac_no, pos_terminals}` sub-document, and no `ALTER TABLE` was needed. Query 2 finds them with `doc @> '{"business": {}}'`.
- **Indexed document queries:** the containment query on nested preferences uses a **Bitmap Index Scan on the GIN index** (2.4 ms, 1,666 matches).
- **JSONPath** query into the embedded `accounts` array: `$.accounts[*] ? (@.balance > 245000)`.

**Trade-off:** the embedded `recent_txns` and `balance` values are **copies** that go stale. They must be refreshed when a transaction commits, for example by a trigger or a change-data-capture consumer. Because of that, the document is a *read model* and is never used to authorise payments.

## B. Key-value model: Redis

| Key pattern | Type | Why key-value |
|---|---|---|
| `session:<token>` | STRING, TTL 900 s | O(1) lookup on every API call. Expiry is automatic. |
| `acct:<number>:bal` | STRING, TTL 60 s | **Cache-aside**: a miss reads PostgreSQL, a hit avoids it, and a transfer `DEL`s the key to invalidate it |
| `limit:<cust>:<date>` | counter, TTL 24 h | KYC daily limit. A **Lua script** makes check-and-increment atomic. The output shows 20k ✓, 25k ✓, 8k ✗ (would be 53k), 5k ✓ (exactly 50k). |
| `lb:receivers:<yyyymm>` | SORTED SET | Top receiving accounts. Loaded with 3,449 members from PostgreSQL. `ZINCRBY` updates rank in O(log n), and acct:42 jumped to rank 0. |
| `stream:txn` | STREAM + consumer group | Append-only event log that fraud and SMS services consume independently (`XREADGROUP`) |

**Suitability:** sub-millisecond reads and writes, built-in TTL and atomic counters. **Limitation:** no joins or ad-hoc queries, and data must fit in memory. AOF persistence (`--appendonly yes`) reduces, but doesn't remove, the durability gap compared with PostgreSQL's WAL. So Redis never holds the authoritative balance.

## C. Graph model: fraud ring detection

Money laundering often moves funds A → B → C → D → A within minutes. In a graph, accounts are **nodes** and transfers are **edges**. The question "is there a cycle of length 3–5 in the last 24 h, with time moving forward?" is a natural **variable-length path** query (`MATCH (a)-[:SENT*3..5]->(a)` in Cypher). I planted a 4-hop ring of ₦480,000 transfers, and the recursive traversal found exactly that ring: `{7001,7002,7003,7004,7001}`.

**Suitability:** in SQL every extra hop is another self-join, which grows quickly. A native graph DB uses index-free adjacency, so each hop is a pointer follow. For large-scale fraud analytics a dedicated graph DB (Neo4j, Amazon Neptune) is the better choice. A recursive CTE is enough for a nightly batch check.

## How to run

```bash
export PGHOST=/tmp PGUSER=postgres
psql -d swiftpay -f 01_document_model_jsonb.sql
redis-server --daemonize yes --appendonly yes && ./02_key_value_redis.sh
psql -d swiftpay -f 03_graph_fraud_ring.sql
```
