#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

install_script="$ROOT/install/hardware/intel/ipu7-camera.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
acpi_devices="$test_tmp/acpi"
mkdir -p "$stub_bin" "$acpi_devices/device:00" "$acpi_devices/device:01"

echo 'INTC1059' >"$acpi_devices/device:00/hid"

# Chatty past the pipe buffer after the match, so a gate that piped lspci into a
# grep that stops reading would die of SIGPIPE and read as "no IPU7" (#6608).
cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

(( ${LSPCI_STATUS:-0} == 0 )) || exit "$LSPCI_STATUS"
[[ -n ${IPU_PCI_ID:-} ]] &&
  printf '00:05.0 Multimedia controller [0480]: Intel Corporation Image Processing Unit [8086:%s]\n' "$IPU_PCI_ID"
for _ in {1..4096}; do
  echo '02:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash

printf 'omarchy-pkg-add\t%s\n' "$*" >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_install() {
  : >"$calls"
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    IPU_PCI_ID="${1:-}" \
    LSPCI_STATUS="${2:-0}" \
    OMARCHY_ACPI_DEVICES_PATH="$acpi_devices" \
    bash -euo pipefail -c 'source "$1"' bash "$install_script"
}

echo 'OVTI08F4' >"$acpi_devices/device:01/hid"

run_install b05d
grep -Fxq $'omarchy-pkg-add\tintel-ipu7-camera' "$calls" ||
  fail "Panther Lake installs the IPU7 camera stack" "$(cat "$calls")"
pass "Panther Lake with an ov08x40 sensor installs the IPU7 camera stack"

# The sensor spans generations, and the package builds only the ipu75xa HAL: every
# other controller gets a camera stack that cannot drive it (#7697).
run_install 7d19
[[ ! -s $calls ]] ||
  fail "Meteor Lake IPU6 skips the IPU7 camera stack" "$(cat "$calls")"

run_install a75d
[[ ! -s $calls ]] ||
  fail "Raptor Lake IPU6 skips the IPU7 camera stack" "$(cat "$calls")"

run_install 645d
[[ ! -s $calls ]] ||
  fail "Lunar Lake, which the ipu75xa HAL does not cover, is skipped" "$(cat "$calls")"
pass "the same sensor behind another controller installs nothing"

run_install "" 1
[[ ! -s $calls ]] ||
  fail "an unreadable PCI bus skips the IPU7 camera stack" "$(cat "$calls")"
pass "an unreadable PCI bus installs nothing"

echo 'OVTI2680' >"$acpi_devices/device:01/hid"

run_install b05d
[[ ! -s $calls ]] ||
  fail "a machine without an ov08x40 sensor installs nothing" "$(cat "$calls")"
pass "hardware without an ov08x40 sensor installs nothing"
