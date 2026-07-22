#!/bin/bash

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source test/acceptance.d/base-test.sh from an acceptance test; do not run it directly" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
ARTIFACTS="${OMARCHY_ACCEPTANCE_DIR:-/tmp/omarchy-acceptance}"

mkdir -p "$ARTIFACTS"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  local description="$1"
  local detail="${2:-}"

  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  screenshot "failure-$(date +%s)"
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

screenshot() {
  grim "$ARTIFACTS/$1.png" 2>/dev/null || true
}

# Poll a command until it succeeds; screenshot and fail on timeout.
wait_until() {
  local description="$1" timeout="$2"
  shift 2

  local deadline=$((SECONDS + timeout))

  until "$@" >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      fail "$description" "timed out after ${timeout}s waiting for: $*"
    fi
    sleep 1
  done

  pass "$description"
}

window_present() {
  hyprctl -j clients | jq -e --arg class "$1" '[.[] | select(.class | test($class))] | length > 0'
}

window_absent() {
  ! window_present "$1"
}

layer_present() {
  hyprctl -j layers | jq -e --arg ns "$1" '[.. | objects | select(.namespace? == $ns)] | length > 0'
}

layer_absent() {
  ! layer_present "$1"
}

# Close every window matching a class regex, by address so multi-window apps
# are fully closed. Tries the quattro Lua dispatcher first, then classic.
close_windows() {
  local class="$1"
  local addr

  while read -r addr; do
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null 2>&1 ||
      hyprctl dispatch closewindow "address:$addr" >/dev/null 2>&1 || true
  done < <(hyprctl -j clients | jq -r --arg class "$class" '.[] | select(.class | test($class)) | .address')
}

launch_app() {
  setsid -f bash -c "$1" >/dev/null 2>&1
}
