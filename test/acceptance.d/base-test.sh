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
  local step=${description,,}

  step=${step// /-}
  step=${step//[^a-z0-9-]/}

  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  screenshot "failure-$step"
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

screenshot() {
  timeout 10 grim "$ARTIFACTS/$1.png" 2>/dev/null || true
}

screen_contains() {
  local text="$1"
  local snapshot="/tmp/omarchy-acceptance-ocr-$$.png"

  if ! timeout 10 grim "$snapshot" 2>/dev/null; then
    rm -f "$snapshot"
    return 1
  fi
  tesseract "$snapshot" stdout --psm 11 2>/dev/null | grep -Fi -- "$text" >/dev/null
  local status=$?
  rm -f "$snapshot"
  return $status
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

# A layer can be mapped but parked off the monitor: the bar hides that way so
# revealing it does not have to rebuild the surface. Assert on geometry when
# what matters is that the user can actually see it. Layer boxes are in logical
# coordinates, so the monitor's pixel size has to be divided by its scale.
layer_on_screen() {
  local monitors
  monitors=$(hyprctl -j monitors) || return 1

  hyprctl -j layers | jq -e --arg ns "$1" --argjson monitors "$monitors" '
    to_entries[]
    | .key as $name
    | .value as $levels
    | ($monitors[] | select(.name == $name)) as $m
    | [$levels | .. | objects | select(.namespace? == $ns)][]
    | select(
        .x + .w > $m.x and .x < $m.x + $m.width / $m.scale and
        .y + .h > $m.y and .y < $m.y + $m.height / $m.scale
      )
  ' >/dev/null
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
