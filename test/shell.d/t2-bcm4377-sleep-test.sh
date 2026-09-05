#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

fix_t2="$ROOT/install/hardware/apple/fix-t2.sh"
leaf="$ROOT/install/hardware/apple/fix-suspend-bcm4377.sh"
unit_src="$ROOT/install/hardware/apple/omarchy-t2-bcm4377-sleep.service"
helper="$ROOT/bin/omarchy-t2-bcm4377-sleep"
detector="$ROOT/bin/omarchy-hw-t2-bcm4377"
hardware_all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1788544020.sh"

grep -Fq 'KERNEL_CMDLINE[default]+=" intel_iommu=on iommu=pt pm_async=off mem_sleep_default=deep"' "$fix_t2" ||
  fail "T2 setup still selects deep sleep"
! grep -Eq 'mem_sleep_default=s2idle|SuspendState=freeze' "$leaf" "$unit_src" "$migration" ||
  fail "BCM4377 sleep setup does not force s2idle"
if [[ -f $hardware_all ]]; then
  grep -q 'apple/fix-suspend-bcm4377.sh' "$hardware_all" ||
    fail "the BCM4377 sleep leaf runs during hardware setup"
  awk '
    /fix-t2\.sh/ { t2=NR }
    /fix-suspend-bcm4377\.sh/ { bcm=NR }
    /fix-brcmfmac-supplicant\.sh/ { brcm=NR }
    END {
      if (!(t2 && bcm && brcm) || !(t2 < bcm && bcm < brcm))
        exit 1
    }
  ' "$hardware_all" ||
    fail "the BCM4377 sleep leaf sits between T2 setup and the brcmfmac quirk"
fi
! grep -Eq '(tee|cat >).*/etc/modprobe.d/brcmfmac.conf|options brcmfmac' "$leaf" ||
  fail "only fix-brcmfmac-supplicant.sh writes /etc/modprobe.d/brcmfmac.conf"
grep -Fq 'systemctl enable omarchy-t2-bcm4377-sleep.service' "$leaf" ||
  fail "T2 BCM4377 setup enables the sleep service"
! grep -Eq 'systemctl enable --now' "$leaf" "$migration" ||
  fail "the sleep service is not started at install time"
grep -Fq 'DefaultDependencies=no' "$unit_src" ||
  fail "the sleep unit avoids the normal shutdown dependency graph"
grep -Fq 'ExecStart=/usr/bin/omarchy-t2-bcm4377-sleep pre' "$unit_src" ||
  fail "the sleep unit unloads Wi-Fi before sleep.target"
grep -Fq 'ExecStopPost=/usr/bin/omarchy-t2-bcm4377-sleep post' "$unit_src" ||
  fail "the sleep unit rolls back failed preparation and restores after sleep"
grep -Fq 'RequiredBy=sleep.target' "$unit_src" ||
  fail "failed Wi-Fi preparation prevents a broken sleep attempt"
grep -Fq 'RemainAfterExit=yes' "$unit_src" ||
  fail "the sleep unit keeps Wi-Fi unloaded through suspend-then-hibernate"
! grep -Eqi 't2fan|fan._manual|release_fan|restore_fan' "$helper" ||
  fail "the Wi-Fi workaround does not alter independent fan policy"
pass "BCM4377 sleep files keep deep S3 and isolate the Wi-Fi workaround"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
if (( ${T2_HARDWARE:-0} == 1 )); then
  echo '74:00.1 Non-VGA unclassified device [0000]: Apple Inc. T2 Bridge Controller [106b:1801] (rev 01)'
fi
if [[ -n ${WIFI_ID:-} ]]; then
  echo "73:00.0 Network controller [0280]: Broadcom Inc. Wireless [14e4:$WIFI_ID]"
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

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash

printf 'systemctl' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

if [[ ${1:-} == "enable" && ${2:-} == "omarchy-t2-bcm4377-sleep.service" ]] &&
  [[ -n ${FAIL_ENABLE_ONCE_MARKER:-} && ! -e $FAIL_ENABLE_ONCE_MARKER ]]; then
  touch "$FAIL_ENABLE_ONCE_MARKER"
  exit 1
fi
SH

cat >"$stub_bin/install" <<'SH'
#!/bin/bash

