#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/setsid" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/setsid"

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir:$ROOT/bin:$PATH"

"$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "echo hello"

launch=$(<"$TEST_LOG")
[[ $launch == *"xdg-terminal-exec --app-id=org.omarchy.terminal"* ]] || fail "floating terminal launches Omarchy terminal" "$launch"
pass "floating terminal launches Omarchy terminal"

# The wrapper runs its caller's words rather than rebuilding them into shell
# source, so a value that arrives as one argument stays one argument whatever
# it holds.
cat >"$tmp_dir/omarchy-show-logo" <<'STUB'
#!/bin/bash
exit 0
STUB
cp "$tmp_dir/omarchy-show-logo" "$tmp_dir/omarchy-show-done"

cat >"$tmp_dir/record-argv" <<'STUB'
#!/bin/bash
printf '%s\n' "$#" "$@" >"$TEST_ARGV"
STUB

chmod +x "$tmp_dir/omarchy-show-logo" "$tmp_dir/omarchy-show-done" "$tmp_dir/record-argv"

export TEST_ARGV="$tmp_dir/argv"
canary="$tmp_dir/canary"
hostile="a';touch $canary;'b"

bash -c 'omarchy-show-logo; "$@"; if (( $? != 130 )); then omarchy-show-done; fi' \
  bash record-argv "$hostile" "two words"

[[ ! -e $canary ]] || fail "an argument carrying shell syntax reaches the wrapped command as data"

printf '%s\n' 2 "$hostile" "two words" >"$tmp_dir/argv-expected"
cmp -s "$TEST_ARGV" "$tmp_dir/argv-expected" ||
  fail "the wrapped command gets each argument whole" "$(cat "$TEST_ARGV")"

pass "the presentation wrapper hands its caller's words over as argv"

# An argv wrapper runs its first argument as the command name, so a caller that
# still packs a command and its arguments into one quoted string asks for a
# program whose name contains a space. Nothing runs and nothing complains where
# the user can see it -- the menu entry simply does nothing. No caller may spell
# it that way, in a script or in a menu action.
cat >"$tmp_dir/string-caller.re" <<'RE'
omarchy-launch-floating-terminal-with-presentation +\\?["'][^"']*[[:space:]]
RE

# The sweep only ever reports what it finds, so a renamed directory would turn it
# into a check that passes because it read nothing. Count the callers first.
caller_lines=$(
  { grep -rhcF "omarchy-launch-floating-terminal-with-presentation" \
      "$ROOT/bin" "$ROOT/default" "$ROOT/config" "$ROOT/applications" 2>/dev/null || true; } |
    awk '{ total += $1 } END { print total + 0 }'
)

(( caller_lines > 0 )) ||
  fail "the sweep reads the directories that hold the wrapper's callers"

string_callers=$(
  grep -rnEf "$tmp_dir/string-caller.re" \
    "$ROOT/bin" "$ROOT/default" "$ROOT/config" "$ROOT/applications" 2>/dev/null || true
)

[[ -z $string_callers ]] ||
  fail "every caller passes the command and its arguments as separate words" "$string_callers"

pass "no caller packs a command line into one string for the presentation wrapper"
