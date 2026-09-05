#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

wrapper="$ROOT/default/initcpio/cryptsetup-wrapper"
dropin="$ROOT/default/initcpio/zz-omarchy-duress.conf"
setup="$ROOT/bin/omarchy-setup-security-duress"
reset="$ROOT/bin/omarchy-system-factory-reset"
unit="$ROOT/install/provisioning/omarchy-system-duress-wipe.service"

[[ -x $wrapper ]] || chmod +x "$wrapper"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/cryptsetup" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_CALLS"
cat >"$TEST_STDIN" 2>/dev/null || true

if [[ $1 == token && $2 == export ]]; then
  token_id=""
  prev=""
  for arg in "$@"; do
    [[ $prev == --token-id ]] && token_id=$arg
    prev=$arg
  done
  [[ $token_id == 0 ]] || exit 1
  printf '%s\n' '{
  "type": "luks2",
  "keyslots": [
    "1"
  ]
}'
  exit 0
fi

if [[ $* == *luksDump* ]]; then
  cat <<'DUMP'
Keyslots:
  0: luks2
        Key:        512 bits
  1: luks2
        Key:        512 bits
DUMP
  exit 0
fi

if [[ $* == *luksKillSlot* ]]; then
  exit 0
fi

if [[ $* == *--test-passphrase* && $* == *--key-slot* ]]; then
  pw=$(cat "$TEST_STDIN" 2>/dev/null || true)
  [[ $pw == "duress-secret" ]] && exit 0
  exit 1
fi

if [[ $* == *open* ]]; then
  exit 0
fi

exit 0
EOF
chmod +x "$tmp_dir/cryptsetup"

run_wrapper() {
  local password=$1
  shift
  mkdir -p "$tmp_dir/run"
  : >"$TEST_CALLS"
  printf '%s' "$password" | \
    OMARCHY_CRYPTSETUP="$tmp_dir/cryptsetup" \
    OMARCHY_DURESS_RUN_DIR="$tmp_dir/run" \
    bash "$wrapper" "$@"
}

export TEST_CALLS="$tmp_dir/calls.log"
export TEST_STDIN="$tmp_dir/stdin"

rm -rf "$tmp_dir/run"
mkdir -p "$tmp_dir/run"
run_wrapper "real-secret" open --type luks --key-file=- /dev/fake-luks root
[[ ! -e $tmp_dir/run/omarchy-duress ]] || fail "a real passphrase does not arm duress"
grep -q 'open --type luks --key-file=- /dev/fake-luks root' "$TEST_CALLS" ||
  fail "wrapper passes a normal open through to cryptsetup"
pass "a real passphrase unlocks without arming duress"

rm -rf "$tmp_dir/run"
mkdir -p "$tmp_dir/run"
: >"$TEST_CALLS"
run_wrapper "duress-secret" open --type luks --key-file=- /dev/fake-luks root
[[ -f $tmp_dir/run/omarchy-duress ]] || fail "a duress passphrase arms the pending marker"
[[ $(cat "$tmp_dir/run/omarchy-duress-key") == "duress-secret" ]] ||
  fail "duress keyfile stores the passphrase without a trailing newline"
grep -q 'luksKillSlot' "$TEST_CALLS" || fail "duress open kills the other LUKS slots"
grep -q 'token remove' "$TEST_CALLS" || fail "duress open removes the duress LUKS token"
pass "a duress passphrase arms wipe and kills the real keyslot"

: >"$TEST_CALLS"
OMARCHY_CRYPTSETUP="$tmp_dir/cryptsetup" bash "$wrapper" luksDump /dev/fake-luks >/dev/null
grep -qx 'luksDump /dev/fake-luks' "$TEST_CALLS" || fail "non-open cryptsetup commands pass through"
pass "non-open cryptsetup commands are not intercepted"

: >"$TEST_CALLS"
OMARCHY_CRYPTSETUP="$tmp_dir/cryptsetup" bash "$wrapper" --key-file /crypto_keyfile.bin open --type luks /dev/fake-luks root
[[ ! -e $tmp_dir/run/omarchy-duress ]] || true
grep -q -- '--key-file /crypto_keyfile.bin open' "$TEST_CALLS" ||
  fail "keyfile unlocks pass through without reading stdin as a passphrase"
pass "keyfile unlocks are not treated as duress"

