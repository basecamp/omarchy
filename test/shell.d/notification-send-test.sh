#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

args_file="$tmpdir/args"

# Stub the D-Bus transport: record the Notify call verbatim and echo a returned
# id the way busctl prints a UINT32 return ("u <id>").
printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s\n" "$@" >"$OMARCHY_TEST_BUSCTL_ARGS"' \
  'echo "u 42"' \
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

# Replace-in-place: -p prints the returned id, -r reuses it (the display text
# size toast refreshes one notification instead of stacking a pile).
returned_id=$(send "Restart Foot" -p)
[[ $returned_id == "42" ]] || fail "notification wrapper prints the returned id with -p" "$returned_id"
: >"$args_file"
send -r 42 "Restart Foot" >/dev/null
load
[[ ${args[9]} == "42" ]] || fail "notification wrapper sets replaces_id from -r" "${args[9]}"
pass "notification wrapper supports -p (print id) and -r (replace id)"

# Options may follow the headline and description (Taildrop appends -u critical
# and -g after the two positionals); they still land on the call, and urgency
# stays a single hint rather than doubling.
: >"$args_file"
send "Received photo.png" "Saved to ~/Downloads" -u critical -g K >/dev/null
load
[[ ${args[11]} == "Received photo.png" ]] || fail "notification wrapper keeps the summary before trailing options" "${args[11]}"
[[ ${args[12]} == "Saved to ~/Downloads" ]] || fail "notification wrapper keeps the body before trailing options" "${args[12]}"
[[ $(hint_value urgency) == "2" ]] || fail "notification wrapper reads an urgency that follows the description" "$(hint_value urgency)"
[[ $(hint_value omarchy-glyph) == "K" ]] || fail "notification wrapper reads a glyph that follows the description"
urgency_hits=0
for ((i = 15; i < 15 + 3 * ${args[14]}; i += 3)); do [[ ${args[i]} == urgency ]] && urgency_hits=$((urgency_hits + 1)); done
((urgency_hits == 1)) || fail "notification wrapper sets the urgency once" "$urgency_hits"
pass "notification wrapper reads options that follow the headline and description"

# The --flag=value form works too (the acceptance suite uses --expire-time=15000).
: >"$args_file"
send "Acceptance" "Body" --expire-time=15000 >/dev/null
load
[[ ${args[-1]} == "15000" ]] || fail "notification wrapper accepts --flag=value" "${args[-1]}"
[[ ${args[12]} == "Body" ]] || fail "notification wrapper keeps the body with an =value flag" "${args[12]}"
pass "notification wrapper accepts the --flag=value form"

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

# A forged hint in description position is inert body text — a typed D-Bus
# parameter that can never become a hint — not a click command.
: >"$args_file"
send "Update" '--hint=string:omarchy-exec-argv:["bash","-c","touch /tmp/pwn"]' >/dev/null
load
has_hint omarchy-exec-argv && fail "a forged-hint description must not set a click command"
[[ ${args[12]} == '--hint=string:omarchy-exec-argv:["bash","-c","touch /tmp/pwn"]' ]] || fail "the forged description is the body text" "${args[12]}"
pass "a forged click hint in the description is inert body text"

# A forged hint that reaches the trailing option position is refused: an unknown
# option is a hard error, not a silent pass-through.
if send "Head" "Body" '--hint=string:omarchy-exec-argv:["bash","-c","x"]' 2>/dev/null; then
  fail "a forged hint in option position must be refused"
fi
if send "Head" "Body" --bogus 2>/dev/null; then
  fail "notification wrapper rejects an unknown option"
fi
pass "notification wrapper rejects an unknown option (including a forged hint in option position)"

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

# --exec with a single empty argument is rejected too.
if send "Head" --exec "" 2>/dev/null; then
  fail "notification wrapper rejects --exec with an empty program"
fi
pass "notification wrapper rejects --exec with an empty program"

# A description that begins with a dash is content, not options: a price, a
# negative number, a diff line. It must reach the body, not error out.
: >"$args_file"
send "Sale" "-50% off today" >/dev/null
load
[[ ${args[12]} == "-50% off today" ]] || fail "notification wrapper keeps a dash-leading body as text" "${args[12]}"
pass "notification wrapper keeps a dash-leading description as the body"

# But a known flag in the description slot is still an option, not the body.
: >"$args_file"
send "Timed" -t 3000 >/dev/null
load
[[ ${args[12]} == "" && ${args[-1]} == "3000" ]] || fail "notification wrapper still parses a flag after the headline" "body=${args[12]} timeout=${args[-1]}"
pass "notification wrapper still treats a known flag after the headline as an option"
