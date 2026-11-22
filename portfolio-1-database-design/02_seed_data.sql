-- =====================================================================
-- Portfolio 1 - Seed data (synthetic, generated with generate_series)
-- 5 000 customers, 8 750 accounts, 300 000 transactions
-- Large enough for meaningful execution plans in Portfolio 2
-- =====================================================================
SET search_path TO swiftpay;
SELECT setseed(0.42);   -- reproducible random data

INSERT INTO kyc_tier VALUES
 (1, 'TIER_1',    50000.00,   300000.00),
 (2, 'TIER_2',   200000.00,   500000.00),
 (3, 'TIER_3',  5000000.00, 100000000.00);

INSERT INTO branch(branch_name, state) VALUES
 ('Ikeja','Lagos'), ('Victoria Island','Lagos'), ('Wuse','FCT'),
 ('Garki','FCT'), ('Port Harcourt GRA','Rivers'), ('Bodija','Oyo'),
 ('Nassarawa','Kano'), ('Independence Layout','Enugu');

INSERT INTO customer(first_name, last_name, email, phone, bvn, date_of_birth, tier_id, branch_id, created_at)
SELECT
  (ARRAY['Chinedu','Aisha','Tunde','Ngozi','Emeka','Fatima','Bola','Ifeoma','Musa','Kemi',
         'Obinna','Zainab','Segun','Amaka','Ibrahim','Funmi'])[1 + (g % 16)],
  (ARRAY['Okafor','Bello','Adeyemi','Eze','Ibrahim','Ogunleye','Nwosu','Abubakar',
         'Balogun','Okonkwo','Danjuma','Adebayo'])[1 + ((g / 16) % 12)],
  'user' || g || '@swiftpay.ng',
  '080' || lpad(g::text, 8, '0'),
  lpad((22100000000 + g)::text, 11, '0'),
  DATE '1960-01-01' + (random() * 15000)::int,
  1 + (random() * 2)::int,
  1 + (random() * 7)::int,
  now() - (random() * 900 || ' days')::interval
FROM generate_series(1, 5000) g;

-- every customer gets a WALLET; ~half also get SAVINGS; ~quarter CURRENT
INSERT INTO account(account_number, customer_id, account_type, balance, opened_at)
SELECT lpad((3000000000 + row_number() OVER ())::text, 10, '0'), c.customer_id, t.account_type,
       round((random() * 250000)::numeric, 2), c.created_at
FROM customer c
CROSS JOIN LATERAL (
    SELECT 'WALLET' AS account_type
    UNION ALL SELECT 'SAVINGS' WHERE c.customer_id % 2 = 0
    UNION ALL SELECT 'CURRENT' WHERE c.customer_id % 4 = 0
) t;

UPDATE account SET status = 'FROZEN' WHERE account_id % 97 = 0;

-- 300 000 transactions across ~2 years (trigger not fired: we insert into txn only)
INSERT INTO txn(txn_type, from_account_id, to_account_id, amount, status, channel, created_at)
SELECT tt,
       CASE WHEN tt = 'DEPOSIT' THEN NULL ELSE a1 END,
       CASE WHEN tt = 'WITHDRAWAL' THEN NULL
            WHEN tt = 'TRANSFER' AND a2 = a1 THEN (a1 % m) + 1
            ELSE a2 END,
       round((100 + random() * 49900)::numeric, 2),
       CASE WHEN random() < 0.03 THEN 'FAILED' ELSE 'SUCCESS' END,
       (ARRAY['APP','USSD','POS','WEB'])[1 + (random() * 3)::int],
       now() - (random() * 730 || ' days')::interval
FROM (
  SELECT (ARRAY['DEPOSIT','WITHDRAWAL','TRANSFER','TRANSFER'])[1 + (random() * 3)::int] AS tt,
         1 + (random() * (m - 1))::int AS a1,
         1 + (random() * (m - 1))::int AS a2,
         m
  FROM generate_series(1, 300000), (SELECT max(account_id) AS m FROM account) mx
) s;

INSERT INTO beneficiary(customer_id, account_id, nickname)
SELECT DISTINCT ON (c, a) c, a, 'Saved #' || a
FROM (SELECT 1 + (random() * 4999)::int c, 1 + (random() * (m - 1))::int a
      FROM generate_series(1, 8000), (SELECT max(account_id) AS m FROM account) mx) s;

ANALYZE;
