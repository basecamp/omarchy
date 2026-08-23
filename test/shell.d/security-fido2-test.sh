#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setup="$ROOT/bin/omarchy-setup-security-fido2"

# The registration block is guarded on the host's own /etc/fido2/fido2, and no
# stub hides a file at an absolute path from it. A machine that already has a
# credential takes the "already registered" branch, where every assertion below
# would pass against a script that never stages anything at all.
if [[ -f /etc/fido2/fido2 ]]; then
  pass "FIDO2 already registered on this machine; skipping the registration checks"
  exit 0
fi

test_tmp=$(mktemp -d)
staged="$test_tmp/staged"
calls="$test_tmp/calls.log"
scratch="$test_tmp/scratch"
stub_bin="$test_tmp/bin"
mkdir -p "$scratch" "$stub_bin"
: >"$staged"

# A script that still names its own path stages a real credential outside the
# scratch directory, so take that file back out instead of leaving one behind
# in whatever directory it chose.
cleanup() {
  local path

  while read -r path _; do
    [[ -n $path && $path != "$test_tmp"/* ]] && rm -f "$path"
  done <"$staged"

  rm -rf "$test_tmp"
  return 0
}
trap cleanup EXIT

# Logged, deliberately not run: every escalation here writes somewhere real
# (/etc/fido2, /etc/pam.d/sudo, /etc/pam.d/polkit-1), and running them would
# rewrite the authentication stack of the machine under test.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/fido2-token" <<'SH'
#!/bin/bash

echo '/dev/hidraw0: vendor=0x1050, product=0x0407 (Yubico YubiKey)'
SH

cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
SH

# pamu2fcfg's stdout is the file the script picked for the credential, so the
# stub reports that file rather than only writing to it: where the secret lands
# and what mode it lands with is the property under test. The append and the
# command substitutions each rebind fd 1, so inspect a duplicate of the
# descriptor the script actually handed over.
cat >"$stub_bin/pamu2fcfg" <<'SH'
#!/bin/bash

exec 9>&1
printf '%s %s\n' "$(readlink -f /proc/self/fd/9)" "$(stat -Lc '%a' /proc/self/fd/9)" >>"$TEST_STAGED"

echo 'tester:credential-handle,public-key,es256,+presence'
SH

chmod +x "$stub_bin/sudo" "$stub_bin/fido2-token" "$stub_bin/omarchy-pkg-add" "$stub_bin/pamu2fcfg"

# mktemp follows TMPDIR, so pointing it at the scratch directory both keeps the
# run out of the shared /tmp and lets the assertions read the staged file's mode
# without racing anything else on the machine.
run_setup() {
  : >"$calls"

  TEST_LOG="$calls" TEST_STAGED="$staged" TMPDIR="$scratch" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$setup" </dev/null >/dev/null ||
    fail "FIDO2 setup registers a device that answers fido2-token" "sudo calls:
$(cat "$calls")"
}

run_setup
credential=$(awk 'NR == 1 { print $1 }' "$staged")
mode=$(awk 'NR == 1 { print $2 }' "$staged")
install_call=$(grep -F $'sudo\tinstall\t-m\t600\t' "$calls" || true)

# The staged file is a complete pam_u2f credential. Written under the caller's
# umask it is readable by anything sharing a group with the user, and readable
# by every local account on a default umask.
[[ $mode == "600" ]] ||
  fail "FIDO2 setup stages the credential unreadable to other users" "mode: $mode, path: $credential"

# Whatever path the script chooses has to be one it made itself. A name it
# hardcodes in a directory other users can write is a file an attacker creates
# first -- as a symlink the redirect then follows -- while the user is waiting
# to be told to touch the key.
[[ $credential == "$scratch"/* ]] ||
  fail "FIDO2 setup stages the credential under TMPDIR rather than a path it names" "got: $credential"

[[ ! -e $credential ]] ||
  fail "FIDO2 setup removes the staged credential once it is installed" "left behind: $credential"

# install(1) creates /etc/fido2/fido2 root-owned and mode 600. mv would carry
# the staged file's own ownership into /etc instead, and a credential file its
# own user can rewrite is a key any local process can swap for one it holds --
# pam_u2f then answers this machine's sudo prompt for whoever swapped it.
[[ -n $install_call ]] ||
  fail "FIDO2 setup installs the credential into /etc rather than moving it there" "sudo calls:
$(cat "$calls")"

[[ $install_call == *$'\t'-o$'\t'root* && $install_call == *$'\t'-g$'\t'root* ]] ||
  fail "FIDO2 setup installs the credential root-owned and mode 600" "got: $install_call"

[[ $install_call == *$'\t'"$credential"$'\t'/etc/fido2/fido2 ]] ||
  fail "FIDO2 setup installs the credential it just staged" "got: $install_call"

! grep -Fq $'sudo\tmv\t' "$calls" ||
  fail "FIDO2 setup does not move a staged file into /etc" "$(grep -F $'sudo\tmv\t' "$calls")"

pass "FIDO2 setup stages the credential privately and installs it root-owned"

# Same test, stated as the attacker sees it: a name that is the same on the next
# run is a name that can be occupied before this run, whatever the name is.
run_setup
[[ $(awk 'NR == 2 { print $1 }' "$staged") != "$credential" ]] ||
  fail "FIDO2 setup stages under a name a second run does not reuse" "both runs used: $credential"

pass "FIDO2 setup stages the credential under an unpredictable name"
