#!/usr/bin/env bash
# =====================================================================
# Portfolio 3 - Concurrency demos with two real concurrent sessions (A and B)
# Each session is a separate psql process; pg_sleep() forces the interleaving.
# Usage: PGHOST=... PGUSER=... DB=swiftpay ./02_concurrency_demos.sh
# =====================================================================
DB=${DB:-swiftpay}
PSQL="psql -d $DB -X -q -v ON_ERROR_STOP=0"
reset() { $PSQL -c "UPDATE swiftpay.account SET balance = 100000 WHERE account_id IN (201,202);" ; }
bal()   { $PSQL -c "SELECT account_id, balance FROM swiftpay.account WHERE account_id IN (201,202) ORDER BY 1;"; }
tag()   { sed "s/^/[$1] /"; }

echo "################ DEMO 2: LOST UPDATE (naive read-modify-write, READ COMMITTED) ################"
echo "Two cashiers each credit account 201 with 10,000 at the same moment. Expected final: 120,000"
reset
$PSQL <<'S' 2>&1 | tag A &
BEGIN;
SELECT balance AS a_reads FROM swiftpay.account WHERE account_id = 201;
SELECT pg_sleep(1);                      -- app computes new value: 100000 + 10000
UPDATE swiftpay.account SET balance = 110000 WHERE account_id = 201;
COMMIT;
S
sleep 0.3
$PSQL <<'S' 2>&1 | tag B
BEGIN;
SELECT balance AS b_reads FROM swiftpay.account WHERE account_id = 201;
SELECT pg_sleep(1.5);
UPDATE swiftpay.account SET balance = 110000 WHERE account_id = 201;   -- also 100000 + 10000
COMMIT;
S
wait; echo "RESULT:"; bal; echo ">>> Account 201 = 110,000, not 120,000: one credit of 10,000 was LOST."

echo; echo "################ DEMO 3: FIX 1 - pessimistic locking with SELECT ... FOR UPDATE ################"
reset
$PSQL <<'S' 2>&1 | tag A &
BEGIN;
SELECT balance AS a_reads FROM swiftpay.account WHERE account_id = 201 FOR UPDATE;
SELECT pg_sleep(1);
UPDATE swiftpay.account SET balance = balance + 10000 WHERE account_id = 201;
SELECT now()::time AS a_commits_at; COMMIT;
S
sleep 0.3
$PSQL <<'S' 2>&1 | tag B
BEGIN;
SELECT now()::time AS b_requests_lock_at;
SELECT balance AS b_reads_after_wait FROM swiftpay.account WHERE account_id = 201 FOR UPDATE;  -- BLOCKS until A commits
UPDATE swiftpay.account SET balance = balance + 10000 WHERE account_id = 201;
COMMIT;
S
wait; echo "RESULT:"; bal; echo ">>> B waited for A's row lock, then read 110,000. Final = 120,000 (correct)."

echo; echo "################ DEMO 4: FIX 2 - optimistic, REPEATABLE READ detects the conflict ################"
reset
$PSQL <<'S' 2>&1 | tag A &
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance AS a_reads FROM swiftpay.account WHERE account_id = 201;
SELECT pg_sleep(1);
UPDATE swiftpay.account SET balance = balance + 10000 WHERE account_id = 201;
COMMIT;
S
sleep 0.3
$PSQL <<'S' 2>&1 | tag B
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance AS b_reads FROM swiftpay.account WHERE account_id = 201;
SELECT pg_sleep(1.5);
UPDATE swiftpay.account SET balance = balance + 10000 WHERE account_id = 201;  -- conflict -> error
COMMIT;
S
wait; echo "RESULT:"; bal; echo ">>> B aborted with 'could not serialize access'; the application must RETRY B. No silent lost update."

echo; echo "################ DEMO 5: NON-REPEATABLE READ - READ COMMITTED vs REPEATABLE READ ################"
reset
for LEVEL in "READ COMMITTED" "REPEATABLE READ"; do
  echo "--- Auditor session A at $LEVEL reads account 201 twice; B commits a withdrawal in between ---"
  $PSQL <<S 2>&1 | tag A &
BEGIN ISOLATION LEVEL $LEVEL;
SELECT balance AS first_read FROM swiftpay.account WHERE account_id = 201;
SELECT pg_sleep(1);
SELECT balance AS second_read FROM swiftpay.account WHERE account_id = 201;
COMMIT;
S
  sleep 0.3
  $PSQL -c "UPDATE swiftpay.account SET balance = balance - 5000 WHERE account_id = 201;" 2>&1 | tag B
  wait
done
echo ">>> READ COMMITTED: the two reads differ. REPEATABLE READ: both reads see the same snapshot."

echo; echo "################ DEMO 6: DEADLOCK from inconsistent lock order, and the fix ################"
reset
$PSQL <<'S' 2>&1 | tag A &
BEGIN;
UPDATE swiftpay.account SET balance = balance - 1000 WHERE account_id = 201;   -- locks 201
SELECT pg_sleep(1);
UPDATE swiftpay.account SET balance = balance + 1000 WHERE account_id = 202;   -- wants 202
COMMIT;
S
sleep 0.3
$PSQL <<'S' 2>&1 | tag B
BEGIN;
UPDATE swiftpay.account SET balance = balance - 2000 WHERE account_id = 202;   -- locks 202
SELECT pg_sleep(1);
UPDATE swiftpay.account SET balance = balance + 2000 WHERE account_id = 201;   -- wants 201 -> cycle
COMMIT;
S
wait; echo "RESULT:"; bal
echo ">>> PostgreSQL's deadlock detector aborted one transaction. Now the same two transfers through transfer_funds() (ordered locking):"
reset
$PSQL -c "CALL swiftpay.transfer_funds(201, 202, 1000);" 2>&1 | tag A &
$PSQL -c "CALL swiftpay.transfer_funds(202, 201, 2000);" 2>&1 | tag B
wait; echo "RESULT:"; bal; echo ">>> Both succeed (201 = 101,000, 202 = 99,000). No deadlock, because both lock 201 before 202."
