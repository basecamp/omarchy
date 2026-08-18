#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

today="$(date +%Y-%m-%d)"
session_dir="$TEST_HOME/.kimi-code/sessions/proj/session_abc/agents/main"
mkdir -p "$session_dir"

wire_line() {
  local scope="$1" model="$2" input="$3" output="$4" cache="$5" write="${6:-0}"
  jq -nc --arg scope "$scope" --arg model "$model" --arg today "$today" \
    --argjson input "$input" --argjson output "$output" --argjson cache "$cache" --argjson write "$write" \
    '{
      type: "usage.record",
      time: ($today + "T12:00:00Z"),
      model: $model,
      usageScope: $scope,
      usage: {
        inputOther: $input,
        output: $output,
        inputCacheRead: $cache,
        inputCacheCreation: $write
      }
    }'
}

{
  echo '{"type":"turn.prompt","input":[]}'
  wire_line turn "kimi-k3" 40 10 20 5
  wire_line turn "kimi-k3" 40 10 20 5
  wire_line session "kimi-k3" 800 200 400 100
  echo '{not json'
  echo '{"type":"usage.record","usage":{}}'
} >"$session_dir/wire.jsonl"

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$TEST_HOME/.cache" KIMI_CODE_HOME="$TEST_HOME/.kimi-code" \
  KIMI_API_KEY="" "$ROOT/bin/omarchy-agent-usage-kimi" --force)

[[ $(jq -r '.id + "/" + .name' <<<"$result") == "kimi/Kimi" ]] ||
  fail "Kimi collector identifies itself" "$result"
pass "Kimi collector identifies itself"

