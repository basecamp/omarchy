#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

grep -qx 'flatpak' "$ROOT/install/omarchy-base.packages" ||
  fail "flatpak ships in the default package set"
pass "flatpak ships in the default package set"

grep -qF 'config/flatpak.sh' "$ROOT/install/config/all.sh" ||
  fail "the Flatpak setup leaf runs during system setup"
pass "the Flatpak setup leaf runs during system setup"

grep -qF 'flatpak remote-add --if-not-exists flathub' "$ROOT/install/config/flatpak.sh" ||
  fail "system setup adds the Flathub remote"
pass "system setup adds the Flathub remote"

# UWSM doesn't source /etc/profile.d, so without this line a session puts no
# Flatpak exports directory on XDG_DATA_DIRS and every installed app is
# missing from the launcher.
grep -qF '/etc/profile.d/flatpak.sh' "$ROOT/default/uwsm/env.d/10-omarchy" ||
  fail "the session puts Flatpak's exported apps on XDG_DATA_DIRS"
pass "the session puts Flatpak's exported apps on XDG_DATA_DIRS"

grep -qx '  omarchy-update-flatpaks' "$ROOT/bin/omarchy-update" ||
  fail "omarchy update updates installed Flatpak apps"
pass "omarchy update updates installed Flatpak apps"

grep -qF 'GROUP_DESCRIPTIONS[flatpak]=' "$ROOT/bin/omarchy" ||
  fail "the flatpak command group is listed in the router"
pass "the flatpak command group is listed in the router"

# The helpers exist so callers stop reasoning about installation scope and
# polkit on their own; a raw install or uninstall anywhere else is that
# reasoning coming back.
raw_flatpak_writes=$(rg -l -P '^[^#\n]*\bflatpak (install|uninstall|update)\b' "$ROOT/bin" \
  | rg -v '/omarchy-(flatpak-|update-flatpaks)' || true)
[[ -z $raw_flatpak_writes ]] || fail "bin commands install and remove Flatpak apps through the helpers" "$raw_flatpak_writes"
pass "bin commands install and remove Flatpak apps through the helpers"
