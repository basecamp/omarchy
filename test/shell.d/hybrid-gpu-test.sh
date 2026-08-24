#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
exit 1
STUB

cat >"$fake_bin/sleep" <<'STUB'
#!/bin/bash
:
STUB

cat >"$fake_bin/gum" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_TMP/prompts"
exit "${CONFIRM_STATUS:-1}"
STUB

cat >"$fake_bin/lspci" <<'STUB'
#!/bin/bash

if [[ ${T2_HARDWARE:-0} == "1" ]]; then
  echo '00:02.0 VGA compatible controller [0300]: Intel Corporation UHD Graphics [8086:3e9b]'
  echo '03:00.0 VGA compatible controller [0300]: AMD Radeon Pro [1002:7340]'
  echo '04:00.1 Non-VGA unclassified device [0000]: Apple T2 Bridge [106b:1801]'
fi
STUB

cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
"$@"
STUB

cat >"$fake_bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
command -v "$1" >/dev/null
STUB

# Both names, so the test never reaches a real one whichever branch is taken.
cat >"$fake_bin/limine-mkinitcpio" <<'STUB'
#!/bin/bash
echo rebuild >>"$TEST_TMP/rebuilds"
exit "${REBUILD_STATUS:-0}"
STUB

cat >"$fake_bin/mkinitcpio" <<'STUB'
#!/bin/bash
echo rebuild >>"$TEST_TMP/rebuilds"
exit "${REBUILD_STATUS:-0}"
STUB

cat >"$fake_bin/omarchy-system-reboot" <<'STUB'
#!/bin/bash
echo reboot >>"$TEST_TMP/reboots"
STUB

cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_TMP/systemctl"
exit "${SYSTEMCTL_STATUS:-0}"
STUB

cat >"$fake_bin/supergfxctl" <<'STUB'
#!/bin/bash
attempts_file="$TEST_TMP/attempts"
attempts=0
[[ -f $attempts_file ]] && attempts=$(<"$attempts_file")
attempts=$((attempts + 1))
printf '%s\n' "$attempts" >"$attempts_file"

if (( attempts < ${SUCCEED_ON_ATTEMPT:-999} )); then
  exit 1
fi

echo Hybrid
STUB

