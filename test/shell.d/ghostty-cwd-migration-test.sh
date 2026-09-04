#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787566169.sh"
[[ -f $migration ]] || fail "Ghostty working-directory migration exists"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

run_migration() {
  local home=$1
  local cache_home=$2

  HOME="$home" XDG_CACHE_HOME="$cache_home" OMARCHY_PATH="$ROOT" \
    bash -euo pipefail "$migration" >/dev/null
}

existing_home="$test_tmp/existing-home"
existing_config="$existing_home/.config/ghostty/config"
existing_desktop="$existing_home/.local/share/applications/com.mitchellh.ghostty.desktop"
existing_cache="$existing_home/custom-cache"

mkdir -p "$(dirname "$existing_config")" "$existing_cache"
printf '%s\n' \
  '# Window' \
  'window-theme = ghostty' >"$existing_config"
touch "$existing_cache/xdg-terminal-exec"

run_migration "$existing_home" "$existing_cache"

single_false=$(grep -cE '^[[:space:]]*gtk-single-instance[[:space:]]*=[[:space:]]*false[[:space:]]*$' "$existing_config" || true)
if (( single_false != 1 )); then
  fail "migration adds the multi-process default to an existing Ghostty config"
fi
cmp -s "$ROOT/default/ghostty/com.mitchellh.ghostty.desktop" "$existing_desktop" ||
  fail "migration installs Omarchy's Ghostty desktop entry"
[[ ! -e $existing_cache/xdg-terminal-exec ]] ||
  fail "migration invalidates the xdg-terminal-exec cache"
pass "migration applies the Ghostty working-directory defaults"

before=$(sha256sum "$existing_config" "$existing_desktop")
run_migration "$existing_home" "$existing_cache"
after=$(sha256sum "$existing_config" "$existing_desktop")
[[ $before == "$after" ]] || fail "Ghostty working-directory migration is idempotent"
pass "Ghostty working-directory migration is idempotent"

current_home="$test_tmp/current-home"
current_config="$current_home/.config/ghostty/config.ghostty"
current_desktop="$current_home/.local/share/applications/com.mitchellh.ghostty.desktop"
current_cache="$current_home/custom-cache"

mkdir -p "$(dirname "$current_config")" "$current_cache"
printf '%s\n' \
  '# Current Ghostty configuration filename' \
  'window-theme = ghostty' >"$current_config"
touch "$current_cache/xdg-terminal-exec"

run_migration "$current_home" "$current_cache"

current_false=$(grep -cE '^[[:space:]]*gtk-single-instance[[:space:]]*=[[:space:]]*false[[:space:]]*$' "$current_config" || true)
if (( current_false != 1 )); then
  fail "migration updates an existing config.ghostty file"
fi
cmp -s "$ROOT/default/ghostty/com.mitchellh.ghostty.desktop" "$current_desktop" ||
  fail "migration installs the desktop entry for a config.ghostty user"
[[ ! -e $current_cache/xdg-terminal-exec ]] ||
  fail "migration invalidates the cache for a config.ghostty user"
pass "migration supports Ghostty's current config.ghostty filename"

dual_home="$test_tmp/dual-home"
dual_legacy_config="$dual_home/.config/ghostty/config"
dual_current_config="$dual_home/.config/ghostty/config.ghostty"
dual_cache="$dual_home/custom-cache"

mkdir -p "$(dirname "$dual_legacy_config")" "$dual_cache"
printf '%s\n' 'window-theme = ghostty' >"$dual_legacy_config"
printf '%s\n' 'cursor-style = block' >"$dual_current_config"
touch "$dual_cache/xdg-terminal-exec"

dual_legacy_before=$(sha256sum "$dual_legacy_config")
run_migration "$dual_home" "$dual_cache"
dual_legacy_after=$(sha256sum "$dual_legacy_config")

[[ $dual_legacy_before == "$dual_legacy_after" ]] ||
  fail "migration leaves the earlier-loaded legacy config unchanged"
