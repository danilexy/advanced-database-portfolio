# MIT 8103 Advanced Database Systems: Practical Portfolio

**Student:** [YOUR FULL NAME] · **Matric No.:** [YOUR MATRIC NUMBER] · **Session:** 2026/2027, First Semester

**Case study:** **SwiftPay Digital Wallet**, a simulated Nigerian fintech that offers wallet, savings and current accounts, with deposits, withdrawals and transfers over the App, USSD, POS and Web. The same case study and database are used in all five portfolio activities.

| # | Activity | Technologies | Highlights |
|---|---|---|---|
| 1 | [Database Design & Modelling](portfolio-1-database-design/) | PostgreSQL 16, Graphviz | 7-table 3NF schema, ER diagram, CHECK/FK/UNIQUE constraints, audit trigger, 300k-row seed data |
| 2 | [Query Processing & Optimisation](portfolio-2-query-optimisation/) | `EXPLAIN ANALYZE`, B-tree/partial/covering indexes, materialized view | 20–66× speed-ups. Q4 analysed: why an index wasn't enough, and the fix (~550×). |
| 3 | [Transactions & Concurrency](portfolio-3-transactions-concurrency/) | PL/pgSQL, MVCC, isolation levels | COMMIT/ROLLBACK/SAVEPOINT, lost update reproduced and fixed two ways, non-repeatable read, deadlock and prevention |
| 4 | [NoSQL & Advanced Data Models](portfolio-4-nosql/) | JSONB + GIN, Redis 7, recursive graph query | Customer-360 documents, sessions/cache/atomic KYC limits/leaderboard/stream, fraud-ring detection |
| 5 | [Distributed & Cloud](portfolio-5-distributed-cloud/) | Streaming replication, hash partitioning, Docker Compose | Live primary→replica, read-only standby, failover with `pg_promote()`, shard pruning, CAP discussion |

## Repository structure

```
advanced-database-portfolio/
├── portfolio-1-database-design/        schema, seed data, ER diagram, constraint tests
├── portfolio-2-query-optimisation/     queries, indexes, benchmark script, plans/, chart
├── portfolio-3-transactions-concurrency/ transfer procedure, demos, outputs
├── portfolio-4-nosql/                  JSONB documents, Redis key-value, graph query
├── portfolio-5-distributed-cloud/      replication & failover, sharding, docker-compose
├── docs/                               LMS summary document
└── README.md
```

Each folder has its own README that explains what was done, how to run it, and the results. Every `output_*.txt` file is the real captured output of the script next to it.

## Quick start

```bash
export PGHOST=localhost PGUSER=postgres
createdb swiftpay
psql -d swiftpay -f portfolio-1-database-design/01_schema.sql
psql -d swiftpay -f portfolio-1-database-design/02_seed_data.sql
# then follow each portfolio folder's README in order (2 -> 5)
```

**Tested with:** PostgreSQL 16.15, Redis 7, Graphviz, Python 3 (matplotlib for the chart).

## AI use declaration
See [`docs/`](docs/) and the final section of the LMS document.
