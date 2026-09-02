#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq

TEST_HOME=$(mktemp -d)
TEST_RUNTIME=$(mktemp -d)
BIN_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$TEST_RUNTIME" "$BIN_DIR"' EXIT

PATH="$BIN_DIR:$PATH"

# Mock pactl with active playback
cat >"$BIN_DIR/pactl" <<'EOF'
#!/bin/bash
if [[ $1 == "--format=json" && $2 == "list" && $3 == "sink-inputs" ]]; then
  echo '[{"index":1,"corked":false,"mute":false,"name":"Firefox"}]'
  exit 0
fi
exit 1
EOF
chmod +x "$BIN_DIR/pactl"

# 1. Active playback claims stay-awake
HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

stay_awake_file="$TEST_HOME/.local/state/omarchy/indicators/stay-awake"
[[ -f $stay_awake_file ]] || fail "audio inhibitor claims stay-awake when audio is playing"
pass "audio inhibitor claims stay-awake when audio is playing"

[[ $(<"$stay_awake_file") == omarchy-audio-inhibit:* ]] ||
  fail "audio inhibitor writes an ownership token"
pass "audio inhibitor writes an ownership token"

status=$(HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --status)
[[ $status == "playing" ]] || fail "audio inhibitor --status reports playing during playback"
pass "audio inhibitor --status reports playing during playback"

# 2. Corked/paused playback releases owned stay-awake
cat >"$BIN_DIR/pactl" <<'EOF'
#!/bin/bash
if [[ $1 == "--format=json" && $2 == "list" && $3 == "sink-inputs" ]]; then
  echo '[{"index":1,"corked":true,"mute":false,"name":"Firefox"}]'
  exit 0
fi
exit 1
EOF

HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

[[ ! -f $stay_awake_file ]] || fail "audio inhibitor releases stay-awake when audio pauses"
pass "audio inhibitor releases stay-awake when audio pauses"

status=$(HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --status)
[[ $status == "idle" ]] || fail "audio inhibitor --status reports idle when audio is paused"
pass "audio inhibitor --status reports idle when audio is paused"

# 3. User-owned stay-awake is preserved when audio stops
mkdir -p "$TEST_HOME/.local/state/omarchy/indicators"
echo "user-choice" >"$stay_awake_file"

HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

[[ $(<"$stay_awake_file") == "user-choice" ]] ||
  fail "audio inhibitor does not clear user-set stay-awake on audio pause"
pass "audio inhibitor does not clear user-set stay-awake on audio pause"