printf 'install' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

while [[ ${1:-} == -* ]]; do
  shift
done

src=${1:-}
dest=${2:-}
if [[ -n $src && -n $dest ]]; then
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
fi
SH

cat >"$stub_bin/sleep" <<'SH'
#!/bin/bash

printf 'sleep' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash

for cmd in "$@"; do
  type -P "$cmd" >/dev/null || exit 1
done
SH

cat >"$stub_bin/nmcli" <<'SH'
#!/bin/bash

printf 'nmcli' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

if [[ $* == "-t -f UUID,DEVICE connection show --active" ]]; then
  if (( ${WIFI_ACTIVE:-1} )); then
    printf '%s:%s\n' "${WIFI_UUID:-test-wifi-uuid}" "${WIFI_IFACE_BEFORE:-wlp2s0}"
  fi
elif [[ $* == "--wait 5 device disconnect ${WIFI_IFACE_BEFORE:-wlp2s0}" ]]; then
  (( ! ${FAIL_NM_DISCONNECT:-0} ))
elif [[ $* == "--wait 0 connection up uuid ${WIFI_UUID:-test-wifi-uuid}"* ]]; then
  (( ! ${FAIL_NM_UP:-0} ))
fi
SH

cat >"$stub_bin/modprobe" <<'SH'
#!/bin/bash

printf 'modprobe' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

module_add() {
  grep -q "^$1 " "$TEST_MODULES" || printf '%s 0 0 - Live 0x0\n' "$1" >>"$TEST_MODULES"
}

module_remove() {
  awk -v module="$1" '$1 != module' "$TEST_MODULES" >"$TEST_MODULES.tmp"
  mv "$TEST_MODULES.tmp" "$TEST_MODULES"
}

