#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

stub_bin="$work_dir/bin"
argv_log="$work_dir/argv.log"
mkdir -p "$stub_bin"
: >"$argv_log"

# No windows, so every launch takes the exec path.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

printf '[]\n'
SH
chmod +x "$stub_bin/hyprctl"

# Records one line per argument, so splitting mistakes show up as extra lines
# and a re-parsed metacharacter shows up as a changed line.
cat >"$stub_bin/setsid" <<SH
#!/bin/bash

i=0
for arg in "\$@"; do
  printf '%d:%s\n' "\$i" "\$arg" >>"$argv_log"
  i=\$((i + 1))
done
SH
chmod +x "$stub_bin/setsid"

run_wrapper() {
  : >"$argv_log"
  PATH="$stub_bin:$ROOT/bin:$PATH" "$@" >/dev/null 2>&1
}

# --- omarchy-launch-or-focus-tui ------------------------------------------------

# The wrapper hands omarchy-launch-or-focus one string, which re-parses it with
# eval. Quoting each word first is what keeps an argument whole on that ride.
run_wrapper "$ROOT/bin/omarchy-launch-or-focus-tui" mytui "two words" 'a;b$(id)'

grep -Fxq '0:omarchy-launch-tui' "$argv_log" ||
  fail "tui wrapper launches through omarchy-launch-tui" "$(cat "$argv_log")"
grep -Fxq '2:two words' "$argv_log" ||
  fail "tui wrapper keeps a two-word argument whole through the re-parse" "$(cat "$argv_log")"
grep -Fxq '3:a;b$(id)' "$argv_log" ||
  fail "tui wrapper keeps shell characters inert through the re-parse" "$(cat "$argv_log")"
(( $(wc -l <"$argv_log") == 4 )) ||
  fail "tui wrapper adds no extra words through the re-parse" "$(cat "$argv_log")"
pass "tui wrapper carries arguments whole through the launch-or-focus re-parse"

# The app id flag is part of the same string ride and must survive it too.
run_wrapper "$ROOT/bin/omarchy-launch-or-focus-tui" --app-id=org.custom mytui

grep -Fxq '1:--app-id=org.custom' "$argv_log" ||
  fail "tui wrapper keeps the app id flag whole" "$(cat "$argv_log")"
pass "tui wrapper keeps the app id flag whole"

# --- omarchy-launch-or-focus-webapp ---------------------------------------------

# A URL with a query string holds & and =. Unquoted, eval reads & as a command
# separator and the browser gets a truncated URL.
run_wrapper "$ROOT/bin/omarchy-launch-or-focus-webapp" "Chat" 'https://chat.example/?a=1&b=2'

grep -Fxq '1:https://chat.example/?a=1&b=2' "$argv_log" ||
  fail "webapp wrapper keeps a URL with a query string whole" "$(cat "$argv_log")"
(( $(wc -l <"$argv_log") == 2 )) ||
  fail "webapp wrapper adds no extra words through the re-parse" "$(cat "$argv_log")"
pass "webapp wrapper carries a URL with a query string whole"

# --- omarchy-launch-tui ----------------------------------------------------------

# Direct quoting: the command path and the app id reach the terminal unchanged.
run_wrapper "$ROOT/bin/omarchy-launch-tui" --app-id=org.custom "/opt/my tools/foo" "two words"

grep -Fxq '2:xdg-terminal-exec' "$argv_log" ||
  fail "launch-tui still drives xdg-terminal-exec" "$(cat "$argv_log")"
grep -Fxq '3:--app-id=org.custom' "$argv_log" ||
  fail "launch-tui quotes the app id" "$(cat "$argv_log")"
grep -Fxq '5:/opt/my tools/foo' "$argv_log" ||
  fail "launch-tui keeps a command path with a space whole" "$(cat "$argv_log")"
grep -Fxq '6:two words' "$argv_log" ||
  fail "launch-tui keeps arguments whole" "$(cat "$argv_log")"
pass "launch-tui quotes the app id and the command path"

# Without the flag, the app id comes from the basename of a path that may hold
# spaces.
run_wrapper "$ROOT/bin/omarchy-launch-tui" "/opt/my tools/foo"

grep -Fxq '3:--app-id=org.omarchy.foo' "$argv_log" ||
  fail "launch-tui derives the app id from a path with spaces" "$(cat "$argv_log")"
pass "launch-tui derives the app id from a path with spaces"
