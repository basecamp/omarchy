#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"
args_file="$test_dir/args"

cat >"$test_dir/bin/omarchy-launch-or-focus" <<'STUB'
#!/bin/bash
printf '%s\0' "$@" >"$ARGS_FILE"
STUB
chmod +x "$test_dir/bin/omarchy-launch-or-focus"

ARGS_FILE="$args_file" PATH="$test_dir/bin:$PATH" \
  "$ROOT/bin/omarchy-launch-or-focus-webapp" \
  '^chrome-teams[.]microsoft[.]com__-Profile_2$' \
  'https://teams.microsoft.com' \
  '--profile-directory=Profile 2'

mapfile -d '' -t args <"$args_file"
[[ ${#args[@]} == 4 ]] || fail "webapp launcher preserves argument count" "got ${#args[@]} arguments"
[[ ${args[0]} == '^chrome-teams[.]microsoft[.]com__-Profile_2$' ]] || fail "webapp launcher preserves window pattern"
[[ ${args[1]} == "omarchy-launch-webapp" ]] || fail "webapp launcher forwards the launch command"
[[ ${args[2]} == "https://teams.microsoft.com" ]] || fail "webapp launcher preserves URL"
[[ ${args[3]} == "--profile-directory=Profile 2" ]] || fail "webapp launcher preserves flags containing spaces"
pass "webapp launcher forwards URL and flags as discrete arguments"

ARGS_FILE="$args_file" PATH="$test_dir/bin:$PATH" \
  "$ROOT/bin/omarchy-launch-or-focus-tui" \
  --app-id=org.custom \
  command-name \
  'argument with spaces' \
  '--literal=*'

mapfile -d '' -t args <"$args_file"
[[ ${#args[@]} == 6 ]] || fail "TUI launcher preserves argument count" "got ${#args[@]} arguments"
[[ ${args[0]} == "org.custom" ]] || fail "TUI launcher forwards the app ID as the window pattern"
[[ ${args[1]} == "omarchy-launch-tui" ]] || fail "TUI launcher forwards the launch command"
[[ ${args[2]} == "--app-id=org.custom" ]] || fail "TUI launcher preserves its app ID flag"
[[ ${args[3]} == "command-name" ]] || fail "TUI launcher preserves the command"
[[ ${args[4]} == "argument with spaces" ]] || fail "TUI launcher preserves spaces"
[[ ${args[5]} == '--literal=*' ]] || fail "TUI launcher preserves glob characters"
pass "TUI launcher forwards arguments without reparsing"

launch_sole=$(lua - "$ROOT/default/hypr/helpers.lua" <<'LUA'
dofile(arg[1])
print(o.launch_sole("^obsidian$", "obsidian --flag"))
LUA
)
[[ $launch_sole == "omarchy-launch-or-focus '^obsidian$' bash -c 'uwsm-app -- obsidian --flag'" ]] ||
  fail "Hyprland launch helper requests shell evaluation explicitly" "got: $launch_sole"
pass "Hyprland launch helper requests shell evaluation explicitly"

cat >"$test_dir/bin/hyprctl" <<'STUB'
#!/bin/bash
printf '[]\n'
STUB
cat >"$test_dir/bin/setsid" <<'STUB'
#!/bin/bash
printf '%s\0' "$@" >"$ARGS_FILE"
STUB
chmod +x "$test_dir/bin/hyprctl" "$test_dir/bin/setsid"

ARGS_FILE="$args_file" PATH="$test_dir/bin:$PATH" \
  "$ROOT/bin/omarchy-launch-or-focus" \
  'missing-window' command-name 'argument with spaces' '--literal=*'

mapfile -d '' -t args <"$args_file"
[[ ${#args[@]} == 3 ]] || fail "argv launch mode preserves argument count" "got ${#args[@]} arguments"
[[ ${args[0]} == "command-name" ]] || fail "argv launch mode preserves command"
[[ ${args[1]} == "argument with spaces" ]] || fail "argv launch mode preserves spaces"
[[ ${args[2]} == '--literal=*' ]] || fail "argv launch mode does not expand glob characters"
pass "launch-or-focus argv mode executes arguments without reparsing"

ARGS_FILE="$args_file" PATH="$test_dir/bin:$PATH" \
  "$ROOT/bin/omarchy-launch-or-focus" 'default-command'

mapfile -d '' -t args <"$args_file"
[[ ${#args[@]} == 3 ]] || fail "default launch preserves argument count" "got ${#args[@]} arguments"
[[ ${args[0]} == "uwsm-app" ]] || fail "default launch uses uwsm-app"
[[ ${args[1]} == "--" ]] || fail "default launch terminates uwsm-app options"
[[ ${args[2]} == "default-command" ]] || fail "default launch uses the window pattern as its command"
pass "launch-or-focus retains its default launch command"
