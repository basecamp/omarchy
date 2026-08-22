#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log_file="$test_tmp/tmux.log"
theme_dir="$test_tmp/home/.local/state/omarchy/current/theme"
mkdir -p "$stub_bin" "$theme_dir"

# Two sessions, no panes or clients: enough to count the calls that matter
# without dragging the pane and client loops into the numbers.
cat >"$stub_bin/tmux" <<'SH'
#!/bin/bash

printf 'tmux' >>"$OMARCHY_TMUX_TEST_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$OMARCHY_TMUX_TEST_LOG"
done
printf '\n' >>"$OMARCHY_TMUX_TEST_LOG"

case "$1" in
  list-sessions)
    printf '$0\n$1\n'
    ;;
esac
SH
chmod +x "$stub_bin/tmux"

cat >"$stub_bin/omarchy-theme-color" <<'SH'
#!/bin/bash

case "${!#}" in
  mode) echo dark ;;
  *) echo '#000000' ;;
esac
SH
chmod +x "$stub_bin/omarchy-theme-color"

cat >"$stub_bin/omarchy-theme-osc" <<'SH'
#!/bin/bash
SH
chmod +x "$stub_bin/omarchy-theme-osc"

cat >"$theme_dir/gum_env.lua" <<'LUA'
hl.env("GUM_ONE", "1")
hl.env("GUM_TWO", "2")
hl.env("GUM_THREE", "3")
LUA
: >"$theme_dir/colors.toml"

: >"$log_file"
HOME="$test_tmp/home" \
  OMARCHY_TMUX_TEST_LOG="$log_file" \
  PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-theme-set-tmux"

count_lines() {
  grep -c -- "$1" "$log_file" || true
}

# One call is the guard at the top, one reads the list for the loop. Every key
# used to add another, so this is the number that proves the list is read once.
list_calls=$(count_lines $'^tmux\tlist-sessions')
(( list_calls == 2 )) ||
  fail "theme-set-tmux reads the session list once for all keys" "list-sessions calls: $list_calls"
pass "theme-set-tmux reads the session list once for all keys"

# Three keys from gum_env plus COLORFGBG, each set globally and in both sessions.
global_sets=$(count_lines $'^tmux\tset-environment\t-g\t')
(( global_sets == 4 )) ||
  fail "theme-set-tmux sets every key globally" "global set-environment calls: $global_sets"
pass "theme-set-tmux sets every key globally"

for session in '$0' '$1'; do
  for key in GUM_ONE GUM_TWO GUM_THREE COLORFGBG; do
    grep -qF -- $'tmux\tset-environment\t-t\t'"$session"$'\t'"$key"$'\t' "$log_file" ||
      fail "theme-set-tmux sets $key in session $session" "$(cat "$log_file")"
  done
done
pass "theme-set-tmux sets every key in every session"

session_sets=$(count_lines $'^tmux\tset-environment\t-t\t')
(( session_sets == 8 )) ||
  fail "theme-set-tmux sets each key once per session" "per-session set-environment calls: $session_sets"
pass "theme-set-tmux sets each key once per session"
