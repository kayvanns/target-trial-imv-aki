#!/usr/bin/env bash
# Rebuild every table in order, then rerun every check (refreshes results/).
# Usage:  bash scripts/run_all.sh            # pipeline + checks
#         bash scripts/run_all.sh pipeline   # tables only
#         bash scripts/run_all.sh checks     # checks only
set -euo pipefail
cd "$(dirname "$0")/.."

what="${1:-all}"

if [[ "$what" == "all" || "$what" == "pipeline" ]]; then
  for f in sql/pipeline/*.sql; do
    python scripts/run_sql.py "$f"
  done
fi

if [[ "$what" == "all" || "$what" == "checks" ]]; then
  for f in sql/checks/*.sql; do
    python scripts/run_sql.py "$f"
  done
fi
