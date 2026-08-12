#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
exit 1
STUB

cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
if [[ $1 == "btrfs" ]]; then
  echo 12345
elif [[ $1 == "sed" ]]; then
  "$@"
else
  printf 'sudo %s\n' "$*" >>"$TEST_LOG"
fi
STUB

chmod +x "$fake_bin"/*

image_size="$test_tmp/image_size"
mkinitcpio_conf="$test_tmp/omarchy_resume.conf"
swap_file="$test_tmp/swapfile"
resume_drop_in="$test_tmp/resume.conf"
test_log="$test_tmp/calls.log"

touch "$image_size" "$swap_file"
printf '%s\n' 'HOOKS+=(resume)' >"$mkinitcpio_conf"

run_setup() {
  OMARCHY_HIBERNATION_IMAGE_SIZE_PATH="$image_size" \
    OMARCHY_HIBERNATION_MKINITCPIO_CONF="$mkinitcpio_conf" \
    OMARCHY_HIBERNATION_SWAP_FILE="$swap_file" \
    OMARCHY_HIBERNATION_RESUME_DROP_IN="$resume_drop_in" \
    TEST_LOG="$test_log" PATH="$fake_bin:$PATH" \
    "$ROOT/bin/omarchy-hibernation-setup" "$@"
}

run_setup >/dev/null
[[ ! -e $test_log ]] || fail "configured hibernation skips an unnecessary UKI rebuild"
pass "configured hibernation remains a no-op without force"

run_setup --force >/dev/null
rebuild_count=$(grep -cFx 'sudo limine-mkinitcpio' "$test_log")
(( rebuild_count == 1 )) ||
  fail "forced hibernation setup rebuilds the UKI once" "$(cat "$test_log")"
pass "forced hibernation setup rebuilds an already-configured UKI"

rm -f "$test_log"
run_setup --force --no-rebuild >/dev/null
[[ ! -e $test_log ]] || fail "no-rebuild suppresses a forced UKI rebuild" "$(cat "$test_log")"
pass "forced hibernation setup honors no-rebuild callers"

printf '%s\n' 'KERNEL_CMDLINE[default]+=" resume=/dev/root resume_offset="' >"$resume_drop_in"
rm -f "$test_log"
run_setup --force >/dev/null

grep -qF 'resume_offset=12345"' "$resume_drop_in" ||
  fail "forced hibernation setup repairs an empty resume offset"
rebuild_count=$(grep -cFx 'sudo limine-mkinitcpio' "$test_log")
(( rebuild_count == 1 )) ||
  fail "offset repair and force share one UKI rebuild" "$(cat "$test_log")"
pass "forced offset repair rebuilds the UKI exactly once"
