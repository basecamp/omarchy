#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_bin=$(mktemp -d)
monitors_file=$(mktemp)

cleanup() {
  rm -rf "$test_bin"
  rm -f "$monitors_file"
}
trap cleanup EXIT

cat >"$test_bin/hyprctl" <<'EOF'
#!/bin/bash
[[ $* == "monitors all -j" ]] || exit 1
cat "$FAKE_MONITORS"
EOF

cat >"$test_bin/omarchy-brightness-display" <<'EOF'
#!/bin/bash
echo 42
EOF

cat >"$test_bin/omarchy-hyprland-monitor-scaling" <<'EOF'
#!/bin/bash
echo 1.5
EOF

chmod +x "$test_bin"/*

# The panel reads this output by line index, so every case has to answer with
# the same number of lines. A helper that dies mid-script drops its line and
# silently shifts every field below it into the wrong property.
state_lines=()
monitor_state() {
  printf '%s\n' "$1" >"$monitors_file"

  mapfile -t state_lines < <(
    FAKE_MONITORS="$monitors_file" PATH="$test_bin:$PATH" \
      bash "$ROOT/bin/omarchy-monitor-state" 2>/dev/null
  )
}

assert_line() {
  local index="$1" expected="$2" description="$3"

  [[ ${state_lines[index]-} == "$expected" ]] ||
    fail "$description" "line $index expected: $expected"$'\n'"line $index actual:   ${state_lines[index]-<missing>}"
}

assert_line_count() {
  local description="$1"

  (( ${#state_lines[@]} == 8 )) ||
    fail "$description" "expected 8 lines, got ${#state_lines[@]}"
}

extended='[
  { "name": "eDP-1", "mirrorOf": "none", "disabled": false, "focused": false, "width": 1920, "height": 1080 },
  { "name": "DP-1", "mirrorOf": "none", "disabled": false, "focused": true, "width": 2560, "height": 1440 }
]'

# Omarchy mirrors by pointing the external at the internal, so `mirrorOf` lands
# on the external and the internal keeps saying "none".
mirrored='[
  { "name": "eDP-1", "mirrorOf": "none", "disabled": false, "focused": true, "width": 1920, "height": 1080 },
  { "name": "DP-1", "mirrorOf": "eDP-1", "disabled": false, "focused": false, "width": 1920, "height": 1080 }
]'

# A monitors.lua of the user's own can mirror the other way instead.
reverse_mirrored='[
  { "name": "eDP-1", "mirrorOf": "DP-1", "disabled": false, "focused": false, "width": 2560, "height": 1440 },
  { "name": "DP-1", "mirrorOf": "none", "disabled": false, "focused": true, "width": 2560, "height": 1440 }
]'

clamshell='[
  { "name": "eDP-1", "mirrorOf": "none", "disabled": true, "focused": false, "width": 0, "height": 0 },
  { "name": "DP-1", "mirrorOf": "none", "disabled": false, "focused": true, "width": 2560, "height": 1440 }
]'

monitor_state "$extended"
assert_line_count "monitor state answers every line while extended"
assert_line 0 42 "monitor state reports brightness"
assert_line 1 eDP-1 "monitor state names the internal monitor"
assert_line 2 DP-1 "monitor state names the external monitor"
assert_line 3 eDP-1 "monitor state reports the internal monitor enabled"
assert_line 4 "" "monitor state reports no mirror while extended"
assert_line 5 DP-1 "monitor state reports the focused monitor"
assert_line 6 1.5 "monitor state reports the scale"
pass "monitor state keeps its lines aligned when nothing is mirrored"

monitor_state "$mirrored"
assert_line_count "monitor state answers every line while mirroring"
assert_line 4 DP-1 "monitor state names the mirroring external monitor"
assert_line 5 eDP-1 "monitor state still reports the focused monitor while mirroring"
pass "monitor state reports the external monitor when it mirrors the internal"

monitor_state "$reverse_mirrored"
assert_line_count "monitor state answers every line while mirroring in reverse"
assert_line 4 DP-1 "monitor state names the external monitor either way round"
pass "monitor state reports the external monitor when the internal mirrors it"

monitor_state "$clamshell"
assert_line_count "monitor state answers every line while clamshelled"
assert_line 1 eDP-1 "monitor state still names a disabled internal monitor"
assert_line 3 "" "monitor state reports the internal monitor disabled"
assert_line 4 "" "monitor state reports no mirror while clamshelled"
pass "monitor state separates a disabled internal monitor from a missing one"

monitor_state "$extended"
[[ ${state_lines[7]-} == '[{"name":"eDP-1","enabled":true,"focused":false,"width":1920,"height":1080},{"name":"DP-1","enabled":true,"focused":true,"width":2560,"height":1440}]' ]] ||
  fail "monitor state lists every display for the panel" "actual: ${state_lines[7]-<missing>}"
monitor_state "$clamshell"
[[ ${state_lines[7]-} == '[{"name":"eDP-1","enabled":false,"focused":false,"width":0,"height":0},{"name":"DP-1","enabled":true,"focused":true,"width":2560,"height":1440}]' ]] ||
  fail "monitor state lists every display for the panel" "actual: ${state_lines[7]-<missing>}"
pass "monitor state lists every display with its enabled and focused state"
