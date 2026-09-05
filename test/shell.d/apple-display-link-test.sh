#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

helper="$ROOT/bin/omarchy-hw-apple-display-link"
unit="$ROOT/default/systemd/system/omarchy-apple-display-link.service"
rule="$ROOT/default/udev/apple-display-link.rules"
fix_t2="$ROOT/install/hardware/apple/fix-t2.sh"
migration="$ROOT/migrations/1788346426.sh"

[[ -x $helper ]] || fail "the Apple display link helper is tracked executable"
grep -Fq 'ExecStart=/usr/bin/omarchy-hw-apple-display-link' "$unit" ||
  fail "the service runs the packaged helper"
grep -Fq 'ACTION=="change", SUBSYSTEM=="drm"' "$rule" ||
  fail "the udev rule fires on DRM hotplug"
grep -Fq 'systemctl --no-block start omarchy-apple-display-link.service' "$rule" ||
  fail "the udev rule starts the service without blocking udev"
grep -Fq 'default/udev/apple-display-link.rules' "$fix_t2" ||
  fail "T2 setup installs the udev rule"
grep -Fq 'default/systemd/system/omarchy-apple-display-link.service' "$fix_t2" ||
  fail "T2 setup installs the service"
grep -Fq 'systemctl enable omarchy-apple-display-link.service' "$fix_t2" ||
  fail "T2 setup enables the service"
pass "T2 setup ships the Apple display link service"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

drm="$test_tmp/drm"
dri="$test_tmp/dri"

debug_dir() {
  local name="$1" card=${1%%-*}
  printf '%s\n' "$dri/${card#card}/${name#"$card"-}"
}

# A fake connector with the amdgpu debugfs files the helper reads and writes.
# debugfs pads its reads with NUL bytes, so the fixtures do too.
add_connector() {
  local name="$1" status="$2" product="$3" preferred="$4" dsc="$5"
  local debug
  debug=$(debug_dir "$name")
  mkdir -p "$drm/$name" "$debug"
  echo "$status" >"$drm/$name/status"
  printf 'edid %s\0' "$product" >"$drm/$name/edid"
  printf 'Current:  4  0x14  0  Verified:  4  0x14  16  Reported:  4  0x14  16  Preferred:  %s\n\0' "$preferred" \
    >"$debug/link_settings"
  printf '%s\n\0' "$dsc" >"$debug/dsc_clock_en"
  echo untouched >"$debug/trigger_hotplug"
}

run_helper() {
  OMARCHY_DRM_PATH="$drm" OMARCHY_DRI_DEBUG_PATH="$dri" OMARCHY_APPLE_DISPLAY_SETTLE=0 bash "$helper"
}

link_settings() {
  tr -d '\0' <"$(debug_dir "$1")/link_settings"
}

trigger_hotplug() {
  tr -d '\0' <"$(debug_dir "$1")/trigger_hotplug"
}

add_connector card2-DP-6 connected StudioDisplay "0  0x0  0" 1
add_connector card2-DP-7 connected StudioDisplay "4  0x1e  0" 0
add_connector card2-DP-4 connected "DELL U2723QE" "0  0x0  0" 1
add_connector card2-DP-5 disconnected StudioDisplay "0  0x0  0" 0
add_connector card2-eDP-1 connected StudioDisplay "0  0x0  0" 0

output=$(run_helper)

[[ $(link_settings card2-DP-6) == "4 0x1e" ]] ||
  fail "a connected Studio Display on an HBR2 link gets HBR3 preferred" "$output"
[[ $(trigger_hotplug card2-DP-6) == 1 ]] ||
  fail "a stream still compressed after the retrain gets a simulated replug" "$output"
grep -Fq 'card2-DP-6: DisplayPort link pinned to HBR3' <<<"$output" ||
  fail "the helper names the connector it pinned" "$output"
[[ $(link_settings card2-DP-7) == Current:* ]] ||
  fail "a link already preferring HBR3 is left alone"
[[ $(trigger_hotplug card2-DP-7) == untouched ]] ||
  fail "a link already preferring HBR3 is not replugged"
[[ $(link_settings card2-DP-4) == Current:* ]] ||
  fail "other monitors keep their link settings"
[[ $(link_settings card2-DP-5) == Current:* ]] ||
  fail "a disconnected Studio Display is left alone"
[[ $(link_settings card2-eDP-1) == Current:* ]] ||
  fail "internal panels are never touched"
pass "the helper pins HBR3 on connected Studio Displays only"

rm -rf "$drm" "$dri"
add_connector card2-DP-6 connected StudioDisplay "0  0x0  0" 0

run_helper >/dev/null

[[ $(link_settings card2-DP-6) == "4 0x1e" ]] ||
  fail "the helper still pins HBR3 when the retrain alone drops DSC"
[[ $(trigger_hotplug card2-DP-6) == untouched ]] ||
  fail "an uncompressed stream after the retrain is not replugged"
pass "the helper only replugs a stream that stayed compressed"

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the T2
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no T2 hardware" (#6608).
if (( ${T2_HARDWARE:-0} == 1 )); then
  echo '01:00.0 Bridge [0680]: Apple Inc. T2 Security Chip [106b:1801]'
fi
for _ in {1..4096}; do
  echo '02:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

for tool in systemctl udevadm; do
  cat >"$stub_bin/$tool" <<SH
#!/bin/bash

printf '$tool' >>"\$TEST_LOG"
printf '\\t%s' "\$@" >>"\$TEST_LOG"
printf '\\n' >>"\$TEST_LOG"
SH
done

chmod +x "$stub_bin"/*

unit_target="$test_tmp/etc/systemd/system/omarchy-apple-display-link.service"
rule_target="$test_tmp/etc/udev/rules.d/90-omarchy-apple-display-link.rules"

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    T2_HARDWARE="$1" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_APPLE_DISPLAY_UNIT="$unit_target" \
    OMARCHY_APPLE_DISPLAY_RULE="$rule_target" \
    bash -euo pipefail "$migration" >/dev/null
}

run_migration 1

cmp -s "$unit" "$unit_target" || fail "the migration installs the shipped service"
cmp -s "$rule" "$rule_target" || fail "the migration installs the shipped udev rule"
grep -Fq $'systemctl\tdaemon-reload' "$calls" || fail "the migration reloads systemd" "$(cat "$calls")"
grep -Fq $'udevadm\tcontrol\t--reload' "$calls" || fail "the migration reloads udev" "$(cat "$calls")"
grep -Fq $'systemctl\tenable\t--now\tomarchy-apple-display-link.service' "$calls" ||
  fail "the migration enables and starts the service" "$(cat "$calls")"
pass "the migration installs the Apple display link service on existing T2 installs"

: >"$calls"
run_migration 1
[[ ! -s $calls ]] || fail "an already repaired T2 install is left unchanged" "$(cat "$calls")"
pass "the migration is idempotent"

rm -rf "$test_tmp/etc"
: >"$calls"
run_migration 0
[[ ! -e $unit_target && ! -e $rule_target ]] || fail "non-T2 systems get no Apple display link service"
[[ ! -s $calls ]] || fail "non-T2 systems skip the repair" "$(cat "$calls")"
pass "the migration skips unrelated hardware"
