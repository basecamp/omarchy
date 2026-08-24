#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
drm_path="$test_tmp/drm"
mkdir -p "$stub_bin"

# The helper only ever asks `hyprctl monitors all -j`, so the stub answers that
# and nothing else -- an unexpected call is louder as a failure than as an empty
# reply.
cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "monitors" && $2 == "all" && $3 == "-j" ]]; then
  printf '%s' "${OMARCHY_TEST_MONITORS_JSON:-[]}"
  exit 0
fi

printf 'unexpected hyprctl call: %s\n' "$*" >&2
exit 1
SH
chmod +x "$stub_bin/hyprctl"

write_connectors() {
  rm -rf "$drm_path"
  mkdir -p "$drm_path"

  local connector state
  while (($#)); do
    connector="$1"
    state="$2"
    mkdir -p "$drm_path/card0-$connector"
    printf '%s\n' "$state" >"$drm_path/card0-$connector/status"
    shift 2
  done
}

external_active() {
  PATH="$stub_bin:$PATH" \
    OMARCHY_DRM_PATH="$drm_path" \
    OMARCHY_TEST_MONITORS_JSON="$1" \
    "$ROOT/bin/omarchy-hyprland-monitor-external-active"
}

internal_only='[{"name":"eDP-1","disabled":false}]'

# The regression this helper existed to cause: disabling the laptop panel while
# docked and then unplugging the external display empties Hyprland's ENABLED
# monitor set, so its FallbackStateKeeper conjures an output named FALLBACK.
# Counted as an external monitor, it stopped recovery from ever re-enabling the
# panel and left the laptop with no display until the next login.
write_connectors eDP-1 connected DP-1 disconnected
if external_active '[{"name":"eDP-1","disabled":true},{"name":"FALLBACK","disabled":false}]'; then
  fail "the FALLBACK output is not counted as an external monitor"
fi
pass "active external monitor helper ignores Hyprland's FALLBACK output"

write_connectors eDP-1 connected
if external_active '[{"name":"eDP-1","disabled":false},{"name":"HEADLESS-1","disabled":false}]'; then
  fail "a headless output is not counted as an external monitor"
fi
pass "active external monitor helper ignores headless outputs"

# Everything below is the behaviour the helper already had, pinned so the sysfs
# cross-check cannot quietly take it away.
write_connectors eDP-1 connected DP-1 connected
external_active '[{"name":"eDP-1","disabled":false},{"name":"DP-1","disabled":false}]' ||
  fail "a connected external monitor is still reported as active"
pass "active external monitor helper finds a connected external monitor"

# A mirrored external is absent from plain `monitors`, which is why the helper
# asks `monitors all`; it is a real display and must keep counting.
write_connectors eDP-1 connected DP-1 connected
external_active '[{"name":"eDP-1","disabled":false},{"name":"DP-1","disabled":false,"mirrorOf":"eDP-1"}]' ||
  fail "a mirrored external monitor is still reported as active"
pass "active external monitor helper sees mirrored externals"

write_connectors eDP-1 connected DP-1 connected
if external_active '[{"name":"eDP-1","disabled":false},{"name":"DP-1","disabled":true}]'; then
  fail "an external monitor disabled on purpose is not reported as active"
fi
pass "active external monitor helper ignores monitors disabled on purpose"

for connector in eDP-1 LVDS-1 DSI-1; do
  write_connectors "$connector" connected
  if external_active "[{\"name\":\"$connector\",\"disabled\":false}]"; then
    fail "$connector is treated as an internal panel, not an external monitor"
  fi
done
pass "active external monitor helper ignores common internal panel connectors"

write_connectors DP-1 connected
external_active '[{"name":"DP-1","disabled":false}]' ||
  fail "external-only systems still report an active external monitor"
pass "active external monitor helper still supports external-only systems"

# A compositor that cannot be asked is not a compositor with a monitor attached.
write_connectors eDP-1 connected DP-1 connected
if external_active ''; then
  fail "an unanswered query does not invent an external monitor"
fi
pass "active external monitor helper treats an unanswered query as no external monitor"

if external_active "$internal_only"; then
  fail "an internal-only session reports no external monitor"
fi
pass "active external monitor helper reports nothing on an internal-only session"
