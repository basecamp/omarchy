#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command python3

test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT

python3 - "$test_home" <<'PY'
import sqlite3
import sys
import time
from pathlib import Path

home = Path(sys.argv[1])
today = time.time()
yesterday = today - 86400

def sessions_table(conn):
  conn.execute("""
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      model TEXT,
      billing_provider TEXT,
      started_at REAL NOT NULL,
      input_tokens INTEGER DEFAULT 0,
      output_tokens INTEGER DEFAULT 0,
      cache_read_tokens INTEGER DEFAULT 0,
      cache_write_tokens INTEGER DEFAULT 0
    )
  """)

main_db = home / ".hermes" / "state.db"
main_db.parent.mkdir(parents=True)
conn = sqlite3.connect(main_db)
sessions_table(conn)
conn.execute("""
  CREATE TABLE session_model_usage (
    session_id TEXT NOT NULL,
    model TEXT NOT NULL,
    billing_provider TEXT NOT NULL DEFAULT '',
    task TEXT NOT NULL DEFAULT '',
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cache_read_tokens INTEGER NOT NULL DEFAULT 0,
    cache_write_tokens INTEGER NOT NULL DEFAULT 0,
    reasoning_tokens INTEGER NOT NULL DEFAULT 0
  )
""")
conn.executemany("INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [
  ("shared-id", "claude-sonnet-4", "anthropic", today, 100, 50, 20, 10),
  ("fallback", "kimi-k2.5", "openrouter", yesterday, 40, 20, 0, 0),
])
conn.executemany("INSERT INTO session_model_usage VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", [
  ("shared-id", "claude-sonnet-4", "anthropic", "", 60, 30, 10, 5, 15),
  ("shared-id", "gpt-5.2-codex", "openai-codex", "", 20, 10, 0, 0, 5),
  ("shared-id", "labs/future-model-v12", "FutureProvider", "vision", 5, 7, 0, 0, 3),
])
conn.commit()
conn.close()

# A legacy named profile without session_model_usage exercises aggregate
# fallback and proves colliding session ids are distinct across databases.
profile_db = home / ".hermes" / "profiles" / "coder" / "state.db"
profile_db.parent.mkdir(parents=True)
conn = sqlite3.connect(profile_db)
sessions_table(conn)
conn.execute(
  "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
  ("shared-id", "kimi-k2.5", "fireworks", yesterday, 30, 10, 5, 0),
)
conn.commit()
conn.close()

# One damaged profile must not hide healthy usage from the others.
broken = home / ".hermes" / "profiles" / "broken" / "state.db"
broken.parent.mkdir(parents=True)
broken.write_text("not a sqlite database", encoding="utf-8")
PY

fake_runtime="$test_home/hermes-runtime"
mkdir -p "$fake_runtime/venv/bin"
cat >"$fake_runtime/venv/bin/python" <<'SH'
#!/bin/bash
cat >/dev/null
printf '%s' '{"FutureProvider::labs/future-model-v12":{"provider":"Future Systems","model":"Future Model 12"}}'
SH
chmod +x "$fake_runtime/venv/bin/python"

result=$(HOME="$test_home" HERMES_HOME="$test_home/.hermes" \
  HERMES_INSTALL_DIR="$fake_runtime" \
  "$ROOT/bin/omarchy-agent-usage-hermes" 2>/dev/null)

[[ $(jq -r '.id + "/" + (.limits | tostring)' <<<"$result") == 'hermes/[]' ]] ||
  fail "Hermes collector identifies itself without inventing unified limits" "$result"
pass "Hermes collector identifies itself and reports no unified limits"

[[ $(jq -r '.retryAdvised' <<<"$result") == true ]] ||
  fail "Hermes collector does not retry while its local database is active" "$result"
pass "Hermes collector retries while the local ledger is settling"

[[ $(jq -r '.todayTotalTokens' <<<"$result") == 192 ]] ||
  fail "Hermes collector reconciles main usage and adds auxiliary usage once" "$result"
pass "Hermes collector reconciles main and auxiliary usage without double-counting"

[[ $(jq -c '.modelUsage["anthropic::claude-sonnet-4"]' <<<"$result") == '{"inputTokens":80,"outputTokens":40,"cacheReadInputTokens":20,"cacheCreationInputTokens":10}' ]] ||
  fail "Hermes collector attributes only the positive main-loop residual" "$result"
pass "Hermes collector attributes absolute-update residuals to the session route"

[[ $(jq -r '.modelUsage | keys | map(select(endswith("::kimi-k2.5"))) | length' <<<"$result") == 2 ]] ||
  fail "Hermes collector keeps identical models separate across providers" "$result"
pass "Hermes collector separates identical models by billing provider"

[[ $(jq -r '.modelUsage | has("FutureProvider::labs/future-model-v12")' <<<"$result") == true ]] ||
  fail "Hermes collector preserves model and provider names from Hermes" "$result"
pass "Hermes collector passes unfamiliar model and provider names through verbatim"

[[ $(jq -c '.modelLabels["FutureProvider::labs/future-model-v12"]' <<<"$result") == '{"provider":"Future Systems","model":"Future Model 12"}' ]] ||
  fail "Hermes collector uses labels resolved by the installed Hermes runtime" "$result"
pass "Hermes collector lets Hermes supply model and provider display names"

[[ $(jq -r '[.modelUsage[] | .inputTokens + .outputTokens + .cacheReadInputTokens + .cacheCreationInputTokens] | add' <<<"$result") == 297 ]] ||
  fail "Hermes collector excludes reasoning tokens already contained in output" "$result"
pass "Hermes collector does not double-count reasoning tokens"

[[ $(jq -r '.totalSessions' <<<"$result") == 3 ]] ||
  fail "Hermes collector distinguishes colliding session ids across profiles" "$result"
[[ $(jq -r '.activeDays' <<<"$result") == 2 ]] ||
  fail "Hermes collector aggregates active dates across profiles" "$result"
[[ $(jq -r '.tierLabel' <<<"$result") == '5 providers · 4 models' ]] ||
  fail "Hermes collector summarizes its multi-provider model mix" "$result"
pass "Hermes collector aggregates named profiles"

[[ $(jq -r '.hasPromptStats' <<<"$result") == false ]] ||
  fail "Hermes collector does not label API calls as prompts" "$result"
pass "Hermes collector avoids inventing prompt counts"
