-- =====================================================================
-- Portfolio 4C - GRAPH model: money-mule / circular-transfer detection
-- Nodes = accounts, edges = successful transfers in the last 24 h.
-- A graph DB (e.g. Neo4j) would express this as:
--   MATCH p=(a:Account)-[:SENT*3..5]->(a) RETURN p
-- Here the same traversal is run with a recursive CTE in PostgreSQL.
-- =====================================================================
SET search_path TO swiftpay;
-- Plant a suspicious ring: 7001 -> 7002 -> 7003 -> 7004 -> 7001 within minutes
DELETE FROM txn WHERE channel = 'WEB' AND amount = 480000;
INSERT INTO txn(txn_type, from_account_id, to_account_id, amount, channel, created_at) VALUES
 ('TRANSFER', 7001, 7002, 480000, 'WEB', now() - interval '40 min'),
 ('TRANSFER', 7002, 7003, 480000, 'WEB', now() - interval '30 min'),
 ('TRANSFER', 7003, 7004, 480000, 'WEB', now() - interval '20 min'),
 ('TRANSFER', 7004, 7001, 480000, 'WEB', now() - interval '10 min');

WITH RECURSIVE edges AS (
    SELECT from_account_id AS src, to_account_id AS dst, amount, created_at
    FROM txn WHERE txn_type = 'TRANSFER' AND status = 'SUCCESS'
      AND created_at >= now() - interval '24 hours' AND amount >= 100000
), walk(start, curr, path, hops, last_at) AS (
    SELECT src, dst, ARRAY[src, dst], 1, created_at FROM edges
    UNION ALL
    SELECT w.start, e.dst, w.path || e.dst, w.hops + 1, e.created_at
    FROM walk w JOIN edges e ON e.src = w.curr AND e.created_at > w.last_at   -- money must flow forward in time
    WHERE w.hops < 5 AND (e.dst = w.start OR NOT e.dst = ANY(w.path))
)
SELECT path AS suspicious_cycle, hops
FROM walk WHERE curr = start AND start = (SELECT min(x) FROM unnest(path) x);   -- report each cycle once
