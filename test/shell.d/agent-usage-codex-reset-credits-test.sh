#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

# fetch_reset_credits reaches ChatGPT, so the reader that interprets its answer
# is exercised on its own: the collector loads as a module, and a recorded
# payload stands in for the response.
read_credits() {
  COLLECTOR="$ROOT/bin/omarchy-agent-usage-codex" PAYLOAD="$1" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

print(json.dumps(collector.available_reset_credits(json.loads(os.environ["PAYLOAD"]))))
PY
}

# The tally the endpoint reports is the answer, however many credits it lists.
[[ $(read_credits '{"credits": [{"status": "available"}], "available_count": 2}') == "2" ]] ||
  fail "Codex collector reads the banked reset tally the endpoint reports" "$(read_credits '{"credits": [{"status": "available"}], "available_count": 2}')"
pass "Codex collector reads the banked reset tally the endpoint reports"

# A read that reports no banked resets is an answer, not a missing one.
[[ $(read_credits '{"credits": [], "available_count": 0}') == "0" ]] ||
  fail "Codex collector reports zero banked resets as zero" "$(read_credits '{"credits": [], "available_count": 0}')"
pass "Codex collector reports zero banked resets as zero"

# Without a tally the credits are counted: spent, expired, and unspendable ones
# do not count, and a credit with no expiry is still good.
counted=$(read_credits '{"credits": [
  {"status": "available", "expires_at": "2999-01-01T00:00:00Z"},
  {"status": "available"},
  {"status": "available", "expires_at": "2000-01-01T00:00:00Z"},
  {"status": "redeemed", "expires_at": "2999-01-01T00:00:00Z"},
  {"status": "available", "expires_at": "not-a-date"}
]}')
[[ $counted == "3" ]] ||
  fail "Codex collector counts only banked resets it can still spend" "$counted"
pass "Codex collector counts only banked resets it can still spend"

# A record that reaches the panel without the count is better than no record:
# an unreachable endpoint reports nothing rather than raising.
unreachable=$(COLLECTOR="$ROOT/bin/omarchy-agent-usage-codex" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

collector.codex_credentials = lambda: ("token", "account")


def unreachable(request, timeout=None):
  raise OSError("no route to host")


collector.urllib.request.urlopen = unreachable
print(json.dumps(collector.fetch_reset_credits()))
PY
)
[[ $unreachable == "null" ]] ||
  fail "Codex collector reports unknown banked resets when the endpoint is unreachable" "$unreachable"
pass "Codex collector reports unknown banked resets when the endpoint is unreachable"

# Signed out is the same unknown: no auth file, no count, no traceback.
signed_out=$(COLLECTOR="$ROOT/bin/omarchy-agent-usage-codex" CODEX_HOME="$(mktemp -d)" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

print(json.dumps(collector.fetch_reset_credits()))
PY
)
[[ $signed_out == "null" ]] ||
  fail "Codex collector reports unknown banked resets when signed out" "$signed_out"
pass "Codex collector reports unknown banked resets when signed out"
