#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command objcopy

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
modules="$test_tmp/modules"
uki_dir="$test_tmp/boot/EFI/Linux"
limine_config="$test_tmp/boot/limine.conf"
uki_config="$test_tmp/omarchy-uki.conf"
calls="$test_tmp/calls"
mkdir -p "$stub_bin" "$modules/6.1.0-test" "$uki_dir"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
[[ $1 == "-Qqo" && " $OWNED_PKGBASES " == *" $2 "* ]]
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash
echo limine-mkinitcpio >>"$CALLS"
[[ $REPAIR_MODE != "fail" ]] || exit 1

if [[ $REPAIR_MODE == "image" ]]; then
  printf '%s' "$EXPECTED_VERSION" >"$UNAME_SECTION"
  "$REAL_OBJCOPY" --update-section .uname="$UNAME_SECTION" "$UKI"
fi

hash=$(b2sum "$UKI" | awk '{ print $1 }')
sed -i -E "s|(boot\\(\\):/EFI/Linux/$UKI_NAME#)[0-9a-f]+|\\1$hash|" "$LIMINE_CONFIG"
SH

chmod +x "$stub_bin/sudo" "$stub_bin/pacman" "$stub_bin/limine-mkinitcpio"

pkgbase="$modules/6.1.0-test/pkgbase"
uki="$uki_dir/omarchy_linux.efi"
uname_section="$test_tmp/uname"
printf '%s\n' linux >"$pkgbase"
printf '%s\n' 'ENABLE_UKI=yes' >"$uki_config"
: >"$calls"

make_uki() {
  printf '%s' "$1" >"$uname_section"
  objcopy --add-section .uname="$uname_section" /bin/true "$uki"
}

write_limine_config() {
  local hash="${1:-$(b2sum "$uki" | awk '{ print $1 }')}"
  printf '  path: boot():/EFI/Linux/omarchy_linux.efi#%s\n' "$hash" >"$limine_config"
}

run_verifier() {
  OMARCHY_VERIFY_BOOT_TEST=1 \
    OMARCHY_MODULES_DIR="$modules" \
    OMARCHY_UKI_DIR="$uki_dir" \
    OMARCHY_LIMINE_CONFIG="$limine_config" \
    OMARCHY_UKI_CONFIG="$uki_config" \
    OWNED_PKGBASES="$pkgbase" \
    REPAIR_MODE="${REPAIR_MODE:-fail}" \
    CALLS="$calls" \
    EXPECTED_VERSION=6.1.0-test \
    UNAME_SECTION="$uname_section" \
    UKI="$uki" \
    UKI_NAME=omarchy_linux.efi \
    LIMINE_CONFIG="$limine_config" \
    REAL_OBJCOPY="$(command -v objcopy)" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-update-verify-boot"
}

make_uki 6.1.0-test
write_limine_config
run_verifier >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a current UKI is rejected" "$(<"$test_tmp/err")"
[[ ! -s $calls ]] || fail "a current UKI is rebuilt"
pass "a current UKI reaches restart without a rebuild"

printf '  path: boot():/EFI/Linux/omarchy_linux.efi\n' >"$limine_config"
run_verifier >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a current UKI without Limine file verification is rejected" "$(<"$test_tmp/err")"
[[ ! -s $calls ]] || fail "a current UKI without a Limine hash is rebuilt"
pass "a current UKI remains valid when Limine file verification is disabled"

make_uki 6.0.9-old
write_limine_config
REPAIR_MODE=image run_verifier >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a stale UKI is not repaired"
grep -Fxq limine-mkinitcpio "$calls" || fail "a stale UKI does not trigger one rebuild"
[[ $(objcopy --dump-section .uname=/dev/stdout "$uki") == "6.1.0-test" ]] ||
  fail "the repair leaves the old kernel in the UKI"
pass "a stale UKI is rebuilt before restart"

: >"$calls"
write_limine_config deadbeef
REPAIR_MODE=hash run_verifier >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a stale Limine hash is not repaired"
grep -Fxq limine-mkinitcpio "$calls" || fail "a stale Limine hash does not trigger one rebuild"
grep -Fq "#$(b2sum "$uki" | awk '{ print $1 }')" "$limine_config" ||
  fail "the repair leaves Limine pointing at the wrong UKI hash"
pass "a stale Limine hash is rebuilt before restart"

: >"$calls"
make_uki 6.0.9-old
write_limine_config
if REPAIR_MODE=fail run_verifier >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "an unrepaired stale UKI permits a restart"
fi
[[ $(wc -l <"$calls") == 1 ]] || fail "an unsafe UKI rebuild loops"
grep -q 'Do not reboot' "$test_tmp/err" || fail "an unsafe UKI does not explain the recovery boundary"
grep -q 'expected 6.1.0-test' "$test_tmp/err" || fail "an unsafe UKI does not identify the mismatch"
pass "an unrepaired UKI stops the update with an actionable error"

# kernel-modules-hook preserves the running kernel when its package is replaced.
# Limine ignores that unowned module tree, so it must not create a false alarm.
mkdir -p "$modules/5.15-preserved"
printf '%s\n' linux-old >"$modules/5.15-preserved/pkgbase"
make_uki 6.1.0-test
write_limine_config
: >"$calls"
run_verifier >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "an unowned preserved kernel is treated as installed"
[[ ! -s $calls ]] || fail "an unowned preserved kernel triggers a rebuild"
pass "a kernel preserved outside pacman ownership is ignored"

# The analyzer is the last update step before status and restart. Pin the call
# so a failed live verification becomes the update's exit status.
analyzer_stub="$test_tmp/analyzer-bin"
mkdir -p "$analyzer_stub"
cat >"$analyzer_stub/omarchy-update-verify-boot" <<'SH'
#!/bin/bash
exit 23
SH
chmod +x "$analyzer_stub/omarchy-update-verify-boot"
: >"$test_tmp/update.log"
if OMARCHY_UPDATE_LOG="$test_tmp/update.log" PATH="$analyzer_stub:$PATH" \
  bash "$ROOT/bin/omarchy-update-analyze-logs"; then
  fail "boot verification cannot stop an update before restart"
fi
pass "failed boot verification stops the update before restart"
