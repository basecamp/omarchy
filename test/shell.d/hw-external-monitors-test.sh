#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

drm_path="$test_tmp/drm"

write_connectors() {
  rm -rf "$drm_path"
  mkdir -p "$drm_path"

  local connector state
  while (( $# )); do
    connector="$1"
    state="$2"
    mkdir -p "$drm_path/card0-$connector"
    printf '%s\n' "$state" >"$drm_path/card0-$connector/status"
    shift 2
  done
}

has_external_monitor() {
  OMARCHY_DRM_PATH="$drm_path" "$ROOT/bin/omarchy-hw-external-monitors"
}

write_connectors
set +e
empty_error=$(has_external_monitor 2>&1 >/dev/null)
empty_status=$?
set -e

(( empty_status != 0 )) || fail "an empty DRM tree has no external display"
[[ -z $empty_error ]] || fail "an empty DRM tree is handled quietly" "$empty_error"
pass "physical monitor detection handles an empty DRM tree"

for connector in eDP-1 LVDS-1 DSI-1; do
  write_connectors "$connector" connected

  if has_external_monitor; then
    fail "$connector is treated as an internal display"
  fi
done
pass "physical monitor detection ignores common internal panel connectors"

write_connectors LVDS-1 connected DP-1 connected
has_external_monitor || fail "external display is found alongside an LVDS panel"
pass "physical monitor detection finds an external display alongside an LVDS panel"

write_connectors eDP-1 connected HDMI-A-1 disconnected
if has_external_monitor; then
  fail "a disconnected external display is not reported as connected"
fi
pass "physical monitor detection ignores disconnected external displays"

write_connectors DP-1 connected
has_external_monitor || fail "external-only systems still report a connected display"
pass "physical monitor detection still supports external-only systems"
