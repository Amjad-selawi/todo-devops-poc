#!/usr/bin/env bash
# Quick checks that a running deployment really works. Used by the pipeline and locally.
#   ./scripts/smoke-test.sh http://localhost:8080
set -euo pipefail
BASE_URL="${1:-http://localhost:8080}"

check() { echo "--> $1"; }

check "readiness: $BASE_URL/health/ready"
curl -fsS --retry 10 --retry-delay 3 --retry-all-errors "$BASE_URL/health/ready"; echo

check "info: $BASE_URL/"
curl -fsS "$BASE_URL/"; echo

check "create a todo"
curl -fsS -X POST "$BASE_URL/api/todos" -H "Content-Type: application/json" \
  -d '{"title":"smoke test","isDone":false}'; echo

check "list todos contains it"
curl -fsS "$BASE_URL/api/todos" | grep -q "smoke test"

echo "Smoke test passed"
