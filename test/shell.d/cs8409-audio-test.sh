#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hw="$ROOT/bin/omarchy-hw-apple-cs8409"
fix="$ROOT/install/hardware/apple/fix-cs8409-audio.sh"
migration="$ROOT/migrations/1786889011.sh"
manual="$ROOT/manual/44-mac-support.md"

assert_hw() {
  local model=$1 expect=$2 description=$3
  local tmp got
  tmp=$(mktemp)
  printf '%s\n' "$model" >"$tmp"
  if OMARCHY_DMI_PRODUCT_NAME="$tmp" "$hw"; then
    got=yes
  else
    got=no
  fi
  rm -f "$tmp"
  [[ $got == "$expect" ]] || fail "$description"
  pass "$description"
}

assert_hw MacBookPro14,3 yes "MacBookPro14,3 has CS8409 audio"
assert_hw MacBookPro14,2 yes "MacBookPro14,2 has CS8409 audio"
assert_hw MacBookPro14,1 yes "MacBookPro14,1 has CS8409 audio"
assert_hw MacBookPro13,3 yes "MacBookPro13,3 has CS8409 audio"
assert_hw MacBookPro13,2 yes "MacBookPro13,2 has CS8409 audio"
assert_hw MacBookPro13,1 yes "MacBookPro13,1 has CS8409 audio"
assert_hw MacBookPro15,1 no "MacBookPro15,1 is T2, not CS8409"
assert_hw MacBook8,1 no "MacBook8,1 is SPI-only"

grep -Fq 'fix-cs8409-audio.sh' "$ROOT/install/hardware/all.sh" ||
  fail "hardware install runs the CS8409 hook"
pass "CS8409 install hook is wired"

grep -Fq 'snd-hda-macbookpro-dkms' "$fix" ||
  fail "install hook names the omarchy-pkgs package"
grep -Fq 'omarchy-hw-apple-cs8409' "$fix" ||
  fail "install hook is gated on CS8409 detection"
pass "install hook installs snd-hda-macbookpro-dkms"

grep -Fq 'snd-hda-macbookpro-dkms' "$manual" ||
  fail "Mac support chapter names the CS8409 package"
! grep -q 'Sound is not functioning' "$manual" ||
  fail "Mac support chapter no longer lists speakers as unsupported"
pass "Mac support chapter documents CS8409 speakers"

[[ -f $migration ]] || fail "CS8409 migration exists"
grep -Fq 'omarchy-hw-apple-cs8409' "$migration" ||
  fail "migration is gated on CS8409 detection"
grep -Fq 'snd-hda-macbookpro-dkms' "$migration" ||
  fail "migration installs the CS8409 package"
! head -1 "$migration" | grep -q '^#!' ||
  fail "migration has no shebang"
pass "migration installs the driver on CS8409 hardware only"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'omarchy-pkg-add' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH
chmod +x "$stub_bin/omarchy-pkg-add"

dmi="$test_tmp/dmi"
printf 'MacBookPro14,1\n' >"$dmi"
PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  bash -c 'source "$1"' _ "$fix"
grep -Fq $'omarchy-pkg-add\tlinux-headers\tsnd-hda-macbookpro-dkms' "$calls" ||
  fail "install hook adds headers and the CS8409 package on a two-port 13-inch"
pass "install hook runs on MacBookPro14,1 (CS8409, no Touch Bar)"

: >"$calls"
printf 'MacBookPro15,1\n' >"$dmi"
PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$ROOT/install" \
  bash -c 'source "$1"' _ "$fix"
[[ ! -s $calls ]] || fail "T2 hardware skips the CS8409 package" "$(cat "$calls")"
pass "install hook skips T2 hardware"

: >"$calls"
printf 'MacBookPro14,3\n' >"$dmi"
PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  bash -euo pipefail "$migration" >/dev/null
grep -Fq $'omarchy-pkg-add\tlinux-headers\tsnd-hda-macbookpro-dkms' "$calls" ||
  fail "migration installs the CS8409 package on a 15-inch T1"
pass "migration installs the driver on MacBookPro14,3"

: >"$calls"
printf 'MacBookPro16,1\n' >"$dmi"
PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_LOG="$calls" \
  OMARCHY_DMI_PRODUCT_NAME="$dmi" \
  bash -euo pipefail "$migration" >/dev/null
[[ ! -s $calls ]] || fail "migration skips non-CS8409 hardware" "$(cat "$calls")"
pass "migration skips non-CS8409 hardware"
