#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

windows_vm_command="$ROOT/bin/omarchy-windows-vm"
windows_vm_rules="$ROOT/default/hypr/apps/windows-vm.lua"

rg -q '^    restart: "no"$' "$windows_vm_command" ||
  fail "Windows VM uses manual startup by default"
pass "Windows VM uses manual startup by default"

if rg -q '^    restart: unless-stopped$' "$windows_vm_command"; then
  fail "Windows VM does not restart automatically at boot"
fi
pass "Windows VM does not restart automatically at boot"

# Tolerate either shell quoting of the argument -- what must not drift is the
# title itself, since the Hyprland rule below matches on it.
rg -q 'title:"?Windows VM - Omarchy"' "$windows_vm_command" ||
  fail "Windows VM launches FreeRDP with its expected title"
rg -q 'class = "\^xfreerdp\$", title = "\^Windows VM - Omarchy\$"' "$windows_vm_rules" ||
  fail "Windows VM opacity rule targets its FreeRDP window"
rg -q 'tag = "-default-opacity"' "$windows_vm_rules" ||
  fail "Windows VM opts out of default opacity"
rg -q 'opacity = "1 1"' "$windows_vm_rules" ||
  fail "Windows VM stays fully opaque"
pass "Windows VM stays fully opaque"

# User-side source hardening must clear leftover directory setgid. GNU chmod
# 0700 does not, so a pre-existing ~/Windows mode 2700/2777 used to survive
# prepare_user_mount_sources and then fail the privileged exact-700 check.
(
  test_home=$(mktemp -d)
  trap 'rm -rf "$test_home"' EXIT
  mkdir -p "$test_home/.windows" "$test_home/Windows" "$test_home/.config/windows"
  chmod 2700 "$test_home/.windows"
  chmod 2777 "$test_home/Windows"
  chmod 2755 "$test_home/.config/windows"
  HOME=$test_home
  set -- help
  source "$windows_vm_command" >/dev/null
  prepare_user_mount_sources || fail "user mount source hardening failed on setgid directories"
  [[ $(stat -Lc '%a' "$HOME/.windows") == 700 ]] || fail "storage mode is $(stat -Lc '%a' "$HOME/.windows"), expected 700"
  [[ $(stat -Lc '%a' "$HOME/Windows") == 700 ]] || fail "shared mode is $(stat -Lc '%a' "$HOME/Windows"), expected 700"
  write_credentials alice secret || fail "write_credentials failed on a setgid config dir"
  [[ $(stat -Lc '%a' "$HOME/.config/windows") == 700 ]] || fail "credentials dir mode is $(stat -Lc '%a' "$HOME/.config/windows"), expected 700"
)
pass "user mount sources with leftover setgid harden to exactly 700"
