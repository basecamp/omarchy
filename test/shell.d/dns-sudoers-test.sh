#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

dns="$ROOT/bin/omarchy-dns"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-dns"
rule='%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-dns Cloudflare, /usr/bin/omarchy-dns Google, /usr/bin/omarchy-dns DHCP'

grep -Fx "$rule" "$sudoers_file" >/dev/null ||
  fail "dns sudoers rule grants exactly the stock providers passwordlessly"

! grep -F 'omarchy-dns Custom' "$sudoers_file" >/dev/null ||
  fail "dns sudoers rule does not grant Custom, which takes caller-supplied servers"

if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null || fail "dns sudoers rule parses"
fi

grep -Fx 'PACKAGED_PATH=/usr/bin/omarchy-dns' "$dns" >/dev/null ||
  fail "omarchy-dns compares against the path the sudoers rule names"

# sudo -l answers whether a command is permitted, not whether it is
# passwordless, and Omarchy ships a blanket %wheel rule that permits
# everything. A probe built on it sends Custom into `sudo -n`, which fails
# outright instead of falling through to pkexec.
! grep -E '^[[:space:]]*[^#[:space:]].*sudo -n -l' "$dns" >/dev/null ||
  fail "omarchy-dns does not decide elevation with a sudo -l probe"

grep -Fx '    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin' "$dns" >/dev/null ||
  fail "omarchy-dns pins a root-owned PATH once elevated, so a dev-linked checkout on sudo's secure_path cannot supply its helpers"

pass "dns sudoers rule is scoped to the stock providers"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# Both stubs stand in for the exec at the end of require_root, so the DNS
# writes below it never run, and neither real sudo nor real pkexec is reached.
for command in sudo pkexec; do
  cat >"$stub_bin/$command" <<SH
#!/bin/bash
printf '$command %s\n' "\$*" >"\$ELEVATION_LOG"
SH
  chmod +x "$stub_bin/$command"
done

# self_path canonicalizes \$OMARCHY_PATH/bin/omarchy-dns, which is how the
# script decides whether the sudoers rule can name it. On a packaged install
# that link lands on /usr/bin/omarchy-dns; a dev-linked checkout stays inside
# the checkout, where no rule covers it.
mkdir -p "$test_tmp/packaged/bin" "$test_tmp/checkout/bin"
ln -sfn /usr/bin/omarchy-dns "$test_tmp/packaged/bin/omarchy-dns"
cp "$dns" "$test_tmp/checkout/bin/omarchy-dns"

elevation_for() {
  local omarchy_path="$1"
  local provider="$2"

  : >"$test_tmp/elevation"
  ELEVATION_LOG="$test_tmp/elevation" \
  OMARCHY_PATH="$omarchy_path" \
  PATH="$stub_bin:$PATH" \
    bash "$dns" "$provider" </dev/null >/dev/null
  cat "$test_tmp/elevation"
}

for provider in Cloudflare Google DHCP; do
  elevation=$(elevation_for "$test_tmp/packaged" "$provider")
  [[ $elevation == "sudo /usr/bin/omarchy-dns $provider" ]] ||
    fail "omarchy-dns takes the passwordless sudo grant for $provider without a terminal" "got: $elevation"
done

pass "omarchy-dns elevates the stock providers through sudo, not polkit"

custom=$(elevation_for "$test_tmp/packaged" Custom)
[[ $custom == "pkexec /usr/bin/omarchy-dns Custom" ]] ||
  fail "omarchy-dns leaves Custom on the polkit path, since no sudoers rule covers it" "got: $custom"

dev_linked=$(elevation_for "$test_tmp/checkout" Cloudflare)
[[ $dev_linked == "pkexec $test_tmp/checkout/bin/omarchy-dns Cloudflare" ]] ||
  fail "omarchy-dns falls back to polkit where the sudoers rule cannot name the script" "got: $dev_linked"

pass "omarchy-dns falls back to polkit wherever the grant does not reach"
