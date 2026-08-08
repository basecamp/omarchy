#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-brcmfmac-supplicant.sh"
fix_t2="$ROOT/install/hardware/apple/fix-t2.sh"
all="$ROOT/install/hardware/all.sh"

grep -q 'apple/fix-brcmfmac-supplicant.sh' "$all" ||
  fail "the brcmfmac quirk runs during hardware setup"

# Two leaves writing one config means the later one silently wins, and which is
# later is a detail of all.sh nobody would think to check.
! grep -q 'brcmfmac' "$fix_t2" ||
  fail "only one leaf owns /etc/modprobe.d/brcmfmac.conf"
pass "the brcmfmac quirk has a single owner and runs during setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin" "$test_tmp/dmi"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the match,
# so a grep -q consumer would kill this stub with SIGPIPE and pipefail would read
# that as "no such hardware" (#6608).
[[ -n ${STUB_WIFI_LINE:-} ]] && echo "$STUB_WIFI_LINE"
for _ in {1..4096}; do
  echo '02:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH
chmod +x "$stub_bin"/*

# The leaf reads the vendor from an absolute path, so point it at a fixture by
# running with a fake root on PATH-independent state.
run_leaf() {
  local vendor="$1" wifi="${2:-}"
  rm -rf "$test_tmp/etc"
  mkdir -p "$test_tmp/etc"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"

  # Redirect both absolute paths the leaf touches into the sandbox.
  local script="$test_tmp/leaf.sh"
  sed -e "s|/sys/class/dmi/id/sys_vendor|$test_tmp/dmi/sys_vendor|g" \
      -e "s|/etc/modprobe.d|$test_tmp/etc/modprobe.d|g" \
      "$leaf" >"$script"

  STUB_WIFI_LINE="$wifi" PATH="$stub_bin:$PATH" \
    bash -eE -c 'source "$1"' bash "$script" </dev/null
}

broadcom='03:00.0 Network controller [0280]: Broadcom Inc. and subsidiaries BCM43602 802.11ac Wireless LAN SoC [14e4:43ba]'
intel_wifi='03:00.0 Network controller [0280]: Intel Corporation Wi-Fi 6 AX200 [8086:2723]'

# The machine this was written for: a pre-T2 Mac, which the T2 gate never covered.
run_leaf "Apple Inc." "$broadcom" >/dev/null
grep -q 'feature_disable=0x82000' "$test_tmp/etc/modprobe.d/brcmfmac.conf" 2>/dev/null ||
  fail "a Mac with Broadcom Wi-Fi gets the quirk" "$(ls -R "$test_tmp/etc" 2>&1)"
pass "a pre-T2 Mac with Broadcom Wi-Fi gets the quirk"

# Older Macs report the vendor differently.
run_leaf "Apple Computer, Inc." "$broadcom" >/dev/null
[[ -f $test_tmp/etc/modprobe.d/brcmfmac.conf ]] ||
  fail "the older Apple vendor string is recognized"
pass "the older Apple vendor string is recognized"

# The quirk works around Broadcom firmware, so it has no business on a Mac whose
# Wi-Fi is something else.
run_leaf "Apple Inc." "$intel_wifi" >/dev/null
[[ ! -f $test_tmp/etc/modprobe.d/brcmfmac.conf ]] ||
  fail "a Mac without Broadcom Wi-Fi is left alone"
pass "a Mac without Broadcom Wi-Fi is left alone"

# Plenty of non-Apple hardware uses brcmfmac and does not share this bug.
run_leaf "LENOVO" "$broadcom" >/dev/null
[[ ! -f $test_tmp/etc/modprobe.d/brcmfmac.conf ]] ||
  fail "non-Apple hardware with a Broadcom part is left alone"
pass "non-Apple hardware is left alone"

run_leaf "Apple Inc." "" >/dev/null
[[ ! -f $test_tmp/etc/modprobe.d/brcmfmac.conf ]] ||
  fail "a Mac with no wireless device is left alone"
pass "a Mac with no wireless device is left alone"