# Two turn records count; the session-scope running total does not.
[[ $(jq -r '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Kimi collector counts turn-scope usage.record once each" "$result"
[[ $(jq -r '.todayTotalTokens' <<<"$result") == "150" ]] ||
  fail "Kimi collector keeps uncached input, output, and cache disjoint" "$result"
[[ $(jq -c '.modelUsage.k3' <<<"$result") == '{"cacheCreationInputTokens":10,"cacheReadInputTokens":40,"inputTokens":80,"outputTokens":20}' ]] ||
  fail "Kimi collector normalizes kimi-k3 and splits token buckets" "$result"
pass "Kimi collector counts turn records and keeps token buckets disjoint"

[[ $(jq -r '.todaySessions' <<<"$result") == "1" ]] ||
  fail "Kimi collector counts the session directory once" "$result"
pass "Kimi collector counts the session directory once"

[[ $(jq -r '.usageStatusText' <<<"$result") == "Waiting for auth" ]] ||
  fail "Kimi collector reports a missing login" "$result"
[[ $(jq -r '.authHelpText' <<<"$result") == *"kimi login"* ]] ||
  fail "Kimi collector says how to restore limits" "$result"
pass "Kimi collector reports a missing login"

# KIMI_CODE_HOME wins over ~/.kimi-code under HOME.
OTHER_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME"' EXIT
other_dir="$OTHER_HOME/sessions/other/session_xyz/agents/main"
mkdir -p "$other_dir"
wire_line turn "kimi-for-coding" 8 2 0 0 >"$other_dir/wire.jsonl"

result=$(HOME="$TEST_HOME" XDG_CACHE_HOME="$OTHER_HOME/.cache" KIMI_CODE_HOME="$OTHER_HOME" \
  KIMI_API_KEY="" "$ROOT/bin/omarchy-agent-usage-kimi" --force)

[[ $(jq -c '.modelUsage' <<<"$result") == '{"for-coding":{"cacheCreationInputTokens":0,"cacheReadInputTokens":0,"inputTokens":8,"outputTokens":2}}' ]] ||
  fail "Kimi collector honors KIMI_CODE_HOME" "$result"
pass "Kimi collector honors KIMI_CODE_HOME"

# Auth resolution and quota mapping are stubbed; the collector must not reach the network.
AUTH_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$OTHER_HOME" "$AUTH_HOME"' EXIT

result=$(TEST_HOME="$AUTH_HOME" COLLECTOR="$ROOT/bin/omarchy-agent-usage-kimi" python3 - <<'PY'
import importlib.machinery, importlib.util, json, os, time
from pathlib import Path

collector = os.environ["COLLECTOR"]
test_home = Path(os.environ["TEST_HOME"])
os.environ["HOME"] = str(test_home / "home")
os.environ["KIMI_CODE_HOME"] = str(test_home / "kimi-code")
os.environ.pop("KIMI_API_KEY", None)

loader = importlib.machinery.SourceFileLoader("kimi_collector", collector)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

summary = {}

os.environ["KIMI_API_KEY"] = "kimi_env"
summary["envKeyWins"] = scanner.api_key() == "kimi_env"
del os.environ["KIMI_API_KEY"]

code_dir = test_home / "kimi-code" / "credentials"
legacy_dir = test_home / "home" / ".kimi" / "credentials"
code_dir.mkdir(parents=True, exist_ok=True)
legacy_dir.mkdir(parents=True, exist_ok=True)
(legacy_dir / "kimi-code.json").write_text("{}")
summary["legacyFallback"] = scanner.credentials_dir() == legacy_dir
(code_dir / "kimi-code.json").write_text("{}")
summary["codeStorePreferred"] = scanner.credentials_dir() == code_dir

scanner_path = code_dir / "kimi-code.json"
fresh = {"access_token": "at_fresh", "refresh_token": "rt_1", "expires_at": time.time() + 3600}
scanner_path.write_text(json.dumps(fresh))
summary["freshTokenUsed"] = scanner.api_key() == "at_fresh"

expired = {"access_token": "at_old", "refresh_token": "rt_1", "expires_at": time.time() - 10}
scanner_path.write_text(json.dumps(expired))
scanner.request_refresh = lambda token: {
  "access_token": "at_new",
  "refresh_token": "rt_2",
  "expires_in": 3600,
}
granted = scanner.refresh_credentials()
persisted = json.loads(scanner_path.read_text())
summary["refreshRotates"] = (
  granted["access_token"] == "at_new"
  and persisted["refresh_token"] == "rt_2"
  and persisted["access_token"] == "at_new"
)

try:
  scanner.trusted_url("http://evil.example.com/usages")
  summary["httpRefused"] = False
except scanner.KimiError:
  summary["httpRefused"] = True
summary["loopbackAllowed"] = scanner.trusted_url("http://127.0.0.1:9000/usages")[1] is False
summary["kimiTrusted"] = scanner.trusted_url("https://api.kimi.com/coding/v1/usages")[1] is True

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
  "user": {"membership": {"level": "LEVEL_ALLEGRETO"}},
}
summary["limits"] = scanner.to_limits(payload)
summary["plan"] = scanner.plan_label(payload)

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

[[ $(jq -c '.limits' <<<"$result") == '[{"label":"Weekly","percent":0.33,"resetsAt":"2026-08-23T11:52:13.042087Z"},{"label":"Session (5-hour)","percent":0.66,"resetsAt":"2026-08-17T16:52:13Z"},{"label":"Weekly quota","percent":0.25,"resetsAt":""}]' ]] ||
  fail "Kimi collector renders usage windows into display rows" "$result"
[[ $(jq -r '.plan' <<<"$result") == "Allegreto" ]] ||
  fail "Kimi collector labels LEVEL_ALLEGRETO as Allegreto" "$result"
pass "Kimi collector renders usage windows and the plan label"

# --limits-only reuses a seconds-old scan; --force rereads the files.
scan_home="$TEST_HOME"
result=$(HOME="$scan_home" XDG_CACHE_HOME="$scan_home/.cache" KIMI_CODE_HOME="$scan_home/.kimi-code" \
  KIMI_API_KEY="" "$ROOT/bin/omarchy-agent-usage-kimi" --force)
[[ $(jq -r '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Kimi collector --force sees the fixture turns" "$result"

wire_line turn "kimi-k3" 1 1 0 0 >>"$session_dir/wire.jsonl"
result=$(HOME="$scan_home" XDG_CACHE_HOME="$scan_home/.cache" KIMI_CODE_HOME="$scan_home/.kimi-code" \
  KIMI_API_KEY="" "$ROOT/bin/omarchy-agent-usage-kimi" --limits-only)
[[ $(jq -r '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Kimi collector --limits-only reuses a fresh scan cache" "$result"
pass "Kimi collector --limits-only reuses a fresh scan cache"

result=$(HOME="$scan_home" XDG_CACHE_HOME="$scan_home/.cache" KIMI_CODE_HOME="$scan_home/.kimi-code" \
  KIMI_API_KEY="" "$ROOT/bin/omarchy-agent-usage-kimi" --force)
[[ $(jq -r '.todayPrompts' <<<"$result") == "3" ]] ||
  fail "Kimi collector --force rescans past the cache" "$result"
pass "Kimi collector --force rescans past the cache"