dual_false=$(grep -cE '^[[:space:]]*gtk-single-instance[[:space:]]*=[[:space:]]*false[[:space:]]*$' "$dual_current_config" || true)
if (( dual_false != 1 )); then
  fail "migration adds the default to the later-loaded current config"
fi
pass "migration writes to config.ghostty when both config files exist"

for explicit_name in config config.ghostty; do
  custom_home="$test_tmp/custom-${explicit_name//./-}-home"
  custom_config_dir="$custom_home/.config/ghostty"
  custom_legacy_config="$custom_config_dir/config"
  custom_current_config="$custom_config_dir/config.ghostty"
  custom_desktop="$custom_home/.local/share/applications/com.mitchellh.ghostty.desktop"
  custom_cache="$custom_home/custom-cache"

  mkdir -p "$custom_config_dir" "$(dirname "$custom_desktop")" "$custom_cache"
  printf '%s\n' 'window-theme = ghostty' >"$custom_legacy_config"
  printf '%s\n' 'cursor-style = block' >"$custom_current_config"
  printf '%s\n' 'gtk-single-instance = true' >>"$custom_config_dir/$explicit_name"
  printf '%s\n' \
    '[Desktop Entry]' \
    'Name=Custom Ghostty' \
    'Exec=/usr/bin/ghostty --custom' >"$custom_desktop"
  touch "$custom_cache/xdg-terminal-exec"

  custom_before=$(sha256sum "$custom_legacy_config" "$custom_current_config" "$custom_desktop")
  run_migration "$custom_home" "$custom_cache"
  custom_after=$(sha256sum "$custom_legacy_config" "$custom_current_config" "$custom_desktop")

  [[ $custom_before == "$custom_after" ]] ||
    fail "migration preserves an explicit setting in $explicit_name and the desktop override"
  [[ ! -e $custom_cache/xdg-terminal-exec ]] ||
    fail "migration invalidates the cache while preserving $explicit_name customizations"
done
pass "migration preserves explicit settings in either Ghostty config file"

symlink_home="$test_tmp/symlink-home"
symlink_config="$symlink_home/.config/ghostty/config"
symlink_desktop="$symlink_home/.local/share/applications/com.mitchellh.ghostty.desktop"
symlink_target="$test_tmp/custom-ghostty-target"
symlink_cache="$symlink_home/custom-cache"
symlink_error="$test_tmp/migration-symlink-error"

mkdir -p "$(dirname "$symlink_config")" "$(dirname "$symlink_desktop")" "$symlink_cache"
printf '%s\n' 'window-theme = ghostty' >"$symlink_config"
ln -s "$symlink_target" "$symlink_desktop"
touch "$symlink_cache/xdg-terminal-exec"

if ! run_migration "$symlink_home" "$symlink_cache" 2>"$symlink_error"; then
  fail "migration preserves a dangling Ghostty desktop symlink" "$(<"$symlink_error")"
fi
[[ -L $symlink_desktop && $(readlink "$symlink_desktop") == "$symlink_target" ]] ||
  fail "migration leaves a dangling Ghostty desktop symlink unchanged"
[[ ! -e $symlink_target ]] ||
  fail "migration does not create a dangling desktop symlink target"
[[ ! -e $symlink_cache/xdg-terminal-exec ]] ||
  fail "migration invalidates the cache while preserving a desktop symlink"
pass "migration preserves a dangling Ghostty desktop symlink"

unused_home="$test_tmp/unused-home"
unused_cache="$unused_home/custom-cache"
mkdir -p "$unused_cache"
touch "$unused_cache/xdg-terminal-exec"

run_migration "$unused_home" "$unused_cache"

[[ ! -e $unused_home/.config/ghostty ]] ||
  fail "migration does not create a Ghostty config for users without one"
[[ ! -e $unused_home/.local/share/applications/com.mitchellh.ghostty.desktop ]] ||
  fail "migration does not install a Ghostty desktop entry for users without a config"
[[ -e $unused_cache/xdg-terminal-exec ]] ||
  fail "migration leaves unrelated xdg-terminal-exec state alone"
pass "migration leaves users without Ghostty configuration unchanged"
