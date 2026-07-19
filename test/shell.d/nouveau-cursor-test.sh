#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/home/.config/hypr"
cat >"$test_tmp/bin/lspci" <<'SH'
#!/bin/bash
printf '%s\n' "Kernel driver in use: ${TEST_VIDEO_DRIVER:-nouveau}"
SH
chmod +x "$test_tmp/bin/lspci"

looknfeel="$test_tmp/home/.config/hypr/looknfeel.lua"
printf '%s\n' '-- User look and feel' >"$looknfeel"

run_fix() {
  HOME="$test_tmp/home" \
    PATH="$test_tmp/bin:$ROOT/bin:$PATH" \
    OMARCHY_NVIDIA_MODPROBE_CONFIG="$test_tmp/nvidia.conf" \
    TEST_VIDEO_DRIVER="${1:-nouveau}" \
    bash -euo pipefail -c 'source "$ROOT/install/user/hardware/fix-nouveau-cursor.sh"'
}

run_fix >/dev/null
grep -F 'no_hardware_cursors = true' "$looknfeel" >/dev/null
pass "nouveau hardware setup enables software cursors"

run_fix >/dev/null
(( $(grep -c 'no_hardware_cursors = true' "$looknfeel") == 1 )) || fail "nouveau cursor setup is idempotent"
pass "nouveau cursor setup is idempotent"

printf '%s\n' '-- User look and feel' >"$looknfeel"
run_fix i915 >/dev/null
if grep -q 'no_hardware_cursors' "$looknfeel"; then
  fail "nouveau cursor setup ignores other video drivers"
fi
pass "nouveau cursor setup ignores other video drivers"

touch "$test_tmp/nvidia.conf"
run_fix >/dev/null
if grep -q 'no_hardware_cursors' "$looknfeel"; then
  fail "nouveau cursor setup skips proprietary NVIDIA installs"
fi
pass "nouveau cursor setup skips proprietary NVIDIA installs"
