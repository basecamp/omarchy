#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

launch_and_verify() {
  local name="$1" command="$2" class="$3" timeout="${4:-45}"

  # A pre-existing window makes the test ambiguous (and closing it would be
  # hostile on a dev machine) — acceptance runs expect a fresh session.
  if window_present "$class" >/dev/null 2>&1; then
    fail "$name starts with no pre-existing window" "a window matching $class is already open"
  fi

  launch_app "$command"
  wait_until "$name opens a window" "$timeout" window_present "$class"
  sleep 1
  screenshot "success-app-$name"

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

# Keep launch coverage to the primary daily-use paths. The system acceptance
# test separately verifies the complete core package manifest.
# name|command|window class regex|launch timeout
apps='terminal|foot|^foot$
browser|chromium --new-window|(?i)chromium
neovim|xdg-terminal-exec --app-id=org.omarchy.nvim nvim|org.omarchy.nvim
writer|omawrite|(?i)omawrite'

status=0
while IFS='|' read -r name command class timeout; do
  if ! (launch_and_verify "$name" "$command" "$class" "$timeout"); then
    status=1
  fi
done <<<"$apps"

exit $status
