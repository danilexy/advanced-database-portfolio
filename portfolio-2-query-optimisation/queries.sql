-- =====================================================================
-- Portfolio 2 - Business queries for SwiftPay
-- =====================================================================
SET search_path TO swiftpay;

-- Q1: Account statement - last 20 transactions touching account 1234 (customer app screen)
SELECT txn_id, txn_type, from_account_id, to_account_id, amount, status, created_at
FROM txn
WHERE from_account_id = 1234 OR to_account_id = 1234
ORDER BY created_at DESC
LIMIT 20;

-- Q2: Failed transactions in the last 7 days, for the reversal job
SELECT txn_id, reference, from_account_id, amount, created_at
FROM txn
WHERE status = 'FAILED' AND created_at >= now() - INTERVAL '7 days';

-- Q3: Customer lookup by phone number (USSD login)
SELECT c.customer_id, c.first_name, c.last_name, a.account_number, a.balance
FROM customer c JOIN account a ON a.customer_id = c.customer_id
WHERE c.phone = '08000002500';

-- Q4: Monthly transfer volume per branch for the last 6 months (management report)
SELECT b.branch_name, date_trunc('month', t.created_at) AS month,
       count(*) AS transfers, sum(t.amount) AS total_value
FROM txn t
JOIN account  a ON a.account_id  = t.from_account_id
JOIN customer c ON c.customer_id = a.customer_id
JOIN branch   b ON b.branch_id   = c.branch_id
WHERE t.txn_type = 'TRANSFER' AND t.status = 'SUCCESS'
  AND t.created_at >= now() - INTERVAL '6 months'
GROUP BY b.branch_name, month
ORDER BY month, total_value DESC;
