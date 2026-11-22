#!/usr/bin/env bash
# Runs each query with EXPLAIN (ANALYZE, BUFFERS) before and after indexing.
# Usage: ./run_benchmark.sh   (expects database "swiftpay"; PGHOST/PGUSER from env)
set -e
DB=${DB:-swiftpay}
mkdir -p plans
psql -d "$DB" -q -c "SET search_path TO swiftpay; DROP INDEX IF EXISTS idx_txn_from_created, idx_txn_to_created, idx_txn_failed_created, idx_account_customer, idx_txn_type_status_created;"
python3 - "$DB" <<'PY'
import re, subprocess, sys, json
db = sys.argv[1]
sql = open('queries.sql').read()
blocks = re.findall(r'-- (Q\d): (.*?)\n(SELECT.*?;)', sql, re.S)
def run(tag):
    res = {}
    for q, title, body in blocks:
        times = []
        for i in range(5):  # 5 runs, warm cache, keep median
            out = subprocess.run(['psql','-d',db,'-X','-q','-c',
                  'SET search_path TO swiftpay; EXPLAIN (ANALYZE, BUFFERS) ' + body],
                  capture_output=True, text=True, check=True).stdout
            times.append(float(re.search(r'Execution Time: ([\d.]+)', out).group(1)))
        open(f'plans/{q}_{tag}.txt','w').write(f'-- {q}: {title}\n-- {tag.upper()} indexing\n{body}\n\n{out}')
        res[q] = sorted(times)[2]
    return res
before = run('before')
subprocess.run(['psql','-d',db,'-q','-f','indexes.sql'], check=True)
after = run('after')
json.dump({'before':before,'after':after,'titles':{q:t for q,t,_ in blocks}}, open('results.json','w'), indent=2)
print(f"{'Query':6}{'Before (ms)':>14}{'After (ms)':>13}{'Speed-up':>10}")
for q in before:
    print(f"{q:6}{before[q]:>14.2f}{after[q]:>13.3f}{before[q]/after[q]:>9.0f}x")
PY
