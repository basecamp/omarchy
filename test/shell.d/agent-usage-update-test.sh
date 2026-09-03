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

# A collector signed in to several accounts nests the others under
# `accounts`. Each lands as its own file inside the collector's namespace,
# nothing else does, and a namespaced file it stops reporting goes away.
cat >"$FAKE_OMARCHY/bin/omarchy-agent-usage-multi" <<'EOF2'
#!/bin/bash
echo '{"id":"multi","name":"Multi","accounts":[{"id":"multi-work","name":"Multi · work"},{"id":"other-work","name":"Escapee"},{"id":"multi-bad/../x","name":"Traversal"}]}'
EOF2
chmod +x "$FAKE_OMARCHY/bin/omarchy-agent-usage-multi"
echo '{"id":"multi-old"}' >"$usage_dir/multi-old.json"

HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_STATE_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" multi 2>/dev/null ||
  fail "update succeeds for a collector that nests account records"
pass "update succeeds for a collector that nests account records"

[[ $(jq -r '.name' "$usage_dir/multi-work.json") == "Multi · work" ]] ||
  fail "update writes each nested account record as its own file"
pass "update writes each nested account record as its own file"

[[ $(jq -r 'has("accounts")' "$usage_dir/multi.json") == "false" ]] ||
  fail "update strips the nested records from the collector's own file"
pass "update strips the nested records from the collector's own file"

[[ ! -e $usage_dir/other-work.json && -z $(find "$usage_dir" -name '*bad*') ]] ||
  fail "update refuses nested records outside the collector's namespace"
pass "update refuses nested records outside the collector's namespace"

[[ ! -e $usage_dir/multi-old.json ]] ||
  fail "update removes namespaced records the collector no longer reports"
pass "update removes namespaced records the collector no longer reports"