hooks=$(bash -c 'HOOKS=(base udev plymouth encrypt filesystems); source "$1"; echo "${HOOKS[*]}"' bash "$dropin")
[[ $hooks == "base udev plymouth encrypt omarchy-duress filesystems" ]] ||
  fail "mkinitcpio drop-in inserts omarchy-duress after encrypt" "got: $hooks"
pass "mkinitcpio drop-in inserts omarchy-duress after encrypt"

hooks=$(bash -c 'HOOKS=(base encrypt omarchy-duress filesystems); source "$1"; echo "${HOOKS[*]}"' bash "$dropin")
[[ $hooks == "base encrypt omarchy-duress filesystems" ]] ||
  fail "mkinitcpio drop-in is idempotent" "got: $hooks"
pass "mkinitcpio drop-in is idempotent"

grep -q 'unattended factory reset must run as root' "$reset" ||
  fail "unattended reset refuses to sudo"
grep -q 'unattended reset requires a duress pending marker' "$reset" ||
  fail "unattended reset requires duress-pending"
grep -q 'ExecStart=/usr/bin/omarchy-system-factory-reset --unattended' "$unit" ||
  fail "duress unit runs factory reset unattended"
grep -q 'Before=.*home.mount' "$unit" || fail "duress unit runs before home.mount"
grep -q 'Before=.*sddm.service' "$unit" || fail "duress unit runs before sddm"
pass "unattended reset is root-only, marker-gated, and starts before the session"

if "$reset" --unattended >/dev/null 2>"$tmp_dir/unattended.err"; then
  fail "unattended reset as a user does not succeed"
fi
grep -q 'must run as root' "$tmp_dir/unattended.err" ||
  fail "unattended reset as a user says it must run as root" "$(cat "$tmp_dir/unattended.err")"
pass "unattended reset as a user fails without elevating"

grep -q "Type 'wipe' to continue" "$setup" || fail "enroll confirms with wipe"
grep -q 'token add --key-slot' "$setup" || fail "enroll writes a generic luks2 token"
if grep -q '{"type":"omarchy-duress"' "$setup"; then
  fail "enroll must not write a custom omarchy-duress token type"
fi
grep -q 'omarchy-duress' "$setup" || fail "setup still recognizes leftover omarchy-duress tokens"
grep -q -- '--change' "$setup" || fail "setup can change an enrolled duress password"
grep -q -- '--refresh-boot' "$setup" || fail "setup can refresh boot files after a package update"
grep -q 'convert_legacy_duress_tokens' "$setup" || fail "refresh-boot converts leftover omarchy-duress tokens"
grep -q 'write_duress_owner' "$setup" || fail "enroll stores a post-wipe owner identity"
if grep -q -- '--arg password' "$setup"; then
  fail "duress-owner must not store the passphrase"
fi
grep -q 'duress-owner' "$reset" || fail "unattended reset copies the post-wipe owner identity"
grep -q 'duress-key' "$reset" || fail "unattended reset copies the duress keyfile onto the factory clone"
grep -q 'shred -u' "$reset" || fail "unattended reset shreds the live duress keyfile after swap"
grep -q 'load_duress_owner' "$ROOT/bin/omarchy-provision-owner" ||
  fail "first-boot setup can skip the wizard after a duress wipe"
grep -q 'duress-key' "$ROOT/bin/omarchy-provision-owner" ||
  fail "silent provision reads the account password from duress-key"
grep -q -- '--silent' "$ROOT/bin/omarchy-provision-owner" ||
  fail "duress post-wipe setup can run without a tty"
grep -q 'omarchy-provision-duress.service' "$reset" ||
  fail "unattended reset arms silent post-wipe setup"
grep -q 'systemctl soft-reboot' "$reset" ||
  fail "unattended reset prefers a userspace switch over a firmware reboot"
grep -q 'skip-welcome' "$ROOT/bin/omarchy-provision-owner" ||
  fail "duress decoy account suppresses the first-run keybindings toast"
grep -q 'skip-welcome' "$ROOT/install/user/first-run/welcome.sh" ||
  fail "welcome notification honors skip-welcome"
grep -q 'timeout: 0' "$reset" ||
  fail "unattended reset hides the Limine menu if it does reboot"
grep -q 'omarchy-duress' "$wrapper" || fail "wrapper still recognizes leftover omarchy-duress tokens"
pass "duress setup confirms with wipe and enrolls a LUKS token"

if grep -qw tr "$wrapper"; then
  fail "wrapper must not call tr; initramfs busybox does not ship that applet"
fi
pass "wrapper stays within initramfs busybox applets"