remove_wifi_iface() {
  local d driver
  for d in "$TEST_SYS_CLASS_NET"/*; do
    [[ -e $d/device/driver ]] || continue
    driver=$(basename "$(readlink -f "$d/device/driver")")
    [[ $driver == "brcmfmac" ]] || continue
    rm -f "$d/device/driver"
    rmdir "$d/device" "$d"
  done
}

if [[ ${1:-} == "-r" ]]; then
  case "${2:-}" in
    brcmfmac_wcc)
      (( ! ${FAIL_WCC_UNLOAD:-0} )) || exit 1
      module_remove brcmfmac_wcc
      ;;
    brcmfmac)
      (( ! ${FAIL_BRCM_UNLOAD:-0} )) || exit 1
      module_remove brcmfmac
      remove_wifi_iface
      ;;
  esac
else
  case "${1:-}" in
    brcmfmac)
      (( ! ${FAIL_BRCM_LOAD:-0} )) || exit 1
      module_add brcmfmac
      mkdir -p "$TEST_SYS_CLASS_NET/${WIFI_IFACE_AFTER:-wlan0}/device"
      ln -sfn "$TEST_BRCM_DRIVER" "$TEST_SYS_CLASS_NET/${WIFI_IFACE_AFTER:-wlan0}/device/driver"
      ;;
    brcmfmac_wcc)
      (( ! ${FAIL_WCC_LOAD:-0} )) || exit 1
      module_add brcmfmac_wcc
      ;;
  esac
fi
SH

chmod +x "$stub_bin"/*

run_detector() {
  PATH="$stub_bin:$PATH" T2_HARDWARE="$1" WIFI_ID="${2:-}" "$detector"
}

run_detector 1 4488
pass "detector matches T2 + BCM4377b"

if run_detector 1 4464; then
  fail "detector refuses BCM4364"
fi
pass "detector refuses BCM4364"

if run_detector 1 ""; then
  fail "detector ignores T2 machines without BCM4377b"
fi
pass "detector ignores T2 machines without BCM4377b"

if run_detector 0 4488; then
  fail "detector ignores BCM4377b on non-T2 hardware"
fi
pass "detector ignores BCM4377b on non-T2 hardware"

cat >"$stub_bin/omarchy-hw-t2-bcm4377" <<'SH'
#!/bin/bash

(( ${T2_BCM4377:-0} == 1 ))
SH
chmod +x "$stub_bin/omarchy-hw-t2-bcm4377"

if PATH="$stub_bin:$PATH" "$helper" >/dev/null 2>&1; then
  fail "sleep helper requires pre or post"
fi
pass "sleep helper requires pre or post"

PATH="$stub_bin:$PATH" T2_BCM4377=0 "$helper" pre >/dev/null
pass "sleep helper no-ops on machines without BCM4377b"

helper_root="$test_tmp/helper"
state="$helper_root/run/omarchy-t2-bcm4377-sleep.state"
modules="$helper_root/proc/modules"
sys_class_net="$helper_root/sys/class/net"
t2bce_module="$helper_root/sys/module/t2bce_core"
pm_async="$helper_root/sys/power/pm_async"
brcm_driver="$helper_root/drivers/brcmfmac"

reset_helper_fixture() {
  rm -rf "$helper_root"
  mkdir -p "$helper_root/run" "$(dirname "$modules")" "$sys_class_net/wlp2s0/device" \
    "$t2bce_module" "$(dirname "$pm_async")" "$brcm_driver"
  printf 'brcmfmac 0 0 - Live 0x0\nbrcmfmac_wcc 0 0 - Live 0x0\n' >"$modules"
  printf '0\n' >"$pm_async"
  ln -s "$brcm_driver" "$sys_class_net/wlp2s0/device/driver"
  : >"$calls"
}

run_helper() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    TEST_MODULES="$modules" \
    TEST_SYS_CLASS_NET="$sys_class_net" \
    TEST_BRCM_DRIVER="$brcm_driver" \
    T2_BCM4377="${T2_BCM4377:-1}" \
    WIFI_ACTIVE="${WIFI_ACTIVE:-1}" \
    WIFI_IFACE_BEFORE="${WIFI_IFACE_BEFORE:-wlp2s0}" \
    WIFI_IFACE_AFTER="${WIFI_IFACE_AFTER:-wlan0}" \
    WIFI_UUID="${WIFI_UUID:-test-wifi-uuid}" \
    FAIL_NM_DISCONNECT="${FAIL_NM_DISCONNECT:-0}" \
    FAIL_NM_UP="${FAIL_NM_UP:-0}" \
    FAIL_WCC_UNLOAD="${FAIL_WCC_UNLOAD:-0}" \
    FAIL_BRCM_UNLOAD="${FAIL_BRCM_UNLOAD:-0}" \
    FAIL_BRCM_LOAD="${FAIL_BRCM_LOAD:-0}" \
    FAIL_WCC_LOAD="${FAIL_WCC_LOAD:-0}" \
    OMARCHY_T2_BCM4377_STATE="$state" \
    OMARCHY_T2_BCM4377_PROC_MODULES="$modules" \
    OMARCHY_T2_BCM4377_SYS_CLASS_NET="$sys_class_net" \
    OMARCHY_T2_BCM4377_T2BCE_MODULE="$t2bce_module" \
    OMARCHY_T2_BCM4377_PM_ASYNC="$pm_async" \
    "$helper" "$@"
}

reset_helper_fixture
run_helper pre >/dev/null
[[ -f $state ]] || fail "pre records exactly what it changed"
[[ $(stat -c %a "$state") == "600" ]] || fail "sleep state is root-private"
! grep -q '^brcmfmac ' "$modules" || fail "pre unloads brcmfmac"
! grep -q '^brcmfmac_wcc ' "$modules" || fail "pre unloads the brcmfmac_wcc holder"
grep -Fqx $'nmcli\t--wait\t5\tdevice\tdisconnect\twlp2s0' "$calls" ||
  fail "pre bounds NetworkManager disconnect time"
grep -Fqx $'modprobe\t-r\tbrcmfmac_wcc' "$calls" || fail "pre unloads wcc first"
grep -Fqx $'modprobe\t-r\tbrcmfmac' "$calls" || fail "pre unloads the core driver"

run_helper post >/dev/null
grep -q '^brcmfmac ' "$modules" || fail "post restores brcmfmac"
grep -q '^brcmfmac_wcc ' "$modules" || fail "post restores brcmfmac_wcc"
grep -Fqx $'nmcli\t--wait\t0\tconnection\tup\tuuid\ttest-wifi-uuid\tifname\twlan0' "$calls" ||
  fail "post queues the saved connection on the newly discovered interface"
[[ ! -e $state ]] || fail "post clears successfully restored state"
pass "sleep helper unloads and transactionally restores BCM4377 Wi-Fi"

reset_helper_fixture
printf '1\n' >"$pm_async"
run_helper pre >/dev/null
[[ ! -e $state ]] || fail "legacy asynchronous PCI PM does not create sleep state"
! grep -q '^modprobe' "$calls" || fail "legacy asynchronous PCI PM does not unload Wi-Fi"
pass "sleep helper waits for the t2bce pm_async=off stack"

reset_helper_fixture
rm -rf "$t2bce_module"
run_helper pre >/dev/null
[[ ! -e $state ]] || fail "the legacy apple_bce stack does not create sleep state"
! grep -q '^modprobe' "$calls" || fail "the legacy apple_bce stack does not unload Wi-Fi"
pass "sleep helper does not race an update before the t2bce reboot"

reset_helper_fixture
: >"$modules"
run_helper pre >/dev/null
[[ ! -e $state ]] || fail "an originally unloaded driver needs no restore state"
! grep -q '^modprobe' "$calls" || fail "an originally unloaded driver remains untouched"
run_helper post >/dev/null
! grep -q '^modprobe' "$calls" || fail "post does not load a driver pre did not unload"
pass "sleep helper preserves an originally unloaded driver"

reset_helper_fixture
if FAIL_BRCM_UNLOAD=1 run_helper pre >/dev/null; then
  fail "pre reports a core driver unload failure"
fi
[[ $(grep -Fxc $'modprobe\t-r\tbrcmfmac' "$calls") == "5" ]] ||
  fail "pre retries a transient core unload"
grep -q '^brcmfmac ' "$modules" || fail "rollback leaves the core driver loaded"
grep -q '^brcmfmac_wcc ' "$modules" || fail "rollback restores the unloaded wcc holder"
grep -Fqx $'nmcli\t--wait\t0\tconnection\tup\tuuid\ttest-wifi-uuid\tifname\twlp2s0' "$calls" ||
  fail "rollback queues the connection it disconnected"
[[ ! -e $state ]] || fail "successful rollback clears transaction state"
pass "failed sleep preparation rolls back before systemd aborts sleep"

reset_helper_fixture
run_helper pre >/dev/null
if FAIL_BRCM_LOAD=1 run_helper post >/dev/null; then
  fail "post reports a core driver reload failure"
fi
[[ -e $state ]] || fail "failed resume keeps state for an explicit retry"
run_helper post >/dev/null
[[ ! -e $state ]] || fail "a successful resume retry clears state"
grep -q '^brcmfmac_wcc ' "$modules" || fail "a resume retry restores the plugin"
pass "failed resume remains safely retryable"

unit="$test_tmp/system/omarchy-t2-bcm4377-sleep.service"
legacy="$test_tmp/system/t2-bcm4377-sleep.service"
legacy_script="$test_tmp/sbin/t2-bcm4377-sleep.sh"
legacy_fan_lib="$test_tmp/lib/t2-fan.sh"
legacy_fan_etc="$test_tmp/etc-sleep/t2-fan.sh"
machine_marker="$test_tmp/var/lib/omarchy/migrations/1788544020"
enable_failure_marker="$test_tmp/enable-failed-once"

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    T2_BCM4377="${1:-1}" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_T2_BCM4377_UNIT="$unit" \
    OMARCHY_T2_BCM4377_LEGACY_UNIT="$legacy" \
    OMARCHY_T2_BCM4377_MARKER="$machine_marker" \
    FAIL_ENABLE_ONCE_MARKER="${FAIL_ENABLE_ONCE_MARKER:-}" \
    bash -euo pipefail "$migration" >/dev/null
}

run_leaf() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    T2_BCM4377="${1:-1}" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_T2_BCM4377_UNIT="$unit" \
    OMARCHY_T2_BCM4377_LEGACY_UNIT="$legacy" \
    bash -euo pipefail "$leaf" >/dev/null
}

write_known_legacy_unit() {
  mkdir -p "$(dirname "$legacy")"
  cat >"$legacy" <<'UNIT'
[Service]
ExecStart=/usr/local/sbin/t2-bcm4377-sleep.sh pre
ExecStop=/usr/local/sbin/t2-bcm4377-sleep.sh post
UNIT
}

rm -f "$unit" "$legacy" "$machine_marker"
: >"$calls"
run_migration 1
[[ -f $unit ]] || fail "migration installs the sleep unit"
grep -Fq 'ExecStart=/usr/bin/omarchy-t2-bcm4377-sleep pre' "$unit" ||
  fail "migration copies the packaged sleep unit"
grep -Fq $'systemctl\tenable\tomarchy-t2-bcm4377-sleep.service' "$calls" ||
  fail "migration enables the sleep service"
! grep -q 'enable --now' "$calls" || fail "migration does not start the sleep service"
[[ -f $machine_marker ]] || fail "migration records machine-wide completion last"
pass "migration installs and enables the sleep service on BCM4377b"

: >"$calls"
run_migration 1
[[ ! -s $calls ]] || fail "an already repaired machine is left unchanged" "$(cat "$calls")"
pass "migration is machine-idempotent across users"

rm -f "$unit" "$machine_marker" "$enable_failure_marker"
: >"$calls"
if FAIL_ENABLE_ONCE_MARKER="$enable_failure_marker" run_migration 1; then
  fail "migration propagates a failed service enable"
fi
[[ ! -e $machine_marker ]] || fail "an interrupted migration remains pending"
: >"$calls"
FAIL_ENABLE_ONCE_MARKER="$enable_failure_marker" run_migration 1
grep -Fq $'install\t-Dm644' "$calls" || fail "migration reinstalls after partial completion"
[[ -f $machine_marker ]] || fail "a successful retry records completion"
pass "migration retries cleanly after partial installation"

mkdir -p "$(dirname "$legacy_script")" "$(dirname "$legacy_fan_lib")" \
  "$(dirname "$legacy_fan_etc")"
write_known_legacy_unit
: >"$legacy_script"
: >"$legacy_fan_lib"
: >"$legacy_fan_etc"
rm -f "$unit" "$machine_marker"
: >"$calls"
run_migration 1
grep -Fq $'systemctl\tdisable\tt2-bcm4377-sleep.service' "$calls" ||
  fail "migration disables the known overlapping standalone unit"
[[ -f $legacy && -f $legacy_script && -f $legacy_fan_lib && -f $legacy_fan_etc ]] ||
  fail "migration preserves administrator-owned legacy files and fan policy"
pass "migration disables only the overlap and preserves local files"

printf '[Service]\nExecStart=/usr/local/sbin/custom-sleep pre\n' >"$legacy"
rm -f "$unit" "$machine_marker"
: >"$calls"
run_migration 1
! grep -Fq $'systemctl\tdisable\tt2-bcm4377-sleep.service' "$calls" ||
  fail "migration does not disable an unrecognized administrator unit"
[[ -f $legacy ]] || fail "migration preserves an unrecognized administrator unit"
pass "migration leaves unrelated administrator policy alone"

rm -f "$unit" "$legacy" "$machine_marker"
: >"$calls"
run_migration 0
[[ ! -e $unit ]] || fail "non-BCM4377 systems get no sleep unit"
[[ ! -e $machine_marker ]] || fail "unrelated hardware is not marked repaired"
[[ ! -s $calls ]] || fail "non-BCM4377 systems skip the sleep repair" "$(cat "$calls")"
pass "migration skips unrelated hardware"

write_known_legacy_unit
rm -f "$unit"
: >"$calls"
run_leaf 1
[[ -f $unit ]] || fail "installer leaf installs the sleep unit"
grep -Fq $'systemctl\tdisable\tt2-bcm4377-sleep.service' "$calls" ||
  fail "installer leaf disables the known overlapping unit"
grep -Fq $'systemctl\tenable\tomarchy-t2-bcm4377-sleep.service' "$calls" ||
  fail "installer leaf enables the sleep service"
[[ -f $legacy ]] || fail "installer leaf preserves the legacy unit file"
pass "installer leaf installs one active BCM4377 sleep implementation"

rm -f "$unit" "$legacy"
: >"$calls"
run_leaf 0
[[ ! -e $unit ]] || fail "installer leaf skips machines without BCM4377b"
[[ ! -s $calls ]] || fail "installer leaf is silent on unrelated hardware" "$(cat "$calls")"
pass "installer leaf skips unrelated hardware"
