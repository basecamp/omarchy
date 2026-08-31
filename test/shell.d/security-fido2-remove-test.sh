#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

remove="$ROOT/bin/omarchy-remove-security-fido2"

test_tmp=$(mktemp -d)
stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
authdir="$test_tmp/etc-fido2"
elsewhere="$test_tmp/elsewhere"
remove_copy="$test_tmp/remove.sh"
mkdir -p "$stub_bin"

cleanup() {
  rm -rf "$test_tmp"
  return 0
}
trap cleanup EXIT

# The same seam the setup and migration suites use: the removal deletes an
# absolute path no unprivileged suite can own, and an environment override in
# the shipped command would hand a privileged rm -rf an operand the caller
# chooses. Retarget a copy instead, and fail if the path is not named exactly
# once so this seam cannot quietly stop standing for the command it copies.
occurrences=$(grep -Fxc 'authdir=/etc/fido2' "$remove") || occurrences=0
(( occurrences == 1 )) ||
  fail "the removal names its FIDO2 directory exactly once" "found $occurrences occurrences"
pass "removal names its FIDO2 directory once, and the test drives a retargeted copy"

sed "s|^authdir=/etc/fido2$|authdir=$authdir|" "$remove" >"$remove_copy"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

set -euo pipefail

reject() {
  printf 'refusing unexpected sudo invocation:' >&2
  printf ' %q' "$@" >&2
  printf '\n' >&2
  exit 97
}

if [[ ${TEST_AUTHDIR:-} != /* || ${TEST_LOG:-} != /* ]]; then
  reject "$@"
fi

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

case "${1:-}" in
  rm)
    if (( $# != 3 )) || [[ $2 != "-rf" || $3 != "$TEST_AUTHDIR" ]]; then
      reject "$@"
    fi

    exec /usr/bin/rm -rf "$TEST_AUTHDIR"
    ;;
  sed)
    if (( $# != 4 )) || [[ $2 != "-i" ]]; then
      reject "$@"
    fi
    ;;
  *)
    reject "$@"
    ;;
esac
SH

cat >"$stub_bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
SH

chmod +x "$stub_bin/sudo" "$stub_bin/omarchy-pkg-drop"

invoke_remove() {
  : >"$calls"
  TEST_AUTHDIR="$authdir" TEST_LOG="$calls" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$remove_copy" </dev/null >/dev/null
}

# The ordinary case: a real directory holding a registration.
rm -rf "$authdir"
mkdir -p "$authdir"
printf 'tester:credential-handle,public-key,es256,+presence\n' >"$authdir/fido2"
invoke_remove
grep -Fxq $'sudo\trm\t-rf\t'"$authdir" "$calls" ||
  fail "removal deletes the FIDO2 directory" "$(cat "$calls")"
[[ ! -e $authdir ]] || fail "the FIDO2 directory is gone"
pass "removal deletes a real FIDO2 directory"

# -d is false for a dangling link, so the guard it replaced left one sitting
# there for the next setup to install an authfile through.
rm -rf "$authdir"
ln -s "$test_tmp/missing" "$authdir"
invoke_remove
grep -Fxq $'sudo\trm\t-rf\t'"$authdir" "$calls" ||
  fail "removal deletes a dangling symlink at the FIDO2 directory" "$(cat "$calls")"
[[ ! -e $authdir && ! -L $authdir ]] ||
  fail "the dangling symlink is gone"
pass "removal deletes a dangling symlink where -d would have skipped it"

# rm -rf on a symlink unlinks the link. Whatever it pointed at is not ours.
rm -rf "$authdir"
rm -rf "$elsewhere"
mkdir -p "$elsewhere"
printf 'keep me\n' >"$elsewhere/canary"
ln -s "$elsewhere" "$authdir"
invoke_remove
[[ ! -e $authdir && ! -L $authdir ]] ||
  fail "the symlink at the FIDO2 directory is gone"
[[ -d $elsewhere && -f $elsewhere/canary ]] ||
  fail "removal takes the symlink, never the directory it points at"
pass "removal takes a symlink itself and leaves its target intact"

# Nothing there at all: no escalation, so removing FIDO2 twice costs no prompt.
rm -rf "$authdir"
invoke_remove
! grep -Fq $'sudo\trm\t' "$calls" ||
  fail "removal escalates no rm when there is no FIDO2 directory" "$(cat "$calls")"
pass "removal escalates nothing when there is no FIDO2 directory"
