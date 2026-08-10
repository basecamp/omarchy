#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub="$tmpdir/notify-send"
args_file="$tmpdir/args"

printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s\n" "$@" >"$OMARCHY_TEST_NOTIFY_ARGS"' \
  >"$stub"
chmod +x "$stub"

OMARCHY_TEST_NOTIFY_ARGS="$args_file" PATH="$tmpdir:$ROOT/bin:$PATH" \
  omarchy-notification-send --app-name custom-app -g K -u critical --image /tmp/image.png \
  --exec "omarchy-menu-keybindings 'a b'" "Learn Keybindings" "Body"

mapfile -t args <"$args_file"

[[ ${args[0]} == "-a" ]] || fail "notification wrapper passes app flag"
[[ ${args[1]} == "custom-app" ]] || fail "notification wrapper uses custom app name"
[[ ${args[2]} == "-u" ]] || fail "notification wrapper passes urgency flag"
[[ ${args[3]} == "critical" ]] || fail "notification wrapper uses custom urgency"
[[ ${args[4]} == "--hint=string:omarchy-glyph:K" ]] || fail "notification wrapper converts glyph to hint"
[[ ${args[5]} == "--hint=string:image-path:/tmp/image.png" ]] || fail "notification wrapper converts image to hint"
[[ ${args[6]} == "--hint=string:omarchy-exec:omarchy-menu-keybindings 'a b'" ]] || fail "notification wrapper converts exec to hint"
[[ ${args[7]} == "Learn Keybindings" ]] || fail "notification wrapper preserves headline"
[[ ${args[8]} == "Body" ]] || fail "notification wrapper preserves description"
pass "notification wrapper supports app, glyph, urgency, image, and exec options"

# The shell runs the click command itself, so nothing may block the sender on a
# libnotify action round-trip.
grep -q -- "-A" "$args_file" && fail "notification wrapper must not register a libnotify action"

: >"$args_file"
OMARCHY_TEST_NOTIFY_ARGS="$args_file" PATH="$tmpdir:$ROOT/bin:$PATH" \
  omarchy-notification-send "Plain" >/dev/null

grep -q "omarchy-exec" "$args_file" && fail "notification wrapper adds no exec hint without --exec"
pass "notification wrapper omits the exec hint when no command is given"

if OMARCHY_TEST_NOTIFY_ARGS="$args_file" PATH="$tmpdir:$ROOT/bin:$PATH" \
  omarchy-notification-send "Headline" --exec 2>/dev/null; then
  fail "notification wrapper rejects --exec without a command"
fi
pass "notification wrapper rejects --exec without a command"
