#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-brcmfmac-supplicant.sh"
fix_t2="$ROOT/install/hardware/apple/fix-t2.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1786391100.sh"
cleanup="$ROOT/migrations/1787163407.sh"

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
calls="$test_tmp/calls.log"
conf="$test_tmp/etc/modprobe.d/brcmfmac.conf"
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

# The quirk is for Intel Macs, so every case has to say which architecture it
# runs on rather than inherit whichever machine the suite is running on.
cat >"$stub_bin/uname" <<'SH'
#!/bin/bash

if [[ ${1:-} == "-m" ]]; then
  echo "${ARCH:-x86_64}"
else
  exec /usr/bin/uname "$@"
fi
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

# Stubbed rather than run: the real one would write the running user's state.
cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

# The leaf reads the vendor from an absolute path, so point it at a fixture by
# running with a fake root on PATH-independent state. pipefail is on, so a
# grep -q gate would go silent here the way #6608 did.
run_leaf() {
  local vendor="$1" wifi_id="${2:-}" t2="${3:-0}" arch="${4:-x86_64}"
  rm -rf "$test_tmp/etc"
  mkdir -p "$test_tmp/etc"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"

  # Redirect both absolute paths the leaf touches into the sandbox.
  local script="$test_tmp/leaf.sh"
  sed -e "s|/sys/class/dmi/id/sys_vendor|$test_tmp/dmi/sys_vendor|g" \
      -e "s|/etc/modprobe.d|$test_tmp/etc/modprobe.d|g" \
      "$leaf" >"$script"

  WIFI_ID="$wifi_id" T2_HARDWARE="$t2" ARCH="$arch" PATH="$stub_bin:$PATH" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

# The quirk shipped for T2 Macs first, and the move to its own leaf must not
# drop them.
run_leaf "Apple Inc." 4488 1 >/dev/null
grep -q 'feature_disable=0x82000' "$conf" 2>/dev/null ||
  fail "a T2 Mac still gets the quirk" "$(ls -R "$test_tmp/etc" 2>&1)"
pass "a T2 Mac still gets the quirk"

# Every Broadcom part brcmfmac drives, on an Intel Mac with no T2 to detect:
# BCM43602 and its single-band variants, BCM4350, BCM4355, BCM4364, BCM4378,
# BCM4387.
for wifi_id in 43ba 43bb 43bc 43a3 43dc 4464 4425 4433; do
  run_leaf "Apple Inc." "$wifi_id" 0 >/dev/null
  [[ -f $conf ]] || fail "a Mac without a T2 gets the quirk" "14e4:$wifi_id"
done
pass "every brcmfmac part on a Mac without a T2 gets the quirk"

# BCM4378 and BCM4387 are Apple Silicon parts too, and there the offload is the
# half that works: with it disabled a BCM4387 cannot associate at all (#7439).
# Same vendor string and the same PCI IDs, so only the architecture tells them
# apart.
for wifi_id in 4425 4433; do
  run_leaf "Apple Inc." "$wifi_id" 0 aarch64 >/dev/null
  [[ ! -f $conf ]] || fail "an Apple Silicon Mac is left alone" "14e4:$wifi_id"
done
pass "an Apple Silicon Mac is left alone"

# Older Macs report the vendor differently.
run_leaf "Apple Computer, Inc." 43ba 0 >/dev/null
[[ -f $conf ]] || fail "the older Apple vendor string is recognized"
pass "the older Apple vendor string is recognized"

# BCM4360 Macs run the out-of-tree wl driver, which never reads this option, so
# writing it would only look like the machine had been dealt with.
run_leaf "Apple Inc." 43a0 0 >/dev/null
[[ ! -f $conf ]] || fail "a Mac whose Wi-Fi brcmfmac does not drive is left alone"
pass "a Mac whose Wi-Fi brcmfmac does not drive is left alone"

# Plenty of non-Apple hardware uses brcmfmac and does not share this bug.
run_leaf "LENOVO" 43ba 0 >/dev/null
[[ ! -f $conf ]] || fail "non-Apple hardware is left alone"
pass "non-Apple hardware is left alone"

run_leaf "Apple Inc." "" 0 >/dev/null
[[ ! -f $conf ]] || fail "a Mac with no wireless device is left alone"
pass "a Mac with no wireless device is left alone"

# Installs that predate the quirk never ran the leaf, so the migration has to
# reach them. It runs as the user under pipefail, the context #6608 was about.
run_migration() {
  local vendor="$1" wifi_id="${2:-}" t2="${3:-0}" arch="${4:-x86_64}"
  printf '%s' "$vendor" >"$test_tmp/dmi/sys_vendor"
  : >"$calls"

  WIFI_ID="$wifi_id" T2_HARDWARE="$t2" ARCH="$arch" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_BRCMFMAC_DMI_VENDOR="$test_tmp/dmi/sys_vendor" \
    OMARCHY_BRCMFMAC_CONF="$conf" \
    bash -euo pipefail "$migration" >/dev/null
}

# A T2 install from before the quirk shipped has no config at all, so this is
# the case that proves the T2 gate itself still fires -- and it is the piped
# grep, run under pipefail, that #6608 was about.
rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 4488 1
grep -q '^options brcmfmac feature_disable=0x82000$' "$conf" 2>/dev/null ||
  fail "the migration fixes a T2 install that never got the quirk" "$(ls -R "$test_tmp/etc" 2>&1)"
# The option only reaches the driver when brcmfmac next loads.
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies it" "$(cat "$calls")"
pass "the migration fixes a T2 install that never got the quirk"

run_migration "Apple Inc." 4488 1
(( $(grep -c '^options brcmfmac feature_disable=0x82000$' "$conf") == 1 )) ||
  fail "the migration is idempotent" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "a repaired install is left untouched" "$(cat "$calls")"
pass "the migration is idempotent"

# The machine this was written for, with no T2 to fall back on.
rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 43ba 0
grep -q '^options brcmfmac feature_disable=0x82000$' "$conf" 2>/dev/null ||
  fail "the migration fixes an install on a Mac without a T2" "$(ls -R "$test_tmp/etc" 2>&1)"
pass "the migration fixes an install on a Mac without a T2"

# Written without a trailing newline, the way a hand-edited config often is.
printf '%s' 'options brcmfmac roamoff=1' >"$conf"
run_migration "Apple Inc." 43ba 0
grep -qx 'options brcmfmac roamoff=1' "$conf" ||
  fail "the migration keeps other options in the config" "$(cat "$conf")"
grep -qx 'options brcmfmac feature_disable=0x82000' "$conf" ||
  fail "the migration appends the quirk to an existing config" "$(cat "$conf")"
pass "the migration appends to a config that holds other options"

# Someone who commented their line out is still on the broken default.
printf '#options brcmfmac feature_disable=0x82000\n' >"$conf"
run_migration "Apple Inc." 43ba 0
grep -qx 'options brcmfmac feature_disable=0x82000' "$conf" ||
  fail "a commented-out option does not count as applied" "$(cat "$conf")"
pass "a commented-out option does not count as applied"

rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 43a0 0
[[ ! -e $conf ]] || fail "the migration skips a Mac brcmfmac does not drive" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected Macs" "$(cat "$calls")"
pass "the migration skips hardware brcmfmac does not drive"

rm -rf "$test_tmp/etc"
run_migration "Apple Inc." 4433 0 aarch64
[[ ! -e $conf ]] || fail "the migration skips an Apple Silicon Mac" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "the migration escalates nothing on an Apple Silicon Mac" "$(cat "$calls")"
pass "the migration skips an Apple Silicon Mac"

# An Apple Silicon Mac that already ran either of those is carrying the option
# that breaks its Wi-Fi, so a second migration takes it off.
run_cleanup() {
  local wifi_id="${1:-}" arch="${2:-aarch64}"
  : >"$calls"

  WIFI_ID="$wifi_id" T2_HARDWARE=0 ARCH="$arch" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_BRCMFMAC_CONF="$conf" \
    bash -euo pipefail "$cleanup" >/dev/null
}

# Byte for byte what the leaf writes, which is also the ownership test the
# cleanup applies: only content ending in exactly this block is Omarchy's.
write_quirk_conf() {
  mkdir -p "$(dirname "$conf")"
  cat >"$conf" <<'EOF'
# Broadcom's firmware supplicant and authenticator fail the WPA four-way
# handshake on Apple hardware, which surfaces as a rejected password. Disable
# both so wpa_supplicant performs the handshake instead.
options brcmfmac feature_disable=0x82000
EOF
}

rm -rf "$test_tmp/etc"
write_quirk_conf
run_cleanup 4433
[[ ! -e $conf ]] || fail "the cleanup retires a config that held only the quirk" "$(cat "$conf")"
pass "the cleanup retires a config that held only the quirk"

# The reboot request has to land before the edit: interrupted between the two,
# a spare reboot prompt beats an edited config nothing asks to apply.
state_line=$(grep -Fn $'omarchy-state\tset\treboot-required' "$calls" | cut -d: -f1 | head -1 || true)
edit_line=$(grep -En $'sudo\t(rm|tee)' "$calls" | cut -d: -f1 | head -1 || true)
[[ -n $state_line && -n $edit_line ]] ||
  fail "the cleanup asks for the reboot that applies it" "$(cat "$calls")"
(( state_line < edit_line )) ||
  fail "the reboot request lands before the file is touched" "$(cat "$calls")"
pass "the reboot request lands before the file is touched"

run_cleanup 4433
[[ ! -s $calls ]] || fail "a machine already cleaned up is left untouched" "$(cat "$calls")"
pass "the cleanup is idempotent"

# migrations/1786391100.sh appended the block after a blank line, below whatever
# the user already kept there. That part survives, the block does not.
write_quirk_conf
mv "$conf" "$conf.block"
printf 'options brcmfmac roamoff=1\n' >"$conf"
printf '\n' >>"$conf"
cat "$conf.block" >>"$conf"
rm -f "$conf.block"
run_cleanup 4433
grep -qx 'options brcmfmac roamoff=1' "$conf" ||
  fail "the cleanup keeps what the user had above the appended block" "$(cat "$conf")"
! grep -q 'feature_disable=0x82000' "$conf" ||
  fail "the cleanup removes the appended block" "$(cat "$conf")"
! grep -q '^# Broadcom' "$conf" ||
  fail "the cleanup takes its own comments with the block" "$(cat "$conf")"
pass "the cleanup strips the appended block and keeps the rest"

# A line the user merged another option onto is no longer the line Omarchy
# wrote, and deleting it would take roamoff=1 with it. Not ours to edit.
printf 'options brcmfmac feature_disable=0x82000 roamoff=1\n' >"$conf"
run_cleanup 4433
grep -qx 'options brcmfmac feature_disable=0x82000 roamoff=1' "$conf" ||
  fail "a merged options line is left alone" "$(cat "$conf")"
pass "a merged options line is left alone"

# Same for a hand-written file that happens to set the same option: without
# Omarchy's comment block above it, nothing proves Omarchy wrote it.
printf '# my notes\noptions brcmfmac feature_disable=0x82000\n' >"$conf"
run_cleanup 4433
grep -qx '# my notes' "$conf" ||
  fail "a hand-written config is left alone" "$(cat "$conf")"
pass "a hand-written config is left alone"

# A symlinked config keeps its link: tee writes through it where sed -i would
# have replaced the link with a regular file and left the target still broken.
rm -rf "$test_tmp/etc"
mkdir -p "$test_tmp/etc/modprobe.d" "$test_tmp/real"
write_quirk_conf
mv "$conf" "$test_tmp/real/brcmfmac.conf"
ln -s "$test_tmp/real/brcmfmac.conf" "$conf"
run_cleanup 4433
[[ -L $conf ]] || fail "a symlinked config keeps its link"
! grep -q 'feature_disable=0x82000' "$test_tmp/real/brcmfmac.conf" ||
  fail "the cleanup empties a symlinked config through the link" "$(cat "$test_tmp/real/brcmfmac.conf")"
pass "the cleanup writes through a symlinked config"

# The Intel Macs the quirk was written for still need it.
rm -rf "$test_tmp/etc"
write_quirk_conf
run_cleanup 4488 x86_64
grep -qx 'options brcmfmac feature_disable=0x82000' "$conf" ||
  fail "an Intel Mac keeps the quirk" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "the cleanup escalates nothing on an Intel Mac" "$(cat "$calls")"
pass "the cleanup leaves Intel Macs alone"

# brcmfmac drives plenty of hardware Omarchy never wrote this option on, and a
# hand-written config there is not this migration's to remove.
rm -rf "$test_tmp/etc"
write_quirk_conf
run_cleanup ""
grep -qx 'options brcmfmac feature_disable=0x82000' "$conf" ||
  fail "a config on other brcmfmac hardware is left alone" "$(cat "$conf")"
pass "the cleanup only touches the parts the gate matched"

# BCM4378 sits behind the same gate as BCM4387.
rm -rf "$test_tmp/etc"
write_quirk_conf
run_cleanup 4425
[[ ! -e $conf ]] || fail "the cleanup covers BCM4378 too" "$(cat "$conf")"
pass "the cleanup covers BCM4378 too"

# Naming the architecture the repair is for keeps every other one out, rather
# than treating everything that is not an Intel Mac as an Apple Silicon one.
rm -rf "$test_tmp/etc"
write_quirk_conf
run_cleanup 4433 riscv64
grep -qx 'options brcmfmac feature_disable=0x82000' "$conf" ||
  fail "an unrelated architecture is left alone" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "the cleanup escalates nothing on an unrelated architecture" "$(cat "$calls")"
pass "the cleanup leaves unrelated architectures alone"
