#!/bin/bash

set -euo pipefail

# omarchy-launch-or-focus-tui and omarchy-launch-or-focus-webapp build
# LAUNCH_COMMAND for omarchy-launch-or-focus, which re-parses it with eval.
# Both quote their arguments with printf %q before joining, so this is
# exercised with hyprctl and setsid stubbed: a guard that stopped working
# shows up either as setsid receiving a mangled/split argument list, or as a
# command-substitution payload actually running instead of being passed
# through as inert text.
#
# Plain ; command chaining is not a usable check here: eval's leading exec
# replaces the process before a later ;-joined command would run, so it
# proves nothing either way. Command substitution runs during eval's
# re-parse, before exec ever starts, so it is the payload that actually
# exercises the guard.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

# No matching window, so omarchy-launch-or-focus always falls through to its
# eval branch.
cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
[[ $1 == clients ]] && { echo '[]'; exit 0; }
exit 0
SH

# Records exactly what argv it receives instead of actually starting a
# session leader -- this is the sink omarchy-launch-or-focus execs into.
cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf '%s\n' "$#" >"$OMARCHY_TEST_SETSID_CALLS"
printf '%s\n' "$@" >>"$OMARCHY_TEST_SETSID_CALLS"
SH

chmod +x "$mock_bin"/*

setsid_calls="$test_tmp/setsid-calls"
injected="$test_tmp/injected"

run_tui() {
  : >"$setsid_calls"
  rm -f "$injected"
  PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_TEST_SETSID_CALLS="$setsid_calls" \
    bash "$ROOT/bin/omarchy-launch-or-focus-tui" "$@" >"$test_tmp/out" 2>&1
}

run_webapp() {
  : >"$setsid_calls"
  rm -f "$injected"
  PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_TEST_SETSID_CALLS="$setsid_calls" \
    bash "$ROOT/bin/omarchy-launch-or-focus-webapp" "$@" >"$test_tmp/out" 2>&1
}

# Normal arguments reach setsid split exactly as given: an argument count,
# then one argument per line.
run_tui --app-id=org.omarchy.about omarchy-launch-about --render
mapfile -t got <"$setsid_calls"
expected=(4 omarchy-launch-tui --app-id=org.omarchy.about omarchy-launch-about --render)
[[ ${got[*]} == "${expected[*]}" ]] ||
  fail "omarchy-launch-or-focus-tui passes normal arguments through unchanged" "$(cat "$setsid_calls")"

pass "omarchy-launch-or-focus-tui passes normal arguments through unchanged"

# A command substitution embedded in an argument must reach setsid as inert
# text, not run during eval's re-parse.
payload="\$(touch $injected)"
run_tui "some-command" "$payload"
[[ ! -e $injected ]] ||
  fail "omarchy-launch-or-focus-tui does not execute a command substitution in its arguments"
grep -qxF "$payload" "$setsid_calls" ||
  fail "omarchy-launch-or-focus-tui passes the command substitution through as literal text" "$(cat "$setsid_calls")"

pass "omarchy-launch-or-focus-tui neutralizes a command substitution in its arguments"

# Same two guarantees for omarchy-launch-or-focus-webapp.
run_webapp MyApp "https://example.com" "--user-agent=test"
mapfile -t got <"$setsid_calls"
expected=(3 omarchy-launch-webapp https://example.com --user-agent=test)
[[ ${got[*]} == "${expected[*]}" ]] ||
  fail "omarchy-launch-or-focus-webapp passes normal arguments through unchanged" "$(cat "$setsid_calls")"

pass "omarchy-launch-or-focus-webapp passes normal arguments through unchanged"

run_webapp MyApp "$payload"
[[ ! -e $injected ]] ||
  fail "omarchy-launch-or-focus-webapp does not execute a command substitution in its arguments"
grep -qxF "$payload" "$setsid_calls" ||
  fail "omarchy-launch-or-focus-webapp passes the command substitution through as literal text" "$(cat "$setsid_calls")"

pass "omarchy-launch-or-focus-webapp neutralizes a command substitution in its arguments"
