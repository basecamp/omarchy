#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hook="$ROOT/default/systemd/system-sleep/iwlwifi-reset"

[[ -f $hook ]] || fail "iwlwifi-reset hook exists in default/systemd/system-sleep/"
pass "iwlwifi-reset hook exists"

bash -n "$hook" || fail "iwlwifi-reset hook has valid bash syntax"
pass "iwlwifi-reset hook has valid bash syntax"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

setup_env() {
  local lsmod_output="$1"
  local lspci_output="$2"

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

  cat >"$tmp_dir/bin/modprobe" <<'SH'
#!/bin/bash
echo "modprobe $*" >>"$CALLS_FILE"
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
  CALLS_FILE="$tmp_dir/calls" \
  OMARCHY_IWLWIFI_STATE_FILE="$tmp_dir/run/iwlwifi-suspended" \
  PATH="$tmp_dir/bin:$PATH" \
  bash "$hook" "$action" "$sleep_type"
}

# Test 1: pre suspend with iwlmld (WiFi 7) unloads iwlmld then iwlwifi and sets state
setup_env "iwlmld 123 0\niwlwifi 456 1 iwlmld" ""
run_hook pre suspend

[[ -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend creates state file"
[[ $(<"$tmp_dir/run/iwlwifi-suspended") == "iwlmld" ]] || fail "state file records iwlmld opmode"
grep -Fx 'modprobe -r iwlmld' "$tmp_dir/calls" >/dev/null || fail "pre suspend unloads iwlmld"
grep -Fx 'modprobe -r iwlwifi' "$tmp_dir/calls" >/dev/null || fail "pre suspend unloads iwlwifi"
pass "pre suspend with WiFi 7 unloads modules and records state"

# Test 2: post suspend reloads iwlwifi then iwlmld and cleans up state file
setup_env "" ""
echo "iwlmld" >"$tmp_dir/run/iwlwifi-suspended"
run_hook post suspend

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "post suspend cleans up state file"
grep -Fx 'modprobe iwlwifi' "$tmp_dir/calls" >/dev/null || fail "post suspend reloads iwlwifi"
grep -Fx 'modprobe iwlmld' "$tmp_dir/calls" >/dev/null || fail "post suspend reloads iwlmld"
pass "post suspend reloads drivers and cleans up state"

# Test 3: pre suspend with iwlmvm (WiFi 6) unloads iwlmvm then iwlwifi
setup_env "iwlmvm 123 0\niwlwifi 456 1 iwlmvm" ""
run_hook pre suspend

[[ $(<"$tmp_dir/run/iwlwifi-suspended") == "iwlmvm" ]] || fail "state file records iwlmvm opmode"
grep -Fx 'modprobe -r iwlmvm' "$tmp_dir/calls" >/dev/null || fail "pre suspend unloads iwlmvm"
grep -Fx 'modprobe -r iwlwifi' "$tmp_dir/calls" >/dev/null || fail "pre suspend unloads iwlwifi"
pass "pre suspend with WiFi 6 unloads modules and records state"

# Test 4: pre hibernate does not unload drivers
setup_env "iwlmld 123 0\niwlwifi 456 1 iwlmld" ""
run_hook pre hibernate

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre hibernate must not create state file"
[[ ! -s $tmp_dir/calls ]] || fail "pre hibernate must not unload drivers"
pass "pre hibernate leaves drivers untouched"

# Test 5: post fallback reloads iwlwifi when missing and Intel card is present
setup_env "" "0000:55:00.0 Network controller: Intel Corporation Wi-Fi 7"
run_hook post suspend

grep -Fx 'modprobe iwlwifi' "$tmp_dir/calls" >/dev/null || fail "post fallback reloads iwlwifi when Intel hardware detected"
pass "post fallback reloads iwlwifi when Intel hardware is present"

# Test 6: pre suspend on system without iwlwifi does nothing
setup_env "rtw89_8852be 123 0" ""
run_hook pre suspend

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend without iwlwifi must not create state file"
[[ ! -s $tmp_dir/calls ]] || fail "pre suspend without iwlwifi must not execute modprobe"
pass "pre suspend on non-Intel system is a no-op"
