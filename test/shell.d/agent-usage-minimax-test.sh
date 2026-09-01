#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

no_key=$(HOME="$TEST_HOME" XDG_DATA_HOME="$TEST_HOME/.local/share" MINIMAX_API_KEY="" \
  MMX_CONFIG_DIR="$TEST_HOME/missing" "$ROOT/bin/omarchy-agent-usage-minimax")

[[ $(jq -r '.id + ":" + (.ready | tostring) + ":" + .tierLabel' <<<"$no_key") == "minimax:false:Token Plan" ]] ||
  fail "MiniMax collector prints a valid record without credentials" "$no_key"
pass "MiniMax collector prints a valid record without credentials"

result=$(python3 - "$ROOT/bin/omarchy-agent-usage-minimax" "$TEST_HOME" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import sys
from pathlib import Path

collector_path = sys.argv[1]
home = Path(sys.argv[2])
os.environ["HOME"] = str(home)
os.environ["MMX_CONFIG_DIR"] = str(home / ".mmx")
os.environ["XDG_DATA_HOME"] = str(home / ".local/share")

loader = importlib.machinery.SourceFileLoader("minimax_collector", collector_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
scanner = importlib.util.module_from_spec(spec)
loader.exec_module(scanner)

payload = {
  "model_remains": [
    {
      "model_name": "general",
      "end_time": 1782399600000,
      "current_interval_remaining_percent": 10,
      "current_interval_status": 1,
      "weekly_end_time": 1782691200000,
      "current_weekly_remaining_percent": 69,
      "current_weekly_status": 1,
    },
    {
      "model_name": "video",
      "current_interval_total_count": 0,
      "current_interval_remaining_percent": 100,
      "current_interval_status": 3,
    },
  ],
  "base_resp": {"status_code": 0, "status_msg": "success"},
}

limits = scanner.quota_limits(payload)

config_dir = home / ".mmx"
config_dir.mkdir(parents=True)
(config_dir / "config.json").write_text(json.dumps({"api_key": "mmx_saved"}))
saved_key, saved_base_url = scanner.credentials()

(config_dir / "config.json").write_text(json.dumps({
  "oauth": {
    "access_token": "mmx_oauth",
    "refresh_token": "refresh",
    "expires_at": "2099-01-01T00:00:00Z",
    "region": "cn",
  }
}))
oauth_key, oauth_base_url = scanner.credentials()

(config_dir / "config.json").unlink()
opencode = home / ".local/share/opencode/auth.json"
opencode.parent.mkdir(parents=True)
opencode.write_text(json.dumps({"minimax": {"type": "api", "key": "mmx_opencode"}}))
opencode_key, opencode_base_url = scanner.credentials()

class WorkingClient:
  pass

scanner.fetch_quota = lambda api_key, base_url: payload
record = scanner.collect("mmx_test", "https://example.invalid")

print(json.dumps({
  "limits": limits,
  "savedKey": saved_key,
  "savedBaseUrl": saved_base_url,
  "oauthKey": oauth_key,
  "oauthBaseUrl": oauth_base_url,
  "opencodeKey": opencode_key,
  "record": record,
}))
PY
)

[[ $(jq -c '.limits | map({label, percent})' <<<"$result") == '[{"label":"Session (5-hour)","percent":0.9},{"label":"Weekly (7-day)","percent":0.31000000000000005}]' ]] ||
  fail "MiniMax remaining percentages become Omarchy used fractions" "$result"
pass "MiniMax remaining percentages become Omarchy used fractions"

[[ $(jq -r '.limits[0].resetsAt + ":" + .limits[1].resetsAt' <<<"$result") == "2026-06-25T15:00:00+00:00:2026-06-29T00:00:00+00:00" ]] ||
  fail "MiniMax quota reset timestamps are normalized" "$result"
pass "MiniMax quota reset timestamps are normalized"

[[ $(jq -r '.savedKey + ":" + .opencodeKey' <<<"$result") == "mmx_saved:mmx_opencode" ]] ||
  fail "MiniMax credentials use mmx and opencode logins" "$result"
pass "MiniMax credentials use mmx and opencode logins"

[[ $(jq -r '.oauthKey + ":" + .oauthBaseUrl' <<<"$result") == "mmx_oauth:https://api.minimaxi.com" ]] ||
  fail "MiniMax credentials use the OAuth session and region saved by mmx" "$result"
pass "MiniMax credentials use the OAuth session and region saved by mmx"

[[ $(jq -c '.record | {id, ready, hasLocalStats, hasPromptStats, scope, tierLabel}' <<<"$result") == '{"id":"minimax","ready":true,"hasLocalStats":false,"hasPromptStats":false,"scope":"account","tierLabel":"Token Plan"}' ]] ||
  fail "MiniMax collector prints the display-ready record contract" "$result"
pass "MiniMax collector prints the display-ready record contract"
