#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

make_state_db() {
  local path="$1"
  shift
  python3 - "$path" "$@" <<'PY'
import sqlite3
import sys

path = sys.argv[1]
pairs = list(zip(sys.argv[2::2], sys.argv[3::2]))
conn = sqlite3.connect(path)
conn.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)")
for key, value in pairs:
  conn.execute("INSERT INTO ItemTable(key, value) VALUES (?, ?)", (key, value))
conn.commit()
conn.close()
PY
}

missing=$(HOME="$TEST_HOME" python3 "$ROOT/shell/plugins/model-usage/scripts/cursor_usage_scanner.py" \
  --state-db "$TEST_HOME/missing-state.vscdb")

[[ $(jq -r '.usageStatusText' <<<"$missing") == "Cursor unavailable" ]] ||
  fail "Cursor scanner reports missing state database" "$missing"
pass "Cursor scanner reports missing state database"

[[ $(jq -r '.authHelpText' <<<"$missing") == *"not found"* ]] ||
  fail "Cursor scanner explains missing state database" "$missing"
pass "Cursor scanner explains missing state database"

no_token_db="$TEST_HOME/no-token.vscdb"
make_state_db "$no_token_db" \
  "cursorAuth/stripeMembershipType" "pro"

no_token=$(HOME="$TEST_HOME" python3 "$ROOT/shell/plugins/model-usage/scripts/cursor_usage_scanner.py" \
  --state-db "$no_token_db")

[[ $(jq -r '.usageStatusText' <<<"$no_token") == "Sign in to Cursor" ]] ||
  fail "Cursor scanner reports missing access token" "$no_token"
pass "Cursor scanner reports missing access token"

[[ $(jq -r '.authHelpText' <<<"$no_token") == *"sign in"* ]] ||
  fail "Cursor scanner explains missing access token" "$no_token"
pass "Cursor scanner explains missing access token"

[[ $(jq -r '.rateLimitPercent' <<<"$no_token") == "-1" ]] ||
  fail "Cursor scanner keeps meters unset without a token" "$no_token"
pass "Cursor scanner keeps meters unset without a token"

state_db="$TEST_HOME/state.vscdb"
make_state_db "$state_db" \
  "cursorAuth/accessToken" "test-token" \
  "cursorAuth/stripeMembershipType" "pro"

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

[[ $(jq -r '.hasLocalStats' <<<"$mapped") == "false" ]] ||
  fail "Cursor scanner reports hasLocalStats false for meters-only" "$mapped"
pass "Cursor scanner reports hasLocalStats false for meters-only"

[[ $(jq -r '.hasLocalStats' <<<"$missing") == "false" && $(jq -r '.hasLocalStats' <<<"$no_token") == "false" ]] ||
  fail "Cursor scanner keeps hasLocalStats false without credentials" "$missing $no_token"
pass "Cursor scanner keeps hasLocalStats false without credentials"

