#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

open_and_close() {
  local name="$1" plugin="$2" namespace="$3" payload="${4:-}"

  if [[ -n $payload ]]; then
    omarchy-shell shell summon "$plugin" "$payload" >/dev/null
  else
    omarchy-shell shell summon "$plugin" >/dev/null
  fi

  wait_until "$name opens" 15 layer_present "$namespace"
  sleep 1
  screenshot "success-$name-open"

  omarchy-shell shell hide "$plugin" >/dev/null
  wait_until "$name closes" 15 layer_absent "$namespace"
}

# Search and select an emoji. The host harness separately proves the shortcut
# with a QMP hardware key chord, while this test focuses on UI behavior.
omarchy-shell shell summon omarchy.emojis >/dev/null
wait_until "emoji picker opens" 15 layer_present "omarchy-emojis"
wtype "rocket"
sleep 1
screenshot "success-emoji-picker-search"
wtype -k Return
wait_until "emoji picker selection closes" 15 layer_absent "omarchy-emojis"

# Seed two clipboard entries, search for the older one, and copy it back out.
clipboard_token="Omarchy acceptance clipboard $(date +%s)"
printf '%s' "$clipboard_token" | wl-copy
wait_until "clipboard history captures test text" 15 grep -Fq "$clipboard_token" "$HOME/.local/state/omarchy/clipboard-history.json"
printf '%s' "clipboard decoy" | wl-copy
sleep 1

omarchy-shell shell summon omarchy.clipboard >/dev/null
wait_until "clipboard opens" 15 layer_present "omarchy-clipboard"
wtype "$clipboard_token"
wait_until "clipboard search finds test text" 15 screen_contains "Omarchy acceptance clipboard"
screenshot "success-clipboard-search"
wtype -M shift -k Return -m shift
wait_until "clipboard selection closes" 15 layer_absent "omarchy-clipboard"
wait_until "clipboard selection restores test text" 15 bash -c '[[ $(wl-paste --no-newline) == "$1" ]]' _ "$clipboard_token"

# Exercise the system branch without invoking any destructive action.
omarchy-shell shell summon omarchy.menu '{"menu":"system"}' >/dev/null
wait_until "system menu opens" 15 layer_present "omarchy-menu"
wait_until "system menu content is visible" 15 screen_contains "Shutdown"
screenshot "success-system-menu"
wtype -k Escape
wait_until "system menu closes" 15 layer_absent "omarchy-menu"

# Preview both visual selectors and cancel without changing user state. These
# cover thumbnail generation, the image-grid overlay, and current selection.
launch_app "omarchy-theme-bg-switcher"
wait_until "background selector opens" 30 layer_present "omarchy-image-selector"
sleep 1
screenshot "success-background-selector"
wtype -k Escape
wait_until "background selector closes" 15 layer_absent "omarchy-image-selector"

launch_app "omarchy-theme-switcher"
wait_until "theme selector opens" 30 layer_present "omarchy-image-selector"
sleep 1
screenshot "success-theme-selector"
wtype -k Escape
wait_until "theme selector closes" 15 layer_absent "omarchy-image-selector"

# Walk the reminder flow through each input screen, but dismiss before it
# schedules a real timer in the test user's session.
omarchy-shell shell summon omarchy.reminders >/dev/null
wait_until "reminder flow opens" 15 layer_present "omarchy-reminders"
screenshot "success-reminder-01-minutes-prompt"
wtype "5"
sleep 1
screenshot "success-reminder-02-minutes-entered"
wtype -k Return
wait_until "reminder message prompt opens" 15 screen_contains "Reminder message"
screenshot "success-reminder-03-message-prompt"
wtype -k Escape
wait_until "reminder flow closes" 15 layer_absent "omarchy-reminders"

# Render a real shell notification and clear it through the notification IPC.
omarchy-shell notifications dismissAll >/dev/null
omarchy-notification-send "Acceptance notification" "Shell notification rendering" --expire-time=15000
wait_until "notification popup opens" 15 layer_present "omarchy-notifications"
wait_until "notification content is visible" 15 screen_contains "Acceptance notification"
screenshot "success-notification-popup"
omarchy-shell notifications dismissAll >/dev/null
wait_until "notification popup closes" 15 layer_absent "omarchy-notifications"

# The launcher does the full loop: open, search by typing, launch the top hit.
if window_present "(?i)omawrite" >/dev/null 2>&1; then
  fail "launcher test starts with no Omawrite window" "an Omawrite window is already open"
fi

omarchy-shell shell summon omarchy.launcher >/dev/null
wait_until "launcher opens" 15 layer_present "omarchy-launcher"
sleep 1
screenshot "success-launcher-open"

wtype "omawrite"
sleep 1
screenshot "success-launcher-search"
wtype -k Return

wait_until "launcher launches the top search hit" 60 window_present "(?i)omawrite"
wait_until "launcher closes after launching" 15 layer_absent "omarchy-launcher"

close_windows "(?i)omawrite"
wait_until "Omawrite window closes" 30 window_absent "(?i)omawrite"
