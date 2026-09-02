#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1788320383.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
conf="$test_tmp/etc/modprobe.d/brcmfmac.conf"
mkdir -p "$stub_bin" "$(dirname "$conf")" "$test_tmp/dmi"

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

chmod +x "$stub_bin"/*

run_cleanup() {
  local product="$1"
  printf '%s' "$product" >"$test_tmp/dmi/product_name"
  : >"$calls"

  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_BRCMFMAC_DMI_PRODUCT="$test_tmp/dmi/product_name" \
    OMARCHY_BRCMFMAC_CONF="$conf" \
    bash -euo pipefail "$migration" >/dev/null
}

legacy_block='# Fix for T2 MacBook WiFi connectivity issues
options brcmfmac feature_disable=0x82000'

current_block="# Broadcom's firmware supplicant and authenticator fail the WPA four-way
# handshake on Apple hardware, which surfaces as a rejected password. Disable
# both so wpa_supplicant performs the handshake instead.
options brcmfmac feature_disable=0x82000"

printf '%s\n' "$legacy_block" >"$conf"
run_cleanup "MacBookPro16,1"
[[ ! -e $conf ]] || fail "the cleanup removes the legacy T2-owned quirk"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the legacy cleanup requests the reboot that applies it" "$(cat "$calls")"
state_line=$(grep -Fn $'omarchy-state\tset\treboot-required' "$calls" | cut -d: -f1 | head -1)
edit_line=$(grep -En $'^sudo\t(rm|tee)' "$calls" | cut -d: -f1 | head -1)
(( state_line < edit_line )) ||
  fail "the reboot request lands before the config edit" "$(cat "$calls")"
pass "the cleanup removes the legacy T2-owned quirk"

printf '%s\n' "$current_block" >"$conf"
run_cleanup "MacBookPro16,1"
[[ ! -e $conf ]] || fail "the cleanup removes the current Omarchy-owned quirk"
pass "the cleanup removes the current Omarchy-owned quirk"

printf 'options brcmfmac roamoff=1\n\n%s\n' "$current_block" >"$conf"
run_cleanup "MacBookPro16,1"
grep -qx 'options brcmfmac roamoff=1' "$conf" ||
  fail "the cleanup preserves unrelated brcmfmac options" "$(cat "$conf")"
! grep -q 'feature_disable=0x82000' "$conf" ||
  fail "the cleanup removes only its owned block" "$(cat "$conf")"
pass "the cleanup preserves unrelated brcmfmac options"

rm -rf "$test_tmp/etc"
mkdir -p "$(dirname "$conf")" "$test_tmp/real"
printf '%s\n' "$legacy_block" >"$test_tmp/real/brcmfmac.conf"
ln -s "$test_tmp/real/brcmfmac.conf" "$conf"
run_cleanup "MacBookPro16,1"
[[ -L $conf ]] || fail "the cleanup preserves a symlinked config"
[[ ! -s $test_tmp/real/brcmfmac.conf ]] ||
  fail "the cleanup empties a symlink through its target" "$(cat "$test_tmp/real/brcmfmac.conf")"
pass "the cleanup writes through a symlinked config"

rm -f "$conf"

printf '# Local override\noptions brcmfmac feature_disable=0x82000 roamoff=1\n' >"$conf"
run_cleanup "MacBookPro16,1"
grep -qx 'options brcmfmac feature_disable=0x82000 roamoff=1' "$conf" ||
  fail "the cleanup leaves an administrator-customized option alone" "$(cat "$conf")"
! grep -Eq $'^(sudo\t(rm|tee)|omarchy-state\t)' "$calls" ||
  fail "the customized config triggers no privileged write" "$(cat "$calls")"
pass "the cleanup leaves administrator-customized options alone"

printf '%s\n' "$legacy_block" >"$conf"
run_cleanup "MacBookPro15,1"
grep -qx 'options brcmfmac feature_disable=0x82000' "$conf" ||
  fail "the cleanup leaves other T2 models alone" "$(cat "$conf")"
[[ ! -s $calls ]] || fail "another model triggers no privileged write" "$(cat "$calls")"
pass "the cleanup leaves other T2 models alone"

run_cleanup "MacBookPro16,1"
run_cleanup "MacBookPro16,1"
[[ ! -e $conf ]] || fail "the cleanup remains idempotent"
pass "the cleanup remains idempotent"
