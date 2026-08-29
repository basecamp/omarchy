#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
stub_bin="$test_tmp/bin"
theme_dir="$test_tmp/theme"
calls="$test_tmp/calls"
state_file="$test_home/.local/state/omarchy/current/plymouth.name"
mkdir -p "$test_home" "$stub_bin" "$theme_dir"

cat >"$theme_dir/colors.toml" <<'TOML'
background = "#112233"
foreground = "#ddeeff"
TOML
touch "$theme_dir/unlock.png"

cat >"$stub_bin/omarchy-theme-dir" <<'SH'
#!/bin/bash
echo "$THEME_DIR"
SH
cat >"$stub_bin/omarchy-plymouth-set" <<'SH'
#!/bin/bash
printf 'set %s\n' "$*" >>"$CALLS"
[[ ${FAIL_APPLY:-0} == 0 ]]
SH
chmod +x "$stub_bin/omarchy-theme-dir" "$stub_bin/omarchy-plymouth-set"

HOME="$test_home" THEME_DIR="$theme_dir" CALLS="$calls" PATH="$stub_bin:$PATH" \
  bash "$ROOT/bin/omarchy-plymouth-set-by-theme" tokyo-night

grep -Fxq "set #112233 #ddeeff $theme_dir/unlock.png" "$calls" ||
  fail "unlock theme selection does not apply the selected theme"
[[ $(<"$state_file") == "tokyo-night" ]] || fail "unlock theme selection is not remembered"
pass "unlock theme selection is remembered after it applies"

if HOME="$test_home" THEME_DIR="$theme_dir" CALLS="$calls" FAIL_APPLY=1 PATH="$stub_bin:$PATH" \
  bash "$ROOT/bin/omarchy-plymouth-set-by-theme" broken 2>/dev/null; then
  fail "a failed unlock theme application reports success"
fi
[[ $(<"$state_file") == "tokyo-night" ]] || fail "a failed application replaces the remembered theme"
pass "failed unlock theme changes keep the last working selection"

cat >"$stub_bin/omarchy-plymouth-current" <<'SH'
#!/bin/bash
echo "${CURRENT_THEME:-default}"
SH
cat >"$stub_bin/omarchy-plymouth-list" <<'SH'
#!/bin/bash
printf '%s\n' "${AVAILABLE_THEMES:-}"
SH
cat >"$stub_bin/omarchy-plymouth-set-by-theme" <<'SH'
#!/bin/bash
printf 'restore %s\n' "$1" >>"$CALLS"
SH
chmod +x "$stub_bin/omarchy-plymouth-current" "$stub_bin/omarchy-plymouth-list" \
  "$stub_bin/omarchy-plymouth-set-by-theme"

: >"$calls"
HOME="$test_home" CURRENT_THEME=tokyo-night CALLS="$calls" PATH="$stub_bin:$PATH" \
  bash "$ROOT/bin/omarchy-plymouth-restore"
[[ ! -s $calls ]] || fail "an intact unlock theme is needlessly rebuilt after every update"
pass "an intact unlock theme needs no post-update work"

HOME="$test_home" CURRENT_THEME=default AVAILABLE_THEMES=tokyo-night CALLS="$calls" PATH="$stub_bin:$PATH" \
  bash "$ROOT/bin/omarchy-plymouth-restore"
grep -Fxq 'restore tokyo-night' "$calls" || fail "a package-clobbered unlock theme is not restored"
pass "a package-clobbered unlock theme is restored"

: >"$calls"
HOME="$test_home" CURRENT_THEME=default AVAILABLE_THEMES= CALLS="$calls" PATH="$stub_bin:$PATH" \
  bash "$ROOT/bin/omarchy-plymouth-restore" 2>/dev/null
[[ ! -s $calls ]] || fail "a removed theme is passed to the theme setter"
pass "a removed unlock theme falls back without blocking the update"

cat >"$stub_bin/omarchy-refresh-plymouth" <<'SH'
#!/bin/bash
echo plymouth >>"$CALLS"
SH
cat >"$stub_bin/omarchy-refresh-sddm" <<'SH'
#!/bin/bash
echo sddm >>"$CALLS"
SH
chmod +x "$stub_bin/omarchy-refresh-plymouth" "$stub_bin/omarchy-refresh-sddm"

: >"$calls"
HOME="$test_home" CALLS="$calls" PATH="$stub_bin:$PATH" bash "$ROOT/bin/omarchy-plymouth-reset"
[[ ! -e $state_file ]] || fail "reset leaves the custom unlock theme remembered"
[[ $(tr '\n' ' ' <"$calls") == "plymouth sddm " ]] || fail "reset does not refresh both unlock surfaces"
pass "reset forgets the custom unlock theme"
