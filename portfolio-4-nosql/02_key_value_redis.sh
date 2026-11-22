#!/usr/bin/env bash
# =====================================================================
# Portfolio 4B - KEY-VALUE model in Redis for SwiftPay's hot-path data
# Key design:   <entity>:<id>[:<attribute>]
#   session:<token>              STRING  (TTL 15 min)   - login session
#   acct:<number>:bal            STRING  (TTL 60 s)     - cache-aside balance
#   limit:<customer>:<yyyymmdd>  STRING counter (TTL 24h) - KYC daily spend
#   lb:receivers:<yyyymm>        SORTED SET             - top receiving accounts
#   stream:txn                   STREAM                 - event feed for fraud/notifications
# Usage: PGHOST=... PGUSER=... ./02_key_value_redis.sh
# =====================================================================
R="redis-cli --no-raw"
PSQL="psql -d ${DB:-swiftpay} -X -At"
$R FLUSHDB > /dev/null
echo "=== 1. Session store with automatic expiry (TTL) ==="
$R SET session:9f2c1ab7 '{"customer_id":100,"device":"Android","ip":"102.89.4.11"}' EX 900
$R GET session:9f2c1ab7
echo -n "TTL (s): "; $R TTL session:9f2c1ab7

echo; echo "=== 2. Cache-aside for balance lookups (USSD *123#) ==="
ACCT=3000000173
echo -n "cache lookup: "; $R GET acct:$ACCT:bal
echo "-> MISS, read from PostgreSQL and populate cache with 60 s TTL"
BAL=$($PSQL -c "SELECT balance FROM swiftpay.account WHERE account_number='$ACCT'")
$R SET acct:$ACCT:bal $BAL EX 60 > /dev/null
echo -n "cache lookup: "; $R GET acct:$ACCT:bal; echo "-> HIT (no database round-trip)"
echo "-> after a transfer the app DELetes the key (invalidation) so the next read is fresh:"
$R DEL acct:$ACCT:bal

echo; echo "=== 3. Atomic KYC daily-limit counter (TIER_1 limit = 50,000) ==="
KEY=limit:100:$(date +%Y%m%d)
# Lua script runs atomically inside Redis: check + increment cannot be interleaved by another client
LUA='local t = tonumber(redis.call("GET", KEYS[1]) or "0") + tonumber(ARGV[1])
     if t > tonumber(ARGV[2]) then return "REJECTED (would be " .. t .. ")" end
     redis.call("INCRBYFLOAT", KEYS[1], ARGV[1]); redis.call("EXPIRE", KEYS[1], 86400)
     return "ALLOWED (running total " .. t .. ")"'
for AMT in 20000 25000 8000 5000; do
  echo "spend $AMT -> $($R --raw EVAL "$LUA" 1 $KEY $AMT 50000)"
done
echo "(The Lua script is atomic, so two concurrent requests can never both pass the check)"

echo; echo "=== 4. Sorted set: top 5 receiving accounts this month (loaded from PostgreSQL) ==="
$PSQL -F' ' -c "SELECT sum(amount), to_account_id FROM swiftpay.txn WHERE txn_type='TRANSFER' AND status='SUCCESS'
                AND created_at >= date_trunc('month', now()) GROUP BY to_account_id" |
  while read S A; do echo "ZADD lb:receivers:$(date +%Y%m) $S acct:$A"; done | $R > /dev/null
echo -n "members: "; $R ZCARD lb:receivers:$(date +%Y%m)
$R ZREVRANGE lb:receivers:$(date +%Y%m) 0 4 WITHSCORES
echo "live update when a new transfer of 500,000 lands on acct:42 ->"
$R ZINCRBY lb:receivers:$(date +%Y%m) 500000 acct:42 > /dev/null
echo -n "acct:42 rank (0 = top): "; $R ZREVRANK lb:receivers:$(date +%Y%m) acct:42

echo; echo "=== 5. Stream: append-only transaction events for the fraud & SMS consumers ==="
$R XADD stream:txn '*' ref a23aa687 type TRANSFER from 3000000173 to 3000004034 amount 6284.42 > /dev/null
$R XADD stream:txn '*' ref 9b1e2f00 type WITHDRAWAL from 3000000174 amount 49000 channel POS > /dev/null
$R XGROUP CREATE stream:txn fraud-svc 0 > /dev/null
$R XREADGROUP GROUP fraud-svc worker-1 COUNT 10 STREAMS stream:txn '>'

echo; echo "=== Keyspace summary ==="
$R --scan | sort
