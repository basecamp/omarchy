#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq

TEST_HOME=$(mktemp -d)
FAKE_OMARCHY=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$FAKE_OMARCHY"' EXIT

mkdir -p "$FAKE_OMARCHY/bin"

cat >"$FAKE_OMARCHY/bin/omarchy-agent-usage-good" <<'EOF'
#!/bin/bash
echo '{"schemaVersion":1,"id":"good","name":"Good Agent","totalPrompts":3}'
EOF

cat >"$FAKE_OMARCHY/bin/omarchy-agent-usage-noisy" <<'EOF'
#!/bin/bash
echo "this is not json"
EOF

cat >"$FAKE_OMARCHY/bin/omarchy-agent-usage-skipped" <<'EOF'
#!/bin/bash
echo '{"id":"skipped"}'
EOF

# The updater itself lives in the same namespace as the collectors it globs.
cat >"$FAKE_OMARCHY/bin/omarchy-agent-usage-update" <<'EOF'
#!/bin/bash
echo '{"id":"update"}'
EOF

chmod +x "$FAKE_OMARCHY/bin/"omarchy-agent-usage-*

usage_dir="$TEST_HOME/.local/state/omarchy/agents/usage"

HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_STATE_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" --except skipped 2>/dev/null && fail "update reports a failing collector"
pass "update reports a failing collector"

[[ $(jq -r '.name' "$usage_dir/good.json") == "Good Agent" ]] ||
  fail "update writes each collector's record to the usage directory"
pass "update writes each collector's record to the usage directory"

[[ ! -e $usage_dir/noisy.json ]] ||
  fail "update refuses records that are not valid JSON"
pass "update refuses records that are not valid JSON"

[[ ! -e $usage_dir/skipped.json ]] ||
  fail "update skips agents excluded with --except"
pass "update skips agents excluded with --except"

[[ ! -e $usage_dir/update.json ]] ||
  fail "update does not treat itself as a collector"
pass "update does not treat itself as a collector"

HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_STATE_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" skipped 2>/dev/null ||
  fail "update succeeds when the requested collectors all pass"
pass "update succeeds when the requested collectors all pass"

[[ -e $usage_dir/skipped.json && ! -e $usage_dir/noisy.json ]] ||
  fail "update with agent arguments only runs the named collectors"
pass "update with agent arguments only runs the named collectors"

# User collectors are not package-owned; they live next to custom themes/hooks.
user_collectors="$TEST_HOME/.config/omarchy/agents/collectors"
mkdir -p "$user_collectors"

cat >"$user_collectors/omarchy-agent-usage-custom" <<'COLLECTOR'
#!/bin/bash
echo '{"schemaVersion":1,"id":"custom","name":"User Agent","totalPrompts":1}'
COLLECTOR
chmod +x "$user_collectors/omarchy-agent-usage-custom"

cat >"$user_collectors/omarchy-agent-usage-good" <<'COLLECTOR'
#!/bin/bash
echo '{"schemaVersion":1,"id":"good","name":"User Good","totalPrompts":9}'
COLLECTOR
chmod +x "$user_collectors/omarchy-agent-usage-good"

rm -f "$usage_dir"/*.json

HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_STATE_HOME="" XDG_CONFIG_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" custom 2>/dev/null ||
  fail "update runs a collector from ~/.config/omarchy/agents/collectors"
pass "update runs a collector from ~/.config/omarchy/agents/collectors"

[[ $(jq -r '.name' "$usage_dir/custom.json") == "User Agent" ]] ||
  fail "update writes the user collector record"
pass "update writes the user collector record"

HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_STATE_HOME="" XDG_CONFIG_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" good 2>/dev/null ||
  fail "update prefers a user collector over a packaged one with the same id"
pass "update prefers a user collector over a packaged one with the same id"

[[ $(jq -r '.name' "$usage_dir/good.json") == "User Good" ]] ||
  fail "user collector overrides the packaged record"
pass "user collector overrides the packaged record"
