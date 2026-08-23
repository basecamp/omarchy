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

send() {
  OMARCHY_TEST_NOTIFY_ARGS="$args_file" PATH="$tmpdir:$ROOT/bin:$PATH" \
    omarchy-notification-send "$@"
}

# --exec consumes the rest of the line, so it comes after the headline/description.
send --app-name custom-app -g K -u critical --image /tmp/image.png \
  "Learn Keybindings" "Body" --exec omarchy-menu-keybindings 'a b'

mapfile -t args <"$args_file"

[[ ${args[0]} == "-a" ]] || fail "notification wrapper passes app flag"
[[ ${args[1]} == "custom-app" ]] || fail "notification wrapper uses custom app name"
[[ ${args[2]} == "-u" ]] || fail "notification wrapper passes urgency flag"
[[ ${args[3]} == "critical" ]] || fail "notification wrapper uses custom urgency"
[[ ${args[4]} == "--hint=string:omarchy-glyph:K" ]] || fail "notification wrapper converts glyph to hint"
[[ ${args[5]} == "--hint=string:image-path:/tmp/image.png" ]] || fail "notification wrapper converts image to hint"
[[ ${args[6]} == '--hint=string:omarchy-exec-argv:["omarchy-menu-keybindings","a b"]' ]] || fail "notification wrapper converts the click command to an argv hint" "${args[6]}"
[[ ${args[7]} == "--" ]] || fail "notification wrapper ends the options before the text" "${args[7]}"
[[ ${args[8]} == "Learn Keybindings" ]] || fail "notification wrapper preserves headline"
[[ ${args[9]} == "Body" ]] || fail "notification wrapper preserves description"
pass "notification wrapper supports app, glyph, urgency, image, and exec options"

# The shell runs the click command itself, so nothing may block the sender on a
# libnotify action round-trip.
grep -q -- "-A" "$args_file" && fail "notification wrapper must not register a libnotify action"

: >"$args_file"
send "Plain" >/dev/null
grep -q "omarchy-exec" "$args_file" && fail "notification wrapper adds no exec hint without --exec"
pass "notification wrapper omits the exec hint when no command is given"

# Rest-of-line --exec: the caller's shell has already split the words into
# discrete arguments, and the shell runs them without re-parsing, so shell
# metacharacters in a value are carried as data, never as a command.
: >"$args_file"
send "Download complete" --exec mpv -- '$(rm -rf ~); echo pwned' >/dev/null
argv_hint=$(grep -- "--hint=string:omarchy-exec-argv:" "$args_file")
argv_json=${argv_hint#--hint=string:omarchy-exec-argv:}
[[ $(jq -r '.[0]' <<<"$argv_json") == "mpv" ]] || fail "notification wrapper puts the program first in the exec argv"
[[ $(jq -r '.[1]' <<<"$argv_json") == "--" ]] || fail "notification wrapper preserves a -- separator in the exec argv"
[[ $(jq -r '.[2]' <<<"$argv_json") == '$(rm -rf ~); echo pwned' ]] ||
  fail "notification wrapper carries shell metacharacters as literal argv data" "$argv_json"
pass "notification wrapper encodes rest-of-line --exec as a literal JSON argv vector"

# A quoted argument with spaces stays ONE argument — something a whitespace-split
# of a single string could never do.
: >"$args_file"
send "Head" --exec mpv -- "/tmp/a b.mp4" >/dev/null
argv_hint=$(grep -- "--hint=string:omarchy-exec-argv:" "$args_file")
argv_json=${argv_hint#--hint=string:omarchy-exec-argv:}
[[ $(jq 'length' <<<"$argv_json") == 3 ]] || fail "notification wrapper keeps a spaced path as one argument" "$argv_json"
[[ $(jq -r '.[2]' <<<"$argv_json") == "/tmp/a b.mp4" ]] || fail "notification wrapper preserves the spaced path verbatim" "$argv_json"
pass "notification wrapper keeps a spaced argument intact"

# The muscle-memory trap: a single quoted whole command would run a program named
# with spaces. Reject it and point at the unquoted form rather than splitting it
# ourselves (which is the injection we avoid).
: >"$args_file"
if send "Head" --exec "omarchy toggle something" 2>/dev/null; then
  fail "notification wrapper rejects a quoted whole command"
fi
grep -q "omarchy-exec" "$args_file" && fail "notification wrapper emits no hint for a rejected --exec"
pass "notification wrapper rejects a single quoted whole command"

# --exec with nothing after it is a usage error, not a silent no-op.
if send "Head" --exec 2>/dev/null; then
  fail "notification wrapper rejects --exec with no command"
fi
pass "notification wrapper rejects --exec with no command"

# --exec is recognized only after the positionals, so an untrusted headline or
# description that is literally "--exec" is taken as text and cannot be mistaken
# for the delimiter (the real --exec later still wins).
: >"$args_file"
send "--exec" "a body" --image /tmp/i.png --exec mpv -- /tmp/v.mp4 >/dev/null
argv_hint=$(grep -- "--hint=string:omarchy-exec-argv:" "$args_file")
argv_json=${argv_hint#--hint=string:omarchy-exec-argv:}
[[ $(jq -c '.' <<<"$argv_json") == '["mpv","--","/tmp/v.mp4"]' ]] || fail "notification wrapper ignores a --exec-looking headline as the delimiter" "$argv_json"
grep -qx -- "--exec" "$args_file" || fail "notification wrapper keeps a --exec-looking headline as text"
grep -q 'image-path:/tmp/i.png' "$args_file" || fail "notification wrapper still parses options after a --exec-looking headline"
pass "notification wrapper does not treat a --exec-looking positional as the delimiter"

# The headline and description are text, never options. notify-send parses a
# leading-dash summary as flags ("-rf x" is -r with the value x) and reads a
# `--hint=string:...` word as a hint, so they go behind a `--` separator.
: >"$args_file"
send "-rf oops" "a body" >/dev/null
mapfile -t args <"$args_file"
[[ ${args[-3]} == "--" ]] || fail "notification wrapper separates a dash headline from the options" "${args[*]}"
[[ ${args[-2]} == "-rf oops" ]] || fail "notification wrapper keeps a dash headline as text" "${args[*]}"
[[ ${args[-1]} == "a body" ]] || fail "notification wrapper keeps the description after a dash headline" "${args[*]}"
pass "notification wrapper hands the headline to notify-send as text, not options"

# The click command has exactly one door. A relayed title or filename that
# reaches option position must not be able to forge the hint --exec produces.
: >"$args_file"
if send "Download complete" '--hint=string:omarchy-exec-argv:["sh","-c","touch /tmp/pwned"]' 2>/dev/null; then
  fail "notification wrapper rejects a forged click-command hint"
fi
grep -q "omarchy-exec-argv" "$args_file" && fail "notification wrapper sends nothing when a click hint is forged"
pass "notification wrapper refuses a click-command hint it did not build from --exec"
