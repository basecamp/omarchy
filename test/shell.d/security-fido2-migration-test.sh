#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787494718.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
authfile="$test_tmp/fido2"
migration_copy="$test_tmp/migration.sh"
mkdir -p "$stub_bin"

# The migration repairs an absolute path no unprivileged suite can write, and an
# environment override in the shipped file would hand a root install and mv an
# operand the caller chooses. Retarget a scratch copy instead, and fail if the
# path is not named exactly once, so this seam cannot quietly stop standing for
# the file it copies.
occurrences=$(grep -Fo /etc/fido2/fido2 "$migration" | wc -l) || occurrences=0
(( occurrences == 1 )) ||
  fail "the migration names its authfile exactly once, so the test can retarget a copy" \
    "found $occurrences occurrences"
pass "migration names its authfile once, and the test drives a retargeted copy"

# Log every escalation, then run the rest for real with the ownership flags
# dropped -- that is what leaves a genuine inode, mode and content behind for the
# assertions. Nothing outside the scratch directory is ever executed against: a
# migration that lost its retargeting would otherwise run the repair on the
# host's own authfile, and this suite has to stay safe to run as root.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

for arg in "$@"; do
  [[ $arg == /* ]] || continue
  [[ $arg == "$TEST_TMP"/* ]] || exit 0
done

case "$1" in
  # Unprivileged this can only fail. Swallowing it lets a repair that chowns in
  # place run to completion and be caught by the inode assertion, rather than
  # dying on a permission error that says nothing about what it did wrong.
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

chmod +x "$stub_bin/sudo"

run_migration() {
  local target="${1:-$authfile}"

  : >"$calls"
  sed "s|/etc/fido2/fido2|$target|" "$migration" >"$migration_copy"

  PATH="$stub_bin:$PATH" TEST_LOG="$calls" TEST_TMP="$test_tmp" \
    bash -euo pipefail "$migration_copy" >/dev/null
}

# Every repair case is about an authfile its own user can still rewrite. Run as
# root -- which some CI does -- a fresh file is already the settled state and
# would assert the opposite of what it says, so hand it to somebody else.
write_authfile() {
  printf 'tester:credential-handle,public-key,es256,+presence\n' >"$authfile"
  chmod "$1" "$authfile"
  (( EUID == 0 )) && chown 65534:65534 "$authfile" 2>/dev/null

  [[ $(stat -c %U "$authfile") != "root" ]]
}

# Almost every machine has never registered a key, and establishing that must
# not cost those users a password prompt.
rm -f "$authfile"
run_migration
[[ ! -s $calls ]] || fail "a machine with no authfile escalates nothing" "$(cat "$calls")"
pass "migration skips a machine that never set FIDO2 up"

# What the old `sudo mv` left behind on every machine that did: the authfile PAM
# consults for sudo, owned by the account it authenticates, at the caller's umask.
if write_authfile 644; then
  before_inode=$(stat -c %i "$authfile")
  run_migration

  grep -Fq $'sudo\tinstall\t-T\t-m\t600\t-o\troot\t-g\troot\t' "$calls" ||
    fail "a user-owned authfile is reinstalled root-owned and mode 600" "$(cat "$calls")"
  ! grep -Fq $'sudo\tchown\t' "$calls" ||
    fail "the repair replaces the authfile rather than chowning it" "$(cat "$calls")"
  pass "migration reinstalls a user-owned authfile instead of chowning it"

  [[ $(stat -c %a "$authfile") == "600" ]] ||
    fail "the repaired authfile is mode 600" "got: $(stat -c %a "$authfile")"
  [[ $(cat "$authfile") == "tester:credential-handle,public-key,es256,+presence" ]] ||
    fail "the repaired authfile keeps its credential" "got: $(cat "$authfile")"
  pass "migration preserves the credential and tightens the mode"

  # The whole point of replacing rather than chowning. Permission is checked at
  # open(2), so a descriptor the registering user opened before the update stays
  # writable on the old inode through any chmod or chown -- and pam_u2f
  # resolving the authfile path would keep reading exactly that inode.
  [[ $(stat -c %i "$authfile") != "$before_inode" ]] ||
    fail "the repair lands on a new inode, orphaning any descriptor already open on the old one"
  pass "migration replaces the inode a pre-existing writer would still hold"

  # A staged copy left in /etc/fido2 would sit beside the authfile as a second
  # file nobody reads and nobody cleans up.
  [[ ! -e $authfile.new ]] ||
    fail "the staged copy does not outlive the repair" "left behind: $authfile.new"
  pass "migration leaves no staged copy behind"

  # Right mode is not the settled state on its own; the owner is what decides.
  write_authfile 600
  run_migration
  grep -Fq $'sudo\tinstall\t-T\t' "$calls" ||
    fail "a mode-600 authfile the user still owns is repaired" "$(cat "$calls")"
  pass "migration repairs a user-owned authfile whatever its mode"
else
  pass "cannot stage a non-root-owned authfile here; skipping the repair checks"
fi

# The state a completed repair leaves, which is also where every machine that
# registers after this fix starts. A second account, and a second run for the
# same account, must find it done and escalate nothing. Only root can make that
# fixture, so unprivileged runs borrow one of the host's -- never touched, since
# the stub executes nothing whose operands sit outside the scratch directory.
settled=""
if (( EUID == 0 )); then
  settled="$test_tmp/settled"
  install -m 600 -o root -g root /dev/null "$settled"
else
  for candidate in /etc/shadow /etc/gshadow /etc/crypttab; do
    [[ -f $candidate ]] || continue
    [[ $(stat -c %U "$candidate" 2>/dev/null) == "root" ]] || continue
    [[ $(stat -c %a "$candidate" 2>/dev/null) == "600" ]] || continue
    settled="$candidate"
    break
  done
fi

if [[ -n $settled ]]; then
  run_migration "$settled"
  [[ ! -s $calls ]] ||
    fail "an already root-owned mode-600 authfile escalates nothing" "$(cat "$calls")"
  pass "migration no-ops on a repaired authfile, for every later user and run"
else
  pass "no root-owned mode-600 file on this host; skipping the settled-authfile check"
fi

# Neither of these is ours to rewrite, and both must say so without escalating:
# chown follows a symlink and would take the target instead, and chmod 600 on a
# directory would only make it untraversable. Neither depends on ownership, so
# they run even where the repair cases above could not.
rm -rf "$authfile"
ln -s "$test_tmp/elsewhere" "$authfile"
: >"$test_tmp/elsewhere"
run_migration
[[ ! -s $calls ]] || fail "a symlinked authfile escalates nothing" "$(cat "$calls")"

rm -f "$authfile"
ln -s "$test_tmp/missing" "$authfile"
run_migration
[[ ! -s $calls ]] || fail "a dangling symlink escalates nothing" "$(cat "$calls")"
pass "migration reports a symlinked authfile and repairs nothing"

rm -f "$authfile"
mkdir -p "$authfile"
run_migration
[[ ! -s $calls ]] || fail "a directory at the authfile path escalates nothing" "$(cat "$calls")"
pass "migration reports a non-regular authfile and repairs nothing"
