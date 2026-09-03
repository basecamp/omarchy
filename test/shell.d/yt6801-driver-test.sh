#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls"
mkdir -p "$stub_bin"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash
if [[ $* == "-Dn -d 1f0a:6801" ]]; then
  printf '%s\n' '0000:01:00.0 0200: 1f0a:6801'
elif [[ $* == "-Dks 0000:01:00.0" ]]; then
  if [[ -e $TEST_BOUND_STATE ]]; then
    printf '%s\n' 'Kernel driver in use: dwmac-motorcomm'
  else
    printf '%s\n' 'Kernel modules: dwmac-motorcomm'
  fi
fi
SH

cat >"$stub_bin/modinfo" <<'SH'
#!/bin/bash
printf '%s\n' 'pci:v00001F0Ad00006801sv*sd*bc*sc*i*'
SH

cat >"$stub_bin/lsmod" <<'SH'
#!/bin/bash
[[ ${TEST_VENDOR_LOADED:-1} == 1 ]] && printf '%s\n' 'yt6801 65536 0'
SH

for command in modprobe omarchy-pkg-drop tee; do
  cat >"$stub_bin/$command" <<'SH'
#!/bin/bash
printf '%s\t%s\n' "${0##*/}" "$*" >>"$TEST_CALLS"
if [[ ${0##*/} == "tee" ]]; then
  cat >/dev/null
  touch "$TEST_BOUND_STATE"
fi
SH
done

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo\t%s\n' "$*" >>"$TEST_CALLS"
"$@"
SH

chmod +x "$stub_bin"/*
export TEST_CALLS="$calls"
export TEST_BOUND_STATE="$test_tmp/upstream-bound"

PATH="$stub_bin:$PATH" bash "$ROOT/install/hardware/fix-yt6801-ethernet-adapter.sh"
grep -Fqx $'omarchy-pkg-drop\tyt6801-dkms' "$calls" ||
  fail "hardware setup did not remove the vendor DKMS package"
if grep -Fq $'modprobe\t' "$calls"; then
  fail "hardware setup tried to load a module against the installer kernel"
fi

: >"$calls"
TEST_VENDOR_LOADED=1 PATH="$stub_bin:$PATH" bash -euo pipefail "$ROOT/migrations/1788279117.sh"
grep -Fqx $'sudo\tmodprobe dwmac-motorcomm' "$calls" ||
  fail "migration did not validate-load the upstream driver"
grep -Fqx $'omarchy-pkg-drop\tyt6801-dkms' "$calls" ||
  fail "migration did not remove the vendor DKMS package"
grep -Fqx $'sudo\tmodprobe -r yt6801' "$calls" ||
  fail "migration did not unload the vulnerable driver"
grep -Fqx $'sudo\ttee /sys/bus/pci/drivers_probe' "$calls" ||
  fail "migration did not reprobe the YT6801 device"

# A failed first cutover can leave the vendor module unloaded and the device
# unbound. Rerunning must still reprobe instead of repeating the same failure.
: >"$calls"
rm -f "$TEST_BOUND_STATE"
TEST_VENDOR_LOADED=0 PATH="$stub_bin:$PATH" bash -euo pipefail "$ROOT/migrations/1788279117.sh"
if grep -Fqx $'sudo\tmodprobe -r yt6801' "$calls"; then
  fail "retry tried to unload a vendor module that was already absent"
fi
grep -Fqx $'sudo\ttee /sys/bus/pci/drivers_probe' "$calls" ||
  fail "retry did not reprobe an unbound YT6801 device"
[[ -e $TEST_BOUND_STATE ]] || fail "retry did not restore the upstream binding"

: >"$calls"
TEST_VENDOR_LOADED=0 PATH="$stub_bin:$PATH" bash -euo pipefail "$ROOT/migrations/1788279117.sh"
if grep -Fq $'sudo\ttee /sys/bus/pci/drivers_probe' "$calls"; then
  fail "settled migration unnecessarily reprobed an already-bound device"
fi

if grep -Fxq 'yt6801-dkms' "$ROOT/install/omarchy-other.packages"; then
  fail "default package list still installs yt6801-dkms"
fi

pass "YT6801 installs and retry-safe migrations use the upstream kernel driver"
