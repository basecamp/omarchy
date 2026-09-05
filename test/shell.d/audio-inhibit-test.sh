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
  echo '[{"index":1,"corked":false,"mute":false,"name":"Firefox","properties":{"application.name":"Firefox"}}]'
  exit 0
fi
exit 1
EOF
chmod +x "$BIN_DIR/pactl"

# Mock unlocked session by default
cat >"$BIN_DIR/omarchy-hyprland-session-locked" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$BIN_DIR/omarchy-hyprland-session-locked"

# 1. Active playback claims stay-awake
HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

stay_awake_file="$TEST_HOME/.local/state/omarchy/indicators/stay-awake"
[[ -f $stay_awake_file ]] || fail "audio inhibitor claims stay-awake when audio is playing"
pass "audio inhibitor claims stay-awake when audio is playing"

[[ $(<"$stay_awake_file") == omarchy-audio-inhibit:* ]] ||
  fail "audio inhibitor writes an ownership token"
pass "audio inhibitor writes an ownership token"

# 2. Background daemon audio (e.g. Voxtype) and event sounds do not trigger stay-awake
cat >"$BIN_DIR/pactl" <<'EOF'
#!/bin/bash
if [[ $1 == "--format=json" && $2 == "list" && $3 == "sink-inputs" ]]; then
  echo '[{"index":2,"corked":false,"mute":false,"properties":{"application.name":"PipeWire ALSA [voxtype-vulkan]","node.name":"alsa_playback.voxtype-vulkan"}},{"index":3,"corked":false,"mute":false,"properties":{"media.role":"event"}}]'
  exit 0
fi
exit 1
EOF

HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

[[ ! -f $stay_awake_file ]] ||
  fail "audio inhibitor ignores background daemons and event sounds"
pass "audio inhibitor ignores background daemons and event sounds"

# 3. User explicitly removes stay-awake while audio is playing
cat >"$BIN_DIR/pactl" <<'EOF'
#!/bin/bash
if [[ $1 == "--format=json" && $2 == "list" && $3 == "sink-inputs" ]]; then
  echo '[{"index":1,"corked":false,"mute":false,"name":"Firefox","properties":{"application.name":"Firefox"}}]'
  exit 0
fi
exit 1
EOF

HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

rm -f "$stay_awake_file"

HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

[[ ! -f $stay_awake_file ]] ||
  fail "audio inhibitor does not re-assert stay-awake when user explicitly dismissed it"
pass "audio inhibitor does not re-assert stay-awake when user explicitly dismissed it"

status=$(HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --status)
[[ $status == *"suppressed"* ]] || fail "audio inhibitor status reflects user suppression"
pass "audio inhibitor status reflects user suppression"

# 4. Audio stops completely -> resets suppression
cat >"$BIN_DIR/pactl" <<'EOF'
#!/bin/bash
if [[ $1 == "--format=json" && $2 == "list" && $3 == "sink-inputs" ]]; then
  echo '[]'
  exit 0
fi
exit 1
EOF

HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

[[ ! -f "$TEST_RUNTIME/omarchy-audio-inhibit/suppressed" ]] ||
  fail "stopping audio resets playback session suppression"
pass "stopping audio resets playback session suppression"

# 5. Starting a new audio playback session re-claims stay-awake
cat >"$BIN_DIR/pactl" <<'EOF'
#!/bin/bash
if [[ $1 == "--format=json" && $2 == "list" && $3 == "sink-inputs" ]]; then
  echo '[{"index":4,"corked":false,"mute":false,"name":"Spotify","properties":{"application.name":"Spotify"}}]'
  exit 0
fi
exit 1
EOF

HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

[[ -f $stay_awake_file ]] ||
  fail "new audio playback session re-claims stay-awake automatically"
pass "new audio playback session re-claims stay-awake automatically"

# 6. Session lock releases stay-awake to allow display sleep
cat >"$BIN_DIR/omarchy-hyprland-session-locked" <<'EOF'
#!/bin/bash
exit 0
EOF

HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

[[ ! -f $stay_awake_file ]] ||
  fail "audio inhibitor releases stay-awake while session is locked"
pass "audio inhibitor releases stay-awake while session is locked"

# 7. User-owned stay-awake is preserved when audio stops
cat >"$BIN_DIR/omarchy-hyprland-session-locked" <<'EOF'
#!/bin/bash
exit 1
EOF

mkdir -p "$TEST_HOME/.local/state/omarchy/indicators"
echo "user-choice" >"$stay_awake_file"

cat >"$BIN_DIR/pactl" <<'EOF'
#!/bin/bash
if [[ $1 == "--format=json" && $2 == "list" && $3 == "sink-inputs" ]]; then
  echo '[]'
  exit 0
fi
exit 1
EOF

HOME="$TEST_HOME" XDG_RUNTIME_DIR="$TEST_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

[[ $(<"$stay_awake_file") == "user-choice" ]] ||
  fail "audio inhibitor does not clear user-set stay-awake on audio pause"
pass "audio inhibitor does not clear user-set stay-awake on audio pause"

# 8. Stranded token from prior boot/run is cleaned up at startup when no audio is playing
BOOT_HOME=$(mktemp -d)
BOOT_RUNTIME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$TEST_RUNTIME" "$BIN_DIR" "$BOOT_HOME" "$BOOT_RUNTIME"' EXIT

mkdir -p "$BOOT_HOME/.local/state/omarchy/indicators"
echo "omarchy-audio-inhibit:99999:1234:5678" >"$BOOT_HOME/.local/state/omarchy/indicators/stay-awake"

HOME="$BOOT_HOME" XDG_RUNTIME_DIR="$BOOT_RUNTIME" \
  "$ROOT/bin/omarchy-audio-inhibit" --once

[[ ! -f "$BOOT_HOME/.local/state/omarchy/indicators/stay-awake" ]] ||
  fail "audio inhibitor cleans up stranded tokens from previous boots on startup"
pass "audio inhibitor cleans up stranded tokens from previous boots on startup"
