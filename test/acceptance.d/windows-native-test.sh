#!/bin/bash

# Executable skeleton for WINDOWS_NATIVE_ACCEPTANCE.md — the forty-task
# Windows-native release gate, run in the disposable-VM acceptance suite.
# Cases land here as vertical slices ship; a case with no implementation yet
# reports "skip" so the manifest stays honest about coverage without failing
# the suite. When a case gains steps, replace its skip line with real checks
# using the base-test.sh helpers (pass/fail/wait_until/layer_present/...).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

MANIFEST="$ROOT/WINDOWS_NATIVE_ACCEPTANCE.md"

tasks=(
  "install the OS"
  "connect Wi-Fi"
  "set display scaling to 125%"
  "change the wallpaper"
  "pair Bluetooth headphones"
  "adjust output volume"
  "install Firefox or Chrome"
  "install Steam"
  "open Downloads"
  "create a folder"
  "rename it"
  "copy files"
  "zip them"
  "connect a USB drive"
  "eject it"
  "connect to an SMB share"
  "open a PDF"
  "edit a text file"
  "change the default browser"
  "pin an app"
  "unpin an app"
  "minimize three windows"
  "restore the one they want"
  "snap two windows"
  "use Alt+Tab"
  "find an application that is consuming CPU"
  "disable a startup application"
  "install system updates"
  "inspect update history"
  "create a restore point"
  "roll back a deliberately broken update"
  "add a printer"
  "change keyboard layout"
  "enable night light"
  "change power mode"
  "install one known-compatible .exe"
  "uninstall it"
  "find system/storage information"
  "troubleshoot intentionally broken audio"
  "shut down"
)

# The manifest document and the harness task list must never drift apart.
manifest_tasks=$(grep -cE '^\| [0-9]+ \|' "$MANIFEST")
if ((manifest_tasks != ${#tasks[@]})); then
  fail "manifest/harness drift" "WINDOWS_NATIVE_ACCEPTANCE.md lists $manifest_tasks tasks; harness enumerates ${#tasks[@]}"
fi
pass "acceptance manifest and harness agree on ${#tasks[@]} tasks"

status=0
for task in "${tasks[@]}"; do
  case "$task" in
  # Implemented cases append here as vertical slices ship, e.g.:
  # "connect Wi-Fi")
  #   open_quick_settings
  #   wait_until "Wi-Fi list is visible" 15 screen_contains "Wi-Fi"
  #   ;;
  *)
    printf 'skip - %s (no automated coverage yet)\n' "$task"
    screenshot "pending-$(printf '%s' "$task" | tr -c 'a-z0-9' -)"
    ;;
  esac
done

exit $status
