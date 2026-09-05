#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/fix-rtw89-suspend.sh"
hook="$ROOT/default/systemd/system-sleep/rtw89-suspend"
migration="$ROOT/migrations/1787596412.sh"
all="$ROOT/install/hardware/all.sh"

grep -q 'fix-rtw89-suspend.sh' "$all" ||
  fail "the rtw89 quirk runs during hardware setup"
pass "the rtw89 quirk runs during hardware setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would die of SIGPIPE and pipefail would read that
# as "no such hardware" (#6608).
cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

if [[ -n ${WIFI_ID:-} ]]; then
  echo "05:00.0 Network controller [0280]: Realtek Semiconductor Co., Ltd. RTL8852BE [10ec:$WIFI_ID]"
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

# The hook drives real hardware; every escape from the sandbox is stubbed.
cat >"$stub_bin/modprobe" <<'SH'
#!/bin/bash

printf 'modprobe' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/logger" <<'SH'
#!/bin/bash

printf '%s\n' "${*: -1}" >>"$HOOK_LOG"
SH

# The hook waits for hardware to settle; the sandbox has none to wait for.
cat >"$stub_bin/sleep" <<'SH'
#!/bin/bash

exit 0
SH

chmod +x "$stub_bin"/*

conf="$test_tmp/etc/modprobe.d/omarchy-rtw89.conf"
installed_hook="$test_tmp/lib/systemd/system-sleep/rtw89-suspend"

# The leaf writes to absolute system paths, so rewrite them into the sandbox.
run_leaf() {
  local wifi_id="${1:-}"
  rm -rf "$test_tmp/etc" "$test_tmp/lib"
  : >"$calls"

  local script="$test_tmp/leaf.sh"
  sed -e "s|/etc/modprobe.d|$test_tmp/etc/modprobe.d|g" \
      -e "s|/usr/lib/systemd/system-sleep|$test_tmp/lib/systemd/system-sleep|g" \
      "$leaf" >"$script"

  WIFI_ID="$wifi_id" PATH="$stub_bin:$PATH" TEST_LOG="$calls" OMARCHY_PATH="$ROOT" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

# The case #6608 was about: an affected machine, a chatty lspci, and pipefail.
run_leaf b852 >/dev/null
grep -q 'disable_clkreq=y' "$conf" 2>/dev/null ||
  fail "an affected machine gets the modprobe options" "$(ls -R "$test_tmp" 2>&1)"
[[ -f $installed_hook ]] || fail "an affected machine gets the sleep hook"
pass "an affected machine gets both files under pipefail"

# systemd ignores a sleep hook that is not executable, so the mode is the fix.
[[ -x $installed_hook ]] || fail "the installed sleep hook is executable"
pass "the installed sleep hook is executable"

run_leaf 8852 >/dev/null
[[ ! -f $conf ]] || fail "another rtw89 card is left alone" "$(cat "$conf")"
[[ ! -f $installed_hook ]] || fail "another rtw89 card gets no sleep hook"
pass "another rtw89 card is left alone"

run_leaf "" >/dev/null
[[ ! -f $conf ]] || fail "a machine with no Realtek Wi-Fi is left alone"
pass "a machine with no Realtek Wi-Fi is left alone"

# A sysfs stand-in: the card behind its root port, plus a device that must not
# be mistaken for either.
mock_pci=""
make_mock_pci() {
  local with_netdev="${1:-1}"
  rm -rf "$test_tmp/sys"
  mock_pci="$test_tmp/sys/devices"

  local card="$test_tmp/sys/tree/pci0000:00/0000:00:1c.7/0000:05:00.0"
  local bridge="$test_tmp/sys/tree/pci0000:00/0000:00:1c.7"
  local other="$test_tmp/sys/tree/pci0000:00/0000:00:1f.3"
  mkdir -p "$card/power" "$bridge/power" "$other" "$mock_pci" "$test_tmp/sys/drivers/rtw89_8852be"

  printf '0x10ec\n' >"$card/vendor"
  printf '0xb852\n' >"$card/device"
  printf '1\n' >"$card/d3cold_allowed"
  printf 'on\n' >"$card/power/control"
  : >"$card/remove"
  ln -s "$test_tmp/sys/drivers/rtw89_8852be" "$card/driver"
  (( with_netdev == 1 )) && mkdir -p "$card/net/wlp5s0"

  printf '0x8086\n' >"$bridge/vendor"
  printf '0x51bf\n' >"$bridge/device"
  printf '1\n' >"$bridge/d3cold_allowed"
  printf 'auto\n' >"$bridge/power/control"
  : >"$bridge/rescan"

  printf '0x8086\n' >"$other/vendor"
  printf '0x51ca\n' >"$other/device"

  ln -s "$card" "$mock_pci/0000:05:00.0"
  ln -s "$bridge" "$mock_pci/0000:00:1c.7"
  ln -s "$other" "$mock_pci/0000:00:1f.3"
}

hook_log="$test_tmp/hook.log"
hook_state="$test_tmp/state"

run_hook() {
  local script="$test_tmp/hook.sh"
  sed -e "s|^PCI_DEVICES=.*|PCI_DEVICES=$mock_pci|" \
      -e "s|^STATE=.*|STATE=$hook_state|" \
      -e "s|/sys/bus/pci/rescan|$test_tmp/sys/rescan|g" \
      "$hook" >"$script"

  : >"$hook_log"
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" HOOK_LOG="$hook_log" \
    bash "$script" "$1" suspend </dev/null
}

card_dir="$test_tmp/sys/tree/pci0000:00/0000:00:1c.7/0000:05:00.0"
bridge_dir="$test_tmp/sys/tree/pci0000:00/0000:00:1c.7"

make_mock_pci
run_hook pre

# d3cold_allowed on the port is the whole fix: it is what keeps the slot powered
# across s2idle. The card's own flag keeps the port from being taken down under
# it while the two are still attached.
[[ $(cat "$bridge_dir/d3cold_allowed") == "0" ]] ||
  fail "suspending holds the root port out of D3cold"
[[ $(cat "$card_dir/d3cold_allowed") == "0" ]] ||
  fail "suspending holds the card out of D3cold"
[[ $(cat "$bridge_dir/power/control") == "on" ]] ||
  fail "suspending pins the root port awake"
[[ $(cat "$card_dir/remove") == "1" ]] ||
  fail "suspending takes the card off the bus"
grep -Fq $'modprobe\t-r\trtw89_8852be' "$calls" ||
  fail "suspending unloads the bound module" "$(cat "$calls")"
pass "suspending holds slot power up and takes the card off the bus"

# Discovery has to survive a reboot renumbering the bus, so it is read from
# sysfs rather than hardcoded -- and it must not pick up anything else.
[[ $(cat "$hook_state") == "0000:05:00.0 0000:00:1c.7 rtw89_8852be" ]] ||
  fail "the card, its root port and its module are discovered" "$(cat "$hook_state")"
pass "the card, its root port and its module are discovered from sysfs"

run_hook post
grep -q 'back on attempt 1' "$hook_log" ||
  fail "resuming brings the card back" "$(cat "$hook_log")"
grep -Fq $'modprobe\trtw89_8852be' "$calls" ||
  fail "resuming reloads the module" "$(cat "$calls")"
[[ $(cat "$bridge_dir/power/control") == "auto" ]] ||
  fail "resuming lets the root port sleep again"
[[ ! -e $hook_state ]] || fail "resuming clears the state file"
pass "resuming re-enumerates the card and releases the root port"

# Two failures that need telling apart: on the bus but unclaimed sends you to
# rtw89 errors in dmesg, never reappearing sends you to slot power and the link.
make_mock_pci 0
printf '0000:05:00.0 0000:00:1c.7 rtw89_8852be\n' >"$hook_state"
run_hook post
grep -q 'gave up on 0000:05:00.0 after 3 attempts, enumerated but was never claimed by rtw89_8852be' "$hook_log" ||
  fail "giving up names an unclaimed card as a driver problem" "$(cat "$hook_log")"
pass "giving up on an enumerated card names it a driver problem"

make_mock_pci
rm "$mock_pci/0000:05:00.0"
printf '0000:05:00.0 0000:00:1c.7 rtw89_8852be\n' >"$hook_state"
run_hook post
grep -q 'gave up on 0000:05:00.0 after 3 attempts, never reappeared on the bus' "$hook_log" ||
  fail "giving up names a missing card as a power problem" "$(cat "$hook_log")"
pass "giving up on a card that never returns names it a power problem"

# Nothing to do, and nothing to resume: the hook ships only on affected
# machines but must not misfire if the card is ever pulled.
make_mock_pci
rm "$mock_pci/0000:05:00.0"
run_hook pre
[[ ! -s $hook_state ]] || fail "no card means nothing is recorded" "$(cat "$hook_state")"
run_hook post
[[ ! -s $hook_log ]] || fail "no card means nothing is attempted" "$(cat "$hook_log")"
pass "a machine with the card pulled is left alone"

# Installs that predate the quirk never ran the leaf, so the migration has to
# reach them. It runs as the user under pipefail, the context #6608 was about.
run_migration() {
  local wifi_id="${1:-}"
  : >"$calls"

  local script="$test_tmp/migration.sh"
  sed -e "s|/etc/modprobe.d|$test_tmp/etc/modprobe.d|g" \
      -e "s|/usr/lib/systemd/system-sleep|$test_tmp/lib/systemd/system-sleep|g" \
      "$migration" >"$script"

  WIFI_ID="$wifi_id" PATH="$stub_bin:$PATH" TEST_LOG="$calls" OMARCHY_PATH="$ROOT" \
    bash -euo pipefail "$script" </dev/null
}

rm -rf "$test_tmp/etc" "$test_tmp/lib"
run_migration b852 >/dev/null
grep -q 'disable_clkreq=y' "$conf" 2>/dev/null ||
  fail "the migration fixes an install that never got the quirk" "$(ls -R "$test_tmp" 2>&1)"
[[ -x $installed_hook ]] || fail "the migration installs an executable sleep hook"
pass "the migration fixes an affected install under pipefail"

run_migration b852 >/dev/null
[[ ! -s $calls ]] ||
  fail "a machine another user already repaired is left untouched" "$(cat "$calls")"
pass "the migration is idempotent across users on one machine"

rm -rf "$test_tmp/etc" "$test_tmp/lib"
run_migration 8852 >/dev/null
[[ ! -f $conf ]] || fail "the migration skips an unaffected card" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unaffected machines" "$(cat "$calls")"
pass "the migration skips machines without the affected card"