helpers=$(python3 - "$ROOT/shell/plugins/model-usage/scripts/cursor_usage_scanner.py" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

scanner_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("cursor_usage_scanner", scanner_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

print(json.dumps({
  "ms": mod.to_epoch_ms(1893456000000),
  "seconds": mod.to_epoch_ms(1893456000),
  "reset": mod.parse_billing_cycle_end(1893456000000),
  "bad": mod.parse_billing_cycle_end("not-a-date"),
  "empty": mod.parse_billing_cycle_end(None),
  "oor": mod.parse_billing_cycle_end(10 ** 20),
}))
PY
)

[[ $(jq -r '.ms' <<<"$helpers") == "1893456000000" ]] ||
  fail "Cursor scanner keeps millisecond timestamps as milliseconds" "$helpers"
pass "Cursor scanner keeps millisecond timestamps as milliseconds"

[[ $(jq -r '.seconds' <<<"$helpers") == "1893456000000" ]] ||
  fail "Cursor scanner converts second timestamps to milliseconds" "$helpers"
pass "Cursor scanner converts second timestamps to milliseconds"

[[ $(jq -r '.reset' <<<"$helpers") == "2030-01-01T00:00:00+00:00" ]] ||
  fail "Cursor scanner formats parseable billing cycle ends as ISO" "$helpers"
pass "Cursor scanner formats parseable billing cycle ends as ISO"

[[ $(jq -r '.bad' <<<"$helpers") == "" && $(jq -r '.empty' <<<"$helpers") == "" ]] ||
  fail "Cursor scanner clears unparseable billing cycle ends" "$helpers"
pass "Cursor scanner clears unparseable billing cycle ends"

[[ $(jq -r '.oor' <<<"$helpers") == "" ]] ||
  fail "Cursor scanner clears out-of-range billing cycle ends" "$helpers"
pass "Cursor scanner clears out-of-range billing cycle ends"

bad_payload=$(python3 - "$ROOT/shell/plugins/model-usage/scripts/cursor_usage_scanner.py" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

scanner_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("cursor_usage_scanner", scanner_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

print(json.dumps(mod.build_rate_limits({"accessToken": "x", "membershipType": "pro"}, None)))
PY
)

[[ $(jq -r '.usageStatusText' <<<"$bad_payload") == "Cursor limits unavailable" ]] ||
  fail "Cursor scanner rejects a null usage payload" "$bad_payload"
pass "Cursor scanner rejects a null usage payload"

[[ $(jq -r '.authHelpText' <<<"$bad_payload") == *"JSON object"* ]] ||
  fail "Cursor scanner explains a non-object usage payload" "$bad_payload"
pass "Cursor scanner explains a non-object usage payload"

[[ $(jq -r '.rateLimitPercent' <<<"$bad_payload") == "-1" ]] ||
  fail "Cursor scanner keeps meters unset for a non-object usage payload" "$bad_payload"
pass "Cursor scanner keeps meters unset for a non-object usage payload"

# Full scanner path with a fake successful GetCurrentPeriodUsage response.
http_ok=$(python3 - "$ROOT/shell/plugins/model-usage/scripts/cursor_usage_scanner.py" "$state_db" <<'PY'
import importlib.util
import io
import json
import sys
from contextlib import redirect_stdout
from pathlib import Path

scanner_path = Path(sys.argv[1])
state_db = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("cursor_usage_scanner", scanner_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

payload = {
  "billingCycleEnd": 1893456000000,
  "membershipType": "pro",
  "planUsage": {
    "autoPercentUsed": 12.5,
    "apiPercentUsed": 40,
  },
}
body = json.dumps(payload).encode("utf-8")


class FakeResponse:
  def __init__(self, data, status=200):
    self._data = data
    self.status = status

  def read(self):
    return self._data

  def __enter__(self):
    return self

  def __exit__(self, exc_type, exc, tb):
    return False


def fake_urlopen(request, timeout=None):
  assert "GetCurrentPeriodUsage" in request.full_url
  assert request.get_header("Authorization") == "Bearer test-token"
  return FakeResponse(body)


mod.urllib.request.urlopen = fake_urlopen
buf = io.StringIO()
with redirect_stdout(buf):
  code = mod.main(["--state-db", str(state_db)])
if code != 0:
  raise SystemExit(f"main exited {code}")
print(buf.getvalue().strip())
PY
)

[[ $(jq -r '.rateLimitLabel' <<<"$http_ok") == "Cursor Models" ]] ||
  fail "Cursor scanner maps mocked period usage to Cursor Models" "$http_ok"
pass "Cursor scanner maps mocked period usage to Cursor Models"

[[ $(jq -r '.secondaryRateLimitLabel' <<<"$http_ok") == "Other Models" ]] ||
  fail "Cursor scanner maps mocked period usage to Other Models" "$http_ok"
pass "Cursor scanner maps mocked period usage to Other Models"

[[ $(jq -r '.rateLimitPercent' <<<"$http_ok") == "0.125" && $(jq -r '.secondaryRateLimitPercent' <<<"$http_ok") == "0.4" ]] ||
  fail "Cursor scanner maps mocked period usage percents" "$http_ok"
pass "Cursor scanner maps mocked period usage percents"

[[ $(jq -r '.tierLabel' <<<"$http_ok") == "Pro" ]] ||
  fail "Cursor scanner maps mocked period usage tier" "$http_ok"
pass "Cursor scanner maps mocked period usage tier"

[[ $(jq -r '.rateLimitResetAt' <<<"$http_ok") == "2030-01-01T00:00:00+00:00" ]] ||
  fail "Cursor scanner maps mocked billing cycle end" "$http_ok"
pass "Cursor scanner maps mocked billing cycle end"

[[ $(jq -r '.hasLocalStats' <<<"$http_ok") == "false" ]] ||
  fail "Cursor scanner keeps hasLocalStats false on successful period usage" "$http_ok"
pass "Cursor scanner keeps hasLocalStats false on successful period usage"

# Auth failure from GetCurrentPeriodUsage (HTTP 401).
auth_fail=$(python3 - "$ROOT/shell/plugins/model-usage/scripts/cursor_usage_scanner.py" "$state_db" <<'PY'
import importlib.util
import io
import json
import sys
import urllib.error
from contextlib import redirect_stdout
from pathlib import Path

scanner_path = Path(sys.argv[1])
state_db = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("cursor_usage_scanner", scanner_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def fake_urlopen(request, timeout=None):
  raise urllib.error.HTTPError(
    request.full_url,
    401,
    "Unauthorized",
    hdrs=None,
    fp=io.BytesIO(b'{"error":"unauthorized"}'),
  )


mod.urllib.request.urlopen = fake_urlopen
buf = io.StringIO()
with redirect_stdout(buf):
  code = mod.main(["--state-db", str(state_db)])
if code != 0:
  raise SystemExit(f"main exited {code}")
print(buf.getvalue().strip())
PY
)

[[ $(jq -r '.usageStatusText' <<<"$auth_fail") == "Sign in to Cursor" ]] ||
  fail "Cursor scanner reports expired session on HTTP 401" "$auth_fail"
pass "Cursor scanner reports expired session on HTTP 401"

[[ $(jq -r '.authHelpText' <<<"$auth_fail") == *"expired"* ]] ||
  fail "Cursor scanner explains expired session on HTTP 401" "$auth_fail"
pass "Cursor scanner explains expired session on HTTP 401"

[[ $(jq -r '.rateLimitPercent' <<<"$auth_fail") == "-1" ]] ||
  fail "Cursor scanner keeps meters unset after auth failure" "$auth_fail"
pass "Cursor scanner keeps meters unset after auth failure"
