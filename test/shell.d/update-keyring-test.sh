#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# omarchy-update-keyring fetches the Omarchy key from a keyserver when it is
# missing and refreshes archlinux-keyring. Apple Silicon differs on both counts:
# the key ships with the installed system, so a missing or mismatched key is a
# hard failure rather than a fetch, and packages are signed with Arch Linux
# ARM's keys, so it is archlinuxarm-keyring that needs refreshing.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
calls="$test_tmp/calls"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

# Every privileged tool logs its argv so the cases can assert what ran.
for tool in pacman-key pacman omarchy-pkg-add; do
  cat >"$stub_bin/$tool" <<STUB
#!/bin/bash
printf '%s %s\\n' "$tool" "\$*" >>"\$CALLS"
if [[ $tool == pacman-key && \$1 == --list-keys ]]; then
  [[ \${KEY_IN_PACMAN_KEYRING:-0} == 1 ]]
fi
STUB
done

# gpg answers the Apple Silicon fingerprint check with whatever the case says
# the installed keyring holds, in the --with-colons format the script parses.
cat >"$stub_bin/gpg" <<'STUB'
#!/bin/bash
printf 'gpg %s\n' "$*" >>"$CALLS"
[[ -n ${INSTALLED_FINGERPRINT:-} ]] || exit 2
printf 'pub:u:4096:1:%s::::::::\n' "${INSTALLED_FINGERPRINT: -16}"
printf 'fpr:::::::::%s:\n' "$INSTALLED_FINGERPRINT"
STUB

cat >"$stub_bin/omarchy-pkg-missing" <<'STUB'
#!/bin/bash
[[ ${KEYRING_PKG_MISSING:-0} == 1 ]]
STUB

cat >"$stub_bin/omarchy-hw-apple-silicon" <<'STUB'
#!/bin/bash
[[ ${APPLE_SILICON:-0} == 1 ]]
STUB

chmod +x "$stub_bin"/*

trusted_key=40DFB630FF42BCFFB047046CF0134EE680CAC571

run_keyring() {
  : >"$calls"
  CALLS="$calls" \
    APPLE_SILICON="${APPLE_SILICON:-0}" \
    INSTALLED_FINGERPRINT="${INSTALLED_FINGERPRINT:-}" \
    KEY_IN_PACMAN_KEYRING="${KEY_IN_PACMAN_KEYRING:-0}" \
    KEYRING_PKG_MISSING="${KEYRING_PKG_MISSING:-0}" \
    PATH="$stub_bin:$PATH" \
    bash "$ROOT/bin/omarchy-update-keyring"
}

# Apple Silicon with the shipped key in place: nothing fetched, ARM keyring refreshed.
APPLE_SILICON=1 INSTALLED_FINGERPRINT="$trusted_key" run_keyring >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "an Apple Silicon system with the shipped key fails the keyring update" "$(<"$test_tmp/err")"
grep -q '^pacman -Sy --noconfirm archlinuxarm-keyring$' "$calls" ||
  fail "Apple Silicon does not refresh archlinuxarm-keyring"
grep -q 'archlinux-keyring$' "$calls" &&
  fail "Apple Silicon refreshes archlinux-keyring, which does not sign its packages"
grep -q -- '--recv-keys' "$calls" &&
  fail "Apple Silicon fetches the Omarchy key from a keyserver"
pass "Apple Silicon verifies the shipped key and refreshes archlinuxarm-keyring"

# A mismatched fingerprint on Apple Silicon is not something to paper over
# with a keyserver fetch: stop, and say where the key is supposed to come from.
if APPLE_SILICON=1 INSTALLED_FINGERPRINT=0000000000000000000000000000000000000000 \
  run_keyring >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a wrong Omarchy key on Apple Silicon is accepted"
fi
grep -q -- '--recv-keys' "$calls" &&
  fail "a wrong Omarchy key on Apple Silicon is replaced from a keyserver"
grep -q 'archlinuxarm-keyring' "$calls" &&
  fail "a wrong Omarchy key on Apple Silicon still proceeds to the keyring refresh"
grep -q 'omarchy-keyring' "$test_tmp/err" ||
  fail "a wrong Omarchy key on Apple Silicon does not point at omarchy-keyring"
pass "a wrong Omarchy key on Apple Silicon fails loudly instead of fetching"

# The same for the key being absent entirely.
if APPLE_SILICON=1 run_keyring >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a missing Omarchy key on Apple Silicon is accepted"
fi
grep -q -- '--recv-keys' "$calls" &&
  fail "a missing Omarchy key on Apple Silicon is fetched from a keyserver"
pass "a missing Omarchy key on Apple Silicon fails loudly instead of fetching"

# A missing omarchy-keyring package is caught even when the key itself checks out.
if APPLE_SILICON=1 INSTALLED_FINGERPRINT="$trusted_key" KEYRING_PKG_MISSING=1 \
  run_keyring >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a missing omarchy-keyring package on Apple Silicon is accepted"
fi
pass "a missing omarchy-keyring package on Apple Silicon fails loudly"

# Other hardware keeps the keyserver path and archlinux-keyring.
KEY_IN_PACMAN_KEYRING=1 run_keyring >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a system with the Omarchy key fails the keyring update" "$(<"$test_tmp/err")"
grep -q '^pacman -Sy --noconfirm archlinux-keyring$' "$calls" ||
  fail "other hardware does not refresh archlinux-keyring"
grep -q -- '--recv-keys' "$calls" &&
  fail "other hardware fetches a key it already has"
grep -q '^gpg ' "$calls" &&
  fail "other hardware runs the Apple Silicon fingerprint check"
pass "other hardware refreshes archlinux-keyring without fetching a present key"

run_keyring >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a system without the Omarchy key fails the keyring update" "$(<"$test_tmp/err")"
grep -q "^pacman-key --recv-keys $trusted_key --keyserver keys.openpgp.org$" "$calls" ||
  fail "other hardware does not fetch a missing Omarchy key from the keyserver"
grep -q "^pacman-key --lsign-key $trusted_key$" "$calls" ||
  fail "other hardware does not locally sign the fetched Omarchy key"
grep -q '^omarchy-pkg-add omarchy-keyring$' "$calls" ||
  fail "other hardware does not install omarchy-keyring after fetching the key"
pass "other hardware still fetches a missing Omarchy key from the keyserver"
