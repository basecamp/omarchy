#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

COLLECTOR="$ROOT/bin/omarchy-agent-usage-cursor"

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

missing=$(HOME="$TEST_HOME" python3 "$COLLECTOR" \
  --state-db "$TEST_HOME/missing-state.vscdb")

[[ $(jq -r '.usageStatusText' <<<"$missing") == "Cursor unavailable" ]] ||
  fail "Cursor collector reports missing state database" "$missing"
pass "Cursor collector reports missing state database"

[[ $(jq -r '.authHelpText' <<<"$missing") == *"not found"* ]] ||
  fail "Cursor collector explains missing state database" "$missing"
pass "Cursor collector explains missing state database"

[[ $(jq -r '.id + "/" + .name' <<<"$missing") == "cursor/Cursor" ]] ||
  fail "Cursor collector identifies itself without credentials" "$missing"
pass "Cursor collector identifies itself without credentials"

no_token_db="$TEST_HOME/no-token.vscdb"
make_state_db "$no_token_db" \
  "cursorAuth/stripeMembershipType" "pro"

no_token=$(HOME="$TEST_HOME" python3 "$COLLECTOR" \
  --state-db "$no_token_db")

[[ $(jq -r '.usageStatusText' <<<"$no_token") == "Sign in to Cursor" ]] ||
  fail "Cursor collector reports missing access token" "$no_token"
pass "Cursor collector reports missing access token"

[[ $(jq -r '.authHelpText' <<<"$no_token") == *"sign in"* ]] ||
  fail "Cursor collector explains missing access token" "$no_token"
pass "Cursor collector explains missing access token"

[[ $(jq -r '.limits | length' <<<"$no_token") == "0" ]] ||
  fail "Cursor collector keeps meters unset without a token" "$no_token"
pass "Cursor collector keeps meters unset without a token"

state_db="$TEST_HOME/state.vscdb"
make_state_db "$state_db" \
  "cursorAuth/accessToken" "test-token" \
  "cursorAuth/stripeMembershipType" "pro"

