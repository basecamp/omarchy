#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

dns="$ROOT/bin/omarchy-dns"
sudoers_file="$ROOT/etc/sudoers.d/omarchy-dns"

grep -F '%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-dns Cloudflare, /usr/bin/omarchy-dns Google, /usr/bin/omarchy-dns DHCP' \
  "$sudoers_file" >/dev/null ||
  fail "dns sudoers rule grants the stock providers passwordlessly"

! grep -F 'omarchy-dns Custom' "$sudoers_file" >/dev/null ||
  fail "dns sudoers rule does not grant Custom, which takes caller-supplied servers"

if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null ||
    fail "dns sudoers rule parses"
fi

pass "dns sudoers rule is scoped to the stock providers"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# Both stubs stand in for the exec at the end of require_root, so the DNS
# writes below it never run. `sudo -n -l` is the grant probe: it succeeds only
# when SUDO_GRANTED is set, which is how a machine without the sudoers file
# installed is simulated.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ ${1:-} == -n && ${2:-} == -l ]]; then
  [[ -n ${SUDO_GRANTED:-} ]] || exit 1
  exit 0
fi
printf 'sudo %s\n' "$*" >"$ELEVATION_LOG"
SH

cat >"$stub_bin/pkexec" <<'SH'
#!/bin/bash
printf 'pkexec %s\n' "$*" >"$ELEVATION_LOG"
SH

chmod +x "$stub_bin/sudo" "$stub_bin/pkexec"

elevate_with() {
  local granted="$1"
  local provider="$2"

  : >"$test_tmp/elevation"
  SUDO_GRANTED="$granted" \
  ELEVATION_LOG="$test_tmp/elevation" \
  OMARCHY_PATH="$ROOT" \
  PATH="$stub_bin:$PATH" \
    bash "$dns" "$provider" </dev/null >/dev/null
  cat "$test_tmp/elevation"
}

granted=$(elevate_with granted Cloudflare)
[[ $granted == "sudo -n $dns Cloudflare" ]] ||
  fail "omarchy-dns takes the passwordless sudo grant without a terminal" "got: $granted"

ungranted=$(elevate_with "" Cloudflare)
[[ $ungranted == "pkexec $dns Cloudflare" ]] ||
  fail "omarchy-dns still falls back to pkexec where the grant does not apply" "got: $ungranted"

pass "omarchy-dns elevates through the sudoers grant before polkit"
