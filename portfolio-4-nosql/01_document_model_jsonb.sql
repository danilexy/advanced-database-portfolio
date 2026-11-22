-- =====================================================================
-- Portfolio 4A - DOCUMENT model: Customer 360 profile (MongoDB-style)
-- Implemented with PostgreSQL JSONB + GIN index (document store inside an RDBMS)
-- One document = everything the mobile app home screen needs, read in ONE lookup
-- =====================================================================
SET search_path TO swiftpay;
DROP TABLE IF EXISTS customer_profile_doc;
CREATE TABLE customer_profile_doc (
    customer_id INT PRIMARY KEY,
    doc         JSONB NOT NULL
);

-- Build documents from the relational data (embedding accounts + recent txns + beneficiaries)
INSERT INTO customer_profile_doc
SELECT c.customer_id, jsonb_build_object(
  '_id', c.customer_id,
  'name', jsonb_build_object('first', c.first_name, 'last', c.last_name),
  'contact', jsonb_build_object('email', c.email, 'phone', c.phone),
  'kyc', jsonb_build_object('tier', k.tier_name, 'daily_limit', k.daily_limit),
  'branch', jsonb_build_object('name', b.branch_name, 'state', b.state),
  'accounts', (SELECT jsonb_agg(jsonb_build_object('number', a.account_number, 'type', a.account_type,
                                                   'balance', a.balance, 'status', a.status))
               FROM account a WHERE a.customer_id = c.customer_id),
  'recent_txns', (SELECT coalesce(jsonb_agg(t ORDER BY t->>'at' DESC), '[]') FROM (
        SELECT jsonb_build_object('ref', t.reference, 'type', t.txn_type, 'amount', t.amount,
                                  'status', t.status, 'at', t.created_at) t
        FROM txn t JOIN account a ON a.account_id IN (t.from_account_id, t.to_account_id)
        WHERE a.customer_id = c.customer_id ORDER BY t.created_at DESC LIMIT 5) x),
  'beneficiaries', (SELECT coalesce(jsonb_agg(jsonb_build_object('nickname', bn.nickname,
                                     'account', a.account_number)), '[]')
                    FROM beneficiary bn JOIN account a ON a.account_id = bn.account_id
                    WHERE bn.customer_id = c.customer_id),
  'preferences', CASE WHEN c.customer_id % 3 = 0
                      THEN jsonb_build_object('language','Yoruba','notifications',jsonb_build_array('sms','push'))
                      ELSE jsonb_build_object('language','English','notifications',jsonb_build_array('push')) END
)
FROM customer c JOIN kyc_tier k USING (tier_id) JOIN branch b USING (branch_id);

-- Schema flexibility: some customers have attributes others don't (no ALTER TABLE needed)
UPDATE customer_profile_doc SET doc = doc || '{"business": {"name": "Mama Put Ventures", "cac_no": "RC123456", "pos_terminals": 2}}'
WHERE customer_id % 50 = 0;

CREATE INDEX idx_profile_doc_gin ON customer_profile_doc USING GIN (doc jsonb_path_ops);
ANALYZE customer_profile_doc;

\echo '=== Sample document (customer 100) ==='
SELECT jsonb_pretty(doc) FROM customer_profile_doc WHERE customer_id = 100;

\echo '=== Query 1: containment @> - Yoruba-speaking customers with SMS alerts (uses GIN index) ==='
EXPLAIN (ANALYZE, COSTS OFF)
SELECT customer_id FROM customer_profile_doc
WHERE doc @> '{"preferences": {"language": "Yoruba", "notifications": ["sms"]}}';
SELECT count(*) AS yoruba_sms_customers FROM customer_profile_doc
WHERE doc @> '{"preferences": {"language": "Yoruba", "notifications": ["sms"]}}';

\echo '=== Query 2: customers who are businesses (attribute only exists on some documents) ==='
SELECT customer_id, doc->'business'->>'name' AS business, doc->'business'->>'pos_terminals' AS terminals
FROM customer_profile_doc WHERE doc @> '{"business": {}}' LIMIT 5;

\echo '=== Query 3: JSONPath - customers holding any account with balance > 245,000 ==='
SELECT count(*) AS rich_customers FROM customer_profile_doc
WHERE doc @? '$.accounts[*] ? (@.balance > 245000)';

\echo '=== Comparison: home-screen read, document (1 row) vs relational (4 joins) ==='
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON) SELECT doc FROM customer_profile_doc WHERE customer_id = 100;
