#!/bin/bash
# Creates the replication role and allows it in pg_hba.conf (runs on first start of pg-primary)
set -e
psql -v ON_ERROR_STOP=1 -U postgres <<SQL
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${POSTGRES_PASSWORD}';
SQL
echo "host replication replicator all scram-sha-256" >> "$PGDATA/pg_hba.conf"
