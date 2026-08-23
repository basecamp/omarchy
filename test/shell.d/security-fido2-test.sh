#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setup="$ROOT/bin/omarchy-setup-security-fido2"

test_tmp=$(mktemp -d)
staged="$test_tmp/staged"
calls="$test_tmp/calls.log"
credential="tester:credential-handle,public-key,es256,+presence"
scratch="$test_tmp/scratch"
stub_bin="$test_tmp/bin"
mkdir -p "$scratch" "$stub_bin"
: >"$staged"

# A script that still names its own path stages a real credential outside the
# scratch directory, so take that file back out instead of leaving one behind
# in whatever directory it chose. The path comes from the script under test and
# is reported already resolved, so a script staging through a symlink would name
# a file of the user's: unlink only what this run's own stub wrote into.
cleanup() {
  local path

  while read -r path _; do
    [[ -n $path && $path != "$test_tmp"/* ]] || continue
    [[ -f $path && $(cat "$path" 2>/dev/null) == "$credential" ]] && rm -f "$path"
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

echo "$TEST_CREDENTIAL"
SH

chmod +x "$stub_bin/sudo" "$stub_bin/fido2-token" "$stub_bin/omarchy-pkg-add" "$stub_bin/pamu2fcfg"

# mktemp follows TMPDIR, so pointing it at the scratch directory both keeps the
# run out of the shared /tmp and lets the assertions read the staged file's mode
# without racing anything else on the machine.
run_setup() {
  : >"$calls"

  TEST_LOG="$calls" TEST_STAGED="$staged" TEST_CREDENTIAL="$credential" TMPDIR="$scratch" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$setup" </dev/null >/dev/null ||
    fail "FIDO2 setup registers a device that answers fido2-token" "sudo calls:
$(cat "$calls")"
}

# The registration block is guarded on the host's own /etc/fido2/fido2, and no
# stub hides a file at an absolute path from it. On a machine that already has
# one, every staging assertion below would pass against a script that stages
# nothing at all -- so assert instead what this branch does promise, and stop
# there. Which promise depends on what is at the path: a real registration must
# still be recognised as one, and anything that is not a regular file must be
# refused rather than registered over.
if [[ -f /etc/fido2/fido2 && ! -L /etc/fido2/fido2 ]]; then
  run_setup

  [[ ! -s $staged ]] ||
    fail "FIDO2 setup stages nothing when a registration already exists" "$(cat "$staged")"
  ! grep -Fq $'sudo\tinstall\t-T\t' "$calls" ||
    fail "FIDO2 setup installs nothing over an existing registration" "$(cat "$calls")"

  pass "FIDO2 setup leaves an existing registration alone; skipping the staging checks"
  exit 0
elif [[ -e /etc/fido2/fido2 || -L /etc/fido2/fido2 ]]; then
  : >"$calls"
  TEST_LOG="$calls" TEST_STAGED="$staged" TEST_CREDENTIAL="$credential" TMPDIR="$scratch" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$setup" </dev/null >/dev/null 2>&1 &&
    fail "FIDO2 setup refuses a non-regular authfile" "it exited 0 against $(ls -ld /etc/fido2/fido2)"

  [[ ! -s $staged ]] ||
    fail "FIDO2 setup stages nothing against a non-regular authfile" "$(cat "$staged")"

  pass "FIDO2 setup refuses a non-regular authfile; skipping the staging checks"
  exit 0
fi

run_setup
staged_path=$(awk 'NR == 1 { print $1 }' "$staged")
mode=$(awk 'NR == 1 { print $2 }' "$staged")
install_call=$(grep -F $'sudo\tinstall\t-T\t-m\t600\t' "$calls" || true)

# The staged file is a complete pam_u2f credential. Written under the caller's
# umask it is readable by anything sharing a group with the user, and readable
# by every local account on a default umask.
[[ $mode == "600" ]] ||
  fail "FIDO2 setup stages the credential unreadable to other users" "mode: $mode, path: $staged_path"

# Whatever path the script chooses has to be one it made itself. A name it
# hardcodes in a directory other users can write is a file an attacker creates
# first -- as a symlink the redirect then follows -- while the user is waiting
# to be told to touch the key.
[[ $staged_path == "$scratch"/* ]] ||
  fail "FIDO2 setup stages the credential under TMPDIR rather than a path it names" "got: $staged_path"

[[ ! -e $staged_path ]] ||
  fail "FIDO2 setup removes the staged credential once it is installed" "left behind: $staged_path"

# install(1) creates /etc/fido2/fido2 root-owned and mode 600. mv would carry
# the staged file's own ownership into /etc instead, and a credential file its
# own user can rewrite is a key any local process can swap for one it holds --
# pam_u2f then answers this machine's sudo prompt for whoever swapped it.
[[ -n $install_call ]] ||
  fail "FIDO2 setup installs the credential into /etc rather than moving it there" "sudo calls:
$(cat "$calls")"

[[ $install_call == *$'\t'-o$'\t'root* && $install_call == *$'\t'-g$'\t'root* ]] ||
  fail "FIDO2 setup installs the credential root-owned and mode 600" "got: $install_call"

[[ $install_call == *$'\t'"$staged_path"$'\t'/etc/fido2/fido2 ]] ||
  fail "FIDO2 setup installs the credential it just staged" "got: $install_call"

! grep -Fq $'sudo\tmv\t' "$calls" ||
  fail "FIDO2 setup does not move a staged file into /etc" "$(grep -F $'sudo\tmv\t' "$calls")"

pass "FIDO2 setup stages the credential privately and installs it root-owned"

# Same test, stated as the attacker sees it: a name that is the same on the next
# run is a name that can be occupied before this run, whatever the name is.
run_setup
[[ $(awk 'NR == 2 { print $1 }' "$staged") != "$staged_path" ]] ||
  fail "FIDO2 setup stages under a name a second run does not reuse" "both runs used: $staged_path"

pass "FIDO2 setup stages the credential under an unpredictable name"
