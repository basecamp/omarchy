#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

launch_and_verify() {
  local name="$1" command="$2" class="$3"

  # A pre-existing window makes the test ambiguous (and closing it would be
  # hostile on a dev machine) — acceptance runs expect a fresh session.
  if window_present "$class" >/dev/null 2>&1; then
    fail "$name starts with no pre-existing window" "a window matching $class is already open"
  fi

  launch_app "$command"
  wait_until "$name opens a window" 90 window_present "$class"
  sleep 1
  screenshot "app-$name"

  local deadline=$((SECONDS + 30))
  while window_present "$class" >/dev/null 2>&1; do
    close_windows "$class"

    if ((SECONDS >= deadline)); then
      fail "$name window closes"
    fi

    sleep 2
  done
  pass "$name window closes"
}

# name|command|window class regex
apps='terminal|foot|^foot$
browser|chromium --new-window|(?i)chromium
files|nautilus --new-window|org.gnome.Nautilus
calculator|gnome-calculator|org.gnome.Calculator
notes|obsidian|(?i)obsidian
office|libreoffice|(?i)(soffice|libreoffice)
pdf-viewer|evince|(?i)evince'

while IFS='|' read -r name command class; do
  launch_and_verify "$name" "$command" "$class"
done <<<"$apps"
