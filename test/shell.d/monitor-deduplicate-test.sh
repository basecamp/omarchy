#!/bin/bash

source "$(dirname "$0")/base-test.sh"

bin_dir=$(mktemp -d)
monitors_file=$(mktemp)
calls_file=$(mktemp)

cleanup() {
  rm -rf "$bin_dir"
  rm -f "$monitors_file" "$calls_file"
}
trap cleanup EXIT

cat >"$bin_dir/hyprctl" <<'EOF'
#!/bin/bash
if [[ $* == "monitors all -j" ]]; then
  cat "$FAKE_MONITORS"
elif [[ $1 == "eval" ]]; then
  printf '%s\n' "$2" >>"$FAKE_CALLS"
else
  exit 1
fi
EOF
chmod +x "$bin_dir/hyprctl"

run_deduplicate() {
  : >"$calls_file"
  FAKE_MONITORS="$monitors_file" FAKE_CALLS="$calls_file" PATH="$bin_dir:$PATH" \
    bash "$ROOT/bin/omarchy-hyprland-monitor-deduplicate"
}

cat >"$monitors_file" <<'EOF'
[
  { "name": "DP-1", "make": "Dell Inc.", "model": "DELL U2720Q", "serial": "2PBGZ13", "disabled": false, "focused": false },
  { "name": "DP-3", "make": "Dell Inc.", "model": "DELL U2720Q", "serial": "2PBGZ13", "disabled": false, "focused": true }
]
EOF
run_deduplicate
[[ $(<"$calls_file") == 'hl.monitor({ output = "DP-1", disabled = true })' ]] ||
  fail "duplicate outputs keep the focused output" "calls: $(<"$calls_file")"
pass "duplicate outputs keep the focused output"

cat >"$monitors_file" <<'EOF'
[
  { "name": "DP-1", "make": "Dell Inc.", "model": "DELL U2720Q", "serial": "FIRST", "disabled": false, "focused": true },
  { "name": "DP-3", "make": "Dell Inc.", "model": "DELL U2720Q", "serial": "SECOND", "disabled": false, "focused": false }
]
EOF
run_deduplicate
[[ ! -s $calls_file ]] || fail "separate monitors with the same model stay enabled" "calls: $(<"$calls_file")"
pass "separate monitors with the same model stay enabled"

cat >"$monitors_file" <<'EOF'
[
  { "name": "DP-1", "make": "Dell Inc.", "model": "DELL U2720Q", "serial": "2PBGZ13", "disabled": false, "focused": false },
  { "name": "DP-3", "make": "Dell Inc.", "model": "DELL U2720Q", "serial": "2PBGZ13", "disabled": false, "focused": false }
]
EOF
run_deduplicate
[[ $(<"$calls_file") == 'hl.monitor({ output = "DP-3", disabled = true })' ]] ||
  fail "duplicate outputs choose a stable output before focus exists" "calls: $(<"$calls_file")"
pass "duplicate outputs choose a stable output before focus exists"

cat >"$monitors_file" <<'EOF'
[
  { "name": "DP-1", "make": "Dell Inc.", "model": "DELL U2720Q", "serial": "2PBGZ13", "disabled": true, "focused": false },
  { "name": "DP-3", "make": "Dell Inc.", "model": "DELL U2720Q", "serial": "2PBGZ13", "disabled": false, "focused": true }
]
EOF
run_deduplicate
[[ ! -s $calls_file ]] || fail "an already disabled duplicate stays untouched" "calls: $(<"$calls_file")"
pass "an already disabled duplicate stays untouched"
