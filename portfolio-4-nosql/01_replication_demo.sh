#!/usr/bin/env bash
# =====================================================================
# Portfolio 5A - PostgreSQL streaming replication (primary :5432 -> replica :5433)
# Setup (done once, see setup_replication.md):
#   pg_basebackup -D replica -R -X stream -C -S replica1_slot --checkpoint=fast
#   pg_ctl -D replica -o "-p 5433" start
# =====================================================================
PRI="psql -h ${PGHOST:-/tmp} -p 5432 -U postgres -d swiftpay -X"
REP="psql -h ${PGHOST:-/tmp} -p 5433 -U postgres -d swiftpay -X"

echo "=== 1. Topology: which node is in recovery (read-only standby)? ==="
echo -n "primary :5432 in_recovery = "; $PRI -Atc "SELECT pg_is_in_recovery()"
echo -n "replica :5433 in_recovery = "; $REP -Atc "SELECT pg_is_in_recovery()"

echo; echo "=== 2. Replication status seen from the primary (pg_stat_replication) ==="
$PRI -c "SELECT application_name, state, sync_state, sent_lsn, replay_lsn,
                pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes, replay_lag
         FROM pg_stat_replication;"
$PRI -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"

echo "=== 3. Write on primary -> read on replica ==="
$PRI -q -c "CALL swiftpay.transfer_funds(301, 302, 7500, 'WEB');"
REF=$($PRI -Atc "SELECT reference FROM swiftpay.txn ORDER BY txn_id DESC LIMIT 1")
echo "primary committed transfer ref=$REF at $($PRI -Atc 'SELECT clock_timestamp()::time')"
for i in 1 2 3 4 5; do
  FOUND=$($REP -Atc "SELECT count(*) FROM swiftpay.txn WHERE reference = '$REF'")
  echo "replica check #$i at $($REP -Atc 'SELECT clock_timestamp()::time') -> rows found: $FOUND"
  [ "$FOUND" = "1" ] && break; sleep 0.05
done
echo -n "replica replay delay: "; $REP -Atc "SELECT coalesce(now() - pg_last_xact_replay_timestamp(), '0')::text"

echo; echo "=== 4. Replica is read-only (writes must go to the primary) ==="
$REP -c "UPDATE swiftpay.account SET balance = 0 WHERE account_id = 301;" 2>&1

echo; echo "=== 5. Read scaling: heavy report runs on the replica, primary stays free for payments ==="
$REP -c "SELECT channel, count(*) AS txns, round(sum(amount)/1e6, 1) AS value_millions
         FROM swiftpay.txn WHERE status = 'SUCCESS' GROUP BY channel ORDER BY txns DESC;"

echo "=== 6. Failover: primary 'crashes', replica is promoted ==="
su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg/primary -m immediate stop" >/dev/null 2>&1
echo -n "primary reachable? "; $PRI -Atc "SELECT 1" 2>/dev/null || echo "NO (down)"
$REP -Atc "SELECT pg_promote(wait => true)" >/dev/null && echo "pg_promote() executed on :5433"
echo -n "replica :5433 in_recovery = "; $REP -Atc "SELECT pg_is_in_recovery()"
$REP -q -c "CALL swiftpay.transfer_funds(302, 301, 2500, 'APP');" && echo "new primary :5433 accepted a write (transfer 302 -> 301)"
$REP -c "SELECT account_id, balance FROM swiftpay.account WHERE account_id IN (301,302) ORDER BY 1;"
echo "No committed transfer was lost: the transfer from step 3 is on the new primary:"
$REP -c "SELECT txn_id, from_account_id, to_account_id, amount FROM swiftpay.txn WHERE reference = '$REF';"
