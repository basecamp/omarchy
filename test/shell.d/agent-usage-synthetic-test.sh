#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

collector="$ROOT/bin/omarchy-agent-usage-synthetic"

no_auth=$(HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" SYNTHETIC_API_KEY="" "$collector")
[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.hasLocalStats | tostring)' <<<"$no_auth") == "synthetic:false:false" ]] ||
  fail "Synthetic collector prints a valid record without credentials" "$no_auth"
[[ $(jq -r '.authHelpText' <<<"$no_auth") == *"SYNTHETIC_API_KEY"* ]] ||
  fail "Synthetic collector explains how to authenticate" "$no_auth"
pass "Synthetic collector handles missing credentials"

result=$(python3 - "$collector" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sys
import urllib.error
from pathlib import Path

collector_path = sys.argv[1]
home = Path(sys.argv[2])
os.environ["HOME"] = str(home)
os.environ["XDG_DATA_HOME"] = str(home / ".local" / "share")

loader = importlib.machinery.SourceFileLoader("synthetic_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

pi_auth = home / ".pi" / "agent" / "auth.json"
opencode_auth = home / ".local" / "share" / "opencode" / "auth.json"
pi_auth.parent.mkdir(parents=True, exist_ok=True)
opencode_auth.parent.mkdir(parents=True, exist_ok=True)
pi_auth.write_text(json.dumps({"synthetic": {"key": "pi-key"}}))
opencode_auth.write_text(json.dumps({"synthetic": {"key": "opencode-key"}}))

os.environ["SYNTHETIC_API_KEY"] = "env-key"
env_key = scanner.credentials()
del os.environ["SYNTHETIC_API_KEY"]
pi_key = scanner.credentials()
pi_auth.unlink()
opencode_key = scanner.credentials()

modern_payload = {
  "subscription": {"requests": 0, "limit": 1000, "renewsAt": "2026-08-17T00:00:00Z"},
  "rollingFiveHourLimit": {
    "remaining": 998.3,
    "max": 1000,
    "limited": False,
    "nextTickAt": "2026-08-16T02:00:00Z",
  },
  "weeklyTokenLimit": {
    "percentRemaining": 64.69978866666666,
    "remainingCredits": "$31.05",
    "maxCredits": "$48.00",
    "nextRegenAt": "2026-08-16T04:00:00Z",
  },
  "search": {
    "hourly": {"requests": 4, "limit": 250, "renewsAt": "2026-08-16T03:00:00Z"},
  },
}
modern, status, help_text = scanner.parse_limits(modern_payload)
legacy, _, _ = scanner.parse_limits({
  "subscription": {"requests": 27, "limit": 135, "renewsAt": "2026-08-17T00:00:00Z"},
})
invalid_modern, _, _ = scanner.parse_limits({
  "rollingFiveHourLimit": {},
  "subscription": {"requests": 10, "limit": 100, "renewsAt": "2026-08-17T00:00:00Z"},
})

captured = {}
class Response:
  def __enter__(self):
    return self

  def __exit__(self, *args):
    return False

  def read(self, *args):
    return json.dumps(modern_payload).encode()


def fake_urlopen(request, timeout):
  captured["url"] = request.full_url
  captured["authorization"] = request.get_header("Authorization")
  captured["timeout"] = timeout
  return Response()

real_urlopen = scanner.urllib.request.urlopen
scanner.urllib.request.urlopen = fake_urlopen
fetched = scanner.SyntheticClient("secret", "https://synthetic.test").quotas()

scanner.urllib.request.urlopen = lambda *_args, **_kwargs: (_ for _ in ()).throw(
  urllib.error.URLError("offline")
)
try:
  scanner.SyntheticClient("secret").quotas()
  retry_advised = None
except scanner.SyntheticError as error:
  retry_advised = error.retry_advised
finally:
  scanner.urllib.request.urlopen = real_urlopen

print(json.dumps({
  "credentials": [env_key, pi_key, opencode_key],
  "modern": modern,
  "modernStatus": [status, help_text],
  "legacy": legacy,
  "invalidModern": invalid_modern,
  "request": captured,
  "fetchedMatches": fetched == modern_payload,
  "retryAdvised": retry_advised,
}))
PY
)

[[ $(jq -c '.credentials' <<<"$result") == '["env-key","pi-key","opencode-key"]' ]] ||
  fail "Synthetic credentials follow environment, Pi, then OpenCode priority" "$result"
pass "Synthetic credentials follow the documented priority"

[[ $(jq -c '[.modern[] | {label,percent,detail,resetLabel}]' <<<"$result") == '[{"label":"Requests used / 5h","percent":0.0017000000000000348,"detail":"1.7 / 1,000 used","resetLabel":"Next tick in"},{"label":"Credits used / week","percent":0.3530021133333334,"detail":"$31.05 / $48.00 left","resetLabel":"Next regen in"},{"label":"Search used / hour","percent":0.016,"detail":"4 / 250 used","resetLabel":null}]' ]] ||
  fail "Synthetic collector maps modern quota windows" "$result"
[[ $(jq -r '.modern | map(.label) | index("Subscription requests")' <<<"$result") == "null" ]] ||
  fail "Synthetic collector hides the stale legacy bucket on modern accounts" "$result"
pass "Synthetic collector maps modern quotas without the stale legacy bucket"

[[ $(jq -c '.legacy[0] | {label,percent,detail}' <<<"$result") == '{"label":"Subscription requests","percent":0.2,"detail":"27 / 135 used"}' ]] ||
  fail "Synthetic collector supports the documented legacy subscription quota" "$result"
[[ $(jq -r '.invalidModern[0].label' <<<"$result") == "Subscription requests" ]] ||
  fail "Synthetic collector falls back when modern quota objects are unusable" "$result"
pass "Synthetic collector preserves legacy quota compatibility"

[[ $(jq -r '.request.url' <<<"$result") == "https://synthetic.test/v2/quotas" ]] ||
  fail "Synthetic collector calls the documented quota endpoint" "$result"
[[ $(jq -r '.request.authorization' <<<"$result") == "Bearer secret" ]] ||
  fail "Synthetic collector authenticates quota requests" "$result"
[[ $(jq -r '.fetchedMatches' <<<"$result") == "true" ]] ||
  fail "Synthetic collector decodes quota responses" "$result"
[[ $(jq -r '.retryAdvised' <<<"$result") == "true" ]] ||
  fail "Synthetic collector advises one retry after transport failure" "$result"
pass "Synthetic collector handles the quota transport contract"
