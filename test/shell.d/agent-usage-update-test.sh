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

# XDG_CONFIG_HOME is pinned so a collectors.d on the developer's own machine
# cannot leak into the run.
HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_STATE_HOME="" XDG_CONFIG_HOME="" \
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

HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_STATE_HOME="" XDG_CONFIG_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" skipped 2>/dev/null ||
  fail "update succeeds when the requested collectors all pass"
pass "update succeeds when the requested collectors all pass"

[[ -e $usage_dir/skipped.json && ! -e $usage_dir/noisy.json ]] ||
  fail "update with agent arguments only runs the named collectors"
pass "update with agent arguments only runs the named collectors"

# User collectors in ~/.config/omarchy/agents/collectors.d/ join the shipped
# ones — that is how a second account of a shipped agent exists. One with a
# shipped collector's name replaces it, and everything else (--except, the
# record naming) treats them alike.
user_dir="$TEST_HOME/.config/omarchy/agents/collectors.d"
mkdir -p "$user_dir"

cat >"$user_dir/extra" <<'EOF'
#!/bin/bash
echo '{"schemaVersion":1,"id":"extra","name":"Extra Account","mark":"good","totalPrompts":2}'
EOF

cat >"$user_dir/good" <<'EOF'
#!/bin/bash
echo '{"schemaVersion":1,"id":"good","name":"User Good","totalPrompts":5}'
EOF

cat >"$user_dir/passive" <<'EOF'
#!/bin/bash
echo '{"id":"passive"}'
EOF

chmod +x "$user_dir/extra" "$user_dir/good"

HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_STATE_HOME="" XDG_CONFIG_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" --except noisy 2>/dev/null ||
  fail "update succeeds with user collectors present"
pass "update succeeds with user collectors present"

[[ $(jq -r '.name' "$usage_dir/extra.json") == "Extra Account" ]] ||
  fail "update runs user collectors from collectors.d"
pass "update runs user collectors from collectors.d"

[[ $(jq -r '.name' "$usage_dir/good.json") == "User Good" ]] ||
  fail "a user collector with a shipped collector's name replaces it"
pass "a user collector with a shipped collector's name replaces it"

[[ ! -e $usage_dir/passive.json ]] ||
  fail "update ignores non-executable files in collectors.d"
pass "update ignores non-executable files in collectors.d"

rm -f "$usage_dir/extra.json"
HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_STATE_HOME="" XDG_CONFIG_HOME="" \
  "$ROOT/bin/omarchy-agent-usage-update" --except noisy --except extra 2>/dev/null ||
  fail "update succeeds while excluding a user collector"

[[ ! -e $usage_dir/extra.json ]] ||
  fail "update skips user collectors excluded with --except"
pass "update skips user collectors excluded with --except"

# Shared-tree ownership is resolved here, across every enabled account of a
# tool, so wrappers need no manually paired overrides: an explicit claim wins
# and switches the stock account off; without one the stock account counts
# the trees; with neither enabled they stay uncounted. Each fake answers
# --print-identity and otherwise echoes its argv into its record, so the
# assertions read exactly what this command decided.
for spec in "shared-stock:true:auto" "shared-claimer:false:on" "shared-follower:false:auto"; do
  IFS=: read -r name stock pref <<<"$spec"
  cat >"$user_dir/$name" <<EOF
#!/bin/bash
for arg; do
  [[ \$arg == --print-identity ]] && { echo '{"tool":"sharedtool","stock":$stock,"sharedSessions":"$pref"}'; exit 0; }
done
echo "{\"schemaVersion\":1,\"id\":\"$name\",\"args\":\"\$*\"}"
EOF
  chmod +x "$user_dir/$name"
done

run_update() {
  HOME="$TEST_HOME" OMARCHY_PATH="$FAKE_OMARCHY" XDG_STATE_HOME="" XDG_CONFIG_HOME="" \
    "$ROOT/bin/omarchy-agent-usage-update" --except noisy "$@" 2>/dev/null
}

shared_args() {
  jq -r '.args' "$usage_dir/$1.json"
}

run_update || fail "update succeeds while resolving shared-tree ownership"
[[ $(shared_args shared-claimer) == *"--shared-sessions on"* ]] ||
  fail "an explicit claim owns the shared trees" "$(shared_args shared-claimer)"
[[ $(shared_args shared-stock) == *"--shared-sessions off"* ]] ||
  fail "an explicit claim switches the stock account off without a manual override" "$(shared_args shared-stock)"
[[ $(shared_args shared-follower) == *"--shared-sessions off"* ]] ||
  fail "accounts without a claim are switched off" "$(shared_args shared-follower)"
pass "an explicit claim owns the shared trees and switches the stock account off"

run_update --except shared-claimer || fail "update succeeds without the claimant"
[[ $(shared_args shared-stock) == *"--shared-sessions on"* ]] ||
  fail "without an explicit claim the stock account counts the shared trees" "$(shared_args shared-stock)"
[[ $(shared_args shared-follower) == *"--shared-sessions off"* ]] ||
  fail "a non-stock account stays off when the stock account owns the trees" "$(shared_args shared-follower)"
pass "without an explicit claim the stock account counts the shared trees"

run_update --except shared-claimer --except shared-stock || fail "update succeeds without any claimant"
[[ $(shared_args shared-follower) == *"--shared-sessions off"* ]] ||
  fail "with no claimant and no stock account the shared trees stay uncounted" "$(shared_args shared-follower)"
pass "with no claimant and no stock account the shared trees stay uncounted"

# A partial run must decide ownership over the enabled population, not over
# the agents it happens to regenerate — the claimant owns the trees even
# when only another account refreshes.
rm -f "$usage_dir/shared-follower.json"
run_update shared-follower || fail "update succeeds for a partial run"
[[ $(shared_args shared-follower) == *"--shared-sessions off"* && ! -e $usage_dir/shared-stock.json.tmp ]] ||
  fail "a partial run decides ownership the same way a full one does" "$(shared_args shared-follower)"
pass "a partial run decides ownership the same way a full one does"
