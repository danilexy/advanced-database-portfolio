-- =====================================================================
-- Portfolio 2 - Q4 optimisation step 2: pre-aggregated materialized view
-- An index alone cannot help Q4 much: ~37k rows must still be joined,
-- sorted and aggregated. The report is read many times a day but the
-- underlying data only needs to be fresh to the last refresh (e.g. hourly).
-- =====================================================================
SET search_path TO swiftpay;
DROP MATERIALIZED VIEW IF EXISTS mv_branch_monthly_transfers;
CREATE MATERIALIZED VIEW mv_branch_monthly_transfers AS
SELECT b.branch_name, date_trunc('month', t.created_at) AS month,
       count(*) AS transfers, sum(t.amount) AS total_value
FROM txn t
JOIN account  a ON a.account_id  = t.from_account_id
JOIN customer c ON c.customer_id = a.customer_id
JOIN branch   b ON b.branch_id   = c.branch_id
WHERE t.txn_type = 'TRANSFER' AND t.status = 'SUCCESS'
GROUP BY b.branch_name, month;
CREATE UNIQUE INDEX ON mv_branch_monthly_transfers (branch_name, month);  -- allows REFRESH ... CONCURRENTLY

-- Scheduled refresh (e.g. via pg_cron or an hourly job), non-blocking for readers:
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_branch_monthly_transfers;

-- Q4 rewritten against the view:
EXPLAIN (ANALYZE, BUFFERS)
SELECT branch_name, month, transfers, total_value
FROM mv_branch_monthly_transfers
WHERE month >= date_trunc('month', now() - INTERVAL '6 months')
ORDER BY month, total_value DESC;
