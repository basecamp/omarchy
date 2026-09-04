#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/realtek/fix-rtw89-8852be-resume.sh"
hook="$ROOT/default/systemd/system-sleep/rtw89-8852be"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1786812448.sh"

grep -q 'realtek/fix-rtw89-8852be-resume.sh' "$all" ||
  fail "the RTL8852BE resume hook runs during hardware setup"
[[ -x $hook ]] || fail "the sleep hook is executable so systemd-sleep will run it"
! grep -E 'lspci[^\n]*\|' "$leaf" "$migration" ||
  fail "hardware detection buffers lspci instead of piping it to grep"
pass "the RTL8852BE resume hook is wired and executable"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin" "$test_tmp/pci"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no such hardware" (#6608).
if (( ${RTW89_HARDWARE:-0} == 1 )); then
  echo '02:00.0 Network controller [0280]: Realtek RTL8852BE [10ec:b852]'
fi
for _ in {1..4096}; do
  echo '00:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/modprobe" <<'SH'
#!/bin/bash

printf 'modprobe' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/logger" <<'SH'
#!/bin/bash

printf 'logger' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local script="$test_tmp/leaf.sh"
  rm -rf "$test_tmp/sleep"
  mkdir -p "$test_tmp/sleep"

  sed -e "s|/usr/lib/systemd/system-sleep|$test_tmp/sleep|g" "$leaf" >"$script"

  RTW89_HARDWARE="${1:-0}" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

run_leaf 1 >/dev/null
[[ -x $test_tmp/sleep/rtw89-8852be ]] ||
  fail "the leaf installs an executable hook" "$(ls -la "$test_tmp/sleep" 2>&1)"
cmp -s "$hook" "$test_tmp/sleep/rtw89-8852be" ||
  fail "the installed hook matches the packaged source"
pass "the leaf installs the hook on RTL8852BE"

run_leaf 0 >/dev/null
[[ ! -e $test_tmp/sleep/rtw89-8852be ]] ||
  fail "the leaf leaves other hardware alone"
pass "the leaf leaves other hardware alone"

write_pci() {
  local present="$1"
  rm -rf "$test_tmp/pci"
  mkdir -p "$test_tmp/pci/0000:02:00.0"
  if (( present )); then
    printf '0x10ec\n' >"$test_tmp/pci/0000:02:00.0/vendor"
    printf '0xb852\n' >"$test_tmp/pci/0000:02:00.0/device"
  else
    printf '0x8086\n' >"$test_tmp/pci/0000:02:00.0/vendor"
    printf '0x272b\n' >"$test_tmp/pci/0000:02:00.0/device"
  fi
}

run_hook() {
  local present="$1" phase="$2"
  write_pci "$present"
  : >"$calls"

  local script="$test_tmp/hook.sh"
  sed -e "s|/sys/bus/pci/devices|$test_tmp/pci|g" "$hook" >"$script"
  chmod +x "$script"

  TEST_LOG="$calls" PATH="$stub_bin:$PATH" \
    bash "$script" "$phase" suspend
}

run_hook 1 pre
grep -Fq $'modprobe\t-r\trtw89_8852be\trtw89_8852b\trtw89_8852b_common\trtw89_pci\trtw89_core' "$calls" ||
  fail "pre suspend unloads the rtw89 stack" "$(cat "$calls")"
pass "pre suspend unloads the rtw89 stack"

run_hook 1 post
grep -Fq $'modprobe\trtw89_8852be' "$calls" ||
  fail "post resume reloads rtw89_8852be" "$(cat "$calls")"
! grep -Fq $'modprobe\t-r' "$calls" ||
  fail "post resume does not unload the driver" "$(cat "$calls")"
pass "post resume reloads rtw89_8852be"

run_hook 0 pre
[[ ! -s $calls ]] || fail "the hook is silent without RTL8852BE" "$(cat "$calls")"
run_hook 0 post
[[ ! -s $calls ]] || fail "the hook is silent without RTL8852BE" "$(cat "$calls")"
pass "the hook is a no-op without RTL8852BE"

run_migration() {
  local present="$1"
  : >"$calls"
  RTW89_HARDWARE="$present" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_RTW89_HOOK_SRC="$hook" \
    OMARCHY_RTW89_HOOK_DST="$test_tmp/sleep/rtw89-8852be" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -rf "$test_tmp/sleep"
run_migration 1
[[ -x $test_tmp/sleep/rtw89-8852be ]] ||
  fail "the migration installs the hook" "$(ls -la "$test_tmp/sleep" 2>&1)"
grep -Fq $'sudo\tcp\t-p' "$calls" ||
  fail "the migration copies the hook as root" "$(cat "$calls")"
pass "the migration installs the hook on RTL8852BE"

run_migration 1
[[ ! -s $calls ]] || fail "the migration is idempotent" "$(cat "$calls")"
pass "the migration is idempotent"

rm -rf "$test_tmp/sleep"
run_migration 0
[[ ! -e $test_tmp/sleep/rtw89-8852be ]] ||
  fail "the migration skips other hardware"
[[ ! -s $calls ]] || fail "the migration escalates nothing on other hardware" "$(cat "$calls")"
pass "the migration skips other hardware"
