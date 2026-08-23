#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787085233.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

# The suite runs unprivileged, so the ownership change itself cannot be applied.
# Log every escalated command and run the rest for real, which is what leaves the
# new inode, mode, and content for the assertions to inspect.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

case "$1" in
  # Unprivileged, this can only fail. Swallowing it keeps a repair that chowns
  # the mapping in place from dying on a permission error, so it reaches the
  # assertions and fails on the inode it did not replace.
  chown)
    exit 0
    ;;
  install)
    shift
    args=()
    while (($#)); do
      case "$1" in
        -o|-g) shift 2 ;;
        *)
          args+=("$1")
          shift
          ;;
      esac
    done
    exec install "${args[@]}"
    ;;
  *)
    exec "$@"
    ;;
esac
SH

chmod +x "$stub_bin"/*

authfile="$test_tmp/fido2"

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_FIDO2_AUTHFILE="$authfile" \
    bash -euo pipefail "$migration" >/dev/null
}

# A machine that never registered a key has nothing to repair, and must not
# prompt for a password to establish that.
rm -f "$authfile"
: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "an install without a mapping is left alone" "$(cat "$calls")"
pass "migration skips a machine with no FIDO2 mapping"

# The mapping the old `sudo mv` left behind: owned by the user PAM authenticates.
write_mapping() {
  printf 'user:credential:publickey\n' >"$authfile"
  chmod "$1" "$authfile"
  # The migration's tell is "owner is not root". A suite running as root
  # (CI sandboxes) would otherwise make every fixture look already repaired.
  if [[ $(stat -c '%u' "$authfile") == 0 ]]; then
    chown 65534 "$authfile" 2>/dev/null || true
  fi
}

write_mapping 644
before_inode=$(stat -c '%i' "$authfile")
: >"$calls"
run_migration

grep -q $'^sudo\tinstall\t-o\troot\t-g\troot' "$calls" ||
  fail "a user-owned mapping is reinstalled root-owned" "$(cat "$calls")"
grep -q $'^sudo\tmv\t-f' "$calls" ||
  fail "the staged mapping is renamed over the authfile" "$(cat "$calls")"
pass "migration repairs a user-owned mapping"

[[ $(stat -c '%a' "$authfile") == 644 ]] ||
  fail "the repaired mapping is mode 644" "$(stat -c '%a' "$authfile")"
[[ $(cat "$authfile") == "user:credential:publickey" ]] ||
  fail "the repaired mapping keeps its credential" "$(cat "$authfile")"
pass "migration preserves the credential and normalizes the mode"

# The point of staging a copy over chown: PAM's path must land on a new inode so
# a descriptor opened on the old one can no longer append to what PAM reads.
[[ $(stat -c '%i' "$authfile") != "$before_inode" ]] ||
  fail "the repair replaces the inode rather than chowning it in place"
pass "migration replaces the inode, orphaning any open handle"

# Nothing staged may survive the repair; a leftover copy in /etc/fido2 would sit
# beside the authfile as a second mapping.
(( $(find "$test_tmp" -maxdepth 1 -name '*fido2*' | wc -l) == 1 )) ||
  fail "the staged copy does not outlive the repair" "$(find "$test_tmp" -maxdepth 1 -name '*fido2*')"
pass "migration leaves no staged copy behind"

# A mode that hides the credential from other users is still the wrong owner.
write_mapping 600
: >"$calls"
run_migration

grep -q $'^sudo\tinstall\t-o\troot\t-g\troot' "$calls" ||
  fail "a mode-600 user-owned mapping is still repaired" "$(cat "$calls")"
pass "migration repairs a user-owned mapping whatever its mode"

# The state a completed repair leaves behind, which is also the state every
# machine that registered after the fix starts in: root-owned, no write bit
# outside the owner. Running against it must do nothing at all, so a second user
# on the machine -- and a second run for the same user -- is a silent no-op.
settled=""
for candidate in /etc/fstab /etc/hostname /etc/locale.gen; do
  [[ -f $candidate ]] || continue
  [[ $(stat -c '%u' "$candidate") == 0 ]] || continue
  (( (0$(stat -c '%a' "$candidate") & 0022) == 0 )) || continue
  settled="$candidate"
  break
done

if [[ -n $settled ]]; then
  authfile="$settled"
  : >"$calls"
  run_migration

  [[ ! -s $calls ]] || fail "an already root-owned mapping is left alone" "$(cat "$calls")"
  pass "migration no-ops on a repaired mapping, for every later user and run"
else
  pass "no root-owned reference file; skipping the settled-mapping no-op check"
fi

setup="$ROOT/bin/omarchy-setup-security-fido2"
grep -Fq 'sudo install -o root -g root -m 644' "$setup" ||
  fail "FIDO2 setup installs the mapping root-owned instead of mv"
if grep -Fq '/tmp/fido2' "$setup"; then
  fail "FIDO2 setup must not stage credentials through a predictable /tmp path"
fi
grep -Fq 'mktemp' "$setup" || fail "FIDO2 setup stages the mapping in a random temp file"
pass "FIDO2 setup stages a random temp file and installs it root-owned"
