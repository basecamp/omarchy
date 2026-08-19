#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

dns="$ROOT/bin/omarchy-dns"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-dns"
rule='%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-dns Cloudflare, /usr/bin/omarchy-dns Google, /usr/bin/omarchy-dns DHCP'

# Exactly one rule, matched whole. A second line -- or the same command with its
# arguments dropped, which sudoers reads as "any arguments" -- would widen the
# grant while leaving this line in place.
rules=$(grep -vE '^[[:space:]]*(#|$)' "$sudoers_file")
[[ $rules == "$rule" ]] ||
  fail "dns sudoers file carries exactly the stock-provider rule and nothing else" "got: $rules"

if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null || fail "dns sudoers rule parses"
fi

grep -Fx 'PACKAGED_PATH=/usr/bin/omarchy-dns' "$dns" >/dev/null ||
  fail "omarchy-dns elevates the path the sudoers rule names"

# sudo -l answers whether a command is permitted, not whether it is
# passwordless, and Omarchy ships a blanket %wheel rule that permits
# everything. A probe built on it sends Custom into `sudo -n`, which fails
# outright instead of falling through to pkexec.
! grep -E '^[[:space:]]*[^#[:space:]].*sudo -n -l' "$dns" >/dev/null ||
  fail "omarchy-dns does not decide elevation with a sudo -l probe"

pass "dns sudoers rule is scoped to the stock providers"

# require_root returns immediately for root, so the stubs below would not stand
# between the script and the host's real NetworkManager and resolved config.
if (( EUID == 0 )); then
  pass "running as root; skipping the elevation checks, which would rewrite this machine's DNS"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# Both stubs stand in for the exec at the end of require_root, so the DNS writes
# below it never run, and neither real sudo nor real pkexec is reached.
for command in sudo pkexec; do
  cat >"$stub_bin/$command" <<SH
#!/bin/bash
printf '$command %s\n' "\$*" >"\$ELEVATION_LOG"
SH
  chmod +x "$stub_bin/$command"
done

# The rule is %wheel-scoped, so group membership decides the route as much as
# the provider does. Stub id rather than reading the real groups: the suite has
# to give the same answer on a build user outside wheel.
cat >"$stub_bin/id" <<'SH'
#!/bin/bash
[[ ${1:-} == -nG ]] || exec /usr/bin/id "$@"
printf '%s\n' "${STUB_GROUPS-users wheel}"
SH
chmod +x "$stub_bin/id"

elevation_for() {
  : >"$test_tmp/elevation"
  ELEVATION_LOG="$test_tmp/elevation" \
  PATH="$stub_bin:$PATH" \
    bash "$dns" "$1" </dev/null >/dev/null
  cat "$test_tmp/elevation"
}

for provider in Cloudflare Google DHCP; do
  elevation=$(elevation_for "$provider")
  [[ $elevation == "sudo /usr/bin/omarchy-dns $provider" ]] ||
    fail "omarchy-dns takes the passwordless sudo grant for $provider without a terminal" "got: $elevation"
done

pass "omarchy-dns elevates the stock providers through sudo, not polkit"

# A dev-linked checkout elevates the packaged path like everyone else, rather
# than handing sudo a path no rule can name and losing the grant.
dev_linked=$(OMARCHY_PATH="$test_tmp/checkout" elevation_for Cloudflare)
[[ $dev_linked == "sudo /usr/bin/omarchy-dns Cloudflare" ]] ||
  fail "omarchy-dns elevates the system install wherever OMARCHY_PATH points" "got: $dev_linked"

custom=$(elevation_for Custom)
[[ $custom == "pkexec /usr/bin/omarchy-dns Custom" ]] ||
  fail "omarchy-dns leaves Custom on the polkit path, since no sudoers rule covers it" "got: $custom"

non_wheel=$(STUB_GROUPS="users" elevation_for Cloudflare)
[[ $non_wheel == "pkexec /usr/bin/omarchy-dns Cloudflare" ]] ||
  fail "omarchy-dns leaves a user outside %wheel on the polkit path, since the rule cannot match them" "got: $non_wheel"

pass "omarchy-dns falls back to polkit wherever the grant does not reach"
