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
