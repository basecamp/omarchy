#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

missing=$(HOME="$TEST_HOME" python3 "$ROOT/shell/plugins/model-usage/scripts/cursor_usage_scanner.py" \
  --state-db "$TEST_HOME/missing-state.vscdb")

[[ $(jq -r '.usageStatusText' <<<"$missing") == "Cursor unavailable" ]] ||
  fail "Cursor scanner reports missing state database" "$missing"
pass "Cursor scanner reports missing state database"

[[ $(jq -r '.authHelpText' <<<"$missing") == *"not found"* ]] ||
  fail "Cursor scanner explains missing state database" "$missing"
pass "Cursor scanner explains missing state database"

state_db="$TEST_HOME/state.vscdb"
python3 - "$state_db" <<'PY'
import sqlite3
import sys

path = sys.argv[1]
conn = sqlite3.connect(path)
conn.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)")
conn.execute(
  "INSERT INTO ItemTable(key, value) VALUES (?, ?)",
  ("cursorAuth/accessToken", "test-token"),
)
conn.execute(
  "INSERT INTO ItemTable(key, value) VALUES (?, ?)",
  ("cursorAuth/stripeMembershipType", "pro"),
)
conn.commit()
conn.close()
PY

# Read-only credential load + plan mapping without hitting the network.
mapped=$(python3 - "$ROOT/shell/plugins/model-usage/scripts/cursor_usage_scanner.py" "$state_db" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

scanner_path = Path(sys.argv[1])
state_db = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("cursor_usage_scanner", scanner_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

credentials, error = mod.load_credentials(state_db)
if error is not None:
  print(json.dumps(error))
  raise SystemExit(1)

payload = {
  "billingCycleEnd": 1893456000000,
  "membershipType": "pro",
  "planUsage": {
    "autoPercentUsed": 12.5,
    "apiPercentUsed": 40,
  },
}
print(json.dumps(mod.build_rate_limits(credentials, payload), separators=(",", ":")))
PY
)

[[ $(jq -r '.rateLimitLabel' <<<"$mapped") == "Cursor Models" ]] ||
  fail "Cursor scanner labels auto pool as Cursor Models" "$mapped"
pass "Cursor scanner labels auto pool as Cursor Models"

[[ $(jq -r '.secondaryRateLimitLabel' <<<"$mapped") == "Other Models" ]] ||
  fail "Cursor scanner labels api pool as Other Models" "$mapped"
pass "Cursor scanner labels api pool as Other Models"

[[ $(jq -r '.rateLimitPercent' <<<"$mapped") == "0.125" ]] ||
  fail "Cursor scanner converts auto percent to a fraction" "$mapped"
pass "Cursor scanner converts auto percent to a fraction"

[[ $(jq -r '.secondaryRateLimitPercent' <<<"$mapped") == "0.4" ]] ||
  fail "Cursor scanner converts api percent to a fraction" "$mapped"
pass "Cursor scanner converts api percent to a fraction"

[[ $(jq -r '.tierLabel' <<<"$mapped") == "Pro" ]] ||
  fail "Cursor scanner formats membership tier" "$mapped"
pass "Cursor scanner formats membership tier"

[[ $(jq -r '.rateLimitResetAt' <<<"$mapped") == $(jq -r '.secondaryRateLimitResetAt' <<<"$mapped") ]] ||
  fail "Cursor scanner shares one billing-cycle reset across pools" "$mapped"
pass "Cursor scanner shares one billing-cycle reset across pools"

[[ $(jq -c '.recentDays' <<<"$mapped") == "[]" && $(jq -c '.modelUsage' <<<"$mapped") == "{}" ]] ||
  fail "Cursor scanner keeps day/model charts empty" "$mapped"
pass "Cursor scanner keeps day/model charts empty"
