#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/state"

cat >"$tmp_dir/bin/powerprofilesctl" <<'EOF'
#!/bin/bash

if [[ $1 == "list" ]]; then
  printf '  power-saver:\n* balanced:\n  performance:\n'
fi
EOF
chmod +x "$tmp_dir/bin/powerprofilesctl"

cat >"$tmp_dir/bin/busctl" <<'EOF'
#!/bin/bash

echo "b false"
EOF
chmod +x "$tmp_dir/bin/busctl"

export PATH="$tmp_dir/bin:$ROOT/bin:$PATH"

# Never let the suite reach the real attribute when it runs on a Slimbook.
vendor_file="$tmp_dir/sys_vendor"
mode_file="$tmp_dir/performance_mode"
export OMARCHY_DMI_SYS_VENDOR="$vendor_file"
export OMARCHY_QC71_PERFORMANCE_MODE="$mode_file"

printf 'SLIMBOOK\n' >"$vendor_file"
printf '2\n' >"$mode_file"

"$ROOT/bin/omarchy-powerprofiles-sync-hardware" performance
[[ $(<"$mode_file") == "3" ]] || fail "performance maps onto the qc71 performance mode"
pass "performance maps onto the qc71 performance mode"

"$ROOT/bin/omarchy-powerprofiles-sync-hardware" power-saver
[[ $(<"$mode_file") == "1" ]] || fail "power-saver maps onto the qc71 silent mode"
pass "power-saver maps onto the qc71 silent mode"

"$ROOT/bin/omarchy-powerprofiles-sync-hardware" balanced
[[ $(<"$mode_file") == "2" ]] || fail "balanced maps onto the qc71 normal mode"
pass "balanced maps onto the qc71 normal mode"

# A mode that already agrees must not be rewritten: the write reaches the
# embedded controller, and slimbook-service applies most changes on its own.
chmod 0444 "$mode_file"
"$ROOT/bin/omarchy-powerprofiles-sync-hardware" balanced
chmod 0644 "$mode_file"
pass "an already matching mode is left untouched"

# Anything that is not one of the three profiles must not reach the hardware.
"$ROOT/bin/omarchy-powerprofiles-sync-hardware" nonsense
[[ $(<"$mode_file") == "2" ]] || fail "an unknown profile leaves the mode alone"
"$ROOT/bin/omarchy-powerprofiles-sync-hardware"
[[ $(<"$mode_file") == "2" ]] || fail "a missing profile leaves the mode alone"
pass "unknown and missing profiles leave the mode alone"

printf 'LENOVO\n' >"$vendor_file"
"$ROOT/bin/omarchy-powerprofiles-sync-hardware" performance
[[ $(<"$mode_file") == "2" ]] || fail "other vendors are left alone"
pass "other vendors are left alone"

if omarchy-hw-slimbook-qc71; then
  fail "hardware detection rejects other vendors"
fi
printf 'SLIMBOOK\n' >"$vendor_file"
omarchy-hw-slimbook-qc71 || fail "hardware detection accepts a Slimbook running the qc71 driver"
if OMARCHY_QC71_PERFORMANCE_MODE="$tmp_dir/absent" omarchy-hw-slimbook-qc71; then
  fail "hardware detection needs the qc71 driver, not just the vendor"
fi
# The vendor alone still counts as a Slimbook, so setup can lay the rule down
# ahead of a driver that arrives from Slimbook's own repository later.
OMARCHY_QC71_PERFORMANCE_MODE="$tmp_dir/absent" omarchy-hw-slimbook ||
  fail "vendor detection does not need the qc71 driver"
pass "hardware detection needs both the vendor and the qc71 driver"

# The profile has already been applied by the time the mode is written, so a
# hardware write that fails must not fail the profile change with it.
export OMARCHY_POWERPROFILES_STATE_DIR="$tmp_dir/state"
chmod 0444 "$mode_file"
if ! "$ROOT/bin/omarchy-powerprofiles-set" ac performance 2>"$tmp_dir/stderr"; then
  fail "a mode that cannot be written still reports a successful profile change"
fi
grep -q "qc71" "$tmp_dir/stderr" || fail "a failed mode write explains itself"
# The redirection's own failure has to be caught with the printf's, or a raw
# "Permission denied" escapes into the bar's profile switch alongside it.
if grep -q "Permission denied" "$tmp_dir/stderr"; then
  fail "a failed mode write reports only its own message"
fi
(( $(wc -l <"$tmp_dir/stderr") == 1 )) || fail "a failed mode write reports exactly one message"
chmod 0644 "$mode_file"
pass "a mode that cannot be written neither fails nor hides the profile change"

"$ROOT/bin/omarchy-powerprofiles-set" ac performance
[[ $(<"$mode_file") == "3" ]] || fail "setting a profile carries it onto the hardware"
pass "setting a profile carries it onto the hardware"
