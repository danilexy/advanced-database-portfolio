-- =====================================================================
-- Portfolio 2 - Indexes added after analysing the baseline plans
-- =====================================================================
SET search_path TO swiftpay;

-- Q1: composite indexes so each OR-branch is an index scan already sorted by date
CREATE INDEX idx_txn_from_created ON txn (from_account_id, created_at DESC);
CREATE INDEX idx_txn_to_created   ON txn (to_account_id,   created_at DESC);

-- Q2: PARTIAL index - only ~3% of rows are FAILED, so index just those
CREATE INDEX idx_txn_failed_created ON txn (created_at) WHERE status = 'FAILED';

-- Q3: phone already has a UNIQUE index (from the constraint); add FK index on account
CREATE INDEX idx_account_customer ON account (customer_id);

-- Q4: covering index for the report filter (type, status, date) + INCLUDE columns
CREATE INDEX idx_txn_type_status_created ON txn (txn_type, status, created_at)
       INCLUDE (from_account_id, amount);

ANALYZE txn; ANALYZE account;
