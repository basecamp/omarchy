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

# `sudo -l` on its own answers whether a command is permitted, not whether it
# is passwordless, and Omarchy ships a blanket %wheel rule that permits
# everything. Only the long listing prints the matched entry's tags.
grep -E 'sudo -n -l -l' "$dns" >/dev/null ||
  fail "omarchy-dns reads the grant from the long sudo listing"

pass "dns sudoers rule is scoped to the stock providers"

# The privileged half runs as root under sudo's secure_path, and a dev link
# (etc/sudoers.d/omarchy-dev-path) prepends a user-writable checkout bin/ to it.
# Every helper the script calls by bare name -- dirname, install, tee, nmcli,
# systemctl, awk -- is a system tool, so once it holds root the script pins PATH
# to trusted system directories and never resolves one of them out of the
# checkout. The unprivileged wrapper phase keeps the caller's PATH, which is why
# the pin is gated on EUID rather than set unconditionally.
grep -Eq '^\s*export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin' "$dns" ||
  fail "omarchy-dns pins PATH to trusted system directories when it holds root"
# require_root carries its own `(( EUID == 0 ))`, so matching that text alone
# would pass with the pin deleted. Anchor on the unindented guard and require the
# pin to be the line it opens.
gated=$(grep -A1 -E '^if \(\( EUID == 0 \)\); then$' "$dns" || true)
[[ $gated == *"export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin"* ]] ||
  fail "omarchy-dns gates the trusted-PATH pin on holding root"

# The no-argument path only reads DNS config, so exercise the privileged phase
# directly when the suite is root and as namespaced root otherwise. This reaches
# tr while EUID is 0 without giving an ordinary test run any host privileges.
root_runner=()
if (( EUID != 0 )); then
  root_runner=(unshare --user --map-root-user)
fi

# A sandbox or a hardened kernel can refuse unprivileged user namespaces, and
# the non-graphical suites have to stay green on any machine -- a skip is a
# passing test. Only the runtime probe needs the namespace; the static checks
# above and the elevation checks below run either way.
if (( EUID == 0 )) || unshare --user --map-root-user true 2>/dev/null; then
  poison_dir=$(mktemp -d)
  poison_ran="$poison_dir/ran"
  for helper in tr awk dirname install tee; do
    cat >"$poison_dir/$helper" <<SH
#!/bin/bash
printf 'x' >"$poison_ran"
exec "/usr/bin/$helper" "\$@"
SH
    chmod +x "$poison_dir/$helper"
  done

  if ! PATH="$poison_dir:$PATH" "${root_runner[@]}" bash "$dns" </dev/null >/dev/null 2>&1; then
    rm -rf "$poison_dir"
    fail "root omarchy-dns failed its read-only trusted-PATH probe"
  fi
  if [[ -e $poison_ran ]]; then
    rm -rf "$poison_dir"
    fail "root omarchy-dns resolved a bare helper from the front of PATH instead of a trusted system path"
  fi
  rm -rf "$poison_dir"
  pass "root omarchy-dns resolves system helpers from a trusted PATH, not the invocation PATH"
else
  pass "no unprivileged user namespace; skipping the root trusted-PATH probe"
fi

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

# pkexec stands in for the exec at the end of require_root, so the DNS writes
# below it never run and real pkexec is never reached.
cat >"$stub_bin/pkexec" <<'SH'
#!/bin/bash
printf 'pkexec %s\n' "$*" >"$ELEVATION_LOG"
SH
chmod +x "$stub_bin/pkexec"

# The sudo stub plays both parts: it answers the passwordless probe from
# STUB_GRANTED, the providers etc/sudoers.d/omarchy-dns covers on this machine,
# and logs the elevation otherwise. STUB_GRANTED empty stands for an install
# whose omarchy-settings predates the file.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ $1 == -n && $2 == -l ]]; then
  for granted in ${STUB_GRANTED-Cloudflare Google DHCP}; do
    [[ ${!#} == "$granted" ]] || continue
    echo "    Options: !authenticate"
    exit 0
  done
  echo "    Matched: ${!#}"
  exit 0
fi
printf 'sudo %s\n' "$*" >"$ELEVATION_LOG"
SH
chmod +x "$stub_bin/sudo"

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

# The grant is what makes sudo passwordless, so its absence -- an install still
# on an older omarchy-settings, or a user outside %wheel the rule cannot match
# -- has to route to polkit. Betting on sudo here leaves the panel's one-click
# toggle execing into a password prompt it has no terminal to show.
ungranted=$(STUB_GRANTED="" elevation_for Cloudflare)
[[ $ungranted == "pkexec /usr/bin/omarchy-dns Cloudflare" ]] ||
  fail "omarchy-dns falls back to polkit where the sudoers grant is not installed" "got: $ungranted"

pass "omarchy-dns falls back to polkit wherever the grant does not reach"