chmod +x "$fake_bin"/*

gmux_conf="$test_tmp/modprobe.d/apple-gmux.conf"
dpm_rule="$test_tmp/udev/rules.d/30-omarchy-t2-amdgpu-pm.rules"
dpm_source="$ROOT/default/udev/rules.d/30-omarchy-t2-amdgpu-pm.rules"
renderer_env="$test_tmp/uwsm/env-hyprland.d/20-omarchy-t2-gpu"
renderer_source="$ROOT/default/uwsm/env-hyprland.d/20-omarchy-t2-gpu"
supergfx_conf="$test_tmp/supergfxd.conf"
force_igpu="$test_tmp/system-sleep/force-igpu"
supergfx_delay="$test_tmp/supergfxd.service.d/delay-start.conf"

export OMARCHY_T2_SUPERGFX_CONF="$supergfx_conf"
export OMARCHY_T2_FORCE_IGPU="$force_igpu"
export OMARCHY_T2_SUPERGFX_DELAY="$supergfx_delay"

mkdir -p "$(dirname "$gmux_conf")" "$(dirname "$force_igpu")" "$(dirname "$supergfx_delay")"
printf '{\n  "mode": "Integrated"\n}\n' >"$supergfx_conf"
touch "$force_igpu" "$supergfx_delay"

fake_drm="$test_tmp/sys/class/drm"
mkdir -p "$fake_drm/card4/device" "$fake_drm/card7/device" \
  "$test_tmp/drivers/amdgpu" "$test_tmp/drivers/i915"
ln -s "$test_tmp/drivers/amdgpu" "$fake_drm/card4/device/driver"
ln -s "$test_tmp/drivers/i915" "$fake_drm/card7/device/driver"

printf '%s\n' 'options apple-gmux force_igd=y' >"$gmux_conf"
renderer_devices=$(
  OMARCHY_T2_DRM_DIR="$fake_drm" OMARCHY_T2_GMUX_CONF="$gmux_conf" \
    sh -c '. "$1"; printf "%s" "$AQ_DRM_DEVICES"' _ "$renderer_source"
)
[[ $renderer_devices == "/dev/dri/card7" ]] ||
  fail "T2 integrated renderer policy selects only Intel" "$renderer_devices"
pass "T2 renderer policy discovers dynamic Intel and Radeon card numbers"

rm "$fake_drm/card4/device/driver"
wait_bin="$test_tmp/wait-bin"
mkdir -p "$wait_bin"
cat >"$wait_bin/sleep" <<'STUB'
#!/bin/bash
echo wait >>"$TEST_TMP/renderer-waits"
ln -s "$TEST_TMP/drivers/amdgpu" "$TEST_TMP/sys/class/drm/card4/device/driver"
STUB
chmod +x "$wait_bin/sleep"

printf '%s\n' 'options apple-gmux force_igd=y' >"$gmux_conf"
renderer_devices=$(
  TEST_TMP="$test_tmp" OMARCHY_T2_DRM_DIR="$fake_drm" \
    OMARCHY_T2_GMUX_CONF="$gmux_conf" OMARCHY_T2_GPU_WAIT_ATTEMPTS=2 \
    PATH="$wait_bin:$PATH" \
    sh -c '. "$1"; printf "%s" "$AQ_DRM_DEVICES"' _ "$renderer_source"
)
[[ $renderer_devices == "/dev/dri/card7" ]] ||
  fail "T2 integrated renderer policy waits for Radeon before selecting only Intel" "$renderer_devices"
[[ $(wc -l <"$test_tmp/renderer-waits") == "1" ]] ||
  fail "T2 integrated renderer policy waits once for the delayed Radeon"
pass "T2 integrated renderer policy excludes late Radeon initialization"

rm "$fake_drm/card4/device/driver" "$test_tmp/renderer-waits"
printf '%s\n' 'options apple-gmux force_igd=n' >"$gmux_conf"
renderer_devices=$(
  TEST_TMP="$test_tmp" OMARCHY_T2_DRM_DIR="$fake_drm" \
    OMARCHY_T2_GMUX_CONF="$gmux_conf" OMARCHY_T2_GPU_WAIT_ATTEMPTS=2 \
    PATH="$wait_bin:$PATH" \
    sh -c '. "$1"; printf "%s" "$AQ_DRM_DEVICES"' _ "$renderer_source"
)
[[ $renderer_devices == "/dev/dri/card4" ]] ||
  fail "T2 dedicated renderer policy waits for and selects only Radeon" "$renderer_devices"
[[ $(wc -l <"$test_tmp/renderer-waits") == "1" ]] ||
  fail "T2 dedicated renderer policy waits once for the delayed Radeon"
pass "T2 dedicated renderer policy handles late Radeon initialization"

rm -f "$gmux_conf"
legacy_renderer="$test_tmp/legacy/20-omarchy-t2-gpu"
mkdir -p "$(dirname "$renderer_env")" "$(dirname "$legacy_renderer")"
printf '%s\n' 'legacy omarchy-t2 renderer' >"$legacy_renderer"
ln -s "$legacy_renderer" "$renderer_env"

TEST_TMP="$test_tmp" T2_HARDWARE=1 CONFIRM_STATUS=0 \
  OMARCHY_T2_GMUX_CONF="$gmux_conf" OMARCHY_T2_DGPU_RULE="$dpm_rule" \
  OMARCHY_T2_RENDERER_ENV="$renderer_env" OMARCHY_PATH="$ROOT" \
  PATH="$fake_bin:$PATH" \
  bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" >/dev/null

grep -Fxq 'options apple-gmux force_igd=y' "$gmux_conf" ||
  fail "T2 hybrid graphics can switch to integrated graphics"
cmp -s "$dpm_source" "$dpm_rule" ||
  fail "T2 integrated graphics keeps Radeon in its safe low-power mode"
cmp -s "$renderer_source" "$renderer_env" ||
  fail "T2 integrated graphics prioritizes Intel rendering through UWSM"
[[ ! -L $renderer_env ]] ||
  fail "T2 graphics replaces a legacy omarchy-t2 renderer symlink"
grep -Fq '"mode": "Hybrid"' "$supergfx_conf" ||
  fail "T2 graphics neutralizes stale supergfxd integrated mode"
[[ ! -e $force_igpu ]] || fail "T2 graphics removes the supergfxd sleep hook"
[[ ! -e $supergfx_delay ]] || fail "T2 graphics removes the supergfxd startup delay"
grep -Fxq 'disable --now supergfxd' "$test_tmp/systemctl" ||
  fail "T2 graphics disables the incompatible supergfxd service"
grep -Fq 'Use integrated low-power mode and reboot?' "$test_tmp/prompts" ||
  fail "T2 Intel mode makes the Radeon performance tradeoff explicit"
[[ $(wc -l <"$test_tmp/reboots") == "1" ]] || fail "T2 Intel mode requests one reboot"
[[ $(wc -l <"$test_tmp/rebuilds") == "1" ]] ||
  fail "T2 Intel mode rebuilds the boot image so the new module option is read"
pass "T2 hybrid graphics switches to integrated mode"

: >"$test_tmp/prompts"
TEST_TMP="$test_tmp" T2_HARDWARE=1 CONFIRM_STATUS=0 \
  OMARCHY_T2_GMUX_CONF="$gmux_conf" OMARCHY_T2_DGPU_RULE="$dpm_rule" \
  OMARCHY_T2_RENDERER_ENV="$renderer_env" OMARCHY_PATH="$ROOT" \
  PATH="$fake_bin:$PATH" \
  bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" >/dev/null

grep -Fxq 'options apple-gmux force_igd=n' "$gmux_conf" ||
  fail "T2 hybrid graphics can switch to dedicated graphics"
[[ ! -e $dpm_rule ]] || fail "T2 dedicated graphics restores automatic Radeon performance"
cmp -s "$renderer_source" "$renderer_env" ||
  fail "T2 dedicated graphics keeps explicit renderer selection through UWSM"
renderer_devices=$(
  OMARCHY_T2_DRM_DIR="$fake_drm" OMARCHY_T2_GMUX_CONF="$gmux_conf" \
    sh -c '. "$1"; printf "%s" "$AQ_DRM_DEVICES"' _ "$renderer_env"
)
[[ $renderer_devices == "/dev/dri/card4" ]] ||
  fail "T2 dedicated graphics configures Radeon as the primary renderer" "$renderer_devices"
grep -Fq 'Enable dedicated GPU and reboot?' "$test_tmp/prompts" ||
  fail "T2 AMD mode uses the existing dedicated GPU prompt"
[[ $(wc -l <"$test_tmp/reboots") == "2" ]] || fail "T2 AMD mode requests one reboot"
[[ $(wc -l <"$test_tmp/rebuilds") == "2" ]] ||
  fail "T2 AMD mode rebuilds the boot image so the new module option is read"
pass "T2 hybrid graphics switches back to dedicated mode"

: >"$test_tmp/prompts"
TEST_TMP="$test_tmp" T2_HARDWARE=1 CONFIRM_STATUS=1 \
  OMARCHY_T2_GMUX_CONF="$gmux_conf" OMARCHY_T2_DGPU_RULE="$dpm_rule" \
  OMARCHY_T2_RENDERER_ENV="$renderer_env" OMARCHY_PATH="$ROOT" \
  PATH="$fake_bin:$PATH" \
  bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" >/dev/null

grep -Fxq 'options apple-gmux force_igd=n' "$gmux_conf" ||
  fail "declining a T2 graphics switch preserves the selected mode"
[[ $(wc -l <"$test_tmp/reboots") == "2" ]] || fail "declining a T2 graphics switch skips reboot"
[[ $(wc -l <"$test_tmp/rebuilds") == "2" ]] ||
  fail "declining a T2 graphics switch skips the boot image rebuild"
pass "T2 hybrid graphics leaves a declined switch unchanged"

: >"$test_tmp/prompts"
set +e
error=$(
  TEST_TMP="$test_tmp" T2_HARDWARE=1 CONFIRM_STATUS=0 \
    OMARCHY_T2_GMUX_CONF="$gmux_conf" OMARCHY_T2_DGPU_RULE=/dev/full \
    OMARCHY_T2_RENDERER_ENV="$renderer_env" OMARCHY_PATH="$ROOT" \
    PATH="$fake_bin:$PATH" \
    bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" 2>&1 >/dev/null
)
status=$?
set -e

(( status != 0 )) || fail "a failed Radeon power policy fails the T2 graphics switch"
[[ $(wc -l <"$test_tmp/reboots") == "2" ]] ||
  fail "a failed Radeon power policy leaves the machine running"
[[ $(wc -l <"$test_tmp/rebuilds") == "2" ]] ||
  fail "a failed Radeon power policy skips the boot image rebuild"
grep -qF 'Graphics mode change incomplete' <<<"$error" ||
  fail "a failed Radeon power policy explains the partial change" "$error"
pass "T2 hybrid graphics does not reboot without its Radeon power policy"

: >"$test_tmp/prompts"
printf '%s\n' 'options apple-gmux force_igd=n' >"$gmux_conf"
set +e
error=$(
  TEST_TMP="$test_tmp" T2_HARDWARE=1 CONFIRM_STATUS=0 \
    OMARCHY_T2_GMUX_CONF="$gmux_conf" OMARCHY_T2_DGPU_RULE="$dpm_rule" \
    OMARCHY_T2_RENDERER_ENV=/dev/full OMARCHY_PATH="$ROOT" \
    PATH="$fake_bin:$PATH" \
    bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" 2>&1 >/dev/null
)
status=$?
set -e

(( status != 0 )) || fail "a failed renderer policy fails the T2 graphics switch"
[[ $(wc -l <"$test_tmp/reboots") == "2" ]] ||
  fail "a failed renderer policy leaves the machine running"
[[ $(wc -l <"$test_tmp/rebuilds") == "2" ]] ||
  fail "a failed renderer policy skips the boot image rebuild"
grep -qF 'Graphics mode change incomplete' <<<"$error" ||
  fail "a failed renderer policy explains the partial change" "$error"
pass "T2 hybrid graphics does not reboot without its renderer policy"

: >"$test_tmp/prompts"
set +e
error=$(
  TEST_TMP="$test_tmp" T2_HARDWARE=1 CONFIRM_STATUS=0 REBUILD_STATUS=1 \
    OMARCHY_T2_GMUX_CONF="$gmux_conf" OMARCHY_T2_DGPU_RULE="$dpm_rule" \
    OMARCHY_T2_RENDERER_ENV="$renderer_env" OMARCHY_PATH="$ROOT" \
    PATH="$fake_bin:$PATH" \
    bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" 2>&1 >/dev/null
)
status=$?
set -e

(( status != 0 )) || fail "a failed boot image rebuild fails the T2 graphics switch"
[[ $(wc -l <"$test_tmp/reboots") == "2" ]] ||
  fail "a failed boot image rebuild leaves the machine running"
grep -qF 'Not rebooting' <<<"$error" ||
  fail "a failed boot image rebuild says why nothing happened" "$error"
pass "T2 hybrid graphics does not reboot onto a boot image that failed to build"

TEST_TMP="$test_tmp" SUCCEED_ON_ATTEMPT=3 \
  PATH="$fake_bin:$PATH" bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" >/dev/null

[[ $(<"$test_tmp/attempts") == "3" ]] || fail "hybrid GPU mode query retries transient failures"
pass "hybrid GPU mode query recovers from a transient supergfxd failure"

rm -f "$test_tmp/attempts"

set +e
error=$(
  TEST_TMP="$test_tmp" \
    PATH="$fake_bin:$PATH" bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" 2>&1 >/dev/null
)
status=$?
set -e

(( status != 0 )) || fail "hybrid GPU mode query fails when supergfxd stays unavailable"
[[ $(<"$test_tmp/attempts") == "3" ]] || fail "hybrid GPU mode query stops after three attempts"
grep -qF 'supergfxd is not responding' <<<"$error" ||
  fail "hybrid GPU mode query explains how to diagnose supergfxd" "$error"
pass "hybrid GPU mode query fails clearly instead of hanging"

cat >"$fake_bin/supergfxctl" <<'STUB'
#!/bin/bash
trap '' TERM
/usr/bin/sleep 30
STUB
chmod +x "$fake_bin/supergfxctl"

set +e
output=$(TEST_TMP="$test_tmp" PATH="$fake_bin:$PATH" timeout 25s bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" 2>&1)
status=$?
set -e

(( status != 124 )) || fail "hybrid GPU mode query terminates a blocked client"
(( status != 0 )) || fail "hybrid GPU mode query reports a blocked client as unavailable"
grep -qF 'supergfxd is not responding' <<<"$output" ||
  fail "hybrid GPU mode query diagnoses a blocked client" "$output"
pass "hybrid GPU mode query kills a client that ignores the timeout signal"
