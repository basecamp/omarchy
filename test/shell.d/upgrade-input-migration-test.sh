#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

upgrade_script="$ROOT/bin/omarchy-upgrade-to-quattro"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

migration_functions=$(sed -n '/^legacy_hypr_input_value() {/,/^migrate_uwsm_env_customizations() {/p' "$upgrade_script" | sed '$d')

run_migration() {
  local home="$1"
  printf '%s\nmigrate_legacy_hypr_input\n' "$migration_functions" | HOME="$home" bash -euo pipefail
}

home="$tmp_dir/custom"
mkdir -p "$home/.config/hypr"
cat >"$home/.config/hypr/input.lua" <<'LUA'
-- Quattro input overrides
LUA
cat >"$home/.config/hypr/input.conf" <<'CONF'
device {
  name = example-keyboard
  kb_options = ignored:device_option
}

input {
  kb_layout = no
  kb_variant =
  kb_model = pc105
  kb_options = compose:caps,grp:alt_shift_toggle # Keep AltGr available.
  kb_rules = evdev

  touchpad {
    natural_scroll = true
  }
}
CONF

run_migration "$home"
run_migration "$home"

input_lua="$home/.config/hypr/input.lua"
grep -F '    kb_layout = "no",' "$input_lua" >/dev/null || fail "Quattro upgrade preserves the legacy keyboard layout"
grep -F '    kb_variant = "",' "$input_lua" >/dev/null || fail "Quattro upgrade preserves an empty legacy keyboard variant"
grep -F '    kb_model = "pc105",' "$input_lua" >/dev/null || fail "Quattro upgrade preserves the legacy keyboard model"
grep -F '    kb_options = "compose:caps,grp:alt_shift_toggle",' "$input_lua" >/dev/null || fail "Quattro upgrade preserves legacy keyboard options"
grep -F '    kb_rules = "evdev",' "$input_lua" >/dev/null || fail "Quattro upgrade preserves legacy keyboard rules"
! grep -Fq 'ignored:device_option' "$input_lua" || fail "Quattro upgrade ignores per-device keyboard options"
[[ $(grep -Fc 'Preserved from legacy ~/.config/hypr/input.conf' "$input_lua") == 1 ]] || fail "legacy keyboard migration is idempotent"
pass "Quattro upgrade preserves legacy keyboard input overrides"

home="$tmp_dir/no-overrides"
mkdir -p "$home/.config/hypr"
printf '%s\n' '-- Quattro input overrides' >"$home/.config/hypr/input.lua"
printf '%s\n' '# No active input block' >"$home/.config/hypr/input.conf"
before=$(sha256sum "$home/.config/hypr/input.lua")
run_migration "$home"
after=$(sha256sum "$home/.config/hypr/input.lua")
[[ $after == "$before" ]] || fail "Quattro upgrade leaves input.lua unchanged without legacy overrides"
pass "Quattro upgrade skips legacy input files without overrides"

copy_line=$(grep -n '^copy_always_config_defaults$' "$upgrade_script" | cut -d: -f1)
migrate_line=$(grep -n '^migrate_legacy_hypr_input$' "$upgrade_script" | cut -d: -f1)
[[ -n $copy_line && -n $migrate_line ]] || fail "Quattro input copy and migration calls exist"
(( copy_line < migrate_line )) || fail "legacy input overrides are applied after the Quattro template is copied"
pass "Quattro upgrade migrates input overrides after installing the template"
