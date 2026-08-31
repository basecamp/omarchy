#!/bin/bash

set -euo pipefail

# omarchy-drive-password must discover crypto_LUKS devices without root.
# The desktop menu launches it unprivileged; blkid -t TYPE=crypto_LUKS cannot
# probe headers as a normal user and reported "No encrypted drives available"
# on every LUKS install (issue #9384).

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -r "$tmp_dir"' EXIT

cat >"$tmp_dir/lsblk" <<'EOF'
#!/bin/bash
# Default: one LUKS device. Override via OMARCHY_TEST_LSBLK_OUT.
if [[ -n ${OMARCHY_TEST_LSBLK_OUT+x} ]]; then
  printf '%s' "$OMARCHY_TEST_LSBLK_OUT"
  exit 0
fi
printf '%s\n' '/dev/test-luks crypto_LUKS'
EOF

# blkid must not be consulted — if the script regresses to it, fail loudly.
cat >"$tmp_dir/blkid" <<'EOF'
#!/bin/bash
echo "blkid should not be used for LUKS discovery" >&2
exit 99
EOF

cat >"$tmp_dir/gum" <<'EOF'
#!/bin/bash
head -n 1 "$TEST_INPUTS"
sed -i '1d' "$TEST_INPUTS"
EOF

cat >"$tmp_dir/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_ARGS"
cat >"$TEST_STDIN"
EOF

cat >"$tmp_dir/omarchy-drive-select" <<'EOF'
#!/bin/bash
# Echo the second device from the multi-drive list the script passes through.
printf '%s\n' "$1" | awk 'NR == 2 { print; exit }'
EOF

chmod +x "$tmp_dir/lsblk" "$tmp_dir/blkid" "$tmp_dir/gum" "$tmp_dir/sudo" "$tmp_dir/omarchy-drive-select"
export PATH="$tmp_dir:$ROOT/bin:$PATH"
export TEST_ARGS="$tmp_dir/args" TEST_INPUTS="$tmp_dir/inputs" TEST_STDIN="$tmp_dir/stdin"

# --- empty passphrase rejected, no cryptsetup --------------------------------
rm -f "$TEST_ARGS" "$TEST_STDIN"
printf '\n' >"$TEST_INPUTS"
if "$ROOT/bin/omarchy-drive-password" >/dev/null; then
  fail "drive password rejects an empty passphrase"
fi
[[ ! -e $TEST_ARGS ]] || fail "drive password does not run cryptsetup for an empty passphrase"
pass "drive password rejects an empty passphrase"

# --- mismatched confirmation rejected ----------------------------------------
rm -f "$TEST_ARGS" "$TEST_STDIN"
printf 'secret123\n*\n' >"$TEST_INPUTS"
if "$ROOT/bin/omarchy-drive-password" >/dev/null; then
  fail "drive password rejects a mismatched confirmation"
fi
[[ ! -e $TEST_ARGS ]] || fail "drive password does not run cryptsetup for a mismatched confirmation"
pass "drive password rejects a mismatched confirmation"

# --- happy path: single LUKS device via lsblk --------------------------------
rm -f "$TEST_ARGS" "$TEST_STDIN"
printf 'new password\nnew password\n' >"$TEST_INPUTS"
"$ROOT/bin/omarchy-drive-password" >/dev/null

[[ $(<"$TEST_STDIN") == "new password" ]] || fail "drive password passes the validated passphrase without a newline"
grep -F 'cryptsetup luksChangeKey' "$TEST_ARGS" >/dev/null || fail "drive password changes the LUKS key"
grep -Fx /dev/test-luks "$TEST_ARGS" >/dev/null || fail "drive password targets the selected drive"
pass "drive password discovers a single LUKS device via lsblk and passes validated input to cryptsetup"

# --- no LUKS devices: message + exit 1, never touch blkid --------------------
rm -f "$TEST_ARGS" "$TEST_STDIN"
export OMARCHY_TEST_LSBLK_OUT=""
out=$("$ROOT/bin/omarchy-drive-password" 2>&1) && rc=0 || rc=$?
unset OMARCHY_TEST_LSBLK_OUT
(( rc == 1 )) || fail "no LUKS devices exits 1" "rc=$rc out=$out"
[[ $out == *"No encrypted drives available."* ]] || fail "no LUKS devices prints the expected message" "$out"
[[ ! -e $TEST_ARGS ]] || fail "no LUKS devices does not run cryptsetup"
pass "drive password reports no encrypted drives when lsblk finds none"

# --- multi-device: select path, still no blkid --------------------------------
rm -f "$TEST_ARGS" "$TEST_STDIN"
export OMARCHY_TEST_LSBLK_OUT=$'/dev/nvme0n1p2 crypto_LUKS\n/dev/sda3 crypto_LUKS\n'
printf 'chosen\nchosen\n' >"$TEST_INPUTS"
"$ROOT/bin/omarchy-drive-password" >/dev/null
unset OMARCHY_TEST_LSBLK_OUT
grep -Fx /dev/sda3 "$TEST_ARGS" >/dev/null || fail "multi-device path uses the selected LUKS device" "$(cat "$TEST_ARGS" 2>/dev/null || true)"
grep -F 'cryptsetup luksChangeKey' "$TEST_ARGS" >/dev/null || fail "multi-device path still changes the LUKS key"
pass "drive password offers a chooser when lsblk reports multiple LUKS devices"

# --- non-LUKS rows are ignored -----------------------------------------------
rm -f "$TEST_ARGS" "$TEST_STDIN"
export OMARCHY_TEST_LSBLK_OUT=$'/dev/sda1 vfat\n/dev/sda2 ext4\n/dev/sda3 crypto_LUKS\n/dev/sdb1 xfs\n'
printf 'only\nonly\n' >"$TEST_INPUTS"
"$ROOT/bin/omarchy-drive-password" >/dev/null
unset OMARCHY_TEST_LSBLK_OUT
grep -Fx /dev/sda3 "$TEST_ARGS" >/dev/null || fail "only crypto_LUKS rows are candidates" "$(cat "$TEST_ARGS" 2>/dev/null || true)"
pass "drive password ignores non-LUKS lsblk rows"

# --- stock blkid regression guard: script source must not call blkid ---------
if grep -E -q '^[^#]*\bblkid\b' "$ROOT/bin/omarchy-drive-password"; then
  fail "omarchy-drive-password must not call blkid for discovery"
fi
pass "omarchy-drive-password discovers LUKS via lsblk, not blkid"
