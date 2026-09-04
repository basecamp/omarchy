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
grep -Fq 'ExecStart=/usr/bin/omarchy-t2-bcm4377-sleep pre' "$unit_src" ||
  fail "the sleep unit unloads Wi-Fi before sleep.target"
grep -Fq 'WantedBy=sleep.target' "$unit_src" ||
  fail "the sleep unit is pulled in by every systemd sleep"
grep -Fq 'RemainAfterExit=yes' "$unit_src" ||
  fail "the sleep unit keeps Wi-Fi unloaded through suspend-then-hibernate"
pass "BCM4377 sleep files keep deep S3 and only unload this chipset"

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

unit="$test_tmp/system/omarchy-t2-bcm4377-sleep.service"
legacy="$test_tmp/system/t2-bcm4377-sleep.service"
legacy_script="$test_tmp/sbin/t2-bcm4377-sleep.sh"
legacy_fan_lib="$test_tmp/lib/t2-fan.sh"
legacy_fan_etc="$test_tmp/etc-sleep/t2-fan.sh"

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    T2_BCM4377="${1:-1}" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_T2_BCM4377_UNIT="$unit" \
    OMARCHY_T2_BCM4377_LEGACY_UNIT="$legacy" \
    OMARCHY_T2_BCM4377_LEGACY_SCRIPT="$legacy_script" \
    OMARCHY_T2_BCM4377_LEGACY_FAN_LIB="$legacy_fan_lib" \
    OMARCHY_T2_BCM4377_LEGACY_FAN_ETC="$legacy_fan_etc" \
    bash -euo pipefail "$migration" >/dev/null
}

: >"$calls"
run_migration 1

[[ -f $unit ]] || fail "migration installs the sleep unit"
grep -Fq 'ExecStart=/usr/bin/omarchy-t2-bcm4377-sleep pre' "$unit" ||
  fail "migration copies the packaged sleep unit"
grep -Fq $'systemctl\tenable\tomarchy-t2-bcm4377-sleep.service' "$calls" ||
  fail "migration enables the sleep service"
! grep -q 'enable --now' "$calls" || fail "migration does not start the sleep service"
pass "migration installs and enables the sleep service on BCM4377b"

: >"$calls"
run_migration 1
[[ ! -s $calls ]] || fail "an already repaired BCM4377 install is left unchanged" "$(cat "$calls")"
pass "migration is machine-idempotent"

mkdir -p "$(dirname "$legacy")" "$(dirname "$legacy_script")" \
  "$(dirname "$legacy_fan_lib")" "$(dirname "$legacy_fan_etc")"
: >"$legacy"
: >"$legacy_script"
: >"$legacy_fan_lib"
: >"$legacy_fan_etc"
: >"$calls"
rm -f "$unit"
run_migration 1
grep -Fq $'systemctl\tdisable\tt2-bcm4377-sleep.service' "$calls" ||
  fail "migration disables the standalone Scripts/ unit"
[[ ! -e $legacy ]] || fail "migration removes the standalone Scripts/ unit"
[[ ! -e $legacy_script && ! -e $legacy_fan_lib && ! -e $legacy_fan_etc ]] ||
  fail "migration removes the standalone Scripts/ helper and fan hooks"
pass "migration replaces the standalone Scripts/ unit"

rm -f "$unit" "$legacy"
: >"$calls"
run_migration 0
[[ ! -e $unit ]] || fail "non-BCM4377 systems get no sleep unit"
[[ ! -s $calls ]] || fail "non-BCM4377 systems skip the sleep repair" "$(cat "$calls")"
pass "migration skips unrelated hardware"

run_leaf() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    T2_BCM4377="${1:-1}" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_INSTALL="$ROOT/install" \
    OMARCHY_T2_BCM4377_UNIT="$unit" \
    OMARCHY_T2_BCM4377_LEGACY_UNIT="$legacy" \
    OMARCHY_T2_BCM4377_LEGACY_SCRIPT="$legacy_script" \
    OMARCHY_T2_BCM4377_LEGACY_FAN_LIB="$legacy_fan_lib" \
    OMARCHY_T2_BCM4377_LEGACY_FAN_ETC="$legacy_fan_etc" \
    bash -euo pipefail "$leaf" >/dev/null
}

rm -f "$unit" "$legacy"
: >"$calls"
run_leaf 1
[[ -f $unit ]] || fail "installer leaf installs the sleep unit"
grep -Fq $'systemctl\tenable\tomarchy-t2-bcm4377-sleep.service' "$calls" ||
  fail "installer leaf enables the sleep service"
pass "installer leaf installs the sleep service on BCM4377b"

rm -f "$unit"
: >"$calls"
run_leaf 0
[[ ! -e $unit ]] || fail "installer leaf skips machines without BCM4377b"
[[ ! -s $calls ]] || fail "installer leaf is silent on unrelated hardware" "$(cat "$calls")"
pass "installer leaf skips unrelated hardware"
