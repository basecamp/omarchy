#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-sandy-bridge-idle.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1787217354.sh"

grep -q 'apple/fix-sandy-bridge-idle.sh' "$all" ||
  fail "the Sandy Bridge idle fix runs during hardware setup"
grep -Fq 'KERNEL_CMDLINE[default]+=" intel_idle.max_cstate=1"' "$leaf" ||
  fail "the leaf installs the C-state cap kernel parameter"
pass "the Sandy Bridge idle fix installs the C-state cap during setup"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
conf="$test_tmp/etc/limine-entry-tool.d/apple-sandy-bridge-idle.conf"
marker="$test_tmp/var/lib/omarchy/migrations/1787217354"
cmdline="$test_tmp/proc-cmdline"
mkdir -p "$stub_bin" "$test_tmp/dmi"

# Real matching logic against a fixture, so the model gate itself is exercised.
cat >"$stub_bin/omarchy-hw-match" <<SH
#!/bin/bash

grep -qi "\$1" "$test_tmp/dmi/product_name"
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash

printf 'limine-mkinitcpio\n' >>"$TEST_LOG"
SH

# Stubbed rather than run: the real one would write the running user's state.
cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local model="$1"
  rm -rf "$test_tmp/etc"
  printf '%s' "$model" >"$test_tmp/dmi/product_name"

  # Redirect the absolute path the leaf writes into the sandbox.
  local script="$test_tmp/leaf.sh"
  sed "s|/etc/limine-entry-tool.d|$test_tmp/etc/limine-entry-tool.d|g" \
    "$leaf" >"$script"

  PATH="$stub_bin:$PATH" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

for model in "MacBookAir4,1" "MacBookAir4,2"; do
  run_leaf "$model"
  grep -Fq 'KERNEL_CMDLINE[default]+=" intel_idle.max_cstate=1"' "$conf" 2>/dev/null ||
    fail "an affected Air gets the C-state cap" "$model"
done
pass "both 2011 Air models get the C-state cap"

# Sandy Bridge relatives that do not share the verified freeze, and a model
# whose name would match a sloppier pattern than "MacBookAir4,".
for model in "MacBookPro8,1" "Macmini6,1" "MacBookAir41"; do
  run_leaf "$model"
  [[ ! -e $conf ]] || fail "other Macs are left alone" "$model"
done
pass "other Macs are left alone"

# Installs that predate the leaf never ran hardware setup again, so the
# migration has to reach them.
run_migration() {
  local model="$1" booted="$2"
  printf '%s' "$model" >"$test_tmp/dmi/product_name"
  printf '%s' "$booted" >"$cmdline"
  : >"$calls"

  PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_SANDY_IDLE_LIMINE_CONF="$conf" \
    OMARCHY_SANDY_IDLE_REPAIR_MARKER="$marker" \
    OMARCHY_RUNNING_CMDLINE="$cmdline" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -rf "$test_tmp/etc" "$test_tmp/var"
run_migration "MacBookAir4,1" "quiet splash"
grep -Fq 'KERNEL_CMDLINE[default]+=" intel_idle.max_cstate=1"' "$conf" 2>/dev/null ||
  fail "the migration installs the drop-in on an affected Air" "$(ls -R "$test_tmp/etc" 2>&1)"
grep -Fq 'limine-mkinitcpio' "$calls" ||
  fail "the migration rebuilds the boot image" "$(cat "$calls")"
# The cap only reaches the kernel on the next boot.
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the reboot that applies it" "$(cat "$calls")"
[[ -e $marker ]] || fail "the migration records the machine-wide rebuild"
pass "the migration fixes an install that never got the cap"

# A second user on the same machine: the drop-in and marker exist, so the
# machine-wide rebuild must not repeat, but this user's kernel is still
# uncapped and their per-user state still needs the reboot prompt.
run_migration "MacBookAir4,1" "quiet splash"
! grep -Fq 'limine-mkinitcpio' "$calls" ||
  fail "a recorded rebuild is not repeated" "$(cat "$calls")"
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "a second user is still asked for the pending reboot" "$(cat "$calls")"
pass "a second user skips the rebuild but still gets the reboot prompt"

# After the reboot the cap is live, and a later user's migration has nothing
# left to do at all.
run_migration "MacBookAir4,1" "quiet splash intel_idle.max_cstate=1"
[[ ! -s $calls ]] || fail "a fully applied install is left untouched" "$(cat "$calls")"
pass "a fully applied install is left untouched"

# Someone who already added the cap by hand boots fixed and only needs the
# drop-in baked in, not another reboot.
rm -rf "$test_tmp/etc" "$test_tmp/var"
run_migration "MacBookAir4,1" "quiet splash intel_idle.max_cstate=1"
grep -Fq 'limine-mkinitcpio' "$calls" ||
  fail "a hand-fixed install still gets the drop-in baked in" "$(cat "$calls")"
! grep -Fq 'reboot-required' "$calls" ||
  fail "a hand-fixed install is not asked to reboot" "$(cat "$calls")"
pass "a hand-fixed install gets the drop-in without a reboot prompt"

# A run interrupted mid-install can leave the drop-in truncated; the rerun
# must not trust the file's existence and rebuild an empty config into the
# boot image.
rm -rf "$test_tmp/etc" "$test_tmp/var"
mkdir -p "$(dirname "$conf")"
: >"$conf"
run_migration "MacBookAir4,1" "quiet splash"
grep -Fq 'KERNEL_CMDLINE[default]+=" intel_idle.max_cstate=1"' "$conf" ||
  fail "a truncated drop-in is reinstalled" "$(cat "$conf")"
grep -Fq 'limine-mkinitcpio' "$calls" ||
  fail "a reinstalled drop-in is baked into the boot image" "$(cat "$calls")"
pass "a truncated drop-in is reinstalled and baked in"

# Someone who commented the line out is still on the freezing default.
printf '#KERNEL_CMDLINE[default]+=" intel_idle.max_cstate=1"\n' >"$conf"
rm -rf "$test_tmp/var"
run_migration "MacBookAir4,1" "quiet splash"
grep -Fxq 'KERNEL_CMDLINE[default]+=" intel_idle.max_cstate=1"' "$conf" ||
  fail "a commented-out parameter does not count as applied" "$(cat "$conf")"
pass "a commented-out parameter does not count as applied"

# An interrupted rebuild leaves the drop-in without a marker; the rerun must
# retry rather than trust the config.
rm -rf "$test_tmp/var"
run_migration "MacBookAir4,1" "quiet splash"
grep -Fq 'limine-mkinitcpio' "$calls" ||
  fail "an interrupted rebuild is retried" "$(cat "$calls")"
pass "an interrupted rebuild is retried"

rm -rf "$test_tmp/etc" "$test_tmp/var"
run_migration "Macmini6,1" "quiet splash"
[[ ! -e $conf && ! -s $calls ]] ||
  fail "the migration skips unaffected Macs" "$(cat "$calls")"
pass "the migration skips unaffected Macs"
