#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Without credentials the collector must still print a full, hidden-by-default
# record: the update runner writes whatever valid JSON appears on stdout.
no_key=$(HOME="$TEST_HOME" KIMI_CODE_HOME="$TEST_HOME/kimi-code" KIMI_API_KEY="" \
  "$ROOT/bin/omarchy-agent-usage-kimi")

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + (.scope)' <<<"$no_key") == "kimi:false:account" ]] ||
  fail "Kimi collector prints a valid record without credentials" "$no_key"
pass "Kimi collector prints a valid record without credentials"

result=$(TEST_HOME="$TEST_HOME" python3 - "$ROOT/bin/omarchy-agent-usage-kimi" <<'PY'
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import time
from contextlib import redirect_stdout
from pathlib import Path

collector_path = str(Path(sys.argv[1]))
test_home = Path(os.environ["TEST_HOME"])

os.environ["HOME"] = str(test_home / "home")
os.environ["KIMI_CODE_HOME"] = str(test_home / "kimi-code")

loader = importlib.machinery.SourceFileLoader("kimi_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

summary = {}

# The env key wins without touching any credentials file.
os.environ["KIMI_API_KEY"] = "kimi_env"
summary["envKeyWins"] = scanner.api_key() == "kimi_env"
del os.environ["KIMI_API_KEY"]

# The kimi-code store wins over the legacy kimi-cli one; legacy is the fallback.
code_dir = test_home / "kimi-code" / "credentials"
legacy_dir = test_home / "home" / ".kimi" / "credentials"
code_dir.mkdir(parents=True, exist_ok=True)
legacy_dir.mkdir(parents=True, exist_ok=True)
(legacy_dir / "kimi-code.json").write_text("{}")
summary["legacyFallback"] = scanner.credentials_dir() == legacy_dir
(code_dir / "kimi-code.json").write_text("{}")
summary["codeStorePreferred"] = scanner.credentials_dir() == code_dir

# A fresh token is used as-is; an expired one is refreshed under the lock and
# the rotated single-use refresh token is persisted back.
scanner.CREDENTIALS_DIR = code_dir
scanner.CREDENTIALS_PATH = code_dir / "kimi-code.json"
scanner.CREDENTIALS_LOCK = code_dir / "kimi-code.lock"

fresh = {"access_token": "at_fresh", "refresh_token": "rt_1", "expires_at": time.time() + 3600}
scanner.CREDENTIALS_PATH.write_text(json.dumps(fresh))
summary["freshTokenUsed"] = scanner.api_key() == "at_fresh"

expired = {"access_token": "at_old", "refresh_token": "rt_1", "expires_at": time.time() - 10}
scanner.CREDENTIALS_PATH.write_text(json.dumps(expired))
scanner.request_refresh = lambda token: {
  "access_token": "at_new",
  "refresh_token": "rt_2",
  "expires_in": 3600,
}
granted = scanner.refresh_credentials()
persisted = json.loads(scanner.CREDENTIALS_PATH.read_text())
summary["refreshRotates"] = (
  granted["access_token"] == "at_new"
  and persisted["refresh_token"] == "rt_2"
  and persisted["access_token"] == "at_new"
)

# Endpoint trust: plain HTTP is refused off-loopback; tokens only go to kimi.com.
try:
  scanner.trusted_url("http://evil.example.com/usages")
  summary["httpRefused"] = False
except scanner.KimiError:
  summary["httpRefused"] = True
summary["loopbackAllowed"] = scanner.trusted_url("http://127.0.0.1:9000/usages")[1] is False
summary["kimiTrusted"] = scanner.trusted_url("https://api.kimi.com/coding/v1/usages")[1] is True

# The usage payload renders into display rows: the weekly quota, the 5-hour
# session window, used derived from remaining, and nanosecond stamps trimmed.
payload = {
  "usage": {"limit": 100, "used": 33, "reset_at": "2026-08-23T11:52:13.042087123Z"},
  "limits": [
    {
      "window": {"duration": 300, "timeUnit": "MINUTES"},
      "detail": {"limit": 50, "remaining": 17, "reset_at": "2026-08-17T16:52:13Z"},
    },
    {
      "window": {"duration": 7, "timeUnit": "DAYS"},
      "detail": {"name": "Weekly quota", "limit": 200, "used": 50},
    },
    {"window": {"duration": 0}, "detail": {"limit": 0, "used": 0}},
  ],
}
limits = scanner.to_limits(payload)
summary["limits"] = limits

os.environ["KIMI_API_KEY"] = "kimi_env"
scanner.quota = lambda key: payload
sys.argv = ["omarchy-agent-usage-kimi", "--limits-only"]
out = io.StringIO()
with redirect_stdout(out):
  scanner.main()
summary["record"] = json.loads(out.getvalue())

print(json.dumps(summary, separators=(",", ":")))
PY
)

[[ $(jq -r '.envKeyWins' <<<"$result") == "true" ]] ||
  fail "Kimi collector prefers KIMI_API_KEY over stored credentials" "$result"
pass "Kimi collector prefers KIMI_API_KEY over stored credentials"

[[ $(jq -r '"\(.codeStorePreferred):\(.legacyFallback)"' <<<"$result") == "true:true" ]] ||
  fail "Kimi collector prefers the kimi-code store and falls back to legacy kimi-cli" "$result"
pass "Kimi collector prefers the kimi-code store and falls back to legacy kimi-cli"

[[ $(jq -r '"\(.freshTokenUsed):\(.refreshRotates)"' <<<"$result") == "true:true" ]] ||
  fail "Kimi collector refreshes expired tokens and persists the rotated pair" "$result"
pass "Kimi collector refreshes expired tokens and persists the rotated pair"

[[ $(jq -r '"\(.httpRefused):\(.loopbackAllowed):\(.kimiTrusted)"' <<<"$result") == "true:true:true" ]] ||
  fail "Kimi collector only sends tokens to kimi.com over HTTPS" "$result"
pass "Kimi collector only sends tokens to kimi.com over HTTPS"

[[ $(jq -c '.limits' <<<"$result") == '[{"label":"Weekly limit","percent":0.33,"resetsAt":"2026-08-23T11:52:13.042087Z"},{"label":"Session (5-hour)","percent":0.66,"resetsAt":"2026-08-17T16:52:13Z"},{"label":"Weekly quota","percent":0.25,"resetsAt":""}]' ]] ||
  fail "Kimi collector renders usage windows into display rows" "$result"
pass "Kimi collector renders usage windows into display rows"

[[ $(jq -r '.record.ready | tostring' <<<"$result") == "true" && $(jq -r '.record.id' <<<"$result") == "kimi" ]] ||
  fail "Kimi collector prints the display-ready record contract" "$result"
pass "Kimi collector prints the display-ready record contract"
