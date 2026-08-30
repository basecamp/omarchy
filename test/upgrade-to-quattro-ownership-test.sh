#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
upgrade_to_quattro="$ROOT/bin/omarchy-upgrade-to-quattro"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

overwrite_count=$(awk '!/^[[:space:]]*#/ && /--overwrite/ { count++ } END { print count + 0 }' "$upgrade_to_quattro")
(( overwrite_count == 1 )) || fail "upgrade uses overwrite only for the one-time ownership bridge"

grep -F "pacman -S --noconfirm --ask 4 --overwrite='*' \"\$settings_package\"" "$upgrade_to_quattro" >/dev/null ||
  fail "ownership bridge installs only omarchy-settings"
grep -F 'pacman -Syu --needed --noconfirm --ask 4 "${core_packages[@]}"' "$upgrade_to_quattro" >/dev/null ||
  fail "core installation returns to ordinary ownership checks"
grep -F 'pacman -S --needed --noconfirm --ask 4 "${base_packages[@]}"' "$upgrade_to_quattro" >/dev/null ||
  fail "default package installation uses ordinary ownership checks"
grep -F 'pacman -S --needed --noconfirm --ask 4 "${audio_packages[@]}"' "$upgrade_to_quattro" >/dev/null ||
  fail "audio package installation uses ordinary ownership checks"
grep -F 'pacman -Syu --noconfirm --ask 4' "$upgrade_to_quattro" >/dev/null ||
  fail "final package upgrade uses ordinary ownership checks"
pass "upgrade confines overwrite to omarchy-settings ownership adoption"

if grep -F '/usr/lib/chromium/initial_preferences' "$upgrade_to_quattro" >/dev/null; then
  fail "upgrade does not create an unowned Chromium preferences file"
fi
pass "upgrade does not create an unowned Chromium preferences file"

if grep -F '/etc/sddm.conf.d/99-omarchy-login.conf' "$upgrade_to_quattro" >/dev/null; then
  fail "upgrade does not create an unowned SDDM defaults file"
fi
pass "upgrade leaves SDDM login defaults to the package and SDDM itself"

# Extract only the explicitly marked, non-mutating policy functions. Refuse to
# execute anything if either boundary changes or a mutating command enters the
# block, so a refactor cannot accidentally turn this unit test into an upgrade.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
selection_library="$test_tmp/selection-functions.sh"
mirrorlist="$test_tmp/mirrorlist"

(( $(grep -c '^# OMARCHY_UPGRADE_SELECTION_BEGIN$' "$upgrade_to_quattro") == 1 )) ||
  fail "the upgrade selection test has one extraction start boundary"
(( $(grep -c '^# OMARCHY_UPGRADE_SELECTION_END$' "$upgrade_to_quattro") == 1 )) ||
  fail "the upgrade selection test has one extraction end boundary"

awk '
  /^# OMARCHY_UPGRADE_SELECTION_BEGIN$/ { copying = 1; next }
  /^# OMARCHY_UPGRADE_SELECTION_END$/ { exit }
  copying { print }
' "$upgrade_to_quattro" >"$selection_library"

[[ -s $selection_library ]] || fail "the upgrade selection policy extracts as a non-empty library"
if grep -Ev '^[[:space:]]*(#|$)' "$selection_library" |
  grep -Eq '(^|[[:space:];|&])(sudo|pacman|rm|mv|cp|install|tee|curl|wget|systemctl|reboot|shutdown|mount|umount|chown|chmod)([[:space:];|&]|$)'; then
  fail "the upgrade selection policy contains a system-mutating command"
fi
bash -n "$selection_library" || fail "the extracted upgrade selection policy has valid Bash syntax"
source "$selection_library"

selection_for() {
  local installed_server=$1
  shift

  printf 'Server = %s\n' "$installed_server" >"$mirrorlist"

  (
    channel_override=
    channel_override_cli=0
    target_user=
    yes=0
    auto_reboot=0
    boot_cmdline_unsafe=0
    use_dev_packages=0

    parse_upgrade_arguments "$@"
    normalize_upgrade_dev_mode
    installed_channel=$(detect_installed_channel "$mirrorlist" || true)
    resolve_upgrade_channel "$installed_channel"
    read -r omarchy_package settings_package < <(select_omarchy_package_names)
    printf '%s|%s|%s|%s|%s|%s\n' \
      "$channel" "$use_dev_packages" "$mirror_server" "$package_server" \
      "$omarchy_package" "$settings_package"
  )
}

stable_selection='stable|0|https://stable-mirror.omarchy.org/$repo/os/$arch|https://pkgs.omarchy.org/stable/$arch|omarchy|omarchy-settings'
rc_selection='rc|0|https://rc-mirror.omarchy.org/$repo/os/$arch|https://pkgs.omarchy.org/rc/$arch|omarchy|omarchy-settings'
edge_dev_selection='edge|1|https://mirror.omarchy.org/$repo/os/$arch|https://pkgs.omarchy.org/edge/$arch|omarchy-dev|omarchy-settings-dev'
edge_production_selection='edge|0|https://mirror.omarchy.org/$repo/os/$arch|https://pkgs.omarchy.org/edge/$arch|omarchy|omarchy-settings'

[[ $(selection_for 'https://stable-mirror.omarchy.org/core/os/x86_64') == "$stable_selection" ]] ||
  fail "stable upgrades select stable production artifacts"
[[ $(selection_for 'https://rc-mirror.omarchy.org/core/os/x86_64') == "$rc_selection" ]] ||
  fail "rc upgrades select release-candidate production artifacts"
[[ $(selection_for 'https://mirror.omarchy.org/core/os/x86_64') == "$edge_dev_selection" ]] ||
  fail "edge upgrades select the edge dev pair"
[[ $(selection_for 'https://stable-mirror.omarchy.org/core/os/x86_64' --channel rc) == "$rc_selection" ]] ||
  fail "explicit rc upgrades select release-candidate production artifacts"
[[ $(selection_for 'https://stable-mirror.omarchy.org/core/os/x86_64' --channel edge) == "$edge_production_selection" ]] ||
  fail "explicit edge selection preserves the production package pair"
[[ $(selection_for 'https://stable-mirror.omarchy.org/core/os/x86_64' --dev) == "$edge_dev_selection" ]] ||
  fail "dev package mode selects edge"

for incompatible_channel in stable rc; do
  if selection_for 'https://mirror.omarchy.org/core/os/x86_64' --dev --channel "$incompatible_channel" >"$test_tmp/out" 2>"$test_tmp/err"; then
    fail "dev package mode accepts the $incompatible_channel channel"
  fi
  grep -Fq -- '--dev needs the edge package repo; use --channel edge.' "$test_tmp/err" ||
    fail "dev package mode does not explain why $incompatible_channel is incompatible"
done

pass "upgrade channels select their matching package artifacts"
