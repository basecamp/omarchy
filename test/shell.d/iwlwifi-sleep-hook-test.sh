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

# Test 2: pre suspend with BE211 (8086:e440) and iwlmvm selects, unloads, records, and restores opmode
setup_env "iwlmvm 123 0\niwlwifi 456 1 iwlmvm" "$be211_pci"
run_hook pre suspend

[[ -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend creates state file for BE211 with iwlmvm"
[[ $(<"$tmp_dir/run/iwlwifi-suspended") == "iwlmvm" ]] || fail "state file records iwlmvm opmode"
grep -Fx 'modprobe -r iwlmvm' "$tmp_dir/calls" >/dev/null || fail "pre suspend unloads iwlmvm on BE211"
grep -Fx 'modprobe -r iwlwifi' "$tmp_dir/calls" >/dev/null || fail "pre suspend unloads iwlwifi on BE211"

# Verify subsequent restore on post-resume
run_hook post suspend
[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "post suspend cleans up state file for iwlmvm"
grep -Fx 'modprobe iwlwifi' "$tmp_dir/calls" >/dev/null || fail "post suspend reloads iwlwifi"
grep -Fx 'modprobe iwlmvm' "$tmp_dir/calls" >/dev/null || fail "post suspend reloads iwlmvm"
pass "pre suspend with BE211 and iwlmvm unloads, records, and restores opmode"

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

[[ -f $tmp_dir/run/iwlwifi-suspended ]] || fail "post suspend retains state file if iwlwifi reload fails"
pass "post suspend retains state file if iwlwifi reload fails"

# Test 5: post suspend retains state file if opmode reload fails
setup_env "" "$be200_pci" "iwlmld"
echo "iwlmld" >"$tmp_dir/run/iwlwifi-suspended"
run_hook post suspend

[[ -f $tmp_dir/run/iwlwifi-suspended ]] || fail "post suspend retains state file if opmode reload fails"
pass "post suspend retains state file if opmode reload fails"

# Test 6: pre suspend removes state file and restores opmode when iwlwifi unload fails
setup_env "iwlmld 123 0\niwlwifi 456 1 iwlmld" "$be200_pci" "-r iwlwifi"
run_hook pre suspend

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend must not keep state file when unload fails"
grep -Fx 'modprobe iwlmld' "$tmp_dir/calls" >/dev/null || fail "pre suspend restores opmode when iwlwifi unload fails"
pass "pre suspend cleans up state file and restores opmode when unload fails"

# Test 7: unaffected Intel card (AX210) is not unloaded
setup_env "iwlmvm 123 0\niwlwifi 456 1 iwlmvm" "$ax210_pci"
run_hook pre suspend

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend must not touch AX210"
[[ ! -s $tmp_dir/calls ]] || fail "pre suspend must not unload AX210 drivers"
pass "pre suspend skips unaffected Intel AX210 hardware"

# Test 8: pre hibernate does not unload drivers
setup_env "iwlmld 123 0\niwlwifi 456 1 iwlmld" "$be200_pci"
run_hook pre hibernate

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre hibernate must not create state file"
[[ ! -s $tmp_dir/calls ]] || fail "pre hibernate must not unload drivers"
pass "pre hibernate leaves drivers untouched"

# Test 9: post fallback reloads iwlwifi when missing and affected Intel card is present
setup_env "" "$be200_pci"
run_hook post suspend

grep -Fx 'modprobe iwlwifi' "$tmp_dir/calls" >/dev/null || fail "post fallback reloads iwlwifi when BE200 detected"
pass "post fallback reloads iwlwifi when BE200 is present"

# Test 10: pre suspend on non-Intel system is a no-op
setup_env "rtw89_8852be 123 0" "0000:02:00.0 Network controller [0280]: Realtek [10ec:c852]"
run_hook pre suspend

[[ ! -f $tmp_dir/run/iwlwifi-suspended ]] || fail "pre suspend on non-Intel must not create state file"
[[ ! -s $tmp_dir/calls ]] || fail "pre suspend on non-Intel must not execute modprobe"
pass "pre suspend on non-Intel system is a no-op"

# Test 11: installation script copies hook when BE200 is present
inst_dir=$(mktemp -d)
mkdir -p "$inst_dir/etc/modprobe.d" "$inst_dir/usr/lib/systemd/system-sleep"
(
  export OMARCHY_PATH="$ROOT"
  export PATH="$tmp_dir/bin:$PATH"
  setup_env "" "$be200_pci"
  # Override paths to test install script in isolation
  sed -e "s|/etc/modprobe.d|$inst_dir/etc/modprobe.d|g" \
      -e "s|/usr/lib/systemd/system-sleep|$inst_dir/usr/lib/systemd/system-sleep|g" \
      "$ROOT/install/hardware/intel/fix-wifi7-eht.sh" | bash
)
[[ -f $inst_dir/usr/lib/systemd/system-sleep/iwlwifi-reset ]] || fail "installer copies iwlwifi-reset hook"
pass "hardware installer installs iwlwifi-reset hook for BE200"
rm -rf "$inst_dir"

# Test 12: migration installs hook on BE200 system
migration="$ROOT/migrations/1787718500.sh"
[[ -f $migration ]] || fail "migration 1787718500.sh exists"
pass "migration 1787718500.sh exists"

mig_dir=$(mktemp -d)
mkdir -p "$mig_dir/bin" "$mig_dir/system-sleep"
cat >"$mig_dir/bin/sudo" <<'SH'
#!/bin/bash
echo "sudo $*" >>"$CALLS_FILE"
exec "$@"
SH
chmod +x "$mig_dir/bin/sudo"

run_migration() {
  local pci_info="$1"
  : >"$mig_dir/calls"
  setup_env "" "$pci_info"
  PATH="$mig_dir/bin:$tmp_dir/bin:$PATH" \
  CALLS_FILE="$mig_dir/calls" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_SYSTEM_SLEEP_DIR="$mig_dir/system-sleep" \
  bash -euo pipefail "$migration" >/dev/null
}

# Affected install copies hook
run_migration "$be200_pci"
[[ -f $mig_dir/system-sleep/iwlwifi-reset ]] || fail "migration copies iwlwifi-reset hook for BE200"
grep -q 'sudo cp -p' "$mig_dir/calls" || fail "migration uses sudo to copy hook"
pass "migration installs iwlwifi-reset hook for BE200"

# Up-to-date no-op skips sudo copy
run_migration "$be200_pci"
[[ ! -s $mig_dir/calls ]] || fail "migration does not copy when already up-to-date"
pass "migration is idempotent and skips copy when hook is up-to-date"

# Unaffected no-op skips copy
rm -f "$mig_dir/system-sleep/iwlwifi-reset"
run_migration "$ax210_pci"
[[ ! -f $mig_dir/system-sleep/iwlwifi-reset ]] || fail "migration must not install hook on AX210"
[[ ! -s $mig_dir/calls ]] || fail "migration must not invoke sudo on AX210"
pass "migration no-ops on unaffected hardware"

rm -rf "$mig_dir"
