#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# End-to-end check of the omarchy:// link handler on an installed system: the
# scheme must resolve to our desktop entry the way a browser resolves it, and
# opening a link must land the user in the interactive plugin trust prompt —
# never straight into a clone.

terminal_class='^org\.omarchy\.terminal$'
repo_url='https://github.com/acme/omarchy-weather.git'

if window_present "$terminal_class" >/dev/null 2>&1; then
  fail "url handler starts with no pre-existing terminal" "an Omarchy terminal is already open"
fi

desktop_entry="$HOME/.local/share/applications/omarchy-url-handler.desktop"
[[ -f $desktop_entry ]] ||
  fail "url handler desktop entry is installed for the user" "missing $desktop_entry"
pass "url handler desktop entry is installed for the user"

handler=$(xdg-mime query default x-scheme-handler/omarchy || true)
[[ $handler == "omarchy-url-handler.desktop" ]] ||
  fail "omarchy:// scheme resolves to the url handler" "xdg-mime returned '${handler:-(nothing)}'"
pass "omarchy:// scheme resolves to the url handler"

command -v omarchy-url-handler >/dev/null ||
  fail "omarchy-url-handler is on PATH"
pass "omarchy-url-handler is on PATH"

# Open the link the way a browser hands it off, then expect the plugin trust
# prompt in a floating terminal rather than any git activity.
launch_app "xdg-open 'omarchy://plugin/add?url=${repo_url//\//%2F}'"
wait_until "omarchy:// link opens a terminal" 45 window_present "$terminal_class"
wait_until "terminal shows the plugin trust prompt" 30 screen_contains "Clone and add this plugin"
screenshot "success-url-handler-prompt"

[[ ! -d $HOME/.config/omarchy/plugins/omarchy-weather ]] ||
  fail "link does not clone before confirmation" "plugin directory appeared without confirmation"
pass "link does not clone before confirmation"

close_windows "$terminal_class"
wait_until "url handler terminal closes" 30 window_absent "$terminal_class"

# A rejected link must not open a terminal at all.
launch_app "xdg-open 'omarchy://plugin/add?url=ssh%3A%2F%2Fgit%40example.test%2Facme%2Fplugin.git'"
sleep 5
window_absent "$terminal_class" >/dev/null 2>&1 ||
  fail "rejected ssh link opens no terminal"
pass "rejected ssh link opens no terminal"
