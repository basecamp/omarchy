#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
lsblk_log="$test_tmp/lsblk-args"
mkdir -p "$mock_bin"

cat >"$mock_bin/lsblk" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >"$LSBLK_LOG"
printf '%s\n' "$ROOT_TYPE"
SH
chmod +x "$mock_bin/lsblk"

boot_auth="$ROOT/bin/omarchy-hibernation-boot-auth"
encrypted_cmdline='cryptdevice=UUID=abcd:omarchy_root root=/dev/mapper/omarchy_root resume=/dev/mapper/omarchy_root'

ROOT_TYPE=crypt LSBLK_LOG="$lsblk_log" PATH="$mock_bin:$PATH" \
  "$boot_auth" '/dev/mapper/omarchy_root[/@]' "$encrypted_cmdline" ||
  fail "encrypted hibernate uses interactive boot authentication"
pass "encrypted hibernate uses interactive boot authentication"

grep -F -- '/dev/mapper/omarchy_root' "$lsblk_log" >/dev/null ||
  fail "boot authentication strips the Btrfs subvolume from the root device"
if grep -F -- '[/@]' "$lsblk_log" >/dev/null; then
  fail "boot authentication strips the Btrfs subvolume from the root device"
fi
pass "boot authentication strips the Btrfs subvolume from the root device"

if ROOT_TYPE=part LSBLK_LOG="$lsblk_log" PATH="$mock_bin:$PATH" \
  "$boot_auth" /dev/nvme0n1p2 "$encrypted_cmdline"; then
  fail "unencrypted hibernate keeps the session lock"
fi
pass "unencrypted hibernate keeps the session lock"

if ROOT_TYPE=crypt LSBLK_LOG="$lsblk_log" PATH="$mock_bin:$PATH" \
  "$boot_auth" /dev/mapper/omarchy_root "$encrypted_cmdline cryptkey=rootfs:/crypto_keyfile.bin"; then
  fail "keyfile-backed hibernate keeps the session lock"
fi
pass "keyfile-backed hibernate keeps the session lock"

if ROOT_TYPE=crypt LSBLK_LOG="$lsblk_log" PATH="$mock_bin:$PATH" \
  "$boot_auth" /dev/mapper/omarchy_root 'rd.luks.name=abcd=omarchy_root root=/dev/mapper/omarchy_root'; then
  fail "custom encrypted boot paths keep the session lock"
fi
pass "custom encrypted boot paths keep the session lock"
