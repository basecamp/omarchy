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
  --exec-arg omarchy-menu-keybindings --exec-arg 'a b' "Learn Keybindings" "Body"

mapfile -t args <"$args_file"

[[ ${args[0]} == "-a" ]] || fail "notification wrapper passes app flag"
[[ ${args[1]} == "custom-app" ]] || fail "notification wrapper uses custom app name"
[[ ${args[2]} == "-u" ]] || fail "notification wrapper passes urgency flag"
[[ ${args[3]} == "critical" ]] || fail "notification wrapper uses custom urgency"
[[ ${args[4]} == "--hint=string:omarchy-glyph:K" ]] || fail "notification wrapper converts glyph to hint"
[[ ${args[5]} == "--hint=string:image-path:/tmp/image.png" ]] || fail "notification wrapper converts image to hint"
[[ ${args[6]} == '--hint=string:omarchy-exec-argv:["omarchy-menu-keybindings","a b"]' ]] || fail "notification wrapper converts exec args to an argv hint" "${args[6]}"
[[ ${args[7]} == "Learn Keybindings" ]] || fail "notification wrapper preserves headline"
[[ ${args[8]} == "Body" ]] || fail "notification wrapper preserves description"
pass "notification wrapper supports app, glyph, urgency, image, and exec-arg options"

# The shell runs the click command itself, so nothing may block the sender on a
# libnotify action round-trip.
grep -q -- "-A" "$args_file" && fail "notification wrapper must not register a libnotify action"

: >"$args_file"
OMARCHY_TEST_NOTIFY_ARGS="$args_file" PATH="$tmpdir:$ROOT/bin:$PATH" \
  omarchy-notification-send "Plain" >/dev/null

grep -q "omarchy-exec" "$args_file" && fail "notification wrapper adds no exec hint without --exec"
pass "notification wrapper omits the exec hint when no command is given"

# The free-form shell-string --exec is gone: its existence let a caller skip
# quoting and reintroduce the RCE, so it is rejected outright in favor of the
# argv-only --exec-arg.
: >"$args_file"
if OMARCHY_TEST_NOTIFY_ARGS="$args_file" PATH="$tmpdir:$ROOT/bin:$PATH" \
  omarchy-notification-send --exec 'anything' "Headline" 2>/dev/null; then
  fail "notification wrapper rejects the removed --exec flag"
fi
grep -q "omarchy-exec" "$args_file" && fail "notification wrapper emits no exec hint for a rejected --exec"
pass "notification wrapper rejects the removed --exec flag"

# --exec-arg builds an argv vector encoded as a JSON array, so shell
# metacharacters in a value are carried as data, never as a command. The shell
# runs this argv directly (no shell), which is what keeps a hostile title or
# filename from becoming code when the toast is clicked.
: >"$args_file"
OMARCHY_TEST_NOTIFY_ARGS="$args_file" PATH="$tmpdir:$ROOT/bin:$PATH" \
  omarchy-notification-send --exec-arg mpv --exec-arg -- --exec-arg '$(rm -rf ~); echo pwned' \
  "Download complete" >/dev/null

argv_hint=$(grep -- "--hint=string:omarchy-exec-argv:" "$args_file")
argv_json=${argv_hint#--hint=string:omarchy-exec-argv:}
[[ $(jq -r '.[0]' <<<"$argv_json") == "mpv" ]] || fail "notification wrapper puts the program first in the exec argv"
[[ $(jq -r '.[1]' <<<"$argv_json") == "--" ]] || fail "notification wrapper preserves a -- separator in the exec argv"
[[ $(jq -r '.[2]' <<<"$argv_json") == '$(rm -rf ~); echo pwned' ]] ||
  fail "notification wrapper carries shell metacharacters as literal argv data" "$argv_json"
grep -q "omarchy-exec:" "$args_file" && fail "notification wrapper emits no legacy exec string when --exec-arg is used"
pass "notification wrapper encodes --exec-arg as a literal JSON argv vector"
