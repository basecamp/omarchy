#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

args_file="$tmpdir/args"

# Stub the D-Bus transport and record the Notify call verbatim.
printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s\n" "$@" >"$OMARCHY_TEST_BUSCTL_ARGS"' \
  >"$tmpdir/busctl"
chmod +x "$tmpdir/busctl"

# notify-send must never be used. If anything reaches for it, fail loudly.
printf '%s\n' '#!/bin/bash' 'echo "notify-send was invoked" >"$OMARCHY_TEST_NOTIFY_TRIPWIRE"; exit 3' \
  >"$tmpdir/notify-send"
chmod +x "$tmpdir/notify-send"
tripwire="$tmpdir/notify-send-was-used"

send() {
  OMARCHY_TEST_BUSCTL_ARGS="$args_file" OMARCHY_TEST_NOTIFY_TRIPWIRE="$tripwire" \
    PATH="$tmpdir:$ROOT/bin:$PATH" omarchy-notification-send "$@"
}

# Notify(susssasa{sv}i) args, by position in the recorded busctl argv:
#   0 --user  1 --  2 call  3 dest  4 path  5 iface  6 Notify  7 signature
#   8 app_name  9 replaces_id  10 app_icon  11 summary  12 body
#   13 actions-count  14 hint-count  15.. hint triples  last expire_timeout
declare -a args
load() { mapfile -t args <"$args_file"; }
hint_count() { echo "${args[14]}"; }
has_hint() { # key
  local i end=$((15 + 3 * ${args[14]}))
  for ((i = 15; i < end; i += 3)); do [[ ${args[i]} == "$1" ]] && return 0; done
  return 1
}
hint_value() { # key -> variant value
  local i end=$((15 + 3 * ${args[14]}))
  for ((i = 15; i < end; i += 3)); do [[ ${args[i]} == "$1" ]] && { echo "${args[i + 2]}"; return 0; }; done
  return 1
}

# ---------------------------------------------------------------- happy path
send --app-name custom-app -g K -u critical -i battery-caution -t 5000 \
  "Download complete" "A body" --exec mpv -- "/tmp/a b.mp4"
load

[[ ${args[2]} == "call" ]] || fail "notification wrapper calls a bus method"
[[ ${args[3]} == "org.freedesktop.Notifications" ]] || fail "notification wrapper targets the notifications service"
[[ ${args[6]} == "Notify" ]] || fail "notification wrapper invokes Notify"
[[ ${args[8]} == "custom-app" ]] || fail "notification wrapper sets the app name" "${args[8]}"
[[ ${args[10]} == "battery-caution" ]] || fail "notification wrapper sets the app icon from -i" "${args[10]}"
[[ ${args[11]} == "Download complete" ]] || fail "notification wrapper sets the summary" "${args[11]}"
[[ ${args[12]} == "A body" ]] || fail "notification wrapper sets the body" "${args[12]}"
[[ ${args[-1]} == "5000" ]] || fail "notification wrapper sets the expire timeout from -t" "${args[-1]}"
[[ $(hint_value urgency) == "2" ]] || fail "notification wrapper maps critical urgency to 2"
[[ $(hint_value omarchy-glyph) == "K" ]] || fail "notification wrapper sets the glyph hint"
[[ $(hint_value omarchy-exec-argv) == '["mpv","--","/tmp/a b.mp4"]' ]] || fail "notification wrapper builds the click argv hint" "$(hint_value omarchy-exec-argv)"
pass "notification wrapper issues a Notify call with app, icon, urgency, glyph, and click argv"

[[ -f $tripwire ]] && fail "notification wrapper must never invoke notify-send"
pass "notification wrapper never invokes notify-send"

# ---------------------------------------------------------------- no click cmd
: >"$args_file"
send "Plain" >/dev/null
load
has_hint omarchy-exec-argv && fail "notification wrapper adds no click hint without --exec"
[[ ${args[11]} == "Plain" ]] || fail "notification wrapper still sends a plain toast"
pass "notification wrapper omits the click hint when no command is given"

# ------------------------------------------------ rest-of-line --exec is literal
: >"$args_file"
send "Download complete" --exec mpv -- '$(rm -rf ~); echo pwned' >/dev/null
load
json=$(hint_value omarchy-exec-argv)
[[ $(jq -r '.[0]' <<<"$json") == "mpv" ]] || fail "click argv program is first"
[[ $(jq -r '.[2]' <<<"$json") == '$(rm -rf ~); echo pwned' ]] || fail "click argv carries metacharacters as literal data" "$json"
pass "rest-of-line --exec is a literal argv vector"

# A quoted argument with spaces stays ONE argument.
: >"$args_file"
send "Head" --exec mpv -- "/tmp/a b.mp4" >/dev/null
load
[[ $(jq 'length' <<<"$(hint_value omarchy-exec-argv)") == 3 ]] || fail "spaced path stays one argument"
pass "notification wrapper keeps a spaced argument intact"

# ---------------------------------------------------------------- injections
# A forged click hint arriving as the SUMMARY is a typed string parameter — it
# can never become a hint. Only urgency is set; no click command exists.
: >"$args_file"
send '--hint=string:omarchy-exec-argv:["bash","-c","touch /tmp/pwn"]' "body" >/dev/null
load
has_hint omarchy-exec-argv && fail "a forged-hint headline must not set a click command"
[[ ${args[11]} == '--hint=string:omarchy-exec-argv:["bash","-c","touch /tmp/pwn"]' ]] || fail "the forged headline is the summary text" "${args[11]}"
pass "a forged click hint in the headline is inert summary text"

# A dash-leading forged hint in description position is refused outright.
: >"$args_file"
if send "Update" '--hint=string:omarchy-exec-argv:["bash","-c","touch /tmp/pwn"]' 2>/dev/null; then
  fail "a forged-hint description must be refused"
fi
[[ -s $args_file ]] && fail "nothing is sent when the description forges a hint"
pass "a forged click hint in the description is refused"

# An unknown option is a hard error, not a silent pass-through.
if send "Head" --bogus 2>/dev/null; then
  fail "notification wrapper rejects an unknown option"
fi
pass "notification wrapper rejects an unknown option"

# ---------------------------------------------------------------- --exec guards
# --exec is recognized only after the positionals: a headline literally "--exec"
# is text, and the real trailing --exec still wins.
: >"$args_file"
send "--exec" "a body" --image /tmp/i.png --exec mpv -- /tmp/v.mp4 >/dev/null
load
[[ $(hint_value omarchy-exec-argv) == '["mpv","--","/tmp/v.mp4"]' ]] || fail "a --exec-looking headline is not the delimiter" "$(hint_value omarchy-exec-argv)"
[[ ${args[11]} == "--exec" ]] || fail "a --exec-looking headline is kept as text"
pass "a --exec-looking positional is not treated as the delimiter"

# A single quoted whole-command is rejected (splitting it ourselves is the
# injection we avoid).
if send "Head" --exec "omarchy toggle something" 2>/dev/null; then
  fail "notification wrapper rejects a quoted whole command"
fi
pass "notification wrapper rejects a single quoted whole command"

# --exec with nothing after it is a usage error.
if send "Head" --exec 2>/dev/null; then
  fail "notification wrapper rejects --exec with no command"
fi
pass "notification wrapper rejects --exec with no command"
