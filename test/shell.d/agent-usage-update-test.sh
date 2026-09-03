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

mkdir -p "$TEST_HOME/.config/omarchy"
cat >"$TEST_HOME/.config/omarchy/agent-meter.json" <<'EOF'
{"sources":{"good":{"type":"test"}}}
EOF

cat >"$FAKE_OMARCHY/bin/omarchy-agent-meter" <<'EOF'
#!/bin/bash
usage_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage"
mkdir -p "$usage_dir"
echo '{"schemaVersion":1,"id":"good","name":"Remote Good","totalPrompts":9}' >"$usage_dir/good.json"
EOF
chmod +x "$FAKE_OMARCHY/bin/omarchy-agent-meter"

HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_STATE_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" good 2>/dev/null ||
  fail "update accepts a successful system meter collection"
[[ $(jq -r '.name' "$usage_dir/good.json") == "Remote Good" ]] ||
  fail "local collector overwrites a fresh system meter record"
pass "update gives a successful system meter collection precedence"

cat >"$FAKE_OMARCHY/bin/omarchy-agent-meter" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$FAKE_OMARCHY/bin/omarchy-agent-meter"

HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_STATE_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" good 2>/dev/null ||
  fail "update falls back when the system meter fails"
[[ $(jq -r '.name' "$usage_dir/good.json") == "Good Agent" ]] ||
  fail "update does not resume its local collector after a meter failure"
pass "update falls back to the local collector when the meter fails"

jq '.sources.good.enabled = false' "$TEST_HOME/.config/omarchy/agent-meter.json" \
  >"$TEST_HOME/.config/omarchy/agent-meter.disabled.json"
mv "$TEST_HOME/.config/omarchy/agent-meter.disabled.json" \
  "$TEST_HOME/.config/omarchy/agent-meter.json"
cat >"$FAKE_OMARCHY/bin/omarchy-agent-meter" <<'EOF'
#!/bin/bash
touch "$HOME/meter-called"
exit 1
EOF
chmod +x "$FAKE_OMARCHY/bin/omarchy-agent-meter"

HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_STATE_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" good 2>/dev/null ||
  fail "update cannot use a local collector after remote tracking is disabled"
[[ $(jq -r '.name' "$usage_dir/good.json") == "Good Agent" ]] ||
  fail "disabled remote source still replaces local collection"
[[ ! -e $TEST_HOME/meter-called ]] ||
  fail "disabled remote source is still contacted"
pass "update honors the local usage source selection"
