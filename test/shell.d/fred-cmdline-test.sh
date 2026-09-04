#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

all="$ROOT/install/hardware/all.sh"
shipped_migration="$ROOT/migrations/1788521801.sh"

if grep -q 'hardware/intel/fred.sh' "$all"; then
  fail "hardware setup no longer writes fred=on"
fi
pass "hardware setup no longer writes fred=on"

[[ ! -e $ROOT/install/hardware/intel/fred.sh ]] ||
  fail "the FRED drop-in installer is retired; Linux 7.1 ignores fred=on"
pass "the FRED drop-in installer is retired"

[[ -f $shipped_migration ]] || fail "a migration removes the stale fred=on drop-in from existing installs"
grep -Fxq 'drop_in=/etc/limine-entry-tool.d/intel-panther-lake-fred.conf' "$shipped_migration" ||
  fail "the production fred drop-in path is a fixed literal"
grep -Fxq 'rebuild_needed=/var/lib/omarchy/migrations/1788521801-rebuild-needed' "$shipped_migration" ||
  fail "the production rebuild marker is a fixed literal"
if grep -q 'OMARCHY_FRED_' "$shipped_migration"; then
  fail "the migration does not accept caller-controlled privileged paths"
fi
pass "a migration removes the stale fred=on drop-in from existing installs"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
drop_in="$test_tmp/intel-panther-lake-fred.conf"
rebuild_needed="$test_tmp/rebuild-needed"
limine_mkinitcpio="$test_tmp/bin/limine-mkinitcpio"
migration="$test_tmp/migration.sh"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$limine_mkinitcpio" <<'SH'
#!/bin/bash
echo 'limine-mkinitcpio' >>"$TEST_LOG"
SH

chmod +x "$stub_bin/sudo" "$limine_mkinitcpio"

sed \
  -e "s|^drop_in=/etc/limine-entry-tool.d/intel-panther-lake-fred.conf$|drop_in=$drop_in|" \
  -e "s|^rebuild_needed=/var/lib/omarchy/migrations/1788521801-rebuild-needed$|rebuild_needed=$rebuild_needed|" \
  -e "s|^limine_mkinitcpio=/usr/bin/limine-mkinitcpio$|limine_mkinitcpio=$limine_mkinitcpio|" \
  "$shipped_migration" >"$migration"

run_migration() {
  PATH="$stub_bin:$PATH" TEST_LOG="$calls" bash -euo pipefail "$migration" >/dev/null
}

write_shipped_drop_in() {
  cat >"$drop_in" <<'EOF'
# Intel Panther Lake FRED support
KERNEL_CMDLINE[default]+=" fred=on"
EOF
}

write_shipped_drop_in
run_migration

[[ ! -e $drop_in ]] || fail "migration deletes the shipped fred=on drop-in"
grep -Fxq 'limine-mkinitcpio' "$calls" || fail "migration rebuilds the boot image after removing fred=on"
[[ ! -e $rebuild_needed ]] || fail "migration clears the pending rebuild marker after success"
pass "migration removes the shipped fred=on drop-in and rebuilds"

: >"$calls"
run_migration
[[ ! -s $calls ]] || fail "a completed fred repair is not repeated" "$(cat "$calls")"
pass "fred drop-in migration is machine-idempotent"

write_shipped_drop_in
: >"$rebuild_needed"
: >"$calls"
rm -f "$drop_in"
run_migration
grep -Fxq 'limine-mkinitcpio' "$calls" || fail "an interrupted rebuild is retried"
[[ ! -e $rebuild_needed ]] || fail "a retried rebuild clears the pending marker"
pass "migration retries an interrupted fred rebuild"

custom="$test_tmp/custom.conf"
custom_migration="$test_tmp/custom-migration.sh"
cat >"$custom" <<'EOF'
# Intel Panther Lake FRED support
KERNEL_CMDLINE[default]+=" fred=on quiet"
EOF
sed \
  -e "s|^drop_in=/etc/limine-entry-tool.d/intel-panther-lake-fred.conf$|drop_in=$custom|" \
  -e "s|^rebuild_needed=/var/lib/omarchy/migrations/1788521801-rebuild-needed$|rebuild_needed=$rebuild_needed|" \
  -e "s|^limine_mkinitcpio=/usr/bin/limine-mkinitcpio$|limine_mkinitcpio=$limine_mkinitcpio|" \
  "$shipped_migration" >"$custom_migration"
: >"$calls"
PATH="$stub_bin:$PATH" TEST_LOG="$calls" bash -euo pipefail "$custom_migration" >/dev/null

[[ -f $custom ]] || fail "migration leaves an edited drop-in alone"
[[ ! -s $calls ]] || fail "an edited drop-in does not trigger a rebuild" "$(cat "$calls")"
pass "migration leaves an edited fred drop-in alone"