# Read-only credential load + plan mapping without hitting the network.
mapped=$(python3 - "$COLLECTOR" "$state_db" <<'PY'
import importlib.util
import json
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

scanner_path = Path(sys.argv[1])
state_db = Path(sys.argv[2])
loader = SourceFileLoader("omarchy_agent_usage_cursor", str(scanner_path))
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

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

[[ $(jq -r '.limits[0].label' <<<"$mapped") == "Cursor Models" ]] ||
  fail "Cursor collector labels auto pool as Cursor Models" "$mapped"
pass "Cursor collector labels auto pool as Cursor Models"

[[ $(jq -r '.limits[1].label' <<<"$mapped") == "Other Models" ]] ||
  fail "Cursor collector labels api pool as Other Models" "$mapped"
pass "Cursor collector labels api pool as Other Models"

[[ $(jq -r '.limits[0].percent' <<<"$mapped") == "0.125" ]] ||
  fail "Cursor collector converts auto percent to a fraction" "$mapped"
pass "Cursor collector converts auto percent to a fraction"

[[ $(jq -r '.limits[1].percent' <<<"$mapped") == "0.4" ]] ||
  fail "Cursor collector converts api percent to a fraction" "$mapped"
pass "Cursor collector converts api percent to a fraction"

[[ $(jq -r '.tierLabel' <<<"$mapped") == "Pro" ]] ||
  fail "Cursor collector formats membership tier" "$mapped"
pass "Cursor collector formats membership tier"

[[ $(jq -r '.limits[0].resetsAt' <<<"$mapped") == $(jq -r '.limits[1].resetsAt' <<<"$mapped") ]] ||
  fail "Cursor collector shares one billing-cycle reset across pools" "$mapped"
pass "Cursor collector shares one billing-cycle reset across pools"

[[ $(jq -c '.recentDays' <<<"$mapped") == "[]" && $(jq -c '.modelUsage' <<<"$mapped") == "{}" ]] ||
  fail "Cursor collector keeps day/model charts empty" "$mapped"
pass "Cursor collector keeps day/model charts empty"

[[ $(jq -r '.hasLocalStats' <<<"$mapped") == "false" ]] ||
  fail "Cursor collector reports hasLocalStats false for meters-only" "$mapped"
pass "Cursor collector reports hasLocalStats false for meters-only"

[[ $(jq -r '.hasLocalStats' <<<"$missing") == "false" && $(jq -r '.hasLocalStats' <<<"$no_token") == "false" ]] ||
  fail "Cursor collector keeps hasLocalStats false without credentials" "$missing $no_token"
pass "Cursor collector keeps hasLocalStats false without credentials"

helpers=$(python3 - "$COLLECTOR" <<'PY'
import importlib.util
import json
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

scanner_path = Path(sys.argv[1])
loader = SourceFileLoader("omarchy_agent_usage_cursor", str(scanner_path))
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

print(json.dumps({
  "ms": mod.to_epoch_ms(1893456000000),
  "seconds": mod.to_epoch_ms(1893456000),
  "reset": mod.parse_billing_cycle_end(1893456000000),
  "bad": mod.parse_billing_cycle_end("not-a-date"),
  "empty": mod.parse_billing_cycle_end(None),
  "oor": mod.parse_billing_cycle_end(10 ** 20),
  "inf": mod.parse_billing_cycle_end(float("inf")),
  "nan": mod.parse_billing_cycle_end(float("nan")),
  "pct": mod.percent_to_fraction(12.5),
  "pct_inf": mod.percent_to_fraction(float("inf")),
  "pct_nan": mod.percent_to_fraction(float("nan")),
  "pct_bad": mod.percent_to_fraction("nope"),
}))
PY
)

[[ $(jq -r '.ms' <<<"$helpers") == "1893456000000" ]] ||
  fail "Cursor collector keeps millisecond timestamps as milliseconds" "$helpers"
pass "Cursor collector keeps millisecond timestamps as milliseconds"

[[ $(jq -r '.seconds' <<<"$helpers") == "1893456000000" ]] ||
  fail "Cursor collector converts second timestamps to milliseconds" "$helpers"
pass "Cursor collector converts second timestamps to milliseconds"

[[ $(jq -r '.reset' <<<"$helpers") == "2030-01-01T00:00:00+00:00" ]] ||
  fail "Cursor collector formats parseable billing cycle ends as ISO" "$helpers"
pass "Cursor collector formats parseable billing cycle ends as ISO"

[[ $(jq -r '.bad' <<<"$helpers") == "" && $(jq -r '.empty' <<<"$helpers") == "" ]] ||
  fail "Cursor collector clears unparseable billing cycle ends" "$helpers"
pass "Cursor collector clears unparseable billing cycle ends"

[[ $(jq -r '.oor' <<<"$helpers") == "" ]] ||
  fail "Cursor collector clears out-of-range billing cycle ends" "$helpers"
pass "Cursor collector clears out-of-range billing cycle ends"

[[ $(jq -r '.inf' <<<"$helpers") == "" && $(jq -r '.nan' <<<"$helpers") == "" ]] ||
  fail "Cursor collector clears non-finite billing cycle ends" "$helpers"
pass "Cursor collector clears non-finite billing cycle ends"

[[ $(jq -e '.pct == 0.125' <<<"$helpers") == "true" ]] ||
  fail "Cursor collector converts finite percents to fractions" "$helpers"
pass "Cursor collector converts finite percents to fractions"

[[ $(jq -e '.pct_inf == -1 and .pct_nan == -1 and .pct_bad == -1' <<<"$helpers") == "true" ]] ||
  fail "Cursor collector rejects non-finite and invalid percents" "$helpers"
pass "Cursor collector rejects non-finite and invalid percents"

bad_payload=$(python3 - "$COLLECTOR" <<'PY'
import importlib.util
import json
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

scanner_path = Path(sys.argv[1])
loader = SourceFileLoader("omarchy_agent_usage_cursor", str(scanner_path))
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

print(json.dumps(mod.build_rate_limits({"accessToken": "x", "membershipType": "pro"}, None)))
PY
)

[[ $(jq -r '.usageStatusText' <<<"$bad_payload") == "Cursor limits unavailable" ]] ||
  fail "Cursor collector rejects a null usage payload" "$bad_payload"
pass "Cursor collector rejects a null usage payload"

[[ $(jq -r '.authHelpText' <<<"$bad_payload") == *"JSON object"* ]] ||
  fail "Cursor collector explains a non-object usage payload" "$bad_payload"
pass "Cursor collector explains a non-object usage payload"

[[ $(jq -r '.limits | length' <<<"$bad_payload") == "0" ]] ||
  fail "Cursor collector keeps meters unset for a non-object usage payload" "$bad_payload"
pass "Cursor collector keeps meters unset for a non-object usage payload"

# Full collector path with a fake successful GetCurrentPeriodUsage response.
http_ok=$(python3 - "$COLLECTOR" "$state_db" <<'PY'
import importlib.util
import io
import json
import sys
from contextlib import redirect_stdout
from importlib.machinery import SourceFileLoader
from pathlib import Path

scanner_path = Path(sys.argv[1])
state_db = Path(sys.argv[2])
loader = SourceFileLoader("omarchy_agent_usage_cursor", str(scanner_path))
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

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

[[ $(jq -r '.limits[0].label' <<<"$http_ok") == "Cursor Models" ]] ||
  fail "Cursor collector maps mocked period usage to Cursor Models" "$http_ok"
pass "Cursor collector maps mocked period usage to Cursor Models"

[[ $(jq -r '.limits[1].label' <<<"$http_ok") == "Other Models" ]] ||
  fail "Cursor collector maps mocked period usage to Other Models" "$http_ok"
pass "Cursor collector maps mocked period usage to Other Models"

[[ $(jq -r '.limits[0].percent' <<<"$http_ok") == "0.125" && $(jq -r '.limits[1].percent' <<<"$http_ok") == "0.4" ]] ||
  fail "Cursor collector maps mocked period usage percents" "$http_ok"
pass "Cursor collector maps mocked period usage percents"

[[ $(jq -r '.tierLabel' <<<"$http_ok") == "Pro" ]] ||
  fail "Cursor collector maps mocked period usage tier" "$http_ok"
pass "Cursor collector maps mocked period usage tier"

[[ $(jq -r '.limits[0].resetsAt' <<<"$http_ok") == "2030-01-01T00:00:00+00:00" ]] ||
  fail "Cursor collector maps mocked billing cycle end" "$http_ok"
pass "Cursor collector maps mocked billing cycle end"

[[ $(jq -r '.hasLocalStats' <<<"$http_ok") == "false" ]] ||
  fail "Cursor collector keeps hasLocalStats false on successful period usage" "$http_ok"
pass "Cursor collector keeps hasLocalStats false on successful period usage"

[[ $(jq -r '.ready' <<<"$http_ok") == "true" ]] ||
  fail "Cursor collector marks ready when period meters are present" "$http_ok"
pass "Cursor collector marks ready when period meters are present"

# Auth failure from GetCurrentPeriodUsage (HTTP 401).
auth_fail=$(python3 - "$COLLECTOR" "$state_db" <<'PY'
import importlib.util
import io
import json
import sys
import urllib.error
from contextlib import redirect_stdout
from importlib.machinery import SourceFileLoader
from pathlib import Path

scanner_path = Path(sys.argv[1])
state_db = Path(sys.argv[2])
loader = SourceFileLoader("omarchy_agent_usage_cursor", str(scanner_path))
spec = importlib.util.spec_from_loader(loader.name, loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)


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
  fail "Cursor collector reports expired session on HTTP 401" "$auth_fail"
pass "Cursor collector reports expired session on HTTP 401"

[[ $(jq -r '.authHelpText' <<<"$auth_fail") == *"expired"* ]] ||
  fail "Cursor collector explains expired session on HTTP 401" "$auth_fail"
pass "Cursor collector explains expired session on HTTP 401"

[[ $(jq -r '.limits | length' <<<"$auth_fail") == "0" ]] ||
  fail "Cursor collector keeps meters unset after auth failure" "$auth_fail"
pass "Cursor collector keeps meters unset after auth failure"
