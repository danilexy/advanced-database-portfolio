-- =====================================================================
-- Demo 1: COMMIT, ROLLBACK, SAVEPOINT, atomic failure
-- =====================================================================
SET search_path TO swiftpay;
\echo '=== Starting balances ==='
SELECT account_id, balance FROM account WHERE account_id IN (101,102,103) ORDER BY 1;

\echo '=== 1a. Successful transfer of 25,000 from 101 -> 102, then COMMIT ==='
BEGIN;
CALL transfer_funds(101, 102, 25000);
COMMIT;
SELECT account_id, balance FROM account WHERE account_id IN (101,102) ORDER BY 1;

\echo '=== 1b. Explicit ROLLBACK: operator debits 101 by 50,000 then cancels ==='
BEGIN;
UPDATE account SET balance = balance - 50000 WHERE account_id = 101;
SELECT account_id, balance AS balance_inside_txn FROM account WHERE account_id = 101;
ROLLBACK;
SELECT account_id, balance AS balance_after_rollback FROM account WHERE account_id = 101;

\echo '=== 1c. Atomicity: transfer of 1,000,000 fails (insufficient funds) -> whole txn aborted ==='
BEGIN;
CALL transfer_funds(101, 102, 1000000);
COMMIT;   -- PostgreSQL turns this into ROLLBACK because the txn is in an aborted state
SELECT account_id, balance FROM account WHERE account_id IN (101,102) ORDER BY 1;

\echo '=== 1d. SAVEPOINT: batch salary payment, one bad line rolled back, rest committed ==='
BEGIN;
CALL transfer_funds(103, 101, 10000);
SAVEPOINT before_bad_line;
CALL transfer_funds(103, 102, 9999999);           -- fails
ROLLBACK TO SAVEPOINT before_bad_line;
CALL transfer_funds(103, 102, 5000);
COMMIT;
SELECT account_id, balance FROM account WHERE account_id IN (101,102,103) ORDER BY 1;

\echo '=== Audit trail written by trigger (only committed changes survive) ==='
SELECT account_id, old_balance, new_balance FROM audit_log ORDER BY audit_id;
