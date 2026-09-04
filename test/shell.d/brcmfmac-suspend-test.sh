#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-brcmfmac-suspend.sh"
hook="$ROOT/default/systemd/system-sleep/brcmfmac-suspend"
all="$ROOT/install/hardware/all.sh"

grep -q 'apple/fix-brcmfmac-suspend.sh' "$all" ||
  fail "the brcmfmac suspend workaround runs during hardware setup"
pass "the brcmfmac suspend workaround runs during setup"

[[ -x $hook ]] || fail "the sleep hook ships executable"
pass "the sleep hook ships executable"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin" "$test_tmp/dmi"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
if [[ -n ${WIFI_ID:-} ]]; then
  echo "03:00.0 Network controller [0280]: Broadcom Inc. Wireless [14e4:$WIFI_ID]"
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

chmod +x "$stub_bin"/*

# The leaf reads the vendor from an absolute path, so point it at a fixture by
# running with a fake root on PATH-independent state. Its destination under
# /usr is sed-rewritten into the sandbox, and pipefail is on, so a grep -q
# gate would go silent here the way #6608 did.
run_leaf() {
  local vendor="$1" wifi_id="${2:-}"
  rm -rf "$test_tmp/dmi/sys_vendor" "$test_tmp/system-sleep"
  mkdir -p "$test_tmp/dmi" "$test_tmp/system-sleep"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"

  local script="$test_tmp/leaf.sh"
  sed -e "s|/sys/class/dmi/id/sys_vendor|$test_tmp/dmi/sys_vendor|g" \
      -e "s|/usr/lib/systemd/system-sleep|$test_tmp/system-sleep|g" \
      "$leaf" >"$script"

  : >"$calls"
  WIFI_ID="$wifi_id" PATH="$stub_bin:$PATH" TEST_LOG="$calls" OMARCHY_PATH="$ROOT" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

run_leaf "Apple Inc." 43ba >/dev/null
[[ -f $test_tmp/system-sleep/brcmfmac-suspend ]] ||
  fail "a Mac with BCM43602 Wi-Fi at 03:00.0 gets the hook" "$(ls -R "$test_tmp/system-sleep" 2>&1)"
pass "a Mac with BCM43602 Wi-Fi at 03:00.0 gets the hook"

run_leaf "Apple Computer, Inc." 43ba >/dev/null
[[ -f $test_tmp/system-sleep/brcmfmac-suspend ]] ||
  fail "the older Apple vendor string is recognized" "$(ls -R "$test_tmp/system-sleep" 2>&1)"
pass "the older Apple vendor string is recognized"

run_leaf "LENOVO" 43ba >/dev/null
[[ ! -e $test_tmp/system-sleep/brcmfmac-suspend ]] ||
  fail "non-Apple hardware with the same Wi-Fi part is left alone"
pass "non-Apple hardware with the same Wi-Fi part is left alone"

run_leaf "Apple Inc." 43a0 >/dev/null
[[ ! -e $test_tmp/system-sleep/brcmfmac-suspend ]] ||
  fail "a Mac whose Wi-Fi runs the out-of-tree wl driver is left alone"
pass "a Mac whose Wi-Fi runs the out-of-tree wl driver is left alone"

run_leaf "Apple Inc." "" >/dev/null
[[ ! -e $test_tmp/system-sleep/brcmfmac-suspend ]] ||
  fail "a Mac with no wireless device is left alone"
pass "a Mac with no wireless device is left alone"

# The hook itself, against a sandbox sysfs. sysfs attributes are write-only
# files, so a stub cannot sit inside them: instead the two sysfs writes in the
# hook are sed-rewritten into stub invocations that maintain the device's
# driver symlink the way the PCI core does.
pci_dir="$test_tmp/sys/bus/pci/devices/0000:03:00.0"
drv_dir="$test_tmp/sys/bus/pci/drivers/brcmfmac"
marker="$test_tmp/marker"
bind_calls="$test_tmp/bind_calls.log"
mkdir -p "$pci_dir" "$drv_dir"

cat >"$drv_dir/unbind" <<SH
#!/bin/bash
rm -f "$pci_dir/driver"
SH
cat >"$drv_dir/bind" <<SH
#!/bin/bash
printf '%s\n' bind >>"$bind_calls"
ln -sfn ../../../../bus/pci/drivers/brcmfmac "$pci_dir/driver"
SH
chmod +x "$drv_dir/unbind" "$drv_dir/bind"

run_hook() {
  local script="$test_tmp/hook.sh"
  # Path rewrites first; the sysfs writes are rewritten last because their
  # replacement text carries the sandbox path, which the path patterns would
  # otherwise match a second time.
  sed -e "s|/sys/bus/pci/devices/0000:03:00.0|$pci_dir|g" \
      -e "s|/sys/bus/pci/drivers/brcmfmac|$drv_dir|g" \
      -e "s|/run/omarchy-brcmfmac-suspend|$marker|g" \
      -e "s|echo \"0000:03:00.0\" > \"\\\$driver/unbind\"|\"$drv_dir/unbind\"|" \
      -e "s|echo \"0000:03:00.0\" > \"\\\$driver/bind\" 2>/dev/null|\"$drv_dir/bind\"|" \
      "$hook" >"$script"
  : >"$bind_calls"
  bash "$script" "$@"
}

ln -sfn ../../../../bus/pci/drivers/brcmfmac "$pci_dir/driver"
run_hook pre suspend
[[ ! -L $pci_dir/driver ]] || fail "pre unbinds a brcmfmac device"
[[ -f $marker ]] || fail "pre records that it unbound the device"
pass "pre unbinds a brcmfmac device and records it"

run_hook post suspend
[[ -L $pci_dir/driver ]] || fail "post binds the device again"
[[ ! -e $marker ]] || fail "post clears the marker"
pass "post binds the device again and clears the marker"

rm -f "$pci_dir/driver"
run_hook pre suspend
[[ ! -e $marker ]] || fail "pre leaves a device that is not brcmfmac alone"
pass "pre leaves a device that is not brcmfmac alone"

run_hook post suspend
[[ ! -s $bind_calls ]] || fail "post leaves alone a device pre did not unbind" "$(cat "$bind_calls")"
pass "post leaves alone a device pre did not unbind"
