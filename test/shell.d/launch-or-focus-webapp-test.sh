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
[[ ${#args[@]} == 5 ]] || fail "webapp launcher preserves argument count" "got ${#args[@]} arguments"
[[ ${args[0]} == '^chrome-teams[.]microsoft[.]com__-Profile_2$' ]] || fail "webapp launcher preserves window pattern"
[[ ${args[1]} == "--" ]] || fail "webapp launcher selects argv mode"
[[ ${args[2]} == "omarchy-launch-webapp" ]] || fail "webapp launcher forwards the launch command"
[[ ${args[3]} == "https://teams.microsoft.com" ]] || fail "webapp launcher preserves URL"
[[ ${args[4]} == "--profile-directory=Profile 2" ]] || fail "webapp launcher preserves flags containing spaces"
pass "webapp launcher forwards URL and flags as discrete arguments"

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
  'missing-window' -- command-name 'argument with spaces' '--literal=*'

mapfile -d '' -t args <"$args_file"
[[ ${#args[@]} == 3 ]] || fail "argv launch mode preserves argument count" "got ${#args[@]} arguments"
[[ ${args[0]} == "command-name" ]] || fail "argv launch mode preserves command"
[[ ${args[1]} == "argument with spaces" ]] || fail "argv launch mode preserves spaces"
[[ ${args[2]} == '--literal=*' ]] || fail "argv launch mode does not expand glob characters"
pass "launch-or-focus argv mode executes arguments without reparsing"
