#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

apply="$ROOT/bin/omarchy-hyprland-monitor-apply"
[[ -f $apply ]] || fail "omarchy-hyprland-monitor-apply exists"
grep -Fq 'omarchy:hidden=true' "$apply" || fail "monitor apply is a hidden hyprland helper"
grep -Fq '>= 50' "$apply" || fail "monitor apply treats 4K as a desktop mode only at >= 50 Hz"
grep -Fq 'omarchy-hyprland-monitor-apply' "$ROOT/bin/omarchy-hyprland-monitor-watch" \
  || fail "monitor watcher applies a working desktop mode on start and hotplug"
grep -Fq 'omarchy-hyprland-monitor-apply' "$ROOT/config/hypr/monitors.lua" \
  || fail "monitors.lua asks apply for the first modeset so preferred is not the desktop default"
grep -Fq -- '--emit-lua' "$ROOT/config/hypr/monitors.lua" \
  || fail "monitors.lua emits hl.monitor from the connector at parse time"
if grep -E 'hl\.monitor\(\{[^}]*mode = "preferred"' "$ROOT/config/hypr/monitors.lua"; then
  fail "monitors.lua fallback must not be EDID preferred; that is cinema 4K on a TV"
fi
grep -E 'hl\.monitor\(\{[^}]*mode = "highrr"' "$ROOT/config/hypr/monitors.lua" >/dev/null \
  || fail "empty-connector fallback is highrr, the highest refresh, not preferred"
grep -F 'omarchy-hyprland-monitor-apply.service' "$ROOT/install/user/first-run/enable-user-units.sh" \
  || fail "first-run enables the monitor apply unit so safe-mode still configures the panel"
pass "monitor apply is wired through config load, the watcher, and login"
if awk '/^if \(\( emit_lua \)\)/,/^fi$/' "$apply" | grep -v '^[[:space:]]*#' | grep -qE 'apply_hyprctl|[[:space:]]hyprctl'; then
  fail "emit-lua must not call hyprctl; that deadlocks Hyprland config parse"
fi
grep -Fq 'emit_from_drm' "$apply" || fail "parse-time emit reads the connector from DRM"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub="$test_tmp/bin"
mkdir -p "$stub"
eval_log="$test_tmp/eval.log"

samsung='[{"name":"HDMI-A-1","disabled":false,"width":3840,"height":2160,"refreshRate":30,"scale":2,"physicalWidth":1420,"physicalHeight":800,"availableModes":["3840x2160@30.00Hz","4096x2160@29.97Hz","2560x1440@59.95Hz","1920x1080@60.00Hz"]}]'
uhd60='[{"name":"HDMI-A-1","disabled":false,"width":1920,"height":1080,"refreshRate":60,"scale":1,"physicalWidth":1420,"physicalHeight":800,"availableModes":["3840x2160@60.00Hz","3840x2160@30.00Hz","1920x1080@60.00Hz"]}]'
uhd30_monitor='[{"name":"HDMI-A-1","disabled":false,"width":3840,"height":2160,"refreshRate":30,"scale":2,"physicalWidth":600,"physicalHeight":340,"availableModes":["3840x2160@30.00Hz","1920x1080@60.00Hz"]}]'
qhd='[{"name":"DP-1","disabled":false,"width":1920,"height":1080,"refreshRate":60,"scale":1,"physicalWidth":600,"physicalHeight":340,"availableModes":["2560x1440@144.00Hz","1920x1080@60.00Hz"]}]'
fhd='[{"name":"HDMI-A-1","disabled":false,"width":1280,"height":720,"refreshRate":60,"scale":1,"physicalWidth":510,"physicalHeight":290,"availableModes":["1920x1080@60.00Hz","1280x720@60.00Hz"]}]'
hz244='[{"name":"DP-1","disabled":false,"width":1920,"height":1080,"refreshRate":60,"scale":1,"physicalWidth":530,"physicalHeight":300,"availableModes":["1920x1080@244.00Hz","1920x1080@239.76Hz","1920x1080@60.00Hz","1280x720@244.00Hz"]}]'
qhd240='[{"name":"DP-1","disabled":false,"width":1920,"height":1080,"refreshRate":60,"scale":1,"physicalWidth":530,"physicalHeight":300,"availableModes":["2560x1440@240.00Hz","2560x1440@144.00Hz","1920x1080@240.00Hz"]}]'

