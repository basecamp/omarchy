#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
omarchy="$test_tmp/omarchy"
mock_bin="$test_tmp/bin"
set_log="$test_tmp/theme-set"
notify_log="$test_tmp/notify"

mkdir -p "$mock_bin" \
  "$home/.config/omarchy/themes" \
  "$home/.local/state/omarchy/current" \
  "$omarchy/themes"

cat >"$mock_bin/omarchy-theme-set" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_THEME_SET"
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_NOTIFY"
SH

chmod +x "$mock_bin"/*

# Stock + user dirs, same union omarchy-theme-list walks. Slugs sort as
# catppuccin, gruvbox, tokyo-night → Catppuccin, Gruvbox, Tokyo Night.
mkdir -p "$omarchy/themes/catppuccin" "$omarchy/themes/tokyo-night" \
  "$home/.config/omarchy/themes/gruvbox"

run_cycle() {
  : >"$set_log"
  : >"$notify_log"
  HOME="$home" OMARCHY_PATH="$omarchy" PATH="$mock_bin:$ROOT/bin:$PATH" \
    OMARCHY_TEST_THEME_SET="$set_log" OMARCHY_TEST_NOTIFY="$notify_log" \
    bash "$ROOT/bin/$1"
}

printf 'gruvbox\n' >"$home/.local/state/omarchy/current/theme.name"
run_cycle omarchy-theme-next
grep -Fx 'Tokyo Night' "$set_log" >/dev/null || fail "next from Gruvbox applies Tokyo Night" "$(cat "$set_log")"
grep -Fq 'Tokyo Night' "$notify_log" >/dev/null || fail "next notifies Tokyo Night" "$(cat "$notify_log")"

printf 'gruvbox\n' >"$home/.local/state/omarchy/current/theme.name"
run_cycle omarchy-theme-prev
grep -Fx 'Catppuccin' "$set_log" >/dev/null || fail "prev from Gruvbox applies Catppuccin" "$(cat "$set_log")"
grep -Fq 'Catppuccin' "$notify_log" >/dev/null || fail "prev notifies Catppuccin" "$(cat "$notify_log")"

printf 'tokyo-night\n' >"$home/.local/state/omarchy/current/theme.name"
run_cycle omarchy-theme-next
grep -Fx 'Catppuccin' "$set_log" >/dev/null || fail "next wraps last theme to first" "$(cat "$set_log")"

printf 'catppuccin\n' >"$home/.local/state/omarchy/current/theme.name"
run_cycle omarchy-theme-prev
grep -Fx 'Tokyo Night' "$set_log" >/dev/null || fail "prev wraps first theme to last" "$(cat "$set_log")"

rm -rf "$omarchy/themes/tokyo-night" "$home/.config/omarchy/themes/gruvbox"
printf 'catppuccin\n' >"$home/.local/state/omarchy/current/theme.name"
run_cycle omarchy-theme-next
[[ ! -s $set_log ]] || fail "next with one theme does not re-apply" "$(cat "$set_log")"
grep -Fq 'Catppuccin' "$notify_log" >/dev/null || fail "next with one theme still names it" "$(cat "$notify_log")"

run_cycle omarchy-theme-prev
[[ ! -s $set_log ]] || fail "prev with one theme does not re-apply" "$(cat "$set_log")"

pass "theme next and prev wrap installed themes"
