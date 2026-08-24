#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$OMARCHY_SSHD_TEST_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$OMARCHY_SSHD_TEST_LOG"
done
printf '\n' >>"$OMARCHY_SSHD_TEST_LOG"

case "$1" in
  tee)
    cat >"$OMARCHY_SSHD_TEST_CONFIG"
    ;;
  sshd)
    printf 'passwordauthentication %s\n' "${OMARCHY_SSHD_TEST_PASSWORD_AUTH:-no}"
    ;;
esac
SH
chmod +x "$stub_bin/sudo"

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash

printf 'pkg-add\t%s\n' "$*" >>"$OMARCHY_SSHD_TEST_LOG"
SH
chmod +x "$stub_bin/omarchy-pkg-add"

# ufw is present, so open_firewall does not take its skip branch.
cat >"$stub_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash

exit 1
SH
chmod +x "$stub_bin/omarchy-cmd-missing"

cat >"$stub_bin/ssh-keygen" <<'SH'
#!/bin/bash

key=$(cat)
case "$key" in
  ssh-*) printf '256 SHA256:stub %s (ED25519)\n' "$key" ;;
  *) exit 1 ;;
esac
SH
chmod +x "$stub_bin/ssh-keygen"

cat >"$stub_bin/hostname" <<'SH'
#!/bin/bash

printf 'test-host\n'
SH
chmod +x "$stub_bin/hostname"

# Reached only if the setup falls through to the interactive picker, which no
# case here should. Fail loudly rather than hang waiting for a choice.
cat >"$stub_bin/gum" <<'SH'
#!/bin/bash

printf 'gum\t%s\n' "$*" >>"$OMARCHY_SSHD_TEST_LOG"
exit 1
SH
chmod +x "$stub_bin/gum"

run_sshd() {
  local case_dir="$test_tmp/$1"
  shift

  mkdir -p "$case_dir/home"
  log_file="$case_dir/sshd.log"
  config_file="$case_dir/omarchy-keys-only.conf"
  : >"$log_file"
  : >"$config_file"

  HOME="$case_dir/home" \
    OMARCHY_SSHD_TEST_LOG="$log_file" \
    OMARCHY_SSHD_TEST_CONFIG="$config_file" \
    OMARCHY_SSHD_TEST_PASSWORD_AUTH="${password_auth:-no}" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-setup-security-sshd" "$@"
}

# A good key: the setup writes the drop-in, then opens the firewall.
password_auth=no
run_sshd good --key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 tester@host" >/dev/null 2>&1 ||
  fail "setup succeeds with a valid key" "$(cat "$test_tmp/good/sshd.log" 2>/dev/null)"

grep -qx 'PasswordAuthentication no' "$test_tmp/good/omarchy-keys-only.conf" ||
  fail "drop-in turns password logins off" "$(cat "$test_tmp/good/omarchy-keys-only.conf")"
pass "drop-in turns password logins off"

grep -qx 'KbdInteractiveAuthentication no' "$test_tmp/good/omarchy-keys-only.conf" ||
  fail "drop-in turns keyboard-interactive logins off" "$(cat "$test_tmp/good/omarchy-keys-only.conf")"
pass "drop-in turns keyboard-interactive logins off"

grep -q 'ssh-ed25519' "$test_tmp/good/home/.ssh/authorized_keys" ||
  fail "the key still reaches authorized_keys"
pass "the key still reaches authorized_keys"

# The drop-in has to be in place before the server starts listening, and the
# port only opens once sshd confirms password logins are off.
config_line=$(grep -n 'tee' "$test_tmp/good/sshd.log" | head -1 | cut -d: -f1)
start_line=$(grep -n 'enable' "$test_tmp/good/sshd.log" | head -1 | cut -d: -f1)
check_line=$(grep -n 'sshd' "$test_tmp/good/sshd.log" | grep -v enable | grep -v reload | head -1 | cut -d: -f1)
firewall_line=$(grep -n 'ufw' "$test_tmp/good/sshd.log" | head -1 | cut -d: -f1)

(( config_line < start_line )) ||
  fail "the drop-in is written before the server starts" "$(cat "$test_tmp/good/sshd.log")"
pass "the drop-in is written before the server starts"

(( check_line < firewall_line )) ||
  fail "the firewall opens only after sshd confirms the setting" "$(cat "$test_tmp/good/sshd.log")"
pass "the firewall opens only after sshd confirms the setting"

# A key the setup rejects must leave the machine untouched. Before this change
# the server was enabled and the port opened before the key was even read.
password_auth=no
if run_sshd bad --key="not-a-key" >/dev/null 2>&1; then
  fail "setup fails on a key it cannot read"
fi
pass "setup fails on a key it cannot read"

grep -q 'ufw' "$test_tmp/bad/sshd.log" &&
  fail "a rejected key leaves the firewall closed" "$(cat "$test_tmp/bad/sshd.log")"
pass "a rejected key leaves the firewall closed"

grep -q 'enable' "$test_tmp/bad/sshd.log" &&
  fail "a rejected key leaves the server disabled" "$(cat "$test_tmp/bad/sshd.log")"
pass "a rejected key leaves the server disabled"

# sshd is the authority on what it ended up with. If it still reports password
# logins on, the setup stops rather than opening the port anyway.
password_auth=yes
if run_sshd stubborn --key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 tester@host" >/dev/null 2>&1; then
  fail "setup fails when sshd still takes passwords"
fi
pass "setup fails when sshd still takes passwords"

grep -q 'ufw' "$test_tmp/stubborn/sshd.log" &&
  fail "the port stays closed when sshd still takes passwords" "$(cat "$test_tmp/stubborn/sshd.log")"
pass "the port stays closed when sshd still takes passwords"