cat >"$stub/hyprctl" <<SH
#!/bin/bash
if [[ \$1 == monitors && \$2 == all && \$3 == -j ]]; then
  cat "\$OMARCHY_TEST_MONITORS_JSON"
  exit 0
fi
if [[ \$1 == eval ]]; then
  printf '%s\n' "\$2" >>"$eval_log"
  exit 0
fi
exit 1
SH
chmod +x "$stub/hyprctl"

run_apply() {
  : >"$eval_log"
  mkdir -p "$test_tmp/drm-empty"
  printf '%s\n' "$1" >"$test_tmp/monitors.json"
  OMARCHY_TEST_MONITORS_JSON="$test_tmp/monitors.json" \
    OMARCHY_TEST_DRM="$test_tmp/drm-empty" PATH="$stub:$PATH" \
    "$apply"
}

run_apply "$samsung"
grep -F 'mode = "1920x1080@60.00"' "$eval_log" >/dev/null \
  || fail "HDMI TV with only cinema 4K uses 1080p60, the timing the panel locks" "$(cat "$eval_log")"
grep -F 'bitdepth = 8' "$eval_log" >/dev/null \
  || fail "desktop modeset is 8-bit so HDR/10-bit cannot blank the sink" "$(cat "$eval_log")"
! grep -F '3840x2160' "$eval_log" >/dev/null \
  || fail "4K@30 must not be the automatic desktop mode on a TV" "$(cat "$eval_log")"
! grep -F 'scale = 2' "$eval_log" >/dev/null \
  || fail "1080p TV must not be scaled 2x" "$(cat "$eval_log")"
pass "Samsung-style HDMI 1.4 TV becomes 1080p60, not blank 4K30"

run_apply "$uhd60"
grep -F 'mode = "3840x2160@60.00"' "$eval_log" >/dev/null \
  || fail "4K@60 wins when the link advertises a desktop 4K refresh" "$(cat "$eval_log")"
grep -F 'scale = 2' "$eval_log" >/dev/null \
  || fail "4K desktop mode uses scale 2" "$(cat "$eval_log")"
pass "HDMI 2.0 4K@60 is selected when present"

run_apply "$uhd30_monitor"
grep -F 'mode = "1920x1080@60.00"' "$eval_log" >/dev/null \
  || fail "cinema 4K never wins when a >= 50 Hz desktop mode exists" "$(cat "$eval_log")"
! grep -F '3840x2160' "$eval_log" >/dev/null \
  || fail "4K@30 is not a desktop mode even on a small panel" "$(cat "$eval_log")"
pass "4K30 plus 1080p60 uses the desktop timing, not cinema 4K"

run_apply "$qhd"
grep -F 'mode = "2560x1440@144.00"' "$eval_log" >/dev/null \
  || fail "1440p desktop panel uses its high-refresh mode" "$(cat "$eval_log")"
pass "1440p monitor uses the highest >= 50 Hz mode"

run_apply "$fhd"
grep -F 'mode = "1920x1080@60.00"' "$eval_log" >/dev/null \
  || fail "1080p panel without 4K uses 1920x1080@60" "$(cat "$eval_log")"
! grep -F 'scale = 2' "$eval_log" >/dev/null \
  || fail "1080p must not be scaled 2x" "$(cat "$eval_log")"
pass "1080p-only EDID stays 1080p60 at scale 1"

run_apply "$hz244"
grep -F 'mode = "1920x1080@244.00"' "$eval_log" >/dev/null \
  || fail "24 inch 244Hz panel uses native 1080p at 244, not 720p@244" "$(cat "$eval_log")"
! grep -F '1280x720' "$eval_log" >/dev/null \
  || fail "highest refresh at a lower resolution must not beat native" "$(cat "$eval_log")"
pass "244Hz 1080p monitor uses 1920x1080@244"

run_apply "$qhd240"
grep -F 'mode = "2560x1440@240.00"' "$eval_log" >/dev/null \
  || fail "1440p 240Hz panel uses native 1440p at 240, not 1080p@240" "$(cat "$eval_log")"
pass "1440p 240Hz monitor uses native resolution at max refresh"

