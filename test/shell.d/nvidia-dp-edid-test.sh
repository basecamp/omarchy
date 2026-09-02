#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

# A 128-byte, "NVD"-tagged dummy EDID like the one NVIDIA fabricates on DP1.4.
dummy_edid() {
  {
    printf '\x00\xff\xff\xff\xff\xff\xff\x00\x3a\xc4\x00\x00\x00\x00\x00\x00'
    printf 'NVD'
  }
  head -c 109 /dev/zero
}

# A plausible real 384-byte EDID: different PNP, no "NVD" tag.
real_edid() {
  printf '\x00\xff\xff\xff\xff\xff\xff\x00\x06\xb3\x00\x00\x00\x00\x00\x00'
  head -c 368 /dev/zero
}

# Detection tree (what sysfs shows before the OSD switch).
drm_path="$test_tmp/drm"
# Capture tree (what sysfs shows after switching the monitor to DP1.2).
capture_path="$test_tmp/capture"

firmware_dir="$test_tmp/firmware/edid"
mkinitcpio_dir="$test_tmp/mkinitcpio.conf.d"
default_limine="$test_tmp/limine"

# Both trees hold the same connector so the wizard resolves the name via
# detection and then re-reads the capture path during the EDID capture phase.
mkdir -p "$drm_path/card0-DP-2" "$capture_path/card0-DP-2"
printf 'connected\n' >"$drm_path/card0-DP-2/status"
printf 'connected\n' >"$capture_path/card0-DP-2/status"

write_stub sudo 'printf "SUDO %s\n" "$*" >>"$SUDO_LOG"; exec "$@"'
write_stub limine-update 'printf "LIMINE\n" >>"$LIMINE_LOG"'

SUDO_LOG="$test_tmp/sudo.log"
LIMINE_LOG="$test_tmp/limine.log"
export SUDO_LOG LIMINE_LOG

env_for_run() {
  OMARCHY_DRM_PATH="$drm_path" \
  OMARCHY_EDID_CAPTURE_DRM_PATH="$capture_path" \
  OMARCHY_EDID_FIRMWARE_DIR="$firmware_dir" \
  OMARCHY_MKINITCPIO_DIR="$mkinitcpio_dir" \
  OMARCHY_DEFAULT_LIMINE="$default_limine" \
  OMARCHY_EDID_CAPTURE_SLEEP=0 \
  PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-setup-nvidia-dp-edid" -y
}

run_env() {
  OMARCHY_DRM_PATH="$drm_path" \
  OMARCHY_EDID_FIRMWARE_DIR="$firmware_dir" \
  OMARCHY_MKINITCPIO_DIR="$mkinitcpio_dir" \
  OMARCHY_DEFAULT_LIMINE="$default_limine" \
  OMARCHY_EDID_CAPTURE_SLEEP=0 \
  PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-setup-nvidia-dp-edid" -y
}

# Seed a default limine cmdline the wizard appends to.
mkdir -p "$(dirname "$default_limine")"
printf 'KERNEL_CMDLINE[default]+="quiet"\n' >"$default_limine"

# 1) No dummy EDID means there is nothing to fix: abort.
real_edid >"$drm_path/card0-DP-2/edid"
set +e
no_dummy_out=$(run_env 2>&1)
no_dummy_status=$?
set -e
(( no_dummy_status != 0 )) || fail "wizard aborts when no dummy EDID is found"
pass "wizard aborts when no dummy EDID is found"

# 2) Happy path: detection sees dummy, capture presents real EDID.
dummy_edid >"$drm_path/card0-DP-2/edid"
real_edid >"$capture_path/card0-DP-2/edid"
env_for_run >"$test_tmp/run.out" 2>&1

[[ -f "$firmware_dir/DP-2.bin" ]] ||
  fail "wizard installs the forced EDID firmware" "$(cat "$test_tmp/run.out")"
# The installed firmware must be the real (384-byte) EDID, not the dummy.
(( $(wc -c <"$firmware_dir/DP-2.bin") == 384 )) ||
  fail "wizard copies the real EDID, not the dummy"
pass "wizard installs the real EDID as firmware"

grep -q 'FILES+=(.*/DP-2.bin)' "$mkinitcpio_dir/edid-firmware.conf" ||
  fail "wizard writes an mkinitcpio FILES entry" "$(cat "$mkinitcpio_dir/edid-firmware.conf")"
pass "wizard writes an mkinitcpio FILES entry"

grep -q 'drm.edid_firmware=DP-2:edid/DP-2.bin' "$default_limine" ||
  fail "wizard appends the drm.edid_firmware param to limine config" "$(cat "$default_limine")"
pass "wizard appends the drm.edid_firmware param to limine config"

grep -q '^LIMINE$' "$LIMINE_LOG" ||
  fail "wizard regenerates the Limine config" "$(cat "$LIMINE_LOG")"
pass "wizard regenerates the Limine config"

# 3) Idempotence: detection already reads a real EDID after a previous fix.
real_edid >"$drm_path/card0-DP-2/edid"
set +e
env_for_run >"$test_tmp/run2.out" 2>&1
idem_status=$?
set -e
(( idem_status != 0 )) || fail "wizard does not touch a connector already fixed"
pass "wizard does not touch a connector already fixed"
