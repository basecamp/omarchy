#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home_dir="$test_tmp/home"
backgrounds_dir="$home_dir/.local/state/omarchy/current/theme/backgrounds"
current_link="$home_dir/.local/state/omarchy/current/background"
set_log="$test_tmp/bg-set.log"

mkdir -p "$stub_bin" "$backgrounds_dir"
printf 'ristretto\n' >"$home_dir/.local/state/omarchy/current/theme.name"

# A glob character in the name is what breaks a pattern comparison, so one of
# the backgrounds carries brackets the way downloaded wallpapers often do.
bracketed="$backgrounds_dir/aaa [4k].jpg"
plain="$backgrounds_dir/bbb.jpg"
touch "$bracketed" "$plain"

cat >"$stub_bin/omarchy-theme-bg-set" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >"$OMARCHY_TEST_BG_SET_LOG"
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$stub_bin"/*

run_bg_next() {
  ln -sfn "$1" "$current_link"
  : >"$set_log"

  HOME="$home_dir" \
    PATH="$stub_bin:$PATH" \
    OMARCHY_TEST_BG_SET_LOG="$set_log" \
    "$ROOT/bin/omarchy-theme-bg-next"
}

run_bg_next "$bracketed"
selected=$(<"$set_log")
[[ $selected == "$plain" ]] ||
  fail "background cycling advances past a name with glob characters" "expected: $plain
actual:   $selected"
pass "background cycling advances past a name with glob characters"

run_bg_next "$plain"
selected=$(<"$set_log")
[[ $selected == "$bracketed" ]] ||
  fail "background cycling wraps back to the first background" "expected: $bracketed
actual:   $selected"
pass "background cycling wraps back to the first background"
