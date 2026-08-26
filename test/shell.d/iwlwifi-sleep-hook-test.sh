#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hook="$ROOT/default/systemd/system-sleep/iwlwifi-reset"

[[ -f $hook ]] || fail "iwlwifi-reset hook exists in default/systemd/system-sleep/"
[[ -x $hook ]] || fail "iwlwifi-reset hook must be executable"
pass "iwlwifi-reset hook exists and is executable"

bash -n "$hook" || fail "iwlwifi-reset hook has valid bash syntax"
pass "iwlwifi-reset hook has valid bash syntax"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

setup_env() {
  local lsmod_output="$1"
  local lspci_output="$2"
  local modprobe_fail="${3:-}"

  rm -rf "$tmp_dir/bin" "$tmp_dir/run" "$tmp_dir/calls"
  mkdir -p "$tmp_dir/bin" "$tmp_dir/run"
  : >"$tmp_dir/calls"

  cat >"$tmp_dir/bin/lsmod" <<SH
#!/bin/bash
printf '%b\n' "$lsmod_output"
SH

  cat >"$tmp_dir/bin/lspci" <<SH
#!/bin/bash
printf '%b\n' "$lspci_output"
SH

  cat >"$tmp_dir/bin/modprobe" <<SH
#!/bin/bash
echo "modprobe \$*" >>"$tmp_dir/calls"
if [[ -n "$modprobe_fail" && "\$*" == *"$modprobe_fail"* ]]; then
  echo "modprobe error: \$*" >&2
  exit 1
fi
exit 0
SH

  cat >"$tmp_dir/bin/logger" <<'SH'
#!/bin/bash
exit 0
SH

  chmod +x "$tmp_dir/bin"/*
}

run_hook() {
  local action="$1"
  local sleep_type="${2:-suspend}"
  OMARCHY_IWLWIFI_STATE_FILE="$tmp_dir/run/iwlwifi-suspended" \
  PATH="$tmp_dir/bin:$PATH" \
  bash "$hook" "$action" "$sleep_type"
}

be200_pci="0000:55:00.0 Network controller [0280]: Intel Corporation Wi-Fi 7 [8086:272b] (rev 1a)"
be211_pci="0000:00:14.3 Network controller [0280]: Intel Corporation Wi-Fi 7 [8086:e440] (rev 01)"
ax210_pci="0000:01:00.0 Network controller [0280]: Intel Corporation Wi-Fi 6 AX210 [8086:2725] (rev 1a)"

# Test 1: pre suspend with BE200 (8086:272b) and iwlmld unloads drivers and sets state
setup_env "iwlmld 123 0\niwlwifi 456 1 iwlmld" "$be200_pci"
run_hook pre suspend

[[ -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend creates state file"
[[ $(<"$tmp_dir/run/iwlwifi-suspended") == "iwlmld" ]] || fail "state file records iwlmld opmode"
grep -Fx 'modprobe -r iwlmld' "$tmp_dir/calls" >/dev/null || fail "pre suspend unloads iwlmld"
grep -Fx 'modprobe -r iwlwifi' "$tmp_dir/calls" >/dev/null || fail "pre suspend unloads iwlwifi"
pass "pre suspend with BE200 unloads modules and records state"

# Test 2: pre suspend with BE211 (8086:e440) works identically
setup_env "iwlmld 123 0\niwlwifi 456 1 iwlmld" "$be211_pci"
run_hook pre suspend

[[ -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend creates state file for BE211"
grep -Fx 'modprobe -r iwlwifi' "$tmp_dir/calls" >/dev/null || fail "pre suspend unloads iwlwifi on BE211"
pass "pre suspend with BE211 unloads modules and records state"

# Test 3: post suspend reloads iwlwifi then iwlmld and removes state file on success
setup_env "" "$be200_pci"
echo "iwlmld" >"$tmp_dir/run/iwlwifi-suspended"
run_hook post suspend

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "post suspend cleans up state file on success"
grep -Fx 'modprobe iwlwifi' "$tmp_dir/calls" >/dev/null || fail "post suspend reloads iwlwifi"
grep -Fx 'modprobe iwlmld' "$tmp_dir/calls" >/dev/null || fail "post suspend reloads iwlmld"
pass "post suspend reloads drivers and cleans up state on success"

# Test 4: post suspend retains state file if iwlwifi reload fails
setup_env "" "$be200_pci" "iwlwifi"
echo "iwlmld" >"$tmp_dir/run/iwlwifi-suspended"
run_hook post suspend

[[ -f $tmp_dir/run/iwlwifi-suspended ]] || fail "post suspend retains state file if reload fails"
pass "post suspend retains state file if reload fails"

# Test 5: pre suspend removes state file if unload fails
setup_env "iwlmld 123 0\niwlwifi 456 1 iwlmld" "$be200_pci" "iwlwifi"
run_hook pre suspend

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend must not keep state file when unload fails"
pass "pre suspend cleans up state file when unload fails"

# Test 6: unaffected Intel card (AX210) is not unloaded
setup_env "iwlmvm 123 0\niwlwifi 456 1 iwlmvm" "$ax210_pci"
run_hook pre suspend

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend must not touch AX210"
[[ ! -s $tmp_dir/calls ]] || fail "pre suspend must not unload AX210 drivers"
pass "pre suspend skips unaffected Intel AX210 hardware"

# Test 7: pre hibernate does not unload drivers
setup_env "iwlmld 123 0\niwlwifi 456 1 iwlmld" "$be200_pci"
run_hook pre hibernate

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre hibernate must not create state file"
[[ ! -s $tmp_dir/calls ]] || fail "pre hibernate must not unload drivers"
pass "pre hibernate leaves drivers untouched"

# Test 8: post fallback reloads iwlwifi when missing and affected Intel card is present
setup_env "" "$be200_pci"
run_hook post suspend

grep -Fx 'modprobe iwlwifi' "$tmp_dir/calls" >/dev/null || fail "post fallback reloads iwlwifi when BE200 detected"
pass "post fallback reloads iwlwifi when BE200 is present"

# Test 9: pre suspend on non-Intel system is a no-op
setup_env "rtw89_8852be 123 0" "0000:02:00.0 Network controller [0280]: Realtek [10ec:c852]"
run_hook pre suspend

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend on non-Intel must not create state file"
[[ ! -s $tmp_dir/calls ]] || fail "pre suspend on non-Intel must not execute modprobe"
pass "pre suspend on non-Intel system is a no-op"
