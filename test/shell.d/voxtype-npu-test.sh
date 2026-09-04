#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

accel_path="$test_tmp/accel"
mkdir -p "$accel_path/accel0/device"
echo 0x8086 >"$accel_path/accel0/device/vendor"

OMARCHY_ACCEL_PATH="$accel_path" "$ROOT/bin/omarchy-hw-npu" ||
  fail "Intel accelerator is detected as an NPU"

echo 0x1002 >"$accel_path/accel0/device/vendor"
if OMARCHY_ACCEL_PATH="$accel_path" "$ROOT/bin/omarchy-hw-npu"; then
  fail "non-Intel accelerator is not detected as a supported NPU"
fi

pass "NPU detection is limited to Intel accelerators"

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
home="$test_tmp/home"
mkdir -p "$stub_bin" "$home"

cat >"$stub_bin/gum" <<'SH'
#!/bin/bash
[[ $1 == "confirm" ]]
SH

cat >"$stub_bin/omarchy-hw-npu" <<'SH'
#!/bin/bash
(( ${NPU_AVAILABLE:-0} == 1 ))
SH

cat >"$stub_bin/omarchy-hw-vulkan" <<'SH'
#!/bin/bash
(( ${VULKAN_AVAILABLE:-0} == 1 ))
SH

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
(( ${VOXTYPE_PRESENT:-0} == 1 ))
SH

for command in omarchy-pkg-add voxtype systemctl hyprctl omarchy-restart-shell omarchy-notification-send; do
  cat >"$stub_bin/$command" <<'SH'
#!/bin/bash
printf '%s\t%s\n' "$(basename "$0")" "$*" >>"$TEST_LOG"
SH
done

chmod +x "$stub_bin"/*

run_installer() {
  mkdir -p "$home/.config"
  rm -rf "$home/.config/voxtype"
  : >"$calls"
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:/usr/bin" TEST_LOG="$calls" \
    NPU_AVAILABLE="$1" VULKAN_AVAILABLE="$2" bash "$ROOT/bin/omarchy-voxtype-install"
}

run_installer 1 1

grep -Fxq $'omarchy-pkg-add\twtype voxtype-bin openvino-genai openvino-intel-npu-plugin' "$calls" ||
  fail "NPU install includes the version-matched OpenVINO GenAI runtime and NPU plugin"
grep -Fxq $'voxtype\tsetup onnx --enable' "$calls" || fail "NPU install selects an OpenVINO-capable Voxtype binary"
grep -Fxq $'voxtype\tsetup npu --enable' "$calls" || fail "NPU install enables the OpenVINO engine"
! grep -Fq $'voxtype\tsetup gpu --enable' "$calls" || fail "NPU install does not replace the OpenVINO engine with Vulkan"

onnx_line=$(grep -nF $'voxtype\tsetup onnx --enable' "$calls" | cut -d: -f1)
npu_line=$(grep -nF $'voxtype\tsetup npu --enable' "$calls" | cut -d: -f1)
((onnx_line < npu_line)) || fail "NPU install selects the ONNX binary before enabling OpenVINO"

pass "fresh Voxtype installs configure Intel NPU support"

run_installer 0 1

grep -Fxq $'omarchy-pkg-add\twtype voxtype-bin' "$calls" || fail "non-NPU install keeps the standard package set"
grep -Fxq $'voxtype\tsetup --download --no-post-install' "$calls" || fail "non-NPU install downloads the standard model"
grep -Fxq $'voxtype\tsetup gpu --enable' "$calls" || fail "non-NPU install retains Vulkan acceleration"
! grep -Fq 'openvino' "$calls" || fail "non-NPU install does not add OpenVINO packages"

pass "non-NPU Voxtype installs retain the existing path"

migration="$ROOT/migrations/1788538020.sh"
: >"$calls"

PATH="$stub_bin:/usr/bin" TEST_LOG="$calls" NPU_AVAILABLE=1 VOXTYPE_PRESENT=1 \
  bash -euo pipefail "$migration" >/dev/null

grep -Fxq $'omarchy-pkg-add\tvoxtype-bin openvino-genai openvino-intel-npu-plugin' "$calls" ||
  fail "migration installs the complete NPU runtime"
grep -Fxq $'voxtype\tsetup onnx --enable' "$calls" || fail "migration selects an OpenVINO-capable Voxtype binary"
grep -Fxq $'voxtype\tsetup npu --enable' "$calls" || fail "migration enables NPU acceleration"
grep -Fxq $'systemctl\t--user restart voxtype' "$calls" || fail "migration restarts Voxtype"

pass "migration enables NPU support for existing Voxtype installs"

: >"$calls"
PATH="$stub_bin:/usr/bin" TEST_LOG="$calls" NPU_AVAILABLE=0 VOXTYPE_PRESENT=1 \
  bash -euo pipefail "$migration" >/dev/null
[[ ! -s $calls ]] || fail "migration leaves non-NPU systems unchanged"

pass "migration skips systems without an Intel NPU"
