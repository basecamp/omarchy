#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

pacman_leaf="$ROOT/install/hardware/pacman.sh"
migration="$ROOT/migrations/1787847645.sh"

# arch-mact2 has to reach every Mac apple-bcm-firmware is installed on, not
# just T2 ones, or omarchy-pkg-add apple-bcm-firmware has no repo to pull from.
grep -Eq '14e4:\(43ba\|43bb\|43bc\|43a3\|43dc\|4464\|4488\|4425\|4433\)' "$pacman_leaf" ||
  fail "arch-mact2 is added for every Mac brcmfmac drives, not just T2 ones"
pass "arch-mact2 is added for every Mac brcmfmac drives, not just T2 ones"

# This leaf runs after every package-installing leaf in hardware/all.sh, so no
# install in the current run ever depends on its repo being synced yet -- and
# a failed sync here would abort an otherwise offline-capable install for no
# benefit. The refresh belongs only in the migration, which repairs an
# already-installed, networked system.
! grep -q 'pacman -Sy' "$pacman_leaf" ||
  fail "install-time repository persistence does not force a network sync"
pass "install-time repository persistence does not force a network sync"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
pacman_conf="$test_tmp/pacman.conf"
mkdir -p "$stub_bin" "$test_tmp/dmi"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
if (( ${T2_HARDWARE:-0} == 1 )); then
  echo '01:00.0 Bridge [0680]: Apple Inc. T2 Security Chip [106b:1801]'
fi
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

cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

# Stubbed rather than run: the real one would hit pacman. Controlled by
# APPLE_BCM_FIRMWARE_INSTALLED so the same stub covers the fresh-install and
# already-repaired cases.
cat >"$stub_bin/omarchy-pkg-missing" <<'SH'
#!/bin/bash

(( ${APPLE_BCM_FIRMWARE_INSTALLED:-0} == 0 ))
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash

printf 'omarchy-pkg-add' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

# Stubbed rather than run: a real `pacman -Sy` would hit the network and
# mutate this machine's package databases. The sudo stub forwards through to
# this rather than the real binary, since stub_bin leads PATH.
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash

printf 'pacman' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_migration() {
  local vendor="$1" wifi_id="${2:-}" t2="${3:-0}" installed="${4:-0}"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  : >"$calls"

  WIFI_ID="$wifi_id" T2_HARDWARE="$t2" APPLE_BCM_FIRMWARE_INSTALLED="$installed" \
    PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_BRCMFMAC_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    OMARCHY_BRCMFMAC_PACMAN_CONF="$pacman_conf" \
    bash -euo pipefail "$migration" >/dev/null
}

# A T2 install from before apple-bcm-firmware moved to fix-brcmfmac-supplicant.sh
# already has the repo (fix-t2.sh's own pacman.sh call added it), so this proves
# the migration's own repo/package logic still fires on top of that.
printf '[options]\n' >"$pacman_conf"
run_migration "Apple Inc." 4488 1 0
grep -q '^\[arch-mact2\]$' "$pacman_conf" ||
  fail "the migration ensures arch-mact2 exists for a T2 Mac" "$(cat "$pacman_conf")"
grep -Fq $'sudo\tpacman\t-Sy' "$calls" ||
  fail "the migration syncs the freshly added repo before installing from it" "$(cat "$calls")"
grep -Fq $'omarchy-pkg-add\tapple-bcm-firmware' "$calls" ||
  fail "the migration installs the firmware package on a T2 Mac" "$(cat "$calls")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies the firmware" "$(cat "$calls")"
pass "the migration repairs a T2 install"

# The machine this was written for: no T2, so the repo was never added and the
# package was never installed by anything.
printf '[options]\n' >"$pacman_conf"
run_migration "Apple Inc." 43ba 0 0
grep -q '^\[arch-mact2\]$' "$pacman_conf" ||
  fail "the migration adds arch-mact2 on a Mac without a T2" "$(cat "$pacman_conf")"
grep -Fq $'sudo\tpacman\t-Sy' "$calls" ||
  fail "the migration syncs the freshly added repo on a Mac without a T2" "$(cat "$calls")"
grep -Fq $'omarchy-pkg-add\tapple-bcm-firmware' "$calls" ||
  fail "the migration installs the firmware package on a Mac without a T2" "$(cat "$calls")"
pass "the migration repairs an install on a Mac without a T2"

# Repeat runs, and other users on an already-repaired machine, must not
# re-append the repo block, resync it, or ask for another reboot.
run_migration "Apple Inc." 43ba 0 1
(( $(grep -c '^\[arch-mact2\]$' "$pacman_conf") == 1 )) ||
  fail "the migration does not duplicate the repo block" "$(cat "$pacman_conf")"
[[ ! -s $calls ]] || fail "an already repaired install is left untouched" "$(cat "$calls")"
pass "the migration is idempotent"

# Plenty of non-Apple hardware uses brcmfmac and does not share this bug.
printf '[options]\n' >"$pacman_conf"
run_migration "LENOVO" 43ba 0 0
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected Macs" "$(cat "$calls")"
grep -q '^\[arch-mact2\]$' "$pacman_conf" && fail "the migration leaves non-Apple hardware alone" "$(cat "$pacman_conf")"
pass "the migration skips hardware brcmfmac does not drive"

# A prior run could have appended the repo block and then failed the sync (a
# transient network outage), leaving the block in place with no marker
# written. That must not make the sync look already done: the package is
# still missing, so a retry has to sync again before it can install.
printf '%s\n' '[options]' '' '[arch-mact2]' \
  'Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release' \
  'SigLevel = Never' >"$pacman_conf"
run_migration "Apple Inc." 43ba 0 0
grep -Fq $'sudo\tpacman\t-Sy' "$calls" ||
  fail "a retry resyncs an already-appended repo when the package is still missing" "$(cat "$calls")"
grep -Fq $'omarchy-pkg-add\tapple-bcm-firmware' "$calls" ||
  fail "a retry still installs the firmware package" "$(cat "$calls")"
(( $(grep -c '^\[arch-mact2\]$' "$pacman_conf") == 1 )) ||
  fail "a retry does not duplicate the repo block" "$(cat "$pacman_conf")"
pass "an interrupted migration recovers on retry"