write_drm_connector() {
  local dir=$1 status=$2
  shift 2
  mkdir -p "$dir"
  printf '%s\n' "$status" >"$dir/status"
  if (($#)); then
    printf '%s\n' "$@" >"$dir/modes"
  else
    : >"$dir/modes"
  fi
}

run_emit() {
  local drm=$1
  OMARCHY_TEST_DRM="$drm" "$apply" --emit-lua
}

drm_tv="$test_tmp/drm-tv"
write_drm_connector "$drm_tv/card1-HDMI-A-1" connected \
  "3840x2160" "4096x2160" "2560x1440" "1920x1080" "1280x720"
emit_out=$(run_emit "$drm_tv") || fail "emit-lua ranks a names-only HDMI TV" "$emit_out"
grep -F 'mode = "1920x1080@60.00"' <<<"$emit_out" >/dev/null \
  || fail "kernel-preferred cinema 4K plus 1080p becomes 1080p60" "$emit_out"
! grep -F '3840x2160' <<<"$emit_out" >/dev/null \
  || fail "emit-lua must not print cinema 4K when 1080p exists" "$emit_out"
pass "parse-time emit ranks a TV from sysfs names, no pin, no preferred"

drm_uhd60="$test_tmp/drm-uhd60"
write_drm_connector "$drm_uhd60/card1-HDMI-A-1" connected \
  "3840x2160@60.00" "3840x2160@30.00" "1920x1080@60.00"
emit_out=$(run_emit "$drm_uhd60") || fail "emit-lua ranks a 4K60 sink" "$emit_out"
grep -F 'mode = "3840x2160@60.00"' <<<"$emit_out" >/dev/null \
  || fail "UHD at >= 50 Hz is the automatic 4K desktop mode" "$emit_out"
pass "parse-time emit selects 4K60 when the link advertises it"

drm_qhd="$test_tmp/drm-qhd"
write_drm_connector "$drm_qhd/card1-DP-1" connected \
  "2560x1440@144.00" "1920x1080@60.00"
emit_out=$(run_emit "$drm_qhd") || fail "emit-lua ranks a 1440p monitor" "$emit_out"
grep -F 'mode = "2560x1440@144.00"' <<<"$emit_out" >/dev/null \
  || fail "desktop panel uses native high-refresh, not 1080p" "$emit_out"
pass "parse-time emit selects 1440p144 on a desktop monitor"

drm_edid="$test_tmp/drm-edid"
write_drm_connector "$drm_edid/card1-HDMI-A-1" connected \
  "3840x2160" "1920x1080"
python3 - "$drm_edid/card1-HDMI-A-1/edid" <<'PY'
import sys
edid = bytearray(128)
edid[0:8] = bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
edid[21] = 142
edid[22] = 80
edid[54] = 0x04
edid[55] = 0x74
edid[56] = 0x00
edid[57] = 0x30
edid[58] = 0xF2
edid[59] = 0x70
edid[60] = 0x5A
edid[61] = 0x80
edid[127] = (256 - (sum(edid[:127]) % 256)) % 256
open(sys.argv[1], "wb").write(edid)
PY
emit_out=$(run_emit "$drm_edid") || fail "emit-lua ranks EDID cinema DTD plus sysfs 1080p" "$emit_out"
grep -F 'mode = "1920x1080@60.00"' <<<"$emit_out" >/dev/null \
  || fail "EDID 4K30 DTD must lose to sysfs 1080p60 on a TV" "$emit_out"
! grep -F '3840x2160' <<<"$emit_out" >/dev/null \
  || fail "merged candidates still must not emit cinema 4K" "$emit_out"
pass "parse-time emit merges EDID DTDs with sysfs names and picks the desktop mode"

drm_off="$test_tmp/drm-off"
write_drm_connector "$drm_off/card1-DP-1" disconnected
write_drm_connector "$drm_off/card1-HDMI-A-1" connected "1920x1080@60.00"
emit_out=$(run_emit "$drm_off") || fail "emit-lua disables a disconnected DP" "$emit_out"
grep -F 'output = "DP-1", disabled = true' <<<"$emit_out" >/dev/null \
  || fail "disconnected DP is disabled so it cannot steal the modeset" "$emit_out"
grep -F 'mode = "1920x1080@60.00"' <<<"$emit_out" >/dev/null \
  || fail "the connected HDMI still gets a ranked desktop mode" "$emit_out"
pass "parse-time emit disables disconnected outputs"
