# Portfolio 3: Transactions and Concurrency

**Environment:** PostgreSQL 16 (MVCC, default isolation READ COMMITTED). The SwiftPay database is the one from Portfolio 1.
Concurrency demos use **two real concurrent `psql` sessions** (A and B). `pg_sleep()` forces the interleaving so the results can be reproduced.

| File | Content |
|---|---|
| [`00_transfer_procedure.sql`](00_transfer_procedure.sql) | `transfer_funds()` stored procedure: the safe, ACID transfer |
| [`01_commit_rollback.sql`](01_commit_rollback.sql) → [`output_01_commit_rollback.txt`](output_01_commit_rollback.txt) | COMMIT, ROLLBACK, atomic failure, SAVEPOINT |
| [`02_concurrency_demos.sh`](02_concurrency_demos.sh) → [`output_02_concurrency.txt`](output_02_concurrency.txt) | Lost update, locking, isolation levels, deadlock |

## 1. The transfer procedure

A transfer debits one account, credits another and writes a ledger row. These are three writes that must succeed or fail **as a unit**. `transfer_funds()`:

1. Locks **both** account rows with `SELECT … FOR UPDATE` **in ascending `account_id` order**, which prevents deadlocks.
2. Checks that both accounts are `ACTIVE` and that there are sufficient funds. It raises an exception otherwise, which aborts the whole transaction.
3. Runs both `UPDATE`s and the `INSERT INTO txn`. The `audit_log` trigger records each balance change.

## 2. Results (from the actual output files)

| Demo | What happened | ACID property shown |
|---|---|---|
| **1a COMMIT** | 25,000 moved 101 → 102. Balances went to 75,000 / 125,000 and stayed after commit. | Atomicity, Durability |
| **1b ROLLBACK** | Inside the txn, 101 showed 25,000. After `ROLLBACK` it was back to 75,000. | Atomicity |
| **1c Failed transfer** | Request of 1,000,000 > balance 75,000. The exception aborted the txn, PostgreSQL turned `COMMIT` into `ROLLBACK`, and no balances changed. | Atomicity, Consistency (`balance >= 0`) |
| **1d SAVEPOINT** | In a batch of 3 payments, the bad line was rolled back to the savepoint and the other 2 committed. | Partial rollback |
| Audit trail | `audit_log` contains only the 6 *committed* changes. The rolled-back debit is not there. | Consistency |
| **2 Lost update** | A and B both read 100,000 and both wrote 110,000. The final balance was **110,000 instead of 120,000**. | *Isolation failure* (READ COMMITTED + application-side arithmetic) |
| **3 Fix: `FOR UPDATE`** | B's lock request **blocked** until A committed. B then read 110,000, and the final balance was **120,000**. | Pessimistic concurrency control (2PL-style row locks) |
| **4 Fix: REPEATABLE READ** | B got `ERROR: could not serialize access due to concurrent update`. The final balance was 110,000: B's update was *rejected, not lost*, and the application retries it. | Optimistic / snapshot isolation (MVCC) |
| **5 Non-repeatable read** | READ COMMITTED: the auditor saw 100,000 then 95,000 in the same txn. REPEATABLE READ: 95,000 and 95,000 (stable snapshot). | Isolation levels |
| **6 Deadlock** | A locked 201→202 while B locked 202→201. PostgreSQL reported `deadlock detected` and aborted A; B committed. With `transfer_funds()` (ordered locks), **both** transfers succeeded: 101,000 / 99,000. | Deadlock detection vs. prevention |

## 3. Discussion: which control mechanism for SwiftPay?

- **Pessimistic locking (`FOR UPDATE`)** is used for transfers. Money movements on the *same* account are common: salary day, a merchant receiving many POS payments. When conflicts are frequent, waiting briefly for a lock is cheaper than aborting and retrying.
- **REPEATABLE READ / SERIALIZABLE** suits read-heavy jobs that need a consistent view, such as end-of-day reconciliation and statement generation. They also suit low-conflict updates, where the application has a retry loop for SQLSTATE `40001`.
- **READ COMMITTED alone is not safe** when the application reads a value, computes in code, and writes it back (Demo 2). Either the arithmetic happens in SQL (`balance = balance + x`), or the row is locked.
- **Deadlock prevention through a global lock order** is better than relying on the detector. The detector works, but it kills a customer's payment after a `deadlock_timeout` of 1 s.
- `txn.reference` (UNIQUE UUID) serves as an **idempotency key**. A client that retries after a timeout can't create a duplicate transfer.

## 4. How to run

```bash
export PGHOST=/tmp PGUSER=postgres
psql -d swiftpay -f 00_transfer_procedure.sql
psql -d swiftpay -f 01_commit_rollback.sql
./02_concurrency_demos.sh
```
